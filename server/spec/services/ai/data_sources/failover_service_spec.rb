# frozen_string_literal: true

require "rails_helper"

# Phase 4b-3c ordered FAILOVER across equivalent data-source endpoints.
#
# Ai::DataSources::FailoverService#query tries an ORDERED list of
# { data_source:, endpoint: } targets via a full governed
# Ai::DataSources::QueryService#call per attempt, returning the FIRST success
# envelope (no further targets touched) or, when all fail, the LAST failure
# envelope — in both cases stamping failover provenance
# (failover_used / failover_attempts / failover_source). It adds NO fetching of
# its own, catches a per-attempt exception as a failure, and NEVER sleeps.
#
# HERMETIC: QueryService#call is STUBBED to return canned FetchEnvelopes routed
# per target (disambiguated by the QueryService instance's @data_source), so no
# network / embeddings / Redis are hit; the DataSource after_commit KG sync is
# stubbed on every factory create; PiiRedactionService is stubbed to a
# pass-through so the redacted-exception path stays deterministic without the
# detection backend.
RSpec.describe Ai::DataSources::FailoverService, type: :service do
  let(:account) { create(:account) }

  # Primary first, then mirror, then a third fallback — an ordered preference
  # list. Each is a real account-scoped data_source + endpoint pair so
  # target_slug resolves a genuine auto-generated slug for provenance.
  let(:primary) { create(:ai_data_source, account: account, name: "Primary Source") }
  let(:mirror)  { create(:ai_data_source, account: account, name: "Mirror Source") }
  let(:tertiary) { create(:ai_data_source, account: account, name: "Tertiary Source") }

  let(:primary_endpoint)  { create(:ai_data_source_endpoint, data_source: primary) }
  let(:mirror_endpoint)   { create(:ai_data_source_endpoint, data_source: mirror) }
  let(:tertiary_endpoint) { create(:ai_data_source_endpoint, data_source: tertiary) }

  let(:primary_target) { { data_source: primary, endpoint: primary_endpoint } }
  let(:mirror_target)  { { data_source: mirror, endpoint: mirror_endpoint } }
  let(:tertiary_target) { { data_source: tertiary, endpoint: tertiary_endpoint } }

  subject(:service) { described_class.new(account: account) }

  # A successful FetchEnvelope. Provenance carries a slug so we can prove the
  # service stamps failover keys WITHOUT clobbering pre-existing provenance.
  def success_envelope(slug:, data: [{ "city" => "NYC", "temp" => 72 }])
    {
      success: true,
      data: data,
      provenance: { slug: slug, from_cache: false },
      status: "success",
      duration_ms: 12,
      bytes: 128,
      error: nil
    }
  end

  # A failure FetchEnvelope (error / timeout / rate_limited / blocked all share
  # success:false). status is tunable so we can prove the LAST failure's body is
  # preserved verbatim under the failover bookkeeping.
  def failure_envelope(slug:, status: "error", message: "upstream 500")
    {
      success: false,
      data: [],
      provenance: { slug: slug },
      status: status,
      duration_ms: 5,
      bytes: 0,
      error: message
    }
  end

  # Route a canned envelope per target by inspecting the QueryService instance's
  # @data_source id. Any source not in the map raises (an unexpected target was
  # tried), which surfaces ordering / early-stop bugs loudly.
  def stub_query_per_source(map)
    allow_any_instance_of(Ai::DataSources::QueryService).to receive(:call) do |svc|
      ds = svc.instance_variable_get(:@data_source)
      raise "unexpected target queried: #{ds&.id}" unless map.key?(ds.id)

      entry = map[ds.id]
      entry.respond_to?(:call) ? entry.call : entry
    end
  end

  before do
    # DataSource after_commit KG sync would reach embeddings/Redis when the
    # factory persists a source under DatabaseCleaner :deletion.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)

    # The redacted-exception path runs PII redaction over the caught message;
    # stub to a pass-through so it is deterministic and backend-free.
    allow_any_instance_of(Ai::Security::PiiRedactionService).to receive(:redact) do |_svc, text:, **_kw|
      { redacted_text: text, detections_count: 0, types_found: [] }
    end
  end

  # --------------------------------------------------------------------------
  # Primary success — stop immediately, no failover.
  # --------------------------------------------------------------------------
  describe "primary success on the first attempt" do
    before { stub_query_per_source(primary.id => success_envelope(slug: primary.slug)) }

    it "returns the primary's success envelope with failover_used:false" do
      result = service.query([primary_target, mirror_target])

      expect(result[:success]).to be(true)
      expect(result[:provenance][:failover_used]).to be(false)
    end

    it "records exactly one attempt" do
      result = service.query([primary_target, mirror_target])

      expect(result[:provenance][:failover_attempts]).to eq(1)
    end

    it "stamps the winning source slug as the primary" do
      result = service.query([primary_target, mirror_target])

      expect(result[:provenance][:failover_source]).to eq(primary.slug)
    end

    it "never touches any mirror after the primary wins" do
      # The per-source stub raises on any source other than the primary; if a
      # mirror were queried, this expectation would fail with that raise.
      expect { service.query([primary_target, mirror_target, tertiary_target]) }
        .not_to raise_error
    end

    it "preserves the winning envelope's pre-existing provenance" do
      result = service.query([primary_target, mirror_target])

      # from_cache survives; failover keys are merged in alongside it.
      expect(result[:provenance][:from_cache]).to be(false)
      expect(result[:provenance][:slug]).to eq(primary.slug)
    end
  end

  # --------------------------------------------------------------------------
  # Primary fails, mirror succeeds — failover engaged.
  # --------------------------------------------------------------------------
  describe "primary fails then a mirror succeeds" do
    before do
      stub_query_per_source(
        primary.id => failure_envelope(slug: primary.slug, status: "timeout"),
        mirror.id => success_envelope(slug: mirror.slug)
      )
    end

    it "returns the mirror's success envelope" do
      result = service.query([primary_target, mirror_target])

      expect(result[:success]).to be(true)
      expect(result[:data]).to eq([{ "city" => "NYC", "temp" => 72 }])
    end

    it "flags failover_used:true after the primary missed" do
      result = service.query([primary_target, mirror_target])

      expect(result[:provenance][:failover_used]).to be(true)
    end

    it "records two attempts (primary + mirror)" do
      result = service.query([primary_target, mirror_target])

      expect(result[:provenance][:failover_attempts]).to eq(2)
    end

    it "names the mirror as the winning failover_source" do
      result = service.query([primary_target, mirror_target])

      expect(result[:provenance][:failover_source]).to eq(mirror.slug)
    end
  end

  # --------------------------------------------------------------------------
  # All targets fail — return the LAST failure envelope, annotated.
  # --------------------------------------------------------------------------
  describe "every target fails" do
    before do
      stub_query_per_source(
        primary.id => failure_envelope(slug: primary.slug, status: "error", message: "primary down"),
        mirror.id => failure_envelope(slug: mirror.slug, status: "rate_limited", message: "mirror 429"),
        tertiary.id => failure_envelope(slug: tertiary.slug, status: "timeout", message: "tertiary timed out")
      )
    end

    it "returns success:false" do
      result = service.query([primary_target, mirror_target, tertiary_target])

      expect(result[:success]).to be(false)
    end

    it "surfaces the LAST failure envelope's body verbatim" do
      result = service.query([primary_target, mirror_target, tertiary_target])

      expect(result[:status]).to eq("timeout")
      expect(result[:error]).to eq("tertiary timed out")
    end

    it "sets failover_attempts to the full count of targets tried" do
      result = service.query([primary_target, mirror_target, tertiary_target])

      expect(result[:provenance][:failover_attempts]).to eq(3)
    end

    it "leaves failover_source nil because nothing won" do
      result = service.query([primary_target, mirror_target, tertiary_target])

      expect(result[:provenance][:failover_source]).to be_nil
    end

    it "marks failover_used:true since more than one target was attempted" do
      result = service.query([primary_target, mirror_target, tertiary_target])

      expect(result[:provenance][:failover_used]).to be(true)
    end
  end

  # --------------------------------------------------------------------------
  # A raised exception in one attempt is caught as a failure; next target runs.
  # --------------------------------------------------------------------------
  describe "an exception during one attempt" do
    it "is caught and counts as a failure, then the next target is tried" do
      stub_query_per_source(
        primary.id => -> { raise StandardError, "boom in primary fetch" },
        mirror.id => success_envelope(slug: mirror.slug)
      )

      result = service.query([primary_target, mirror_target])

      expect(result[:success]).to be(true)
      expect(result[:provenance][:failover_source]).to eq(mirror.slug)
      expect(result[:provenance][:failover_attempts]).to eq(2)
    end

    it "returns a synthesized failure when the only target raises" do
      stub_query_per_source(primary.id => -> { raise StandardError, "boom" })

      result = service.query([primary_target])

      expect(result[:success]).to be(false)
      expect(result[:provenance][:failover_attempts]).to eq(1)
      expect(result[:provenance][:failover_source]).to be_nil
    end

    it "redacts the raised message into the synthesized failure error" do
      stub_query_per_source(primary.id => -> { raise StandardError, "secret-token-leak" })

      result = service.query([primary_target])

      # PiiRedactionService is stubbed pass-through, so the (redacted) message
      # flows through; the synthesized failure carries the redaction marker.
      expect(result[:error]).to eq("secret-token-leak")
      expect(result[:provenance][:failover_synthesized]).to be(true)
    end
  end

  # --------------------------------------------------------------------------
  # Empty / blank target list — synthesized error envelope, nothing tried.
  # --------------------------------------------------------------------------
  describe "no targets to try" do
    it "returns a synthesized error envelope for an empty array" do
      expect_any_instance_of(Ai::DataSources::QueryService).not_to receive(:call)

      result = service.query([])

      expect(result[:success]).to be(false)
      expect(result[:status]).to eq("error")
    end

    it "stamps zero attempts and a nil source for an empty list" do
      result = service.query([])

      expect(result[:provenance][:failover_attempts]).to eq(0)
      expect(result[:provenance][:failover_used]).to be(false)
      expect(result[:provenance][:failover_source]).to be_nil
    end

    it "treats nil targets as an empty list without raising" do
      result = service.query(nil)

      expect(result[:success]).to be(false)
      expect(result[:provenance][:failover_attempts]).to eq(0)
    end

    it "drops malformed targets (missing endpoint) before attempting" do
      # Only the well-formed primary target survives normalization, so exactly
      # one attempt runs even though two entries were supplied.
      stub_query_per_source(primary.id => success_envelope(slug: primary.slug))

      result = service.query([{ data_source: primary }, primary_target])

      expect(result[:success]).to be(true)
      expect(result[:provenance][:failover_attempts]).to eq(1)
    end
  end

  # --------------------------------------------------------------------------
  # Cross-cutting: no sleep, params pass-through, provenance keys always present.
  # --------------------------------------------------------------------------
  describe "resilience and pass-through" do
    it "never calls Kernel#sleep between attempts" do
      stub_query_per_source(
        primary.id => failure_envelope(slug: primary.slug),
        mirror.id => success_envelope(slug: mirror.slug)
      )

      # Scoped to the service under test, NOT `expect_any_instance_of(Object)`.
      # That form matches every object in the process, so it also catches
      # background threads from unrelated subsystems: the two-machine parity run
      # failed here on Mcp::TransportService's message-cleanup thread
      # (transport_service.rb:393) doing its own `sleep 5` while this example
      # happened to be running. Timing-dependent, so it passed on one box and
      # failed on the other, and would eventually flake on either.
      expect(service).not_to receive(:sleep)
      service.query([primary_target, mirror_target])
    end

    it "forwards params verbatim to each QueryService attempt" do
      captured = []
      allow_any_instance_of(Ai::DataSources::QueryService).to receive(:call) do |svc|
        captured << svc.instance_variable_get(:@params)
        failure_envelope(slug: "x")
      end

      service.query([primary_target, mirror_target], params: { "limit" => "5" })

      expect(captured).to all(eq("limit" => "5"))
    end

    it "always stamps all three failover keys on the returned provenance" do
      stub_query_per_source(primary.id => success_envelope(slug: primary.slug))

      result = service.query([primary_target])

      expect(result[:provenance].keys).to include(
        :failover_used, :failover_attempts, :failover_source
      )
    end
  end
end
