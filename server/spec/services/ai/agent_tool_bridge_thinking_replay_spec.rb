# frozen_string_literal: true

require "rails_helper"

# F3: within a tool loop the assistant turn that called the tools is replayed
# with its thinking blocks, verbatim and in order. The worker returns the raw
# blocks as content_blocks; WorkerLlmClient carries them onto the Response; the
# bridge appends that turn as ONE assistant message carrying them (the worker's
# Anthropic builder sends them unchanged). A turn without thinking keeps the
# per-call assistant messages. Mirrors
# worker/spec/services/llm_proxy_client_thinking_replay_spec.rb.
RSpec.describe Ai::AgentToolBridgeService, "thinking replay across tool rounds" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  subject(:bridge) { described_class.new(agent: agent, account: account) }

  let(:llm) { instance_double(WorkerLlmClient, provider_type: "anthropic") }
  let(:blocks) do
    [ { "type" => "thinking", "thinking" => "", "signature" => "sig-1" },
      { "type" => "tool_use", "id" => "t1", "name" => "search_knowledge", "input" => {} },
      { "type" => "tool_use", "id" => "t2", "name" => "search_knowledge", "input" => {} } ]
  end
  let(:calls) do
    [ { id: "t1", name: "search_knowledge", arguments: {} }, { id: "t2", name: "search_knowledge", arguments: {} } ]
  end

  before do
    allow(bridge).to receive(:tool_definitions_for_llm).and_return([])
    allow(bridge).to receive(:dispatch_tool_call_capturing).and_return([ { success: true }.to_json, nil ])
  end

  def run_loop(tool_round)
    final = Ai::Llm::Response.new(content: "done", finish_reason: "end_turn")
    seen = []
    allow(llm).to receive(:complete_with_tools) do |messages:, **|
      seen << messages.map(&:dup)
      seen.size == 1 ? tool_round : final
    end
    bridge.execute_tool_loop(llm_client: llm, messages: [ { role: "user", content: "hi" } ], model: "claude-fable-5")
    seen.last
  end

  it "replays a thinking turn as one assistant message carrying its blocks, then the results" do
    second = run_loop(Ai::Llm::Response.new(content: nil, finish_reason: "tool_use", tool_calls: calls,
                                            content_blocks: blocks))

    expect(second.map { |m| m[:role] }).to eq(%w[user assistant tool tool])
    expect(second[1][:content_blocks]).to eq(blocks)
    expect(second[2..].map { |m| m[:tool_call_id] }).to eq(%w[t1 t2])
  end

  it "keeps the per-call assistant messages for a turn without thinking" do
    second = run_loop(Ai::Llm::Response.new(content: nil, finish_reason: "tool_use", tool_calls: calls))

    expect(second.map { |m| m[:role] }).to eq(%w[user assistant tool assistant tool])
    expect(second.none? { |m| m.key?(:content_blocks) }).to be(true)
  end

  describe WorkerLlmClient do
    subject(:client) { described_class.new(skip_budget_tracking: true) }

    before { allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt") }

    it "carries the worker's content_blocks onto the Response" do
      worker_url = Rails.application.config.worker_url.chomp("/")
      stub_request(:post, "#{worker_url}/api/v1/llm/complete_with_tools")
        .to_return(status: 200, body: { "data" => { "content" => nil, "content_blocks" => blocks } }.to_json)

      response = client.complete_with_tools(messages: [ { role: "user", content: "hi" } ], tools: [], model: "m")

      expect(response.content_blocks).to eq(blocks)
    end
  end
end
