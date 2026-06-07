# frozen_string_literal: true

require "rails_helper"

# Phase 4 batch schema sync. Ai::DataSources::SchemaSyncService is the cron-tick
# counterpart to the inline drift recording QueryService does on every
# track_schema fetch: #sync walks endpoints that are "due" for a schema refresh
# (track_schema = true OR response_schema blank) on ACTIVE sources, runs a
# governed sample fetch through QueryService, infers a top-level-array JSON
# Schema from the canonical records, appends a version via
# SchemaDriftService#record_version!, and seeds response_schema onto the endpoint
# when it has no baseline yet. Per-endpoint failures are collected and never
# abort the batch; a throttled/blocked/errored sample is a SKIP, not a hard
# error (mirrors MonitorService#tick).
#
# HERMETIC: QueryService#call is STUBBED to return canned FetchEnvelopes so no
# network is hit; SchemaDriftService#record_version! is stubbed (its real
# behaviour is covered by schema_drift_service_spec) so the sync path is asserted
# in isolation; the DataSource after_commit KG sync (which would otherwise reach
# the embedding backend / Redis under DatabaseCleaner :deletion) is stubbed on
# every factory create.
RSpec.describe Ai::DataSources::SchemaSyncService, type: :service do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }

  subject(:service) { described_class.new(account) }

  # A successful FetchEnvelope shaped exactly like QueryService#call's contract:
  # a Hash with :success true and :data carrying canonical records (an Array of
  # Hashes). The default record drives the inferred schema's properties.
  def fetch_envelope(data: [{ "city" => "NYC", "temp" => 72, "active" => true }])
    {
      success: true,
      data: data,
      provenance: { response_sha256: "abc" },
      status: "success",
      duration_ms: 9,
      bytes: 64,
      error: nil
    }
  end

  # A throttled/blocked/errored envelope: :success is false, so the sample yields
  # no usable records and the endpoint is skipped without a hard error.
  def unsuccessful_envelope(message: "rate limited")
    {
      success: false,
      data: [],
      provenance: {},
      status: "error",
      duration_ms: 2,
      bytes: 0,
      error: message
    }
  end

  before do
    # The DataSource after_commit KG sync would otherwise reach embeddings/Redis
    # when the factory persists a source under DatabaseCleaner :deletion.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    # Default: drift recording is a no-op double. Examples that assert ON the call
    # re-stub with an explicit expectation.
    allow_any_instance_of(Ai::DataSources::SchemaDriftService).to receive(:record_version!)
  end

  # ===========================================================================
  # #sync — a due endpoint is sampled, its schema inferred, a version recorded.
  #
  # "due" via track_schema = true (the operator opted into drift tracking). The
  # :with_schema trait gives it a non-blank baseline so the seed-on-blank path is
  # NOT exercised here (that gets its own section).
  # ===========================================================================
  describe "#sync for a track_schema endpoint with an existing baseline" do
    let!(:endpoint) do
      create(:ai_data_source_endpoint, :with_schema,
             data_source: data_source, track_schema: true)
    end

    before do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope)
    end

    it "samples the endpoint via a live QueryService fetch" do
      expect(Ai::DataSources::QueryService).to receive(:new).with(
        hash_including(data_source: data_source, endpoint: endpoint, params: {}, agent: nil, user: nil)
      ).and_call_original

      service.sync(limit: 10)
    end

    it "infers a top-level-array schema from the canonical records and records a version" do
      expect_any_instance_of(Ai::DataSources::SchemaDriftService).to receive(:record_version!).with(
        endpoint,
        {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "city" => { "type" => "string" },
              "temp" => { "type" => "integer" },
              "active" => { "type" => "boolean" }
            }
          }
        }
      )

      service.sync(limit: 10)
    end

    it "counts the endpoint as synced and reports no errors" do
      result = service.sync(limit: 10)

      expect(result[:synced]).to eq(1)
      expect(result[:errors]).to eq([])
    end

    it "does NOT overwrite the already-present response_schema" do
      original = endpoint.response_schema

      expect { service.sync(limit: 10) }
        .not_to(change { endpoint.reload.response_schema })

      expect(endpoint.response_schema).to eq(original)
    end
  end

  # ===========================================================================
  # #sync — seeding response_schema when the endpoint has no baseline.
  #
  # A default endpoint's response_schema is {} (blank), which makes it due even
  # with track_schema = false; the inferred schema is persisted onto it.
  # ===========================================================================
  describe "#sync for an endpoint with a blank response_schema" do
    let!(:endpoint) do
      # track_schema false + blank response_schema ({} factory default) -> still
      # due via the "no baseline captured yet" clause.
      create(:ai_data_source_endpoint, data_source: data_source, track_schema: false)
    end

    before do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(data: [{ "id" => 1, "label" => "x" }]))
    end

    it "is selected as due even though track_schema is false" do
      expect_any_instance_of(Ai::DataSources::SchemaDriftService).to receive(:record_version!)

      result = service.sync(limit: 10)
      expect(result[:synced]).to eq(1)
    end

    it "seeds response_schema with the inferred schema" do
      expect { service.sync(limit: 10) }
        .to change { endpoint.reload.response_schema }.from({})

      expect(endpoint.response_schema).to eq(
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => {
            "id" => { "type" => "integer" },
            "label" => { "type" => "string" }
          }
        }
      )
    end
  end

  # ===========================================================================
  # #sync — busy/blocked/errored samples are skips, not hard errors.
  # ===========================================================================
  describe "#sync when a sample fetch does not succeed" do
    let!(:endpoint) do
      create(:ai_data_source_endpoint, data_source: data_source, track_schema: true)
    end

    it "skips a throttled/blocked/errored sample without adding a hard error" do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(unsuccessful_envelope(message: "429 Too Many Requests"))
      # No version is recorded for a sample that produced no usable records.
      expect_any_instance_of(Ai::DataSources::SchemaDriftService).not_to receive(:record_version!)

      result = service.sync(limit: 10)

      expect(result[:synced]).to eq(0)
      expect(result[:errors]).to eq([])
    end

    it "skips (does not error) when the fetch raises mid-sample" do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_raise(StandardError, "connection reset")
      expect_any_instance_of(Ai::DataSources::SchemaDriftService).not_to receive(:record_version!)

      result = service.sync(limit: 10)

      expect(result[:synced]).to eq(0)
      expect(result[:errors]).to eq([])
    end

    it "skips when the envelope is successful but carries no array payload" do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope(data: { "not" => "an array" }))
      expect_any_instance_of(Ai::DataSources::SchemaDriftService).not_to receive(:record_version!)

      result = service.sync(limit: 10)

      expect(result[:synced]).to eq(0)
      expect(result[:errors]).to eq([])
    end

    it "does NOT seed response_schema when the sample is skipped" do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(unsuccessful_envelope)

      expect { service.sync(limit: 10) }
        .not_to(change { endpoint.reload.response_schema })
    end
  end

  # ===========================================================================
  # #sync — per-endpoint error isolation across a batch.
  #
  # A failure that is NOT a clean skip (record_version! itself raising) is
  # collected into errors[] and must not abort sibling endpoints.
  # ===========================================================================
  describe "#sync per-endpoint error isolation" do
    let!(:endpoint_a) do
      create(:ai_data_source_endpoint, :with_schema, data_source: data_source, track_schema: true)
    end
    let!(:endpoint_b) do
      create(:ai_data_source_endpoint, :with_schema, data_source: data_source, track_schema: true)
    end

    before do
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope)
      # record_version! raises for endpoint_a only; endpoint_b records cleanly.
      allow_any_instance_of(Ai::DataSources::SchemaDriftService).to receive(:record_version!) do |_svc, endpoint, _schema|
        raise StandardError, "drift boom" if endpoint.id == endpoint_a.id
      end
    end

    it "isolates the raised error, continues the batch, and populates errors[]" do
      result = service.sync(limit: 10)

      expect(result[:synced]).to eq(1) # endpoint_b still recorded
      expect(result[:errors].size).to eq(1)
      expect(result[:errors].first[:endpoint_id]).to eq(endpoint_a.id)
      expect(result[:errors].first[:error]).to eq("drift boom")
    end
  end

  # ===========================================================================
  # #sync — due selection: limit, active scoping, account scoping.
  # ===========================================================================
  describe "#sync due selection and scoping" do
    it "respects the limit argument" do
      3.times do
        create(:ai_data_source_endpoint, data_source: data_source, track_schema: true)
      end
      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope)

      result = service.sync(limit: 2)
      expect(result[:synced]).to eq(2)
    end

    it "scopes to active sources only (skips endpoints on an inactive source)" do
      inactive_source = create(:ai_data_source, :inactive, account: account)
      create(:ai_data_source_endpoint, data_source: inactive_source, track_schema: true)

      # The fetch layer must NOT run for an endpoint on an inactive source.
      expect_any_instance_of(Ai::DataSources::QueryService).not_to receive(:call)

      result = service.sync(limit: 10)
      expect(result[:synced]).to eq(0)
    end

    it "does NOT select an endpoint that already has a baseline and opted out of tracking" do
      # track_schema false + non-blank response_schema (:with_schema) -> not due.
      create(:ai_data_source_endpoint, :with_schema,
             data_source: data_source, track_schema: false)
      expect_any_instance_of(Ai::DataSources::QueryService).not_to receive(:call)

      result = service.sync(limit: 10)
      expect(result[:synced]).to eq(0)
    end

    it "scopes to the service account when one is supplied" do
      other_account = create(:account)
      other_source = create(:ai_data_source, account: other_account)
      create(:ai_data_source_endpoint, data_source: other_source, track_schema: true)

      # In-scope due endpoint so the batch has exactly one candidate.
      create(:ai_data_source_endpoint, data_source: data_source, track_schema: true)

      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope)

      result = service.sync(limit: 10)
      expect(result[:synced]).to eq(1) # only the in-account endpoint
    end

    it "sweeps across accounts when no account is supplied" do
      other_account = create(:account)
      other_source = create(:ai_data_source, account: other_account)
      create(:ai_data_source_endpoint, data_source: other_source, track_schema: true)
      create(:ai_data_source_endpoint, data_source: data_source, track_schema: true)

      allow_any_instance_of(Ai::DataSources::QueryService)
        .to receive(:call).and_return(fetch_envelope)

      result = described_class.new(nil).sync(limit: 10)
      expect(result[:synced]).to eq(2)
    end
  end
end
