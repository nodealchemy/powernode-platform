# frozen_string_literal: true

require "rails_helper"

# ContractService aggregates a single "is the data contract met?" verdict for a
# fetch by combining the three Phase 2b signals carried on a QueryService
# FetchEnvelope and its endpoint:
#   - schema_valid    (envelope provenance)
#   - quality_passed  (envelope/provenance, else a FRESH QualityService run)
#   - within_sla      (provenance cache_age_seconds vs endpoint.sla_max_age_seconds)
#
# A nil signal is "not asserted" (no violation); met = all asserted signals true,
# so a contract with no assertions is vacuously met.
#
# These specs are hermetic: no network and no inline quality run unless we ask
# for one. The data-source -> knowledge-graph after_commit sync is stubbed so
# factory creates don't reach Redis/embeddings under DatabaseCleaner :deletion.
RSpec.describe Ai::DataSources::ContractService, type: :service do
  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  let(:data_source) { create(:ai_data_source) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }
  let(:service) { described_class.new }

  # Build a FetchEnvelope-shaped Hash. Only the keys ContractService reads matter:
  # top-level :quality_passed / :data, and provenance :schema_valid /
  # :quality_passed / :cache_age_seconds.
  def envelope(provenance: {}, **top)
    { data: [], provenance: provenance }.merge(top)
  end

  describe "#validate — met when all asserted signals are true" do
    it "is met with all three signals true and no violations" do
      env = envelope(
        quality_passed: true,
        provenance: { schema_valid: true, cache_age_seconds: 10 }
      )
      endpoint.update!(sla_max_age_seconds: 60)

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result).to include(
        met: true,
        schema_valid: true,
        quality_passed: true,
        within_sla: true
      )
      expect(result[:violations]).to be_empty
    end

    it "is vacuously met when nothing is asserted (all signals nil)" do
      # No schema_valid in provenance, no quality verdict anywhere, no SLA, and
      # no endpoint records to run a fresh quality check that would assert.
      result = service.validate(
        data_source: data_source,
        endpoint: endpoint,
        envelope: { provenance: {} }
      )

      expect(result[:schema_valid]).to be_nil
      expect(result[:within_sla]).to be(true) # unset SLA cannot be violated
      expect(result[:violations]).to be_empty
      expect(result[:met]).to be(true)
    end
  end

  describe "#validate — schema_valid signal" do
    it "reads schema_valid=true from provenance" do
      env = envelope(provenance: { schema_valid: true })
      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:schema_valid]).to be(true)
      expect(result[:violations]).not_to include("schema_invalid")
    end

    it "flags schema_invalid and is not met when schema_valid is false" do
      env = envelope(provenance: { schema_valid: false })
      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:schema_valid]).to be(false)
      expect(result[:violations]).to include("schema_invalid")
      expect(result[:met]).to be(false)
    end

    it "leaves schema_valid nil (not asserted) when provenance omits it" do
      env = envelope(provenance: { cache_age_seconds: 1 })
      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:schema_valid]).to be_nil
      expect(result[:violations]).not_to include("schema_invalid")
    end
  end

  describe "#validate — within_sla from cache_age vs sla_max_age_seconds" do
    it "is within_sla when cache age is at or under the SLA budget" do
      endpoint.update!(sla_max_age_seconds: 120)
      env = envelope(provenance: { cache_age_seconds: 120 }) # boundary: <= holds

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:within_sla]).to be(true)
      expect(result[:violations]).not_to include("sla_exceeded")
    end

    it "flags sla_exceeded and is not met when cache age is over the budget" do
      endpoint.update!(sla_max_age_seconds: 60)
      env = envelope(provenance: { cache_age_seconds: 61 })

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:within_sla]).to be(false)
      expect(result[:violations]).to include("sla_exceeded")
      expect(result[:met]).to be(false)
    end

    it "is within_sla=true when no SLA is configured (unset budget cannot be exceeded)" do
      endpoint.update!(sla_max_age_seconds: nil)
      env = envelope(provenance: { cache_age_seconds: 99_999 })

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:within_sla]).to be(true)
      expect(result[:violations]).not_to include("sla_exceeded")
    end

    it "leaves within_sla nil when an SLA is set but the cache age is unknown" do
      endpoint.update!(sla_max_age_seconds: 60)
      env = envelope(provenance: {}) # no cache_age_seconds

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:within_sla]).to be_nil
      expect(result[:violations]).not_to include("sla_exceeded")
    end
  end

  describe "#validate — quality_passed signal" do
    it "reads quality_passed off the envelope top level when present" do
      env = envelope(quality_passed: true, provenance: { quality_passed: false })

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      # Top-level verdict wins over provenance.
      expect(result[:quality_passed]).to be(true)
    end

    it "falls back to the provenance quality verdict when the envelope omits it" do
      env = envelope(provenance: { quality_passed: false })

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:quality_passed]).to be(false)
      expect(result[:violations]).to include("quality_failed")
      expect(result[:met]).to be(false)
    end

    it "runs a FRESH QualityService check over envelope :data when no verdict is carried" do
      # No quality_passed anywhere -> ContractService runs QualityService on the
      # envelope's records. With no configured expectations the built-in WARN
      # defaults pass (passed=true requires no ERROR-severity failure).
      env = { data: [{ "city" => "NYC" }, { "city" => "LA" }], provenance: {} }

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:quality_passed]).to be(true)
      expect(result[:violations]).not_to include("quality_failed")
    end

    it "fails the fresh quality run when an ERROR-severity expectation is violated" do
      create(
        :ai_data_source_expectation,
        endpoint: endpoint,
        rule_type: "min_records",
        severity: "error",
        config: { "min" => 5 }
      )
      env = { data: [{ "a" => 1 }], provenance: {} } # only 1 record < 5

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:quality_passed]).to be(false)
      expect(result[:violations]).to include("quality_failed")
      expect(result[:met]).to be(false)
    end
  end

  describe "#validate — violations list" do
    it "accumulates every failing signal" do
      endpoint.update!(sla_max_age_seconds: 30)
      env = envelope(
        quality_passed: false,
        provenance: { schema_valid: false, quality_passed: false, cache_age_seconds: 90 }
      )

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result[:violations]).to contain_exactly("schema_invalid", "quality_failed", "sla_exceeded")
      expect(result[:met]).to be(false)
    end

    it "honours string-keyed envelope/provenance (indifferent access)" do
      endpoint.update!(sla_max_age_seconds: 60)
      env = {
        "data" => [],
        "quality_passed" => true,
        "provenance" => { "schema_valid" => true, "cache_age_seconds" => 5 }
      }

      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: env)

      expect(result).to include(met: true, schema_valid: true, quality_passed: true, within_sla: true)
    end

    it "tolerates a non-Hash envelope by treating it as empty" do
      result = service.validate(data_source: data_source, endpoint: endpoint, envelope: nil)

      expect(result[:schema_valid]).to be_nil
      expect(result[:within_sla]).to be(true) # no SLA on endpoint
      expect(result[:violations]).to be_empty
    end
  end

  describe "#validate — fresh quality run is nil-safe" do
    it "returns quality_passed nil when no endpoint is supplied and none is carried" do
      env = { data: [{ "a" => 1 }], provenance: {} }

      result = service.validate(data_source: data_source, endpoint: nil, envelope: env)

      expect(result[:quality_passed]).to be_nil
      expect(result[:violations]).not_to include("quality_failed")
    end
  end
end
