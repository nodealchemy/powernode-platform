# frozen_string_literal: true

require "rails_helper"

# Cross-executor wiring regression: migrated rules live as `guidance-*` platform
# knowledge, but the SessionStart digest that surfaces them is Claude-only. These
# pure-constant specs assert the two model-agnostic recall seams that reach
# non-Claude executors are in place:
#   (a) the three loop guardrails arrays (delivered in the dev_next_task payload)
#   (b) the Ai::Agent::BASE_GUARDRAILS baseline (carried by every agent prompt)
RSpec.describe "guidance-* cross-executor recall wiring" do
  describe "loop guardrails carry a guidance-* recall line" do
    {
      "Ai::DevLoop::CampaignDriver::DEFAULT_GUARDRAILS" => Ai::DevLoop::CampaignDriver::DEFAULT_GUARDRAILS,
      "Ai::DevLoop::AuditBacklogSeeder::GUARDRAILS" => Ai::DevLoop::AuditBacklogSeeder::GUARDRAILS,
      "Ai::DevLoop::ImprovementPromotionService::GUARDRAILS" => Ai::DevLoop::ImprovementPromotionService::GUARDRAILS
    }.each do |const_name, guardrails|
      it "#{const_name} includes a search_knowledge tag:guidance-* recall guardrail" do
        expect(guardrails).to include(match(/guidance-\*/))
        expect(guardrails).to include(match(/search_knowledge/))
      end

      it "#{const_name} includes the never-batch-approve bulk-op guardrail" do
        expect(guardrails).to include(match(/batch-approve/i))
      end

      it "#{const_name} includes the verification-gate (validate.sh) recall guardrail" do
        expect(guardrails).to include(match(/validate\.sh/))
        expect(guardrails).to include(match(/verification gate/i))
      end

      it "#{const_name} includes the Fable refusal-handling guardrail" do
        expect(guardrails).to include(match(/Fable.*refusal/i))
        expect(guardrails).to include(match(/guidance-fable5-compliance/))
      end
    end
  end

  describe "Ai::Agent::BASE_GUARDRAILS baseline" do
    subject(:baseline) { Ai::Agent::BASE_GUARDRAILS }

    it "is a non-empty string" do
      expect(baseline).to be_a(String)
      expect(baseline).not_to be_empty
    end

    it "includes the guidance-recall rule" do
      expect(baseline).to match(/guidance-\*/)
      expect(baseline).to match(/search_knowledge/)
    end

    it "includes the stop-and-ask rule" do
      expect(baseline).to match(/3 failed attempts/)
      expect(baseline).to match(/STOP and ask/)
    end

    it "includes the crypto-material-safety rule (migrated cross-executor)" do
      expect(baseline).to match(/Vault-only/)
      expect(baseline).to match(/never handle key material directly/)
    end

    it "includes the bulk-operation-safety rule (migrated cross-executor)" do
      expect(baseline).to match(/batch-approve/i)
      expect(baseline).to match(/state the count/i)
    end

    it "includes the reuse-first rule (migrated cross-executor)" do
      expect(baseline).to match(/Reuse first/i)
      expect(baseline).to match(/never greenfield/i)
    end

    it "includes the audit-report-only rule (migrated cross-executor)" do
      expect(baseline).to match(/audit.*report/i)
      expect(baseline).to match(/do NOT implement/i)
    end

    it "includes the surface-assumptions rule (migrated cross-executor)" do
      expect(baseline).to match(/surface assumptions/i)
    end

    it "includes the Fable refusal-handling + prompting guardrail" do
      expect(baseline).to match(/Fable.*refusal/i)
      expect(baseline).to match(/Opus/)
      expect(baseline).to match(/guidance-fable5-compliance/)
    end
  end
end
