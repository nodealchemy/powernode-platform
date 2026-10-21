# frozen_string_literal: true

require "rails_helper"

# Round-4 L-B: platform_execute_agent's execution row must name a user
# (user_id is NOT NULL), so with no real caller it falls back to the
# account's first user. That fallback, like an agent-bridge call whose user
# is the agent's creator, is a stand-in, and is flagged so McpAgentExecutor
# hands the tool bridge no driver.
RSpec.describe Ai::Tools::AgentManagementTool, "execute_agent stand-in user" do
  let(:account) { create(:account) }
  let!(:first_user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: first_user, status: "active") }

  before { allow(WorkerJobService).to receive(:enqueue_ai_agent_execution) }

  def run(tool)
    result = tool.send(:execute_agent, { agent_id: agent.id, input: "hi" }.with_indifferent_access)
    Ai::AgentExecution.find(result[:execution_id])
  end

  it "flags the account-first-user fallback as a stand-in" do
    execution = run(described_class.new(account: account, user: nil, agent: agent))
    expect(execution.user).to eq(first_user)
    expect(execution.execution_context["user_is_stand_in"]).to be(true)
  end

  it "flags the agent bridge's creator user as a stand-in" do
    tool = described_class.new(account: account, user: first_user, agent: agent)
    tool.call_origin = Ai::Tools::CallOrigin::AGENT_BRIDGE
    expect(run(tool).execution_context["user_is_stand_in"]).to be(true)
  end

  it "does not flag a real caller" do
    tool = described_class.new(account: account, user: first_user, agent: agent)
    tool.call_origin = Ai::Tools::CallOrigin::ALL.find { |o| o != Ai::Tools::CallOrigin::AGENT_BRIDGE }
    execution = run(tool)
    expect(execution.execution_context["user_is_stand_in"]).to be(false)
    expect(Ai::McpAgentExecutor.new(agent: agent, execution: execution).send(:tool_bridge_driving_user)).to eq(first_user)
  end
end
