# frozen_string_literal: true

require "rails_helper"

# M-1: the agent-bridge door runs every tool call as the agent's creator, a
# stand-in. The executor knows the REAL triggering user (its execution's
# user) and hands it to the bridge, so a promotion grant that only its
# granter may drive (granter_driven_only) is decided on who ran the agent.
RSpec.describe Ai::McpAgentExecutor, "driving user on the tool bridge" do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
  let(:runner) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: creator) }
  let(:execution) { create(:ai_agent_execution, agent: agent, account: account, user: runner) }

  it "builds the bridge with the execution's user as the driver, not the creator" do
    bridge = instance_double(Ai::AgentToolBridgeService, tools_enabled?: false)
    allow(Ai::AgentToolBridgeService).to receive(:new).and_return(bridge)
    executor = described_class.new(agent: agent, execution: execution, account: account)
    allow(executor).to receive_messages(build_llm_client: double("llm").as_null_object, build_messages_for_llm: [],
                                        resolve_model_config: [ "m", {} ])

    begin
      executor.send(:execute_with_provider, nil, {})
    rescue StandardError
      nil # the LLM half is not under test; only how the bridge was built
    end

    expect(Ai::AgentToolBridgeService).to have_received(:new)
      .with(agent: agent, account: account, driving_user: runner)
  end
end
