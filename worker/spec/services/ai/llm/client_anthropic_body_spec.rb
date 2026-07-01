# frozen_string_literal: true

require 'spec_helper'

# Fable-aware Anthropic request builder. build_anthropic_body is private and pure
# (no HTTP), so we exercise it via #send; the structured-output merge is verified
# by stubbing http_post to capture the outgoing body.
RSpec.describe Ai::Llm::Client, '#build_anthropic_body' do
  subject(:client) { described_class.new(provider_type: 'anthropic', api_key: 'test-key') }

  let(:messages) { [{ role: 'user', content: 'hi' }] }
  let(:opts) { { temperature: 0.7, top_p: 0.9, effort: 'high' } }

  def body_for(model, extra = {})
    client.send(:build_anthropic_body, messages, model, **opts.merge(extra))
  end

  shared_examples 'an adaptive-only reasoning model' do |model|
    it "omits temperature/top_p and never emits an enabled/disabled thinking block for #{model}" do
      body = body_for(model)
      expect(body).not_to have_key(:temperature)
      expect(body).not_to have_key(:top_p)
      expect(body).not_to have_key(:thinking) # thinking budget must NOT become an enabled block
    end

    it "sets output_config.effort when the effort opt is present for #{model}" do
      expect(body_for(model)[:output_config]).to eq(effort: 'high')
    end

    it "surfaces reasoning only via adaptive+summarized when asked for #{model}" do
      body = body_for(model, surface_reasoning: true)
      expect(body[:thinking]).to eq(type: 'adaptive', display: 'summarized')
    end
  end

  it_behaves_like 'an adaptive-only reasoning model', 'claude-fable-5'
  it_behaves_like 'an adaptive-only reasoning model', 'claude-mythos-5'
  it_behaves_like 'an adaptive-only reasoning model', 'claude-opus-4-8'
  it_behaves_like 'an adaptive-only reasoning model', 'claude-sonnet-5'

  context 'legacy / permissive model (claude-opus-4-6)' do
    let(:body) { body_for('claude-opus-4-6') }

    it 'still sends temperature and top_p (no regression)' do
      expect(body[:temperature]).to eq(0.7)
      expect(body[:top_p]).to eq(0.9)
    end

    it 'emits no thinking block (no caller uses thinking; the budget_tokens path was removed)' do
      expect(body).not_to have_key(:thinking)
    end

    it 'does not send output_config.effort (effort unsupported)' do
      expect(body).not_to have_key(:output_config)
    end
  end

  describe '#complete_structured (output_config merge)' do
    it 'merges effort with the json_schema format instead of clobbering it' do
      captured = nil
      allow(client).to receive(:http_post) do |_url, body|
        captured = body
        [200, { 'content' => [] }, {}]
      end

      client.complete_structured(
        messages: messages,
        schema: { 'type' => 'object' },
        model: 'claude-fable-5',
        effort: 'high'
      )

      expect(captured[:output_config][:effort]).to eq('high')
      expect(captured[:output_config][:format]).to include(type: 'json_schema')
      expect(captured).not_to have_key(:temperature)
    end
  end
end
