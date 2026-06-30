# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Ralph::GateCanaryService do
  describe "#run against the real verification gate" do
    subject(:result) { described_class.new.run }

    it "is healthy — every canary verdict matches expectation" do
      expect(result[:healthy]).to be(true)
      expect(result[:checks]).to all(include(ok: true))
    end

    it "returns one check per canary case with the expected shape" do
      expect(result[:checks].size).to eq(described_class::CANARY_CASES.size)
      expect(result[:checks].first.keys).to contain_exactly(:name, :expected, :actual, :ok)
    end

    it "exercises both known-good (expected true) and known-bad (expected false) cases" do
      expectations = described_class::CANARY_CASES.map { |c| c[:expected] }
      expect(expectations).to include(true)
      expect(expectations).to include(false)
    end

    it "asserts the fail-closed invariant: a blank framework + clean exit is rejected" do
      blank = result[:checks].find { |c| c[:name] == "blank_framework_fail_closed" }
      expect(blank).to include(expected: false, actual: false, ok: true)
    end
  end

  describe "#run when the gate is silently broken (sabotage)" do
    # A regressed gate that always reports success — the exact failure mode this
    # canary exists to catch (e.g. real-test verification regressing to always-pass).
    let(:always_pass_gate) do
      Class.new do
        def evaluate(**)
          { success: true, ran: true }
        end
      end.new
    end

    subject(:result) { described_class.new(gate: always_pass_gate).run }

    it "reports unhealthy" do
      expect(result[:healthy]).to be(false)
    end

    it "flags every known-bad case as not ok (verdict no longer matches expectation)" do
      bad_checks = result[:checks].reject { |c| c[:expected] }
      expect(bad_checks).not_to be_empty
      expect(bad_checks).to all(include(actual: true, ok: false))
    end

    it "still passes the known-good cases (so the offending checks are the bad ones)" do
      good_checks = result[:checks].select { |c| c[:expected] }
      expect(good_checks).to all(include(ok: true))
    end
  end

  describe "#run when the gate breaks a known-good case (false negative)" do
    let(:always_fail_gate) do
      Class.new do
        def evaluate(**)
          { success: false, ran: true }
        end
      end.new
    end

    it "is unhealthy because a known-good input no longer passes" do
      result = described_class.new(gate: always_fail_gate).run
      expect(result[:healthy]).to be(false)
      good = result[:checks].select { |c| c[:expected] }
      expect(good).to all(include(actual: false, ok: false))
    end
  end
end
