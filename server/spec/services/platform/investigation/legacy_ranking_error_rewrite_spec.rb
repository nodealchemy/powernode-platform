# frozen_string_literal: true

require "rails_helper"

# A6 review G2-3 — rows written in the old `evidence.errors.ranking` shape are
# migrated to `evidence.ranking`, never kept readable in both.
RSpec.describe Platform::Investigation::LegacyRankingErrorRewrite do
  let(:account) { create(:account) }
  let(:logger) { instance_double(Logger, warn: nil, info: nil) }

  before { allow(WorkerJobService).to receive(:enqueue_job) }

  # An investigation exactly as the pre-batch door left it: open, with the
  # failure as a bare string under errors.
  def component(ref)
    @components ||= {}
    @components[ref] ||= create(:platform_component_status, account: account, component_kind: "docker_host",
                                                            component_ref: ref,
                                                            verdict: Platform::ComponentStatus::DOWN,
                                                            conditions: [ { "type" => "Connected", "status" => false,
                                                                            "reason" => "ConnectionError",
                                                                            "severity" => "down" } ])
  end

  def legacy(ref, message = "ranker returned no usable hypotheses")
    investigation = Platform::InvestigationService.new(account: account)
                                                  .open!(component(ref), trigger: "operator")[:investigation]
    errors = (investigation.evidence["errors"] || {}).merge("ranking" => message)
    investigation.update_columns(evidence: investigation.evidence.merge("errors" => errors))
    investigation
  end

  describe ".auto_rewrite" do
    it "rewrites an open row into the new shape and concludes it on core's candidates" do
      row = legacy("host-1")

      outcome = described_class.auto_rewrite(logger: logger)

      expect(outcome.status).to eq(:rewritten)
      row.reload
      expect(row.evidence["errors"]).not_to have_key("ranking")
      expect(row.ranking_record).to include("state" => "failed", "reason" => "RankerUnusable", "retryable" => false)
      expect(row).to be_concluded
      expect(row.top_hypothesis["cause"]).to include("ConnectionError")
      expect(row.conclusion).to include("nothing was retrying it")
      expect(Platform::InvestigationService.new(account: account)
               .open!(component("host-1"), trigger: "down")[:opened]).to be(true)
    end

    it "drops the old key without a record when a later attempt ranked the row" do
      row = legacy("host-2")
      row.update_columns(status: Platform::Investigation::STATUS_COMPLETED,
                         agent_id: create(:ai_agent, account: account).id)

      described_class.auto_rewrite(logger: logger)

      row.reload
      expect(row.evidence["errors"]).not_to have_key("ranking")
      expect(row.ranking_record).to be_nil
    end

    it "leaves a row the new writer already recorded alone, apart from the old key" do
      row = legacy("host-3")
      current = { "state" => "failed", "reason" => "ProviderError", "retryable" => true, "attempts" => 1 }
      row.update_columns(evidence: row.evidence.merge("ranking" => current))

      described_class.auto_rewrite(logger: logger)

      row.reload
      expect(row.evidence["errors"]).not_to have_key("ranking")
      expect(row.ranking_record).to eq(current)
      expect(row).to be_open
    end

    it "changes NOTHING above the limit, and says how to proceed" do
      rows = Array.new(described_class::AUTO_LIMIT + 1) { |i| legacy("many-#{i}") }

      outcome = described_class.auto_rewrite(logger: logger)

      expect(outcome.status).to eq(:skipped)
      expect(logger).to have_received(:warn).with(include("CONFIRM=#{rows.size}"))
      expect(rows.map { |r| r.reload.evidence.dig("errors", "ranking") }).to all(be_present)
      expect(rows.map { |r| r.reload.open? }).to all(be(true))
    end

    it "acts at exactly the limit — the other arm" do
      Array.new(described_class::AUTO_LIMIT) { |i| legacy("few-#{i}") }

      expect(described_class.auto_rewrite(logger: logger).count).to eq(described_class::AUTO_LIMIT)
    end

    it "never raises, because live nodes apply pending migrations at boot" do
      allow(described_class).to receive(:matching_ids).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect(described_class.auto_rewrite(logger: logger).status).to eq(:error)
    end

    it "skips a row that fails and still rewrites the others" do
      bad = legacy("bad-1")
      good = legacy("good-1")
      allow(Platform::Investigation).to receive(:lock).and_wrap_original do |original|
        relation = original.call
        allow(relation).to receive(:find).and_wrap_original do |find, id|
          raise ActiveRecord::RecordNotFound, "gone" if id == bad.id

          find.call(id)
        end
        relation
      end

      outcome = described_class.auto_rewrite(logger: logger)

      expect(outcome.investigation_ids).to eq([ good.id ])
      expect(bad.reload.evidence.dig("errors", "ranking")).to be_present
      expect(logger).to have_received(:warn).with(include(bad.id))
    end
  end

  describe ".operator_run" do
    let(:io) { StringIO.new }

    before { Array.new(described_class::AUTO_LIMIT + 1) { |i| legacy("op-#{i}") } }

    it "changes nothing without CONFIRM" do
      expect(described_class.operator_run(confirm: nil, io: io, logger: logger).status).to eq(:unconfirmed)
      expect(described_class.matching_ids.size).to eq(described_class::AUTO_LIMIT + 1)
    end

    it "changes nothing when CONFIRM is not the current count" do
      expect(described_class.operator_run(confirm: "1", io: io, logger: logger).status).to eq(:mismatch)
      expect(described_class.matching_ids.size).to eq(described_class::AUTO_LIMIT + 1)
    end

    it "rewrites every row when CONFIRM is the current count" do
      outcome = described_class.operator_run(confirm: (described_class::AUTO_LIMIT + 1).to_s, io: io, logger: logger)

      expect(outcome.status).to eq(:rewritten)
      expect(described_class.matching_ids).to be_empty
    end
  end

  # Each message the old code could store maps to one of the five tokens, and
  # gate refusals go through Ranking's own rule rather than a copy of it.
  describe ".reason_for" do
    let(:automatic) { Platform::Investigation.new(component_kind: "k", component_ref: "r") }
    let(:opened) { Platform::Investigation.new(component_kind: "k", component_ref: "r", opened_by_user_id: SecureRandom.uuid) }

    {
      "Blocked by security gate (prompt_injection): Prompt injection detected" => %w[SecurityGateRefused refused],
      "Blocked by input guardrail: topic not allowed" => %w[SecurityGateRefused refused],
      "ranker returned no output" => %w[RankerUnusable failed],
      "ranker returned no usable hypotheses" => %w[RankerUnusable failed],
      "no ranking prompt could be resolved" => %w[RankerUnusable failed],
      "Faraday::TimeoutError: execution expired" => %w[ProviderError failed]
    }.each do |message, (reason, state)|
      it "maps #{message.inspect} to #{reason}" do
        expect(described_class.reason_for(message, automatic)).to eq([ reason, state ])
      end
    end

    it "maps an approval refusal with no opener to AutomaticSpendNeedsGrant" do
      message = "Blocked by security gate (anomaly_precheck): Capability matrix requires approval for 'execute'"

      expect(described_class.reason_for(message, automatic)).to eq(%w[AutomaticSpendNeedsGrant not_run])
    end

    it "maps the same refusal with an opener to SecurityGateRefused — the other arm" do
      message = "Blocked by security gate (anomaly_precheck): Capability matrix requires approval for 'execute'"

      expect(described_class.reason_for(message, opened)).to eq(%w[SecurityGateRefused refused])
    end
  end
end
