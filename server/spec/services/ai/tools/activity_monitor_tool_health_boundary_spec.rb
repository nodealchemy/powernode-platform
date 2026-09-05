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
      expect(description).to include("platform_maintenance")
      expect(description).to include("health_check")
    end
  end
end
