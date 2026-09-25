# frozen_string_literal: true

require 'spec_helper'

# F3: within a tool loop, the assistant turn that called the tools is replayed
# with its thinking blocks, verbatim and in order, so the model keeps its
# reasoning across tool rounds (preserved thinking). The response carries the raw
# blocks as content_blocks; the builder sends them back unchanged. On the
# first-party API the request also asks for drop_block, so a block whose prefix
# no longer matches is dropped rather than failing the request with a 400.
RSpec.describe Ai::Llm::Client, 'thinking replay within a tool loop' do
  subject(:client) { described_class.new(provider_type: 'anthropic', api_key: 'k') }

  let(:tools) { [{ name: 'search', description: 'Search', parameters: { type: 'object' } }] }
  let(:thinking) { { 'type' => 'thinking', 'thinking' => '', 'signature' => 'sig-1' } }
  let(:tool_use) { { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'search', 'input' => { 'q' => 'x' } } }

  def sse(*events)
    events.map { |type, data| "event: #{type}\ndata: #{data.to_json}\n\n" }.join
  end

  def capture_post(content)
    captured = {}
    allow(client).to receive(:http_post) do |_url, body|
      captured[:body] = body
      [200, { 'content' => content, 'stop_reason' => 'tool_use' }, {}]
    end
    captured
  end

  describe 'capturing the blocks' do
    it 'keeps thinking, text and tool_use blocks in order from a plain response' do
      capture_post([thinking, { 'type' => 'text', 'text' => 'looking' }, tool_use])
      response = client.complete_with_tools(messages: [{ role: 'user', content: 'hi' }], tools: tools,
                                            model: 'claude-fable-5', max_tokens: 1024)

      expect(response.content_blocks).to eq([thinking, { 'type' => 'text', 'text' => 'looking' }, tool_use])
    end

    it 'leaves content_blocks nil when the turn carries no thinking' do
      capture_post([tool_use])
      response = client.complete_with_tools(messages: [{ role: 'user', content: 'hi' }], tools: tools,
                                            model: 'claude-fable-5', max_tokens: 1024)

      expect(response.content_blocks).to be_nil
    end

    it 'rebuilds the blocks, signature included, from a stream' do
      payload = sse(
        ['content_block_start', { 'index' => 0, 'content_block' => { 'type' => 'thinking', 'thinking' => '' } }],
        ['content_block_delta', { 'index' => 0, 'delta' => { 'type' => 'thinking_delta', 'thinking' => 'plan' } }],
        ['content_block_delta', { 'index' => 0, 'delta' => { 'type' => 'signature_delta', 'signature' => 'sig-1' } }],
        ['content_block_stop', { 'index' => 0 }],
        ['content_block_start', { 'index' => 1, 'content_block' => { 'type' => 'redacted_thinking', 'data' => 'enc' } }],
        ['content_block_stop', { 'index' => 1 }],
        ['content_block_start', { 'index' => 2, 'content_block' => { 'type' => 'tool_use', 'id' => 'tu_1', 'name' => 'search', 'input' => {} } }],
        ['content_block_delta', { 'index' => 2, 'delta' => { 'type' => 'input_json_delta', 'partial_json' => '{"q":"x"}' } }],
        ['content_block_stop', { 'index' => 2 }],
        ['message_delta', { 'delta' => { 'stop_reason' => 'tool_use' } }]
      )
      allow(client).to receive(:http_stream) do |_url, _body, _model, &blk|
        blk.call(double('response').tap { |r| allow(r).to receive(:read_body).and_yield(payload) })
      end

      response = client.complete_with_tools(messages: [{ role: 'user', content: 'hi' }], tools: tools,
                                            model: 'claude-fable-5')

      expect(response.content_blocks).to eq([
        { 'type' => 'thinking', 'thinking' => 'plan', 'signature' => 'sig-1' },
        { 'type' => 'redacted_thinking', 'data' => 'enc' },
        tool_use
      ])
      expect(response.tool_calls).to eq([{ id: 'tu_1', name: 'search', arguments: { 'q' => 'x' } }])
    end
  end

  describe 'replaying the blocks' do
    let(:history) do
      [{ role: 'user', content: 'hi' },
       { 'role' => 'assistant', 'content' => nil,
         'tool_calls' => [{ 'id' => 'tu_1', 'name' => 'search', 'arguments' => { 'q' => 'x' } }],
         'content_blocks' => [thinking, tool_use] },
       { role: 'tool', tool_call_id: 'tu_1', content: '{"hits":1}' }]
    end

    it 'sends the assistant turn verbatim and binds the replay on the first-party API' do
      captured = capture_post([{ 'type' => 'text', 'text' => 'done' }])
      client.complete_with_tools(messages: history, tools: tools, model: 'claude-fable-5', max_tokens: 1024)

      body = captured[:body]
      expect(body[:messages][1]).to eq(role: 'assistant', content: [thinking, tool_use])
      expect(body[:thinking]).to eq(type: 'adaptive', block_binding: { prefix_mismatch_behavior: 'drop_block' })
      expect(client.send(:request_headers, body)['anthropic-beta']).to include('thinking-binding-controls-2026-08-01')
    end

    it 'replays without the binding controls off the first-party API' do
      client = described_class.new(provider_type: 'anthropic', api_key: 'k', base_url: 'https://llm-gateway.example/v1')
      captured = {}
      allow(client).to receive(:http_post) do |_url, body|
        captured[:body] = body
        [200, { 'content' => [{ 'type' => 'text', 'text' => 'done' }], 'stop_reason' => 'end_turn' }, {}]
      end
      client.complete_with_tools(messages: history, tools: tools, model: 'claude-fable-5', max_tokens: 1024)

      expect(captured[:body][:messages][1]).to eq(role: 'assistant', content: [thinking, tool_use])
      expect(captured[:body]).not_to have_key(:thinking)
      expect(client.send(:request_headers, captured[:body])).not_to have_key('anthropic-beta')
    end

    it 'adds no binding when nothing replays thinking' do
      captured = capture_post([{ 'type' => 'text', 'text' => 'done' }])
      client.complete_with_tools(messages: [{ role: 'user', content: 'hi' }], tools: tools,
                                 model: 'claude-fable-5', max_tokens: 1024)

      expect(captured[:body]).not_to have_key(:thinking)
    end
  end
end
