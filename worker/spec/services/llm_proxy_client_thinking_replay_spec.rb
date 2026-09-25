# frozen_string_literal: true

require 'spec_helper'

# F3: the raw assistant blocks (thinking included) ride back to the server on the
# flat JSON body, and the worker-local tool loop replays them on its next round.
RSpec.describe LlmProxyClient, 'thinking replay', type: :service do
  before { mock_powernode_worker_config }

  subject(:proxy) { described_class.new(->(*) {}) }

  let(:config) { { 'model' => 'claude-fable-5', 'provider_type' => 'anthropic', 'provider_credential_id' => 'c1' } }
  let(:blocks) do
    [{ 'type' => 'thinking', 'thinking' => '', 'signature' => 'sig-1' },
     { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'search', 'input' => { 'q' => 'x' } }]
  end
  let(:inner) { instance_double(Ai::Llm::Client) }

  def tool_turn
    Ai::Llm::Response.new(content: nil, model: 'claude-fable-5', finish_reason: 'tool_use',
                          tool_calls: [{ id: 'tu_1', name: 'search', arguments: { 'q' => 'x' } }],
                          content_blocks: blocks)
  end

  before do
    allow(proxy).to receive(:fetch_provider_config).and_return(config)
    allow(proxy).to receive(:calculate_response_cost).and_return(0.0)
    allow(proxy).to receive(:build_llm_client).and_return(inner)
  end

  it 'returns content_blocks from complete_with_tools' do
    allow(inner).to receive(:complete_with_tools).and_return(tool_turn)

    result = proxy.complete_with_tools(agent_id: 'a1', messages: [{ role: 'user', content: 'hi' }], tools: [])

    expect(result['content_blocks']).to eq(blocks)
  end

  it 'replays the blocks on the next round of the worker-local tool loop' do
    allow(proxy).to receive(:call_server).with(:tool_definitions, anything)
      .and_return('tools' => [{ 'name' => 'search', 'parameters' => {} }], 'tools_enabled' => true)
    allow(proxy).to receive(:call_server).with(:dispatch_tool, anything).and_return('result' => { 'hits' => 1 })
    seen = []
    allow(inner).to receive(:complete_with_tools) do |messages:, **|
      seen << messages.map(&:dup)
      seen.size == 1 ? tool_turn : Ai::Llm::Response.new(content: 'done', model: 'claude-fable-5', finish_reason: 'end_turn')
    end

    proxy.execute_tool_loop(agent_id: 'a1', messages: [{ role: 'user', content: 'hi' }])

    assistant = seen.last.find { |m| m[:role] == 'assistant' }
    expect(assistant[:content_blocks]).to eq(blocks)
  end
end
