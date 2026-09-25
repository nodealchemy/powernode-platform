# frozen_string_literal: true

require 'spec_helper'

# Phase 0 (a): the stop reason and cache-write tokens are measured, not dropped.
# cache_creation_input_tokens was never read, so a prompt that rewrote its cache
# every turn looked the same as one that hit it. Mirrors
# server/spec/services/ai/llm/usage_capture_spec.rb.
RSpec.describe Ai::Llm::Client, 'usage capture' do
  subject(:client) { described_class.new(provider_type: 'anthropic', api_key: 'k') }

  let(:messages) { [{ role: 'user', content: 'hi' }] }

  it 'reads cache_creation_input_tokens and the stop reason from a plain response' do
    allow(client).to receive(:http_post).and_return(
      [200, { 'content' => [{ 'type' => 'text', 'text' => 'ok' }], 'stop_reason' => 'max_tokens',
              'usage' => { 'input_tokens' => 10, 'output_tokens' => 5,
                           'cache_read_input_tokens' => 7, 'cache_creation_input_tokens' => 300 } }, {}]
    )

    response = client.complete(messages: messages, model: 'claude-fable-5', max_tokens: 1024)

    expect(response.usage[:cache_creation_tokens]).to eq(300)
    expect(response.usage[:cached_tokens]).to eq(7)
    expect(response.finish_reason).to eq('max_tokens')
  end

  it 'reads cache_creation_input_tokens from a stream' do
    payload = [
      ['message_start', { 'message' => { 'usage' => { 'input_tokens' => 10, 'cache_read_input_tokens' => 0,
                                                      'cache_creation_input_tokens' => 120 } } }],
      ['message_delta', { 'delta' => { 'stop_reason' => 'end_turn' }, 'usage' => { 'output_tokens' => 3 } }]
    ].map { |type, data| "event: #{type}\ndata: #{data.to_json}\n\n" }.join
    allow(client).to receive(:http_stream) do |_url, _body, _model, &blk|
      blk.call(double('response').tap { |r| allow(r).to receive(:read_body).and_yield(payload) })
    end

    response = client.stream(messages: messages, model: 'claude-fable-5') { |_chunk| }

    expect(response.usage[:cache_creation_tokens]).to eq(120)
  end

  it 'defaults cache_creation_tokens to 0 in a normalized usage hash' do
    expect(Ai::Llm::Response.new(usage: { prompt_tokens: 1 }).usage[:cache_creation_tokens]).to eq(0)
  end
end
