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
end
