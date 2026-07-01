# frozen_string_literal: true

require "rails_helper"

# The server's direct adapter path must apply the capability-aware per-request
# HTTP timeout (Ai::Llm::ModelCapabilities.request_timeout_seconds): minutes-long
# adaptive-only turns (Fable / Mythos / Opus 4.7+ / Sonnet 5) get 600s so a
# high-effort turn does not hit a premature ReadTimeout, while legacy models keep
# the historical defaults. Exercised through AnthropicAdapter because it has both
# adaptive-only and legacy models routing through the shared BaseAdapter HTTP
# helpers. Mirrors worker/spec/services/ai/llm/client_timeout_spec.rb.
RSpec.describe Ai::Llm::Adapters::BaseAdapter, "capability-aware request timeout" do
  subject(:adapter) do
    Ai::Llm::Adapters::AnthropicAdapter.new(
      api_key: "test-key", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic"
    )
  end

  let(:messages) { [{ role: "user", content: "hi" }] }

  # -- non-streaming path: http_post → HTTParty.post(timeout:) --
  def stub_post_capturing_timeout
    captured = {}
    allow(HTTParty).to receive(:post) do |_url, opts|
      captured[:timeout] = opts[:timeout]
      instance_double(
        HTTParty::Response,
        code: 200,
        parsed_response: { "content" => [{ "type" => "text", "text" => "ok" }],
                           "stop_reason" => "end_turn", "usage" => {} },
        headers: {}
      )
    end
    captured
  end

  it "uses 600s for an adaptive-only model (Fable) on the non-streaming path" do
    captured = stub_post_capturing_timeout
    adapter.complete(messages: messages, model: "claude-fable-5")
    expect(captured[:timeout]).to eq(600)
  end

  it "uses 120s for a legacy model on the non-streaming path" do
    captured = stub_post_capturing_timeout
    adapter.complete(messages: messages, model: "claude-opus-4-6")
    expect(captured[:timeout]).to eq(120)
  end

  # -- streaming path: http_stream → Net::HTTP#read_timeout= --
  def stub_stream_capturing_read_timeout
    captured = {}
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:read_body) # no SSE chunks — just succeed
    http = instance_double(Net::HTTP)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=) { |v| captured[:read_timeout] = v }
    allow(http).to receive(:request).and_yield(response)
    allow(Net::HTTP).to receive(:new).and_return(http)
    captured
  end

  it "uses a 600s read timeout for an adaptive-only model (Fable) on the streaming path" do
    captured = stub_stream_capturing_read_timeout
    adapter.stream(messages: messages, model: "claude-fable-5") { |_chunk| }
    expect(captured[:read_timeout]).to eq(600)
  end

  it "keeps the historical 300s streaming floor for a legacy model" do
    captured = stub_stream_capturing_read_timeout
    adapter.stream(messages: messages, model: "claude-opus-4-6") { |_chunk| }
    expect(captured[:read_timeout]).to eq(300)
  end
end
