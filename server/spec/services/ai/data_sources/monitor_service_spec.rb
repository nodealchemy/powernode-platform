# frozen_string_literal: true

require "rails_helper"

# Phase 3 server-side monitor loop. MonitorService#tick walks
# Ai::DataSourceSubscription.due_for_poll, runs the governed
# Ai::DataSources::QueryService fetch, change-detects against the stored
# last_checksum / last_etag, warms the cache + emits a "data_source_changed"
# stigmergic signal on a change, and records the poll outcome — collecting
# per-subscription errors without ever aborting the batch.
#
# HERMETIC: QueryService#call is STUBBED to return canned FetchEnvelopes so no
# network is hit; the DataSource after_commit KG sync (which would otherwise
# reach the embedding backend / Redis under DatabaseCleaner :deletion) is
# stubbed on every factory create; the cache warm + signal emit are stubbed so
# the change-detection branch is asserted without touching Redis.
RSpec.describe Ai::DataSources::MonitorService, type: :service do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }

  subject(:service) { described_class.new(account) }

  # A successful FetchEnvelope whose provenance carries an explicit
  # response_sha256 (the raw-body hash MonitorService#canonical_checksum prefers)
  # and an etag. Override either to drive change vs no-change.
  def fetch_envelope(sha:, etag: nil, data: [{ "city" => "NYC", "temp" => 72 }])
    prov = { response_sha256: sha }
    prov[:etag] = etag if etag
    {
      success: true,
      data: data,
      provenance: prov,
      status: "success",
      duration_ms: 12,
      bytes: 128,
      error: nil
    }
  end

  def error_envelope(message: "upstream 500")
    {
      success: false,
      data: [],
      provenance: {},
      status: "error",
      duration_ms: 5,
      bytes: 0,
      error: message
    }
  end

  before do
    # The DataSource after_commit KG sync would otherwise reach embeddings/Redis
    # when the factory persists a source under DatabaseCleaner :deletion.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # --------------------------------------------------------------------------
  # #tick — quota gating
  # --------------------------------------------------------------------------
  describe "#tick quota gating" do
    let!(:subscription) do
      create(:ai_data_source_subscription, :due,
             data_source: data_source, endpoint: endpoint)
    end

    it "SKIPS a subscription whose parent source is over quota (no fetch)" do
      allow(data_source).to receive(:check_quota!).and_return(
        { allowed: false, retry_after: 30, limit: "requests_per_minute" }
      )
      # Pin the in-memory source so the stubbed check_quota! is the one the
      # monitor consults when it loads the subscription's data_source.
      allow_any_instance_of(Ai::DataSourceSubscription).to receive(:data_source).and_return(data_source)

      # The fetch layer must NOT run for a throttled source.
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      result = service.tick

      # The subscription is still counted as visited (polled) but produced no change.
      expect(result[:polled]).to eq(1)
      expect(result[:changed]).to eq(0)
      expect(result[:errors]).to be_empty
    end

    it "re-schedules the deferred subscription without recording a failure" do
      allow(data_source).to receive(:check_quota!).and_return({ allowed: false, limit: "requests_per_minute" })
      allow_any_instance_of(Ai::DataSourceSubscription).to receive(:data_source).and_return(data_source)

      service.tick

      subscription.reload
      expect(subscription.consecutive_failures).to eq(0)
      expect(subscription.status).to eq("active")
      expect(subscription.next_poll_at).to be_present
    end
  end

  # --------------------------------------------------------------------------
  # #tick — change detected
  # --------------------------------------------------------------------------
  describe "#tick when the upstream payload changed" do
    let!(:subscription) do
      create(:ai_data_source_subscription, :due, :with_checksum,
             data_source: data_source, endpoint: endpoint,
             last_checksum: "old-checksum-aaa")
    end

    before do
      # check_quota! is permissive by default (no rate_limits configured), so the
      # real source allows the poll. A fresh-body envelope with a DIFFERENT sha
      # than last_checksum registers as a change.
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(sha: "new-checksum-bbb"))
      # Do not touch Redis from the warm path.
      allow(Ai::DataSources::ResponseCacheService).to receive(:write).and_return(true)
    end

    it "warms ONLY this param-variant's cache entry with the fresh payload" do
      allow_any_instance_of(Ai::Coordination::StigmergicSignalService).to receive(:emit!)

      expect(Ai::DataSources::ResponseCacheService).to receive(:write).with(
        hash_including(
          data_source: data_source,
          endpoint: endpoint,
          payload: hash_including("data" => [{ "city" => "NYC", "temp" => 72 }])
        )
      )

      service.tick
    end

    it "emits a data_source_changed discovery signal (system context, agent nil)" do
      signal = instance_double(Ai::Coordination::StigmergicSignalService)
      expect(Ai::Coordination::StigmergicSignalService).to receive(:new)
        .with(account: account).and_return(signal)
      expect(signal).to receive(:emit!).with(
        hash_including(
          signal_type: "discovery",
          signal_key: "data_source_changed",
          agent: nil,
          payload: hash_including(
            "data_source_id" => data_source.id,
            "endpoint_id" => endpoint.id,
            "subscription_id" => subscription.id,
            "checksum" => "new-checksum-bbb"
          )
        )
      )

      service.tick
    end

    it "records the poll as changed and stores the new checksum" do
      allow_any_instance_of(Ai::Coordination::StigmergicSignalService).to receive(:emit!)

      result = service.tick

      expect(result[:polled]).to eq(1)
      expect(result[:changed]).to eq(1)

      subscription.reload
      expect(subscription.last_checksum).to eq("new-checksum-bbb")
      expect(subscription.consecutive_failures).to eq(0)
      expect(subscription.last_polled_at).to be_present
    end
  end

  # --------------------------------------------------------------------------
  # #tick — no change
  # --------------------------------------------------------------------------
  describe "#tick when the upstream payload is unchanged" do
    let!(:subscription) do
      create(:ai_data_source_subscription, :due,
             data_source: data_source, endpoint: endpoint,
             last_checksum: "same-checksum-xyz")
    end

    before do
      # Envelope sha matches the stored last_checksum -> no change.
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(sha: "same-checksum-xyz"))
    end

    it "records the poll as unchanged" do
      result = service.tick

      expect(result[:polled]).to eq(1)
      expect(result[:changed]).to eq(0)
      expect(result[:errors]).to be_empty
    end

    it "does NOT warm the cache and does NOT emit a signal" do
      expect(Ai::DataSources::ResponseCacheService).not_to receive(:write)
      expect(Ai::Coordination::StigmergicSignalService).not_to receive(:new)

      service.tick

      subscription.reload
      # record_poll!(changed: false) still touches last_polled_at + resets failures.
      expect(subscription.last_polled_at).to be_present
      expect(subscription.consecutive_failures).to eq(0)
    end

    it "treats a matching etag as unchanged even when the checksum differs (304-style)" do
      subscription.update!(last_etag: "W/\"abc\"", last_checksum: "stale")
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(sha: "totally-different", etag: "W/\"abc\""))

      expect(Ai::Coordination::StigmergicSignalService).not_to receive(:new)

      result = service.tick
      expect(result[:changed]).to eq(0)
    end
  end

  # --------------------------------------------------------------------------
  # #tick — fetch error isolation
  # --------------------------------------------------------------------------
  describe "#tick when a fetch returns an unsuccessful envelope" do
    let!(:subscription) do
      create(:ai_data_source_subscription, :due,
             data_source: data_source, endpoint: endpoint)
    end

    before do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(error_envelope(message: "upstream 503"))
    end

    it "records a failure on the subscription and counts it as polled (no change)" do
      result = service.tick

      expect(result[:polled]).to eq(1)
      expect(result[:changed]).to eq(0)

      subscription.reload
      expect(subscription.consecutive_failures).to eq(1)
      expect(subscription.metadata["last_error"]).to eq("upstream 503")
    end

    it "does NOT warm the cache or emit a signal on an unsuccessful fetch" do
      expect(Ai::DataSources::ResponseCacheService).not_to receive(:write)
      expect(Ai::Coordination::StigmergicSignalService).not_to receive(:new)

      service.tick
    end
  end

  # --------------------------------------------------------------------------
  # #tick — per-subscription error isolation across a batch
  # --------------------------------------------------------------------------
  describe "#tick per-subscription error isolation" do
    let(:endpoint_a) { create(:ai_data_source_endpoint, data_source: data_source) }
    let(:endpoint_b) { create(:ai_data_source_endpoint, data_source: data_source) }
    let!(:bad_subscription) do
      create(:ai_data_source_subscription, :due,
             data_source: data_source, endpoint: endpoint_a)
    end
    let!(:good_subscription) do
      create(:ai_data_source_subscription, :due,
             data_source: data_source, endpoint: endpoint_b,
             last_checksum: "old")
    end

    before do
      allow(Ai::DataSources::ResponseCacheService).to receive(:write).and_return(true)
      allow_any_instance_of(Ai::Coordination::StigmergicSignalService).to receive(:emit!)
      # The bad subscription's fetch RAISES; the good one returns a changed payload.
      # Disambiguate by endpoint id so the batch exercises both branches.
      allow_any_instance_of(Ai::DataSources::QueryService).to receive(:call) do |svc|
        if svc.instance_variable_get(:@endpoint).id == endpoint_a.id
          raise StandardError, "boom"
        else
          fetch_envelope(sha: "fresh")
        end
      end
    end

    it "isolates the raised error, continues the batch, and populates errors[]" do
      result = service.tick

      expect(result[:polled]).to eq(2)
      expect(result[:changed]).to eq(1) # the good subscription still processed
      expect(result[:errors].size).to eq(1)
      expect(result[:errors].first[:subscription_id]).to eq(bad_subscription.id)
      expect(result[:errors].first[:error]).to eq("boom")
    end

    it "records a failure on the raising subscription but not the healthy one" do
      service.tick

      expect(bad_subscription.reload.consecutive_failures).to eq(1)
      expect(good_subscription.reload.consecutive_failures).to eq(0)
      expect(good_subscription.last_checksum).to eq("fresh")
    end
  end

  # --------------------------------------------------------------------------
  # #tick — scoping & due selection
  # --------------------------------------------------------------------------
  describe "#tick due selection" do
    it "does not poll a subscription whose next_poll_at is in the future" do
      create(:ai_data_source_subscription, :not_due,
             data_source: data_source, endpoint: endpoint)
      expect_any_instance_of(Ai::DataSources::QueryService).not_to receive(:call)

      result = service.tick
      expect(result[:polled]).to eq(0)
    end

    it "does not poll a paused subscription even if its next_poll_at is past" do
      sub = create(:ai_data_source_subscription, :due,
                   data_source: data_source, endpoint: endpoint)
      # Force paused with a past next_poll_at — due_for_poll must still exclude it.
      sub.update_columns(status: "paused", next_poll_at: 1.minute.ago)
      expect_any_instance_of(Ai::DataSources::QueryService).not_to receive(:call)

      result = service.tick
      expect(result[:polled]).to eq(0)
    end

    it "scopes to the service account when one is supplied" do
      other_account = create(:account)
      other_source = create(:ai_data_source, account: other_account)
      other_endpoint = create(:ai_data_source_endpoint, data_source: other_source)
      create(:ai_data_source_subscription, :due,
             data_source: other_source, endpoint: other_endpoint)

      # In-scope subscription so the batch has exactly one candidate.
      create(:ai_data_source_subscription, :due,
             data_source: data_source, endpoint: endpoint,
             last_checksum: "old")
      allow(Ai::DataSources::ResponseCacheService).to receive(:write).and_return(true)
      allow_any_instance_of(Ai::Coordination::StigmergicSignalService).to receive(:emit!)
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(sha: "fresh"))

      result = service.tick
      expect(result[:polled]).to eq(1) # only the in-account subscription
    end

    it "honours the limit argument" do
      3.times do
        ep = create(:ai_data_source_endpoint, data_source: data_source)
        create(:ai_data_source_subscription, :due, data_source: data_source, endpoint: ep,
                                                   last_checksum: "same")
      end
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(sha: "same"))

      result = service.tick(limit: 2)
      expect(result[:polled]).to eq(2)
    end
  end

  # --------------------------------------------------------------------------
  # #health_tick
  # --------------------------------------------------------------------------
  describe "#health_tick" do
    it "refreshes the health status of every active source in scope" do
      create(:ai_data_source, account: account)
      create(:ai_data_source, account: account)

      result = service.health_tick

      expect(result[:refreshed]).to eq(2)
      expect(result[:errors]).to be_empty
    end

    it "calls update_health_status! on each active source" do
      source = create(:ai_data_source, account: account)
      allow(Ai::DataSource).to receive(:active).and_return(Ai::DataSource.where(id: source.id))
      expect_any_instance_of(Ai::DataSource).to receive(:update_health_status!)

      service.health_tick
    end

    it "isolates a per-source refresh error without aborting the sweep" do
      good = create(:ai_data_source, account: account)
      bad = create(:ai_data_source, account: account)
      allow(Ai::DataSource).to receive(:active).and_return(Ai::DataSource.where(id: [good.id, bad.id]))
      allow_any_instance_of(Ai::DataSource).to receive(:update_health_status!) do |src|
        raise StandardError, "health boom" if src.id == bad.id
      end

      result = service.health_tick

      expect(result[:refreshed]).to eq(1)
      expect(result[:errors].size).to eq(1)
      expect(result[:errors].first[:data_source_id]).to eq(bad.id)
    end

    it "excludes inactive sources from the refresh" do
      create(:ai_data_source, :inactive, account: account)
      result = service.health_tick
      expect(result[:refreshed]).to eq(0)
    end
  end
end
