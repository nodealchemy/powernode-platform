# frozen_string_literal: true

require "rails_helper"

# Specs for Ai::DataSources::QualityService — the data-quality evaluator that
# runs an endpoint's active Ai::DataSourceExpectation rules (or built-in WARN
# defaults) over the canonical Array<Hash> a fetch produced.
#
# CONTRACT under test (read off the real implementation):
#   QualityService.new(endpoint).evaluate(records) => {
#     quality_score: Float(0..1),   # weighted share of rules passed (error rules weigh 2)
#     passed: Boolean,              # false ONLY when an error-severity rule fails
#     results: [{ name:, rule_type:, passed:, severity:, detail: }],
#     anomalies: []                 # rule_type tokens of failed error-severity rules
#   }
#
# HERMETIC: creating an ai_data_source fires an after_commit that syncs the
# source into the knowledge graph (embeddings -> Redis). Under DatabaseCleaner
# :deletion that commit really fires, so we stub the bridge sync to keep these
# specs off the network / Redis (this exact issue bit Phase 2a).
RSpec.describe Ai::DataSources::QualityService, type: :service do
  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  let(:data_source) { create(:ai_data_source) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }

  subject(:service) { described_class.new(endpoint) }

  # Build a persisted expectation row attached to the subject endpoint.
  def expectation(rule_type:, config: {}, severity: "warn", name: nil, is_active: true)
    Ai::DataSourceExpectation.create!(
      endpoint: endpoint,
      name: name || "#{rule_type}_#{severity}",
      rule_type: rule_type,
      config: config,
      severity: severity,
      is_active: is_active
    )
  end

  # Locate one result row by its rule_type token.
  def result_for(outcome, rule_type)
    outcome[:results].find { |r| r[:rule_type] == rule_type }
  end

  describe "#evaluate result shape" do
    it "returns the documented keys" do
      expectation(rule_type: "min_records", config: { "min" => 1 })

      outcome = service.evaluate([{ "a" => 1 }])

      expect(outcome).to include(:quality_score, :passed, :results, :anomalies)
      expect(outcome[:quality_score]).to be_a(Float)
      expect(outcome[:passed]).to be(true).or be(false)
      expect(outcome[:results]).to be_an(Array)
      expect(outcome[:anomalies]).to be_an(Array)

      row = outcome[:results].first
      expect(row.keys).to contain_exactly(:name, :rule_type, :passed, :severity, :detail)
    end

    it "carries the expectation name through to the result row" do
      expectation(rule_type: "min_records", config: { "min" => 1 }, name: "needs_data")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(result_for(outcome, "min_records")[:name]).to eq("needs_data")
    end
  end

  # --- per rule_type: a passing and a failing case ------------------------

  describe "required_fields rule" do
    it "passes when every record has all configured fields" do
      expectation(rule_type: "required_fields", config: { "fields" => %w[city temp] }, severity: "error")

      outcome = service.evaluate([{ "city" => "NYC", "temp" => 70 }, { "city" => "LA", "temp" => 80 }])

      expect(result_for(outcome, "required_fields")[:passed]).to be(true)
      expect(outcome[:passed]).to be(true)
    end

    it "fails when a record is missing a configured field" do
      expectation(rule_type: "required_fields", config: { "fields" => %w[city temp] }, severity: "error")

      outcome = service.evaluate([{ "city" => "NYC" }])

      row = result_for(outcome, "required_fields")
      expect(row[:passed]).to be(false)
      expect(row[:detail]).to include("temp")
    end
  end

  describe "min_records rule" do
    it "passes when the batch meets the minimum" do
      expectation(rule_type: "min_records", config: { "min" => 2 }, severity: "error")

      outcome = service.evaluate([{ "a" => 1 }, { "a" => 2 }])

      expect(result_for(outcome, "min_records")[:passed]).to be(true)
    end

    it "fails when the batch is below the minimum" do
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "error")

      outcome = service.evaluate([{ "a" => 1 }])

      row = result_for(outcome, "min_records")
      expect(row[:passed]).to be(false)
      expect(row[:detail]).to include("1 < 5")
    end
  end

  describe "max_records rule" do
    it "passes when the batch is within the maximum" do
      expectation(rule_type: "max_records", config: { "max" => 3 }, severity: "error")

      outcome = service.evaluate([{ "a" => 1 }, { "a" => 2 }])

      expect(result_for(outcome, "max_records")[:passed]).to be(true)
    end

    it "fails when the batch exceeds the maximum" do
      expectation(rule_type: "max_records", config: { "max" => 1 }, severity: "error")

      outcome = service.evaluate([{ "a" => 1 }, { "a" => 2 }, { "a" => 3 }])

      row = result_for(outcome, "max_records")
      expect(row[:passed]).to be(false)
      expect(row[:detail]).to include("3 > 1")
    end
  end

  describe "non_null rule" do
    it "passes when configured fields are present on every record" do
      expectation(rule_type: "non_null", config: { "fields" => %w[temp] }, severity: "error")

      outcome = service.evaluate([{ "temp" => 70 }, { "temp" => 0 }])

      expect(result_for(outcome, "non_null")[:passed]).to be(true)
    end

    it "fails when a configured field is nil or blank" do
      expectation(rule_type: "non_null", config: { "fields" => %w[temp] }, severity: "error")

      outcome = service.evaluate([{ "temp" => 70 }, { "temp" => nil }, { "temp" => "" }])

      row = result_for(outcome, "non_null")
      expect(row[:passed]).to be(false)
      expect(row[:detail]).to include("record[1].temp")
    end
  end

  describe "allowed_values rule" do
    it "passes when every value is within the allowed set" do
      expectation(rule_type: "allowed_values", config: { "field" => "status", "values" => %w[ok warn] }, severity: "error")

      outcome = service.evaluate([{ "status" => "ok" }, { "status" => "warn" }])

      expect(result_for(outcome, "allowed_values")[:passed]).to be(true)
    end

    it "fails when a value falls outside the allowed set" do
      expectation(rule_type: "allowed_values", config: { "field" => "status", "values" => %w[ok warn] }, severity: "error")

      outcome = service.evaluate([{ "status" => "ok" }, { "status" => "boom" }])

      row = result_for(outcome, "allowed_values")
      expect(row[:passed]).to be(false)
      expect(row[:detail]).to include("status")
    end
  end

  describe "distribution rule" do
    it "passes when a field's null ratio stays within max_null_ratio" do
      expectation(
        rule_type: "distribution",
        config: { "field" => "temp", "max_null_ratio" => 0.5 },
        severity: "error"
      )

      # 1 of 4 null => 0.25 <= 0.5
      records = [{ "temp" => 1 }, { "temp" => 2 }, { "temp" => 3 }, { "temp" => nil }]
      outcome = service.evaluate(records)

      row = result_for(outcome, "distribution")
      expect(row[:passed]).to be(true)
      expect(row[:detail]).to include("0.25")
    end

    it "fails when a field's null ratio exceeds max_null_ratio" do
      expectation(
        rule_type: "distribution",
        config: { "field" => "temp", "max_null_ratio" => 0.25 },
        severity: "error"
      )

      # 2 of 4 null => 0.5 > 0.25
      records = [{ "temp" => 1 }, { "temp" => 2 }, { "temp" => nil }, { "temp" => nil }]
      outcome = service.evaluate(records)

      row = result_for(outcome, "distribution")
      expect(row[:passed]).to be(false)
      expect(row[:detail]).to include("0.5")
    end

    it "degrades to a record-shape uniformity check when no field is configured" do
      expectation(rule_type: "distribution", config: {}, severity: "warn")

      uniform = service.evaluate([{ "a" => 1, "b" => 2 }, { "a" => 3, "b" => 4 }])
      expect(result_for(uniform, "distribution")[:passed]).to be(true)

      mixed = service.evaluate([{ "a" => 1, "b" => 2 }, { "a" => 3 }])
      expect(result_for(mixed, "distribution")[:passed]).to be(false)
    end
  end

  # --- severity gating ----------------------------------------------------

  describe "severity gating" do
    it "keeps passed=true when only WARN-severity rules fail (but lowers the score)" do
      # A warn rule that fails: min_records of 5 against a single record.
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "warn")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(result_for(outcome, "min_records")[:passed]).to be(false)
      expect(outcome[:passed]).to be(true)            # warn failure does NOT fail the batch
      expect(outcome[:quality_score]).to be < 1.0     # but the score reflects the failure
      expect(outcome[:anomalies]).to be_empty         # anomalies only track error failures
    end

    it "sets passed=false when an ERROR-severity rule fails" do
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "error")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(result_for(outcome, "min_records")[:passed]).to be(false)
      expect(outcome[:passed]).to be(false)
    end

    it "keeps passed=true when error rules pass even though a warn rule fails" do
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "error", name: "has_data")
      expectation(rule_type: "max_records", config: { "max" => 1 }, severity: "warn", name: "not_too_many")

      # 2 records: error min_records(1) passes, warn max_records(1) fails.
      outcome = service.evaluate([{ "a" => 1 }, { "a" => 2 }])

      expect(result_for(outcome, "min_records")[:passed]).to be(true)
      expect(result_for(outcome, "max_records")[:passed]).to be(false)
      expect(outcome[:passed]).to be(true)
    end
  end

  # --- anomalies ----------------------------------------------------------

  describe "anomalies" do
    it "lists the rule_type of each failed error-severity rule (de-duplicated)" do
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "error", name: "min_a")
      expectation(rule_type: "required_fields", config: { "fields" => %w[city] }, severity: "error", name: "req")

      outcome = service.evaluate([{ "temp" => 1 }])

      expect(outcome[:anomalies]).to contain_exactly("min_records", "required_fields")
    end

    it "is empty when no error-severity rule fails" do
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "error")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(outcome[:anomalies]).to be_empty
    end
  end

  # --- weighted quality_score --------------------------------------------

  describe "weighted quality_score" do
    it "is 1.0 when every rule passes" do
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "error")
      expectation(rule_type: "max_records", config: { "max" => 10 }, severity: "warn")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(outcome[:quality_score]).to eq(1.0)
    end

    it "weighs an error rule double a warn rule in the score" do
      # error rule passes (weight 2 earned), warn rule fails (weight 1 lost).
      # earned 2 / total 3 = 0.6667.
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "error", name: "err_pass")
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "warn", name: "warn_fail")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(outcome[:quality_score]).to eq(0.6667)
    end

    it "scores 1/3 when a warn rule passes but an error rule fails" do
      # warn passes (weight 1 earned), error fails (weight 2 lost) => 1/3 = 0.3333.
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "warn", name: "warn_pass")
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "error", name: "err_fail")

      outcome = service.evaluate([{ "a" => 1 }])

      expect(outcome[:quality_score]).to eq(0.3333)
      expect(outcome[:passed]).to be(false)
    end

    it "scores 0.0 when all rules fail" do
      expectation(rule_type: "min_records", config: { "min" => 5 }, severity: "error", name: "a")
      expectation(rule_type: "required_fields", config: { "fields" => %w[city] }, severity: "warn", name: "b")

      outcome = service.evaluate([{ "temp" => 1 }])

      expect(outcome[:quality_score]).to eq(0.0)
    end
  end

  # --- built-in defaults --------------------------------------------------

  describe "built-in defaults (no configured expectations)" do
    it "runs the non_empty + uniform_shape WARN defaults" do
      outcome = service.evaluate([{ "a" => 1 }, { "a" => 2 }])

      names = outcome[:results].map { |r| r[:name] }
      expect(names).to contain_exactly("non_empty", "uniform_shape")
      expect(outcome[:results].map { |r| r[:severity] }).to all(eq("warn"))
    end

    it "passes a healthy uniform batch with a perfect score" do
      outcome = service.evaluate([{ "city" => "NYC" }, { "city" => "LA" }])

      expect(outcome[:passed]).to be(true)
      expect(outcome[:quality_score]).to eq(1.0)
    end

    it "keeps passed=true on an empty batch (defaults are WARN only) but lowers the score" do
      outcome = service.evaluate([])

      # non_empty (min 1) fails on an empty batch; uniform_shape passes (vacuously).
      non_empty = result_for(outcome, "min_records")
      expect(non_empty[:passed]).to be(false)
      expect(outcome[:passed]).to be(true)          # no error-severity rule -> batch still passes
      expect(outcome[:anomalies]).to be_empty
      expect(outcome[:quality_score]).to be < 1.0
    end

    it "ignores inactive expectations and falls back to defaults" do
      expectation(rule_type: "min_records", config: { "min" => 99 }, severity: "error", is_active: false)

      outcome = service.evaluate([{ "a" => 1 }])

      # The inactive error rule must NOT run; defaults run instead.
      names = outcome[:results].map { |r| r[:name] }
      expect(names).to contain_exactly("non_empty", "uniform_shape")
      expect(outcome[:passed]).to be(true)
    end
  end

  # --- empty records ------------------------------------------------------

  describe "empty records" do
    it "fails a configured error min_records rule and fails the batch" do
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "error")

      outcome = service.evaluate([])

      expect(result_for(outcome, "min_records")[:passed]).to be(false)
      expect(outcome[:passed]).to be(false)
      expect(outcome[:anomalies]).to include("min_records")
    end

    it "treats nil records as an empty batch without raising" do
      expectation(rule_type: "min_records", config: { "min" => 1 }, severity: "warn")

      outcome = nil
      expect { outcome = service.evaluate(nil) }.not_to raise_error
      expect(result_for(outcome, "min_records")[:passed]).to be(false)
      expect(outcome[:passed]).to be(true)
    end
  end

  # --- robustness ---------------------------------------------------------

  describe "robustness" do
    # Replace the endpoint's expectations relation with a stub that responds to
    # #active (so configured_expectations' respond_to?(:active) guard passes) and
    # whose #active.to_a yields the supplied fake rule rows.
    def stub_active_expectations(rules)
      # `rules` is a plain Array; Array#to_a returns self, satisfying
      # `endpoint.expectations.active.to_a` in configured_expectations.
      relation = double("expectations_relation")
      allow(relation).to receive(:active).and_return(rules)
      allow(endpoint).to receive(:expectations).and_return(relation)
    end

    it "never raises and records an unknown rule_type as a passing no-op" do
      # Build a Struct that quacks like an expectation with an unsupported type,
      # bypassing model validation (which would reject the rule_type).
      bogus = Struct.new(:name, :rule_type, :config, :severity, keyword_init: true).new(
        name: "weird", rule_type: "made_up", config: {}, severity: "error"
      )
      stub_active_expectations([bogus])

      outcome = nil
      expect { outcome = service.evaluate([{ "a" => 1 }]) }.not_to raise_error

      row = result_for(outcome, "made_up")
      expect(row[:passed]).to be(true)
      expect(row[:detail]).to include("unknown rule_type")
      expect(outcome[:passed]).to be(true)
    end

    it "traps an exploding rule into a failed WARN result instead of aborting" do
      exploding = Struct.new(:name, :rule_type, :config, :severity, keyword_init: true).new(
        name: "kaboom", rule_type: "min_records", config: {}, severity: "error"
      )
      stub_active_expectations([exploding])
      # Force the rule body to blow up mid-evaluation. We stub the private
      # dispatch (apply_rule) rather than #config, because rule_config swallows
      # config errors internally and would never reach safe_run's rescue.
      allow(service).to receive(:apply_rule).and_raise(RuntimeError, "boom")

      outcome = nil
      expect { outcome = service.evaluate([{ "a" => 1 }]) }.not_to raise_error

      row = result_for(outcome, "min_records")
      expect(row[:passed]).to be(false)
      expect(row[:severity]).to eq("warn")            # downgraded so it can't fail the batch
      expect(row[:detail]).to include("rule error")   # exception captured into the detail
      expect(outcome[:passed]).to be(true)            # the trapped error is WARN, so batch passes
    end
  end
end
