# frozen_string_literal: true

require "rails_helper"

# A tool_result message counts as the next user message, so it clears a
# turn-scoped (clear_at) system message. The loop appends a fresh copy of the
# turn's context after each tool round, and the cleared copies stay in place
# (append-only), so the context stays in view for the whole turn.
RSpec.describe Ai::AgentToolBridgeService, "turn-scoped context across tool rounds" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  subject(:bridge) { described_class.new(agent: agent, account: account) }

  let(:context) { { role: "system", content: "live context", clear_at: "next_user_message" } }
  let(:llm) { instance_double(WorkerLlmClient, provider_type: "anthropic") }

  before do
    allow(bridge).to receive(:tool_definitions_for_llm).and_return([])
    allow(bridge).to receive(:dispatch_tool_call_capturing).and_return([ { success: true }.to_json, nil ])
  end

  it "re-appends the turn's context after each tool round and keeps every earlier copy" do
    tool_round = Ai::Llm::Response.new(content: nil, finish_reason: "tool_use",
                                       tool_calls: [ { id: "t1", name: "search_knowledge", arguments: {} } ])
    final = Ai::Llm::Response.new(content: "done", finish_reason: "end_turn")
    seen = []
    allow(llm).to receive(:complete_with_tools) do |messages:, **|
      seen << messages.map(&:dup)
      seen.size == 1 ? tool_round : final
    end

    bridge.execute_tool_loop(llm_client: llm, messages: [ { role: "user", content: "hi" }, context ],
                             model: "claude-fable-5")

    second = seen.last
    expect(second.first(2)).to eq([ { role: "user", content: "hi" }, context ])
    expect(second.last).to eq(context)
    expect(second.count { |m| m == context }).to eq(2)
  end
end
