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
  end

  it "defaults cache_creation_tokens to 0" do
    expect(Ai::Llm::Response.new(usage: { prompt_tokens: 1 }).cache_creation_tokens).to eq(0)
  end
end
