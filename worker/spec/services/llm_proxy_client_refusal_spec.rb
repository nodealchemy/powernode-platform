# frozen_string_literal: true

require 'spec_helper'

# Refusal recovery threaded through LlmProxyClient → format_response, so the
# refusal/served_by/refusal_recovery metadata rides the flat JSON body back to
# the server.
RSpec.describe LlmProxyClient, 'refusal recovery wiring', type: :service do
  before { mock_powernode_worker_config }

  subject(:proxy) { described_class.new(->(*) {}) }

  let(:config) do
    { 'model' => 'claude-fable-5', 'fallback_models' => ['claude-opus-4-8'],
      'provider_type' => 'anthropic', 'provider_credential_id' => 'c1' }
  end

  def refusal_resp
    Ai::Llm::Response.new(content: nil, model: 'claude-fable-5',
                          refusal: { 'stop_reason' => 'refusal', 'category' => 'cyber', 'phase' => 'pre_output' })
  end

  def ok_resp(model)
    Ai::Llm::Response.new(content: 'answer', model: model, finish_reason: 'end_turn',
                          usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 })
  end

  before do
    allow(proxy).to receive(:fetch_provider_config).and_return(config)
    allow(proxy).to receive(:calculate_response_cost).and_return(0.0)
  end

  describe '#complete_with_tools' do
    it 'adapts→falls back to a non-Fable model and threads served_by + refusal_recovery' do
      inner = instance_double(Ai::Llm::Client)
      allow(proxy).to receive(:build_llm_client).and_return(inner)
      allow(inner).to receive(:complete_with_tools) do |model:, **_kw|
        model == 'claude-fable-5' ? refusal_resp : ok_resp(model)
      end

      result = proxy.complete_with_tools(agent_id: 'a1',
                                         messages: [{ role: 'user', content: 'hi' }],
                                         tools: [{ name: 't' }])

      expect(result['content']).to eq('answer')
      expect(result['served_by']).to eq('claude-opus-4-8')
      expect(result['refusal_recovery']).to include('fell_back' => true, 'resolved' => true)
      expect(result).not_to have_key('refusal') # resolved → no terminal refusal
    end
  end

  describe '#execute_tool_loop (no-tools fast path)' do
    it 'surfaces a terminal refusal (never a silent nil) when fable + fallback both refuse' do
      allow(proxy).to receive(:call_server)
        .with(:tool_definitions, hash_including(agent_id: 'a1'))
        .and_return('tools' => [], 'tools_enabled' => false)
      inner = instance_double(Ai::Llm::Client)
      allow(proxy).to receive(:build_llm_client).and_return(inner)
      allow(inner).to receive(:complete).and_return(refusal_resp)

      result = proxy.execute_tool_loop(agent_id: 'a1', messages: [{ role: 'user', content: 'hi' }])

      expect(result['refusal']).to be_present
      expect(result['content']).to be_nil
    end
  end
end
