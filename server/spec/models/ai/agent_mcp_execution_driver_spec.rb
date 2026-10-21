# frozen_string_literal: true

require "rails_helper"

# Round-3 L-3: an MCP execution started with no user records the creator on
# the row (user_id is NOT NULL) but marks it as a stand-in, so the executor
# hands the tool bridge NO driver rather than the creator.
RSpec.describe Ai::Agent, "#create_mcp_execution driver" do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
  let(:runner) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: creator) }

  it "marks the creator fallback as a stand-in, and the executor drives with nil" do
    execution = agent.send(:create_mcp_execution, { "input" => "x" }, {})
    expect(execution.user).to eq(creator)
    expect(execution.execution_context["user_is_stand_in"]).to be(true)
    expect(Ai::McpAgentExecutor.new(agent: agent, execution: execution).send(:tool_bridge_driving_user)).to be_nil
  end

  it "keeps a real user as the driver" do
    execution = agent.send(:create_mcp_execution, { "input" => "x" }, { user: runner })
    expect(execution.execution_context["user_is_stand_in"]).to be(false)
    expect(Ai::McpAgentExecutor.new(agent: agent, execution: execution).send(:tool_bridge_driving_user)).to eq(runner)
  end
end
