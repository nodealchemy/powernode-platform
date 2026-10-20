# frozen_string_literal: true

require "rails_helper"

# Offer 01a07024-d980 — regression guard for a WRONG ANSWER, not for a crash.
#
# On 2026-09-05 05:57Z the account Concierge read this tool's `get_system_health`
# block and told the operator "there are no node instances in error status"
# while 12 were. Nothing failed: the block was correct about what it measured
# and silent about what it did not. Its `errors` key counted `Ai::ExecutionEvent`
# rows — AI AGENT EXECUTION errors — under a name that reads, to a model
# choosing a tool, like the platform's errors.
#
# So the guard is on the NAMING and the boundary text. A spec that only
# asserted the block still returns counts would have passed on 09-05 too.
RSpec.describe Ai::Tools::ActivityMonitorTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  describe "get_system_health payload naming" do
    it "names the execution-error block for what it counts, not for platform health" do
      result = tool.execute(params: { action: "get_system_health" })

      expect(result).to include(:agent_execution_errors)
      expect(result).not_to have_key(:errors)
      expect(result[:agent_execution_errors]).to include(
        :total_events_24h, :error_events_24h, :error_rate_percent
      )
    end
  end

  describe "the action description states the boundary" do
    let(:description) do
      described_class.action_definitions.dig("get_system_health", :description).to_s
    end

    it "says the block is AI agent execution errors" do
      expect(description).to match(/agent execution/i)
    end

    it "says it is NOT fleet or node-instance health" do
      expect(description).to match(/not.*(fleet|node instance)/i)
    end

    it "names the verb that does answer fleet health" do
      # IMP-80a353489ba4 split health_check out of platform_maintenance; the
      # fleet-health verb is now platform_health_check and the description must
      # not send a model to the merged action that no longer answers it.
      expect(description).to include("platform_health_check")
      expect(description).not_to include("platform_maintenance")
    end
  end

  describe "get_activity_feed error text (IMP-dbabbea6f81c)" do
    let(:secret) { %w[hunter 2].join }

    it "does not serve a secret quoted in a pre-fix row's error_message" do
      Ai::ExecutionEvent.create!(
        account: account, source_type: "Ai::ApprovalRequest", source_id: SecureRandom.uuid,
        event_type: "approval_execution", status: "failed", error_class: "RuntimeError",
        error_message: "login failed password=#{secret}"
      )

      result = tool.execute(params: { action: "get_activity_feed" })

      expect(result[:agent_execution_errors]).not_to be_empty
      expect(result.to_json).not_to include(secret)
      expect(result[:agent_execution_errors].to_json).to include(Ai::SensitiveParams::MASK)
    end
  end
end
