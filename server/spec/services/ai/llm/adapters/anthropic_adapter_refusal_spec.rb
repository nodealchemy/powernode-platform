# frozen_string_literal: true

require "rails_helper"

# Server mirror of the worker refusal detection: a refusal is HTTP 200 with
# stop_reason "refusal" — detection branches on stop_reason before trusting
# content so a refusal never returns as a silent nil.
RSpec.describe Ai::Llm::Adapters::AnthropicAdapter, "refusal detection" do
  subject(:adapter) do
    described_class.new(api_key: "test-key", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic")
  end

  let(:messages) { [{ role: "user", content: "audit my own infra" }] }

  describe "#complete (pre-output refusal)" do
    it "surfaces a structured refusal with empty content, not a silent nil" do
      parsed = {
        "content" => [],
        "stop_reason" => "refusal",
        "stop_details" => { "type" => "refusal", "category" => "cyber", "explanation" => "declined" },
        "usage" => { "input_tokens" => 0, "output_tokens" => 0 }
      }
      allow(adapter).to receive(:http_post).and_return([200, parsed, {}])

      response = adapter.complete(messages: messages, model: "claude-fable-5")

      expect(response.refused?).to be true
      expect(response.refusal["category"]).to eq("cyber")
      expect(response.refusal["phase"]).to eq("pre_output")
      expect(response.content).to be_nil
    end

    it "does not flag a normal response as a refusal" do
      parsed = {
        "content" => [{ "type" => "text", "text" => "done" }],
        "stop_reason" => "end_turn", "stop_details" => nil,
        "usage" => { "input_tokens" => 2, "output_tokens" => 1 }
      }
      allow(adapter).to receive(:http_post).and_return([200, parsed, {}])

      response = adapter.complete(messages: messages, model: "claude-fable-5")

      expect(response.refused?).to be false
      expect(response.content).to eq("done")
    end
  end

  describe "#stream (mid-stream refusal)" do
    it "discards the streamed partial and returns a mid_stream refusal" do
      events = [
        ["message_start", { "message" => { "usage" => { "input_tokens" => 7 } } }],
        ["content_block_delta", { "delta" => { "type" => "text_delta", "text" => "partial" } }],
        ["message_delta", { "delta" => { "stop_reason" => "refusal",
                                         "stop_details" => { "category" => "bio" } },
                            "usage" => { "output_tokens" => 3 } }]
      ]
      allow(adapter).to receive(:http_stream).and_yield(:resp)
      allow(adapter).to receive(:parse_anthropic_sse_stream) do |_resp, &blk|
        events.each { |evt, payload| blk.call(evt, payload) }
      end

      response = adapter.stream(messages: messages, model: "claude-fable-5") { |_chunk| }

      expect(response.refused?).to be true
      expect(response.refusal["phase"]).to eq("mid_stream")
      expect(response.refusal["category"]).to eq("bio")
      expect(response.content).to be_nil
    end
  end
end
