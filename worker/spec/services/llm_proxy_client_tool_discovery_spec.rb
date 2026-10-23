# frozen_string_literal: true

require 'spec_helper'

# IMP-fea579e125d1: the server caps the catalog; a tool the model found with
# describe_tool must be callable on the next turn, and the first set follows the
# task's intent.
RSpec.describe LlmProxyClient, 'tool discovery', type: :service do
  before { mock_powernode_worker_config }

  subject(:proxy) { described_class.new(->(*) {}) }

  let(:config) { { 'model' => 'm', 'provider_type' => 'anthropic', 'provider_credential_id' => 'c1' } }
  let(:inner) { instance_double(Ai::Llm::Client) }

  before do
    allow(proxy).to receive(:fetch_provider_config).and_return(config)
    allow(proxy).to receive(:calculate_response_cost).and_return(0.0)
    allow(proxy).to receive(:build_llm_client).and_return(inner)
  end

  it 'sends the latest user message with the catalog request and loads a described tool for the next turn' do
    requests = []
    allow(proxy).to receive(:call_server) do |action, **payload|
      requests << [action, payload]
      case action
      when :tool_definitions
        payload[:names] ? { 'tools' => [{ 'name' => 'list_thing_119', 'parameters' => {} }] } :
                          { 'tools' => [{ 'name' => 'describe_tool', 'parameters' => {} }], 'tools_enabled' => true }
      when :dispatch_tool then { 'result' => { 'ok' => true } }
      end
    end
    seen = []
    allow(inner).to receive(:complete_with_tools) do |tools:, **|
      seen << tools.map { |t| t[:name] }
      if seen.size == 1
        Ai::Llm::Response.new(content: nil, model: 'm', finish_reason: 'tool_use',
                              tool_calls: [{ id: 't1', name: 'describe_tool', arguments: { 'name' => 'platform.list_thing_119' } }])
      else
        Ai::Llm::Response.new(content: 'done', model: 'm', finish_reason: 'end_turn')
      end
    end

    proxy.execute_tool_loop(agent_id: 'a1', messages: [{ role: 'user', content: 'check health' }])

    expect(requests.first).to eq([:tool_definitions, { agent_id: 'a1', user_message: 'check health' }])
    expect(seen.first).to eq(%w[describe_tool])
    expect(seen.last).to include('describe_tool', 'list_thing_119')
  end
end
