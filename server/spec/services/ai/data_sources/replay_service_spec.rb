# frozen_string_literal: true

require "rails_helper"

# Forensic replay of a recorded Ai::DataSourceQuery audit row.
#
# ReplayService reconstructs a FetchEnvelope-shaped view of a PAST query from its
# already-redacted audit row WITHOUT ever touching the network. These specs lock
# down the security-critical invariants:
#
#   * account scoping (no cross-tenant replay),
#   * the NEVER-fetch guarantee (QueryService is never invoked),
#   * payload recovery is gated on (a) supplied params whose digest matches the
#     recorded params_hash, (b) a present cache entry, AND (c) the governance
#     AUTHORIZE gate passing for the CURRENT requester,
#   * recovered payloads are RE-MASKED for the current requester before return,
#   * an authorize DENY withholds the cached body entirely (data: []), even when
#     the cache entry exists.
#
# External collaborators are stubbed — no network, no Redis, no embeddings.
RSpec.describe Ai::DataSources::ReplayService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:data_source) do
    create(:ai_data_source, account: account, slug: "weather-noaa", name: "NOAA Weather")
  end
  let(:endpoint) do
    create(:ai_data_source_endpoint, data_source: data_source, name: "observations")
  end

  let(:service) { described_class.new(account: account, agent: nil) }

  # Original request params for the recorded fetch. The recorded params_hash is the
  # SHA256 the QueryService computed from these; payload recovery only runs when the
  # caller supplies params whose digest matches.
  let(:original_params) { { "station" => "KSFO", "limit" => 10 } }

  # Recompute the params digest EXACTLY as the service (and QueryService) does:
  # deep-sorted canonical JSON, SHA256, first 64 hex chars.
  def params_digest(params)
    deep_sorted = deep_sort(params)
    Digest::SHA256.hexdigest(deep_sorted.to_json)[0, 64]
  end

  def deep_sort(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_sort(v) }.sort.to_h
    when Array then obj.map { |v| deep_sort(v) }
    else obj
    end
  end

  # Build a recorded audit row directly (no factory exists for the query model).
  # Mirrors what QueryService persists at fetch time: an already-redacted snapshot
  # carrying the params_hash, response_sha256, served_stage, redacted_url, and
  # forensic metadata — never the body.
  def record_query(overrides = {})
    Ai::DataSourceQuery.create!(
      {
        account_id: account.id,
        ai_data_source_id: data_source.id,
        ai_data_source_endpoint_id: endpoint.id,
        correlation_id: "corr-#{SecureRandom.hex(4)}",
        status: "success",
        http_status: 200,
        cached: false,
        served_stage: "fresh",
        response_sha256: "a" * 64,
        params_hash: params_digest(original_params),
        redacted_url: "https://api.example.com/v1/stations/[REDACTED]/observations",
        policy_decision: "allow",
        schema_valid: true,
        rows_returned: 2,
        bytes_in: 512,
        masking_applied: false,
        metadata: {
          "anomalies" => ["slow_response"],
          "redacted_params" => { "station" => "[REDACTED]" },
          "redacted_response_snippet" => "{\"city\":\"[REDACTED]\"}",
          "audit_chain" => "chain-anchor-xyz",
          "charset" => "utf-8"
        }
      }.merge(overrides)
    )
  end

  # A GovernanceService double standing in for BOTH the authorize gate and the
  # re-mask step. allowed/masking behaviour is parameterised per example.
  def stub_governance(allowed:, masked_records: nil, masked_count: 1, masking_applied: true)
    gov = instance_double(Ai::DataSources::GovernanceService)
    allow(gov).to receive(:authorize).and_return(
      { allowed: allowed, reason: allowed ? nil : "policy_deny", enforcement: allowed ? nil : "block" }
    )
    allow(gov).to receive(:mask_records) do |records|
      {
        records: masked_records.nil? ? records : masked_records,
        masking_applied: masking_applied,
        masked_count: masked_count
      }
    end
    allow(Ai::DataSources::GovernanceService).to receive(:new).and_return(gov)
    gov
  end

  describe "#replay — guard clauses" do
    it "returns replay_not_found when no query reference is supplied" do
      result = service.replay(nil)

      expect(result[:success]).to be(false)
      expect(result[:status]).to eq("replay_not_found")
      expect(result[:replayed]).to be(false)
    end

    it "returns replay_not_found for a blank string reference" do
      result = service.replay("")

      expect(result[:status]).to eq("replay_not_found")
      expect(result[:replayed]).to be(false)
    end

    it "returns replay_not_found when no account context is present" do
      result = described_class.new(account: nil).replay("anything")

      expect(result[:success]).to be(false)
      expect(result[:status]).to eq("replay_not_found")
      expect(result[:error]).to match(/account context/i)
    end
  end

  describe "#replay — resolution (account-scoped; id OR correlation_id)" do
    it "resolves a recorded query by its UUID id" do
      query = record_query

      result = service.replay(query.id)

      expect(result[:success]).to be(true)
      expect(result[:status]).to eq("replayed")
      expect(result[:replayed_from_query_id]).to eq(query.id)
    end

    it "resolves a recorded query by its correlation_id" do
      query = record_query(correlation_id: "corr-lookup-me")

      result = service.replay("corr-lookup-me")

      expect(result[:success]).to be(true)
      expect(result[:status]).to eq("replayed")
      expect(result[:replayed_from_query_id]).to eq(query.id)
      expect(result[:correlation_id]).to eq("corr-lookup-me")
    end

    it "returns the most recent row when a correlation_id is duplicated" do
      record_query(correlation_id: "corr-dup", created_at: 2.hours.ago)
      newer = record_query(correlation_id: "corr-dup", created_at: 1.minute.ago)

      result = service.replay("corr-dup")

      expect(result[:replayed_from_query_id]).to eq(newer.id)
    end

    it "returns replay_not_found for an unknown id (well-formed UUID, no row)" do
      result = service.replay(SecureRandom.uuid)

      expect(result[:status]).to eq("replay_not_found")
      expect(result[:replayed]).to be(false)
    end

    it "does NOT resolve another account's query by id (cross-tenant isolation)" do
      foreign_source = create(:ai_data_source, account: other_account)
      foreign = Ai::DataSourceQuery.create!(
        account_id: other_account.id,
        ai_data_source_id: foreign_source.id,
        status: "success",
        correlation_id: "corr-foreign"
      )

      result = service.replay(foreign.id)

      expect(result[:success]).to be(false)
      expect(result[:status]).to eq("replay_not_found")
    end

    it "does NOT resolve another account's query by correlation_id (cross-tenant isolation)" do
      foreign_source = create(:ai_data_source, account: other_account)
      Ai::DataSourceQuery.create!(
        account_id: other_account.id,
        ai_data_source_id: foreign_source.id,
        status: "success",
        correlation_id: "corr-foreign-only"
      )

      result = service.replay("corr-foreign-only")

      expect(result[:status]).to eq("replay_not_found")
    end
  end

  describe "#replay — successful reconstruction (no payload recovery)" do
    let!(:query) { record_query }

    it "returns status replayed with replayed: true" do
      result = service.replay(query.id)

      expect(result[:success]).to be(true)
      expect(result[:status]).to eq("replayed")
      expect(result[:replayed]).to be(true)
    end

    it "reports zero duration and zero bytes — a replay does no work" do
      result = service.replay(query.id)

      expect(result[:duration_ms]).to eq(0)
      expect(result[:bytes]).to eq(0)
    end

    it "surfaces the recorded timestamp as an ISO8601 recorded_at" do
      result = service.replay(query.id)

      expect(result[:recorded_at]).to eq(query.created_at.utc.iso8601)
      expect(result[:provenance][:recorded_at]).to eq(query.created_at.utc.iso8601)
    end

    it "rebuilds provenance from the recorded (redacted) row, not a live fetch" do
      result = service.replay(query.id)
      prov = result[:provenance]

      expect(prov[:replayed]).to be(true)
      expect(prov[:slug]).to eq("weather-noaa")
      expect(prov[:original_status]).to eq("success")
      expect(prov[:http_status]).to eq(200)
      expect(prov[:response_sha256]).to eq("a" * 64)
      expect(prov[:served_stage]).to eq("fresh")
      expect(prov[:source_url]).to eq(query.redacted_url)
      expect(prov[:policy_decision]).to eq("allow")
      expect(prov[:schema_valid]).to be(true)
      expect(prov[:rows_returned]).to eq(2)
    end

    it "surfaces forensic linkage off the recorded metadata (anomalies, audit_chain, redacted copies)" do
      result = service.replay(query.id)
      prov = result[:provenance]

      expect(prov[:anomalies]).to eq(["slow_response"])
      expect(prov[:audit_chain]).to eq("chain-anchor-xyz")
      expect(prov[:redacted_params]).to eq({ "station" => "[REDACTED]" })
      expect(prov[:redacted_response_snippet]).to eq("{\"city\":\"[REDACTED]\"}")
      expect(prov[:charset]).to eq("utf-8")
    end

    it "NEVER performs an upstream fetch — QueryService is not invoked" do
      expect(Ai::DataSources::QueryService).not_to receive(:new)

      service.replay(query.id)
    end

    it "returns data: [] with the payload_not_cached note when no params are supplied" do
      result = service.replay(query.id) # params: nil

      expect(result[:data]).to eq([])
      expect(result[:provenance][:note]).to eq("payload_not_cached")
      expect(result[:provenance][:payload_not_cached]).to be(true)
    end

    it "does not read the response cache when no params are supplied" do
      expect(Ai::DataSources::ResponseCacheService).not_to receive(:read)

      service.replay(query.id)
    end
  end

  describe "#replay — payload recovery (params match + cache hit + authorize allow)" do
    let!(:query) { record_query }
    let(:raw_records) { [{ "city" => "San Francisco", "temp" => "60" }] }
    let(:remasked_records) { [{ "city" => "[REDACTED]", "temp" => "60" }] }

    it "returns the RE-MASKED cached body for the current requester" do
      stub_governance(allowed: true, masked_records: remasked_records, masked_count: 1)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return(
        { "data" => raw_records, "provenance" => { "from_cache" => true } }
      )

      result = service.replay(query.id, params: original_params)

      expect(result[:success]).to be(true)
      expect(result[:status]).to eq("replayed")
      expect(result[:data]).to eq(remasked_records)
      expect(result[:provenance][:masking_applied]).to be(true)
      expect(result[:provenance][:masked_field_count]).to eq(1)
      expect(result[:provenance][:note]).to be_nil
    end

    it "calls GovernanceService#mask_records with the raw cached records" do
      gov = stub_governance(allowed: true, masked_records: remasked_records)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return(
        { "data" => raw_records }
      )

      service.replay(query.id, params: original_params)

      expect(gov).to have_received(:mask_records).with(raw_records)
    end

    it "reads the cache only AFTER the authorize gate passes" do
      gov = stub_governance(allowed: true, masked_records: remasked_records)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return(
        { "data" => raw_records }
      )

      service.replay(query.id, params: original_params)

      expect(gov).to have_received(:authorize)
      expect(Ai::DataSources::ResponseCacheService).to have_received(:read).with(
        data_source: data_source, endpoint: endpoint, params: original_params
      )
    end

    it "still NEVER performs an upstream fetch during recovery" do
      stub_governance(allowed: true, masked_records: remasked_records)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return({ "data" => raw_records })

      expect(Ai::DataSources::QueryService).not_to receive(:new)

      service.replay(query.id, params: original_params)
    end

    it "recovers a bare-array cache payload (no data wrapper)" do
      stub_governance(allowed: true, masked_records: remasked_records, masked_count: 1)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return(raw_records)

      result = service.replay(query.id, params: original_params)

      expect(result[:data]).to eq(remasked_records)
    end
  end

  describe "#replay — SECURITY: authorize DENY withholds the cached body" do
    let!(:query) { record_query }
    let(:raw_records) { [{ "city" => "San Francisco", "temp" => "60" }] }

    it "returns data: [] with payload_not_cached even though the cache entry exists" do
      stub_governance(allowed: false)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return(
        { "data" => raw_records }
      )

      result = service.replay(query.id, params: original_params)

      # The forensic envelope still succeeds, but the body is WITHHELD.
      expect(result[:success]).to be(true)
      expect(result[:status]).to eq("replayed")
      expect(result[:data]).to eq([])
      expect(result[:provenance][:note]).to eq("payload_not_cached")
      expect(result[:provenance][:payload_not_cached]).to be(true)
    end

    it "does NOT read the cache when authorize denies (gate runs before the read)" do
      stub_governance(allowed: false)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return({ "data" => raw_records })

      service.replay(query.id, params: original_params)

      expect(Ai::DataSources::ResponseCacheService).not_to have_received(:read)
    end

    it "does NOT re-mask any records when authorize denies" do
      gov = stub_governance(allowed: false)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return({ "data" => raw_records })

      service.replay(query.id, params: original_params)

      expect(gov).not_to have_received(:mask_records)
    end
  end

  describe "#replay — payload-not-cached paths (recovery refused or empty)" do
    let!(:query) { record_query }

    it "withholds the body when supplied params do NOT match the recorded params_hash" do
      gov = stub_governance(allowed: true)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return({ "data" => [{ "x" => 1 }] })

      result = service.replay(query.id, params: { "station" => "DIFFERENT" })

      expect(result[:data]).to eq([])
      expect(result[:provenance][:note]).to eq("payload_not_cached")
      # Hash mismatch is detected after the authorize gate but before the cache read.
      expect(Ai::DataSources::ResponseCacheService).not_to have_received(:read)
      expect(gov).not_to have_received(:mask_records)
    end

    it "refuses recovery when the recorded row has no params_hash" do
      no_hash = record_query(params_hash: nil)
      stub_governance(allowed: true)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read)

      result = service.replay(no_hash.id, params: original_params)

      expect(result[:data]).to eq([])
      expect(result[:provenance][:note]).to eq("payload_not_cached")
      expect(Ai::DataSources::ResponseCacheService).not_to have_received(:read)
    end

    it "returns payload_not_cached on a cache miss (entry evicted)" do
      stub_governance(allowed: true)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return(nil)

      result = service.replay(query.id, params: original_params)

      expect(result[:data]).to eq([])
      expect(result[:provenance][:note]).to eq("payload_not_cached")
    end

    it "returns payload_not_cached when the cached entry has no records array" do
      stub_governance(allowed: true)
      allow(Ai::DataSources::ResponseCacheService).to receive(:read).and_return({ "provenance" => {} })

      result = service.replay(query.id, params: original_params)

      expect(result[:data]).to eq([])
      expect(result[:provenance][:note]).to eq("payload_not_cached")
    end
  end

  describe "#replay — resilience" do
    it "degrades to a safe replay_error result when reconstruction raises unexpectedly" do
      query = record_query
      # Force an unexpected fault DURING reconstruction (after the row resolves).
      # build_provenance is not individually rescued, so the fault propagates to the
      # top-level rescue, which must degrade to a safe error result rather than raise.
      allow(service).to receive(:build_provenance).and_raise(StandardError, "boom")

      result = service.replay(query.id)

      expect(result[:success]).to be(false)
      expect(result[:status]).to eq("replay_error")
      expect(result[:replayed]).to be(false)
      expect(result[:error]).to match(/replay failed/i)
    end

    it "degrades to replay_not_found (not a raise) when query resolution itself faults" do
      # resolve_query rescues internally and returns nil, so a resolution fault must
      # surface as a clean not-found rather than an error or an exception.
      allow(Ai::DataSourceQuery).to receive(:for_account).and_raise(StandardError, "db down")

      result = service.replay(SecureRandom.uuid)

      expect(result[:success]).to be(false)
      expect(result[:status]).to eq("replay_not_found")
      expect(result[:replayed]).to be(false)
    end
  end
end
