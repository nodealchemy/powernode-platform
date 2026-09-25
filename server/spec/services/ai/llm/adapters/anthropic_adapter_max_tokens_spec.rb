# frozen_string_literal: true

require "rails_helper"

# Thinking is always on for adaptive-only models and is paid out of max_tokens,
# so the no-thinking-era 4096 default cut replies off. With no caller cap, a
# tool-loop turn gets 64K and a plain completion 16K; legacy models keep 4096.
# Above 16K the request is streamed (an unstreamed response that large risks HTTP
# timeouts) and accumulated into the same Response. Mirrors
# worker/spec/services/ai/llm/client_max_tokens_spec.rb.
RSpec.describe Ai::Llm::Adapters::AnthropicAdapter, "max_tokens defaults and streaming" do
  subject(:adapter) do
    described_class.new(api_key: "test-key", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic")
  end

  let(:messages) { [ { role: "user", content: "hi" } ] }
  let(:tools) { [ { name: "search", description: "Search", parameters: { type: "object" } } ] }

  def capture_post
    captured = {}
    allow(adapter).to receive(:http_post) do |_path, body|
      captured[:body] = body
      [ 200, { "content" => [ { "type" => "text", "text" => "ok" } ], "stop_reason" => "end_turn" }, {} ]
    end
    captured
  end

  def sse(*events)
    events.map { |type, data| "event: #{type}\ndata: #{data.to_json}\n\n" }.join
  end

  def capture_stream(payload)
    captured = {}
    allow(adapter).to receive(:http_stream) do |_path, body, _model, &blk|
      captured[:body] = body
      blk.call(double("response").tap { |r| allow(r).to receive(:read_body).and_yield(payload) })
    end
    captured
  end

  describe "#complete" do
    it "defaults an always-thinking model to 16K, unstreamed" do
      captured = capture_post
      adapter.complete(messages: messages, model: "claude-opus-5")
      expect(captured[:body][:max_tokens]).to eq(16_000)
      expect(captured[:body]).not_to have_key(:stream)
    end

    it "keeps 4096 for a legacy model" do
      captured = capture_post
      adapter.complete(messages: messages, model: "claude-opus-4-6")
      expect(captured[:body][:max_tokens]).to eq(4096)
    end

    it "honors an explicit cap" do
      captured = capture_post
      adapter.complete(messages: messages, model: "claude-opus-5", max_tokens: 500)
      expect(captured[:body][:max_tokens]).to eq(500)
    end
  end

  describe "#complete_with_tools" do
    it "defaults an always-thinking model to 64K and streams it into one Response" do
      payload = sse(
        [ "message_start", { "message" => { "usage" => { "input_tokens" => 10 } } } ],
        [ "content_block_start", { "content_block" => { "type" => "tool_use", "id" => "tu_1", "name" => "search" } } ],
        [ "content_block_delta", { "delta" => { "type" => "input_json_delta", "partial_json" => "{\"q\":\"x\"}" } } ],
        [ "content_block_stop", {} ],
        [ "message_delta", { "delta" => { "stop_reason" => "tool_use" }, "usage" => { "output_tokens" => 5 } } ]
      )
      captured = capture_stream(payload)
      expect(adapter).not_to receive(:http_post)

      response = adapter.complete_with_tools(messages: messages, tools: tools, model: "claude-opus-5")

      expect(captured[:body][:max_tokens]).to eq(64_000)
      expect(captured[:body][:stream]).to be(true)
      expect(response.tool_calls).to eq([ { id: "tu_1", name: "search", arguments: { "q" => "x" } } ])
      expect(response.finish_reason).to eq("tool_use")
    end

    it "keeps 4096, unstreamed, for a legacy model" do
      captured = capture_post
      adapter.complete_with_tools(messages: messages, tools: tools, model: "claude-opus-4-6")
      expect(captured[:body][:max_tokens]).to eq(4096)
    end

    it "sends an explicit cap at or under 16K unstreamed" do
      captured = capture_post
      adapter.complete_with_tools(messages: messages, tools: tools, model: "claude-opus-5", max_tokens: 4096)
      expect(captured[:body][:max_tokens]).to eq(4096)
    end
  end
end
