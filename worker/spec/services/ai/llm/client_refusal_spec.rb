# frozen_string_literal: true

require 'spec_helper'

# Fable/Anthropic safety-classifier refusal detection. A refusal is HTTP 200
# with stop_reason "refusal" — detection must branch on stop_reason BEFORE
# trusting content, so a refusal never returns as a silent nil.
RSpec.describe Ai::Llm::Client, 'refusal detection' do
  subject(:client) { described_class.new(provider_type: 'anthropic', api_key: 'test-key') }

  let(:messages) { [{ role: 'user', content: 'harden my own server' }] }

  describe '#complete (non-streaming, pre-output refusal)' do
    it 'surfaces a structured refusal with empty content instead of a silent nil' do
      parsed = {
        'content' => [],
        'stop_reason' => 'refusal',
        'stop_details' => { 'type' => 'refusal', 'category' => 'cyber', 'explanation' => 'declined' },
        'usage' => { 'input_tokens' => 0, 'output_tokens' => 0 }
      }
      allow(client).to receive(:http_post).and_return([200, parsed, {}])

      response = client.complete(messages: messages, model: 'claude-fable-5')

      expect(response.refused?).to be true
      expect(response.refusal['stop_reason']).to eq('refusal')
      expect(response.refusal['category']).to eq('cyber')
      expect(response.refusal['phase']).to eq('pre_output')
      expect(response.content).to be_nil
    end

    it 'guards on stop_reason even when stop_details is null (category nil is valid)' do
      parsed = { 'content' => [], 'stop_reason' => 'refusal', 'stop_details' => nil, 'usage' => {} }
      allow(client).to receive(:http_post).and_return([200, parsed, {}])

      response = client.complete(messages: messages, model: 'claude-fable-5')

      expect(response.refused?).to be true
      expect(response.refusal['category']).to be_nil
    end

    it 'nils content and tool_calls on a refusal even if a billed partial is present' do
      parsed = {
        'content' => [{ 'type' => 'text', 'text' => 'partial billed answer' },
                      { 'type' => 'tool_use', 'id' => 't1', 'name' => 'x', 'input' => {} }],
        'stop_reason' => 'refusal',
        'stop_details' => { 'category' => 'cyber' },
        'usage' => { 'input_tokens' => 5, 'output_tokens' => 9 }
      }
      allow(client).to receive(:http_post).and_return([200, parsed, {}])

      response = client.complete(messages: messages, model: 'claude-fable-5')

      expect(response.refused?).to be true
      expect(response.content).to be_nil          # billed partial not handed to the caller
      expect(response.tool_calls).to eq([])
      expect(response.refusal['phase']).to eq('mid_stream')
    end

    it 'does NOT flag a normal end_turn response as a refusal' do
      parsed = {
        'content' => [{ 'type' => 'text', 'text' => 'ok' }],
        'stop_reason' => 'end_turn',
        'stop_details' => nil,
        'usage' => { 'input_tokens' => 3, 'output_tokens' => 1 }
      }
      allow(client).to receive(:http_post).and_return([200, parsed, {}])

      response = client.complete(messages: messages, model: 'claude-fable-5')

      expect(response.refused?).to be false
      expect(response.refusal).to be_nil
      expect(response.content).to eq('ok')
    end
  end

  describe '#stream (mid-stream refusal)' do
    it 'discards the already-streamed partial and returns a mid_stream refusal' do
      events = [
        ['message_start', { 'message' => { 'usage' => { 'input_tokens' => 10 } } }],
        ['content_block_delta', { 'delta' => { 'type' => 'text_delta', 'text' => 'partial ans' } }],
        ['message_delta', { 'delta' => { 'stop_reason' => 'refusal',
                                         'stop_details' => { 'category' => 'bio', 'explanation' => 'x' } },
                            'usage' => { 'output_tokens' => 4 } }]
      ]
      allow(client).to receive(:http_stream).and_yield(:resp)
      allow(client).to receive(:parse_anthropic_sse) do |_resp, &blk|
        events.each { |evt, payload| blk.call(evt, payload) }
      end

      response = client.stream(messages: messages, model: 'claude-fable-5') { |_chunk| }

      expect(response.refused?).to be true
      expect(response.refusal['phase']).to eq('mid_stream')
      expect(response.refusal['category']).to eq('bio')
      expect(response.content).to be_nil # partial discarded, never returned as complete
    end
  end
end
