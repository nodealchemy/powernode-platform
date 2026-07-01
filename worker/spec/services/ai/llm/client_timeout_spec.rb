# frozen_string_literal: true

require 'spec_helper'

# The per-request HTTP read timeout must be capability-aware: minutes-long Fable
# turns need the long timeout, or a non-stream call hits Net::ReadTimeout.
RSpec.describe Ai::Llm::Client, 'capability-aware request timeout' do
  subject(:client) { described_class.new(provider_type: 'anthropic', api_key: 'k') }

  def stub_post_capturing_timeout
    captured = {}
    allow(HTTParty).to receive(:post) do |_url, opts|
      captured[:timeout] = opts[:timeout]
      instance_double(HTTParty::Response, code: 200,
                      parsed_response: { 'content' => [{ 'type' => 'text', 'text' => 'ok' }],
                                         'stop_reason' => 'end_turn', 'usage' => {} },
                      headers: {})
    end
    captured
  end

  it 'uses 600s for an adaptive-only model (Fable)' do
    captured = stub_post_capturing_timeout
    client.complete(messages: [{ role: 'user', content: 'hi' }], model: 'claude-fable-5')
    expect(captured[:timeout]).to eq(600)
  end

  it 'uses 120s for a legacy model' do
    captured = stub_post_capturing_timeout
    client.complete(messages: [{ role: 'user', content: 'hi' }], model: 'claude-opus-4-6')
    expect(captured[:timeout]).to eq(120)
  end

  # -- streaming path: http_stream → Net::HTTP#read_timeout= --
  # The streaming read timeout is capability-aware but never below the historical
  # 300s floor: an adaptive-only turn (Fable etc.) may go past 300s before the next
  # SSE chunk, so it gets its 600s profile timeout; every other model keeps 300s.
  def stub_stream_capturing_read_timeout
    captured = {}
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:read_body) # no SSE chunks — just succeed
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=) { |v| captured[:read_timeout] = v }
    allow(http).to receive(:request).and_yield(response)
    allow(Net::HTTP).to receive(:new).and_return(http)
    captured
  end

  it 'uses a 600s read timeout for an adaptive-only model (Fable) on the streaming path' do
    captured = stub_stream_capturing_read_timeout
    client.stream(messages: [{ role: 'user', content: 'hi' }], model: 'claude-fable-5') { |_chunk| }
    expect(captured[:read_timeout]).to eq(600)
  end

  it 'keeps the historical 300s streaming floor for a legacy model' do
    captured = stub_stream_capturing_read_timeout
    client.stream(messages: [{ role: 'user', content: 'hi' }], model: 'claude-opus-4-6') { |_chunk| }
    expect(captured[:read_timeout]).to eq(300)
  end
end
