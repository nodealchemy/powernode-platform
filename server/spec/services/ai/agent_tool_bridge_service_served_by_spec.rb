# frozen_string_literal: true

require "rails_helper"

# The tool-bridge ralph path must carry served_by/refusal_recovery through so the
# maker/checker served-by comparison isn't defeated when the maker falls back.
RSpec.describe Ai::AgentToolBridgeService, "served-by threading" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  subject(:bridge) { described_class.new(agent: agent, account: account) }

  before { allow(bridge).to receive(:tool_definitions_for_llm).and_return([]) }

  it "carries served_by + refusal_recovery from a fallback response into the result" do
    resp = Ai::Llm::Response.new(
      content: "opus answer", model: "claude-fable-5", finish_reason: "end_turn",
      served_by: "claude-opus-4-8",
      refusal_recovery: { "fell_back" => true, "category" => "cyber", "served_by" => "claude-opus-4-8" }
    )
    llm = instance_double(WorkerLlmClient, provider_type: "anthropic")
    allow(llm).to receive(:complete_with_tools).and_return(resp)

    result = bridge.execute_tool_loop(
      llm_client: llm, messages: [{ role: "user", content: "hi" }], model: "claude-fable-5"
    )

    expect(result[:served_by]).to eq("claude-opus-4-8")
    expect(result[:refusal_recovery]).to include("fell_back" => true)
  end
end
