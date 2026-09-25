# frozen_string_literal: true

require "rails_helper"

# Phase 0 (a): the Anthropic adapter reads cache_creation_input_tokens (cache
# writes) alongside cache reads, and Response carries it. Mirrors
# worker/spec/services/ai/llm/client_usage_capture_spec.rb.
RSpec.describe Ai::Llm::Adapters::AnthropicAdapter, "usage capture" do
  subject(:adapter) do
    described_class.new(api_key: "test-key", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic")
  end

  it "reads cache writes and the stop reason from a plain response" do
    allow(adapter).to receive(:http_post).and_return(
      [ 200, { "content" => [ { "type" => "text", "text" => "ok" } ], "stop_reason" => "max_tokens",
               "usage" => { "input_tokens" => 10, "output_tokens" => 5,
                            "cache_read_input_tokens" => 7, "cache_creation_input_tokens" => 300 } }, {} ]
    )

    response = adapter.complete(messages: [ { role: "user", content: "hi" } ], model: "claude-fable-5", max_tokens: 1024)

    expect(response.cache_creation_tokens).to eq(300)
    expect(response.cached_tokens).to eq(7)
    expect(response.finish_reason).to eq("max_tokens")
    # Invariant: cache reads and writes are SUBSETS of prompt_tokens. Anthropic's
    # input_tokens is only the uncached remainder, so the total is the sum.
    expect(response.prompt_tokens).to eq(317)
    expect(response.total_tokens).to eq(322)
  end

  it "totals prompt_tokens the same way from a stream" do
    payload = [
      [ "message_start", { "message" => { "usage" => { "input_tokens" => 10, "cache_read_input_tokens" => 0,
                                                       "cache_creation_input_tokens" => 120 } } } ],
      [ "message_delta", { "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 3 } } ]
    ].map { |type, data| "event: #{type}\ndata: #{data.to_json}\n\n" }.join
    allow(adapter).to receive(:http_stream) do |_path, _body, _model, &blk|
      blk.call(double("response").tap { |r| allow(r).to receive(:read_body).and_yield(payload) })
    end

    response = adapter.stream(messages: [ { role: "user", content: "hi" } ], model: "claude-fable-5") { |_chunk| }

    expect(response.cache_creation_tokens).to eq(120)
    expect(response.prompt_tokens).to eq(130)
    expect(response.total_tokens).to eq(133)
  end

  # The OpenAI parser already reports prompt_tokens as the total with cached
  # tokens inside it; the invariant holds there unchanged.
  it "keeps OpenAI cached tokens inside prompt_tokens" do
    openai = Ai::Llm::Adapters::OpenaiAdapter.new(api_key: "k", base_url: "https://api.openai.com/v1")
    allow(openai).to receive(:http_post).and_return(
      [ 200, { "choices" => [ { "message" => { "content" => "ok" }, "finish_reason" => "stop" } ],
               "usage" => { "prompt_tokens" => 100, "completion_tokens" => 5, "total_tokens" => 105,
                            "prompt_tokens_details" => { "cached_tokens" => 60 } } }, {} ]
    )

    response = openai.complete(messages: [ { role: "user", content: "hi" } ], model: "gpt-test")

    expect(response.prompt_tokens).to eq(100)
    expect(response.cached_tokens).to eq(60)
    expect(response.cache_creation_tokens).to eq(0)
  end

  it "defaults cache_creation_tokens to 0" do
    expect(Ai::Llm::Response.new(usage: { prompt_tokens: 1 }).cache_creation_tokens).to eq(0)
  end
end
