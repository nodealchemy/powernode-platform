# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Ralph::LoopReadinessService, type: :service do
  let(:account) { create(:account) }
  let(:loop_record) do
    create(:ai_ralph_loop, account: account, repository_url: "https://git.example.com/acme/widget.git")
  end

  def evaluate(loop_rec = loop_record)
    described_class.new(loop_rec).evaluate
  end

  describe "#evaluate" do
    it "is ready by default — G1 gate on, iteration cap set, repo present" do
      result = evaluate
      expect(result.ready).to be true
      expect(result.blocked?).to be false
      expect(result.failures).to be_empty
    end

    it "blocks when the objective gate is disabled and not acknowledged (condition 1)" do
      loop_record.update!(configuration: { "real_test_execution" => false })
      result = evaluate
      expect(result.ready).to be false
      expect(result.failures.join).to match(/objective verification gate/i)
    end

    it "downgrades the missing gate to a warning when explicitly acknowledged" do
      loop_record.update!(configuration: { "real_test_execution" => false, "acknowledge_no_gate" => true })
      result = evaluate
      expect(result.ready).to be true
      expect(result.failures).to be_empty
      expect(result.warnings.join).to match(/acknowledge/i)
    end

    it "warns (does not block) when no repository is configured for sandbox verification" do
      loop_record.update!(repository_url: nil)
      result = evaluate
      expect(result.ready).to be true
      expect(result.warnings.join).to match(/repository/i)
    end

    it "warns when a metered (platform-driven) loop has no token/cost cap" do
      loop_record.update!(driver_kind: "platform_agent")
      expect(evaluate.warnings.join).to match(%r{token/cost cap})
    end

    it "does not raise the metered-cap warning for a flat-rate claude_code loop" do
      loop_record.update!(driver_kind: "claude_code")
      expect(evaluate.warnings.join).not_to match(%r{token/cost cap})
    end

    it "does not warn about caps when the metered loop has a cost cap configured" do
      loop_record.update!(driver_kind: "platform_team", configuration: { "max_cost" => 25 })
      expect(evaluate.warnings.join).not_to match(%r{token/cost cap})
    end

    it "warns when no iteration cap is set" do
      loop_record.update!(max_iterations: 0)
      expect(evaluate.warnings.join).to match(/iteration cap/i)
    end

    context "scope in bounds (G14)" do
      it "warns (non-blocking) when the declared scope overlaps a keep-manual path" do
        loop_record.update!(configuration: { "scope" => { "paths" => ["server/app/services/payments/charge.rb"] } })
        result = evaluate
        expect(result.ready).to be true
        expect(result.warnings.join).to match(/keep-manual/i)
        expect(result.warnings.join).to include("payments/charge.rb")
      end

      it "supports a flat target_paths scope shape" do
        loop_record.update!(configuration: { "target_paths" => ["config/master.key"] })
        expect(evaluate.warnings.join).to match(/keep-manual/i)
      end

      it "does not warn when the declared scope is in bounds" do
        loop_record.update!(configuration: { "scope" => { "paths" => ["server/app/models/user.rb"] } })
        result = evaluate
        expect(result.ready).to be true
        expect(result.warnings.join).not_to match(/keep-manual/i)
      end

      it "does not warn when no scope is declared" do
        expect(evaluate.warnings.join).not_to match(/keep-manual/i)
      end
    end
  end
end
