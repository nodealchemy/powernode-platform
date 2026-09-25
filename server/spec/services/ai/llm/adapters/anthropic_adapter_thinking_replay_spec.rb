# frozen_string_literal: true

require "rails_helper"

# Server parity with the worker client (worker/spec/services/ai/llm/
# client_thinking_replay_spec.rb): a tool-loop turn that thought keeps its raw
# content blocks, the builder replays them verbatim, and the first-party API
# gets the drop_block binding. Before, the server adapter ignored
# content_blocks, so a thinking-only assistant turn (no text, no tool_calls)
# went out as `content: null`, which the API rejects.
RSpec.describe Ai::Llm::Adapters::AnthropicAdapter, "thinking replay" do
  subject(:adapter) { described_class.new(api_key: "k", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic") }

  let(:model) { "claude-fable-5" }
  let(:tools) { [ { name: "search", description: "Search", parameters: { type: "object" } } ] }
  let(:thinking) { { "type" => "thinking", "thinking" => "", "signature" => "sig-1" } }
  let(:tool_use) { { "type" => "tool_use", "id" => "tu_1", "name" => "search", "input" => { "q" => "x" } } }

  def capture_post(adapter, content, stop_reason: "tool_use")
    captured = {}
    allow(adapter).to receive(:http_post) do |_path, body, _model|
      captured[:body] = body
      [ 200, { "content" => content, "stop_reason" => stop_reason }, {} ]
    end
    captured
  end

  def sse(*events)
    events.map { |type, data| "event: #{type}\ndata: #{data.to_json}\n\n" }.join
  end

  describe "capturing the blocks" do
    it "keeps thinking, text and tool_use blocks in order from a plain response" do
      capture_post(adapter, [ thinking, { "type" => "text", "text" => "looking" }, tool_use ])
      response = adapter.complete_with_tools(messages: [ { role: "user", content: "hi" } ], tools: tools,
                                             model: model, max_tokens: 1024)

      expect(response.content_blocks).to eq([ thinking, { "type" => "text", "text" => "looking" }, tool_use ])
    end

    it "leaves content_blocks nil when the turn carries no thinking" do
      capture_post(adapter, [ tool_use ])
      response = adapter.complete_with_tools(messages: [ { role: "user", content: "hi" } ], tools: tools,
                                             model: model, max_tokens: 1024)

      expect(response.content_blocks).to be_nil
    end

    it "rebuilds the blocks, signature included, from a stream" do
      payload = sse(
        [ "content_block_start", { "index" => 0, "content_block" => { "type" => "thinking", "thinking" => "" } } ],
        [ "content_block_delta", { "index" => 0, "delta" => { "type" => "thinking_delta", "thinking" => "plan" } } ],
        [ "content_block_delta", { "index" => 0, "delta" => { "type" => "signature_delta", "signature" => "sig-1" } } ],
        [ "content_block_stop", { "index" => 0 } ],
        [ "content_block_start", { "index" => 1, "content_block" => { "type" => "tool_use", "id" => "tu_1", "name" => "search", "input" => {} } } ],
        [ "content_block_delta", { "index" => 1, "delta" => { "type" => "input_json_delta", "partial_json" => '{"q":"x"}' } } ],
        [ "content_block_stop", { "index" => 1 } ],
        [ "message_delta", { "delta" => { "stop_reason" => "tool_use" } } ]
      )
      allow(adapter).to receive(:http_stream) do |_path, _body, _model, &blk|
        blk.call(double("response").tap { |r| allow(r).to receive(:read_body).and_yield(payload) })
      end

      response = adapter.stream(messages: [ { role: "user", content: "hi" } ], model: model) { |_chunk| }

      expect(response.content_blocks).to eq([ { "type" => "thinking", "thinking" => "plan", "signature" => "sig-1" }, tool_use ])
    end
  end

  describe "replaying the blocks" do
    let(:thinking_only_history) do
      [ { role: "user", content: "hi" },
        { "role" => "assistant", "content" => nil, "content_blocks" => [ thinking ] },
        { role: "user", content: "go on" } ]
    end

    it "sends a thinking-only assistant turn as its blocks, never content: null, and binds the replay" do
      captured = capture_post(adapter, [ { "type" => "text", "text" => "done" } ], stop_reason: "end_turn")
      adapter.complete(messages: thinking_only_history, model: model, max_tokens: 1024)

      body = captured[:body]
      expect(body[:messages][1]).to eq(role: "assistant", content: [ thinking ])
      expect(body[:thinking]).to eq(type: "adaptive", block_binding: { prefix_mismatch_behavior: "drop_block" })
      expect(adapter.send(:request_headers, body)["anthropic-beta"]).to include("thinking-binding-controls-2026-08-01")
    end

    it "replays a tool-calling turn verbatim" do
      history = [ { role: "user", content: "hi" },
                  { "role" => "assistant", "content" => nil,
                    "tool_calls" => [ { "id" => "tu_1", "name" => "search", "arguments" => { "q" => "x" } } ],
                    "content_blocks" => [ thinking, tool_use ] },
                  { role: "tool", tool_call_id: "tu_1", content: '{"hits":1}' } ]
      captured = capture_post(adapter, [ { "type" => "text", "text" => "done" } ], stop_reason: "end_turn")
      adapter.complete_with_tools(messages: history, tools: tools, model: model, max_tokens: 1024)

      expect(captured[:body][:messages][1]).to eq(role: "assistant", content: [ thinking, tool_use ])
    end

    it "replays without the binding controls off the first-party API" do
      gateway = described_class.new(api_key: "k", base_url: "https://llm-gateway.example/v1", provider_name: "anthropic")
      captured = capture_post(gateway, [ { "type" => "text", "text" => "done" } ], stop_reason: "end_turn")
      gateway.complete(messages: thinking_only_history, model: model, max_tokens: 1024)

      expect(captured[:body][:messages][1]).to eq(role: "assistant", content: [ thinking ])
      expect(captured[:body]).not_to have_key(:thinking)
      expect(gateway.send(:request_headers, captured[:body])).not_to have_key("anthropic-beta")
    end
  end
end
