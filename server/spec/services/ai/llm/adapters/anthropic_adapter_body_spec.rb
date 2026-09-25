# frozen_string_literal: true

require "rails_helper"

# Fable-aware Anthropic request builder (server mirror of the worker client).
# build_messages_body is private and pure (no HTTP); the structured-output merge
# is verified by stubbing http_post to capture the outgoing body.
RSpec.describe Ai::Llm::Adapters::AnthropicAdapter, "#build_messages_body" do
  subject(:adapter) do
    described_class.new(api_key: "test-key", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic")
  end

  let(:messages) { [{ role: "user", content: "hi" }] }
  let(:opts) { { temperature: 0.7, top_p: 0.9, effort: "high" } }

  def body_for(model, extra = {})
    adapter.send(:build_messages_body, messages, model, **opts.merge(extra))
  end

  shared_examples "an adaptive-only reasoning model" do |model|
    it "omits temperature/top_p and never emits an enabled/disabled thinking block for #{model}" do
      body = body_for(model)
      expect(body).not_to have_key(:temperature)
      expect(body).not_to have_key(:top_p)
      expect(body).not_to have_key(:thinking)
    end

    it "sets output_config.effort when the effort opt is present for #{model}" do
      expect(body_for(model)[:output_config]).to eq(effort: "high")
    end

    it "surfaces reasoning only via adaptive+summarized when asked for #{model}" do
      expect(body_for(model, surface_reasoning: true)[:thinking]).to eq(type: "adaptive", display: "summarized")
    end
  end

  it_behaves_like "an adaptive-only reasoning model", "claude-fable-5"
  it_behaves_like "an adaptive-only reasoning model", "claude-mythos-5"
  it_behaves_like "an adaptive-only reasoning model", "claude-opus-4-8"
  it_behaves_like "an adaptive-only reasoning model", "claude-sonnet-5"

  context "legacy / permissive model (claude-opus-4-6)" do
    let(:body) { body_for("claude-opus-4-6") }

    it "still sends temperature and top_p (no regression)" do
      expect(body[:temperature]).to eq(0.7)
      expect(body[:top_p]).to eq(0.9)
    end

    it "emits no thinking block (no caller uses thinking; the budget_tokens path was removed)" do
      expect(body).not_to have_key(:thinking)
    end

    it "does not send output_config.effort (effort unsupported)" do
      expect(body).not_to have_key(:output_config)
    end
  end

  describe "#complete_structured (output_config merge)" do
    it "merges effort with the json_schema format instead of clobbering it" do
      captured = nil
      allow(adapter).to receive(:http_post) do |_path, body|
        captured = body
        [200, { "content" => [] }, {}]
      end

      adapter.complete_structured(
        messages: messages,
        schema: { "type" => "object", "properties" => { "answer" => { "type" => "string" } } },
        model: "claude-fable-5",
        effort: "high"
      )

      expect(captured[:output_config][:effort]).to eq("high")
      expect(captured[:output_config][:format]).to include(type: "json_schema")
      expect(captured).not_to have_key(:temperature)
    end
  end

  # Prompt caching: the stable prefix (tools + system) must carry ephemeral
  # cache_control breakpoints BY DEFAULT (server mirror of the worker client;
  # IMP-f702df4b0d61 — repeat agent calls were re-billing 114k uncached tokens).
  describe "prompt caching (stable-prefix cache_control)" do
    let(:system_messages) { [{ role: "system", content: "You are a helpful analyst." }, { role: "user", content: "hi" }] }

    it "caches the system prompt by default (block form with cache_control)" do
      body = adapter.send(:build_messages_body, system_messages, "claude-fable-5")
      expect(body[:system]).to eq([{ type: "text", text: "You are a helpful analyst.",
                                     cache_control: { type: "ephemeral" } }])
    end

    it "honors cache_system_prompt: false as an opt-out (plain string system)" do
      body = adapter.send(:build_messages_body, system_messages, "claude-fable-5", cache_system_prompt: false)
      expect(body[:system]).to eq("You are a helpful analyst.")
    end

    it "marks the LAST tool with cache_control in complete_with_tools (caches the whole tools block)" do
      captured = nil
      allow(adapter).to receive(:http_post) do |_path, body|
        captured = body
        [200, { "content" => [] }, {}]
      end

      tools = [
        { name: "tool_a", description: "first", parameters: { type: "object" } },
        { name: "tool_b", description: "second", parameters: { type: "object" } }
      ]
      adapter.complete_with_tools(messages: messages, tools: tools, model: "claude-fable-5", max_tokens: 1024)

      expect(captured[:tools].first).not_to have_key(:cache_control)
      expect(captured[:tools].last[:cache_control]).to eq(type: "ephemeral")
    end

    it "does not annotate tools when caching is opted out" do
      captured = nil
      allow(adapter).to receive(:http_post) do |_path, body|
        captured = body
        [200, { "content" => [] }, {}]
      end

      tools = [{ name: "tool_a", description: "only", parameters: { type: "object" } }]
      adapter.complete_with_tools(messages: messages, tools: tools, model: "claude-fable-5", max_tokens: 1024,
                                  cache_system_prompt: false)

      expect(captured[:tools].last).not_to have_key(:cache_control)
    end
  end

  # The top-level system must stay byte-identical across the turns of a
  # conversation (prompt cache, preserved thinking). A system message that appears
  # later in the history is sent in place, never lifted into it.
  describe "mid-conversation system messages" do
    def body_for_history(history, model) = adapter.send(:build_messages_body, history, model)

    let(:turn1) { [ { role: "system", content: "core prompt" }, { role: "user", content: "first question" } ] }
    let(:turn2) do
      turn1 + [ { role: "assistant", content: "first answer" }, { role: "user", content: "second question" },
                { role: "system", content: "live context for turn 2" } ]
    end

    %w[claude-fable-5 claude-sonnet-5].each do |model|
      it "keeps body[:system] byte-identical when the history gains a mid-array system message (#{model})" do
        first = body_for_history(turn1, model)
        second = body_for_history(turn2, model)
        expect(second[:system]).to eq(first[:system])
        expect(second[:messages].first(first[:messages].size)).to eq(first[:messages])
        expect(second[:messages].to_s).to include("live context for turn 2")
      end
    end

    it "sends the later system message natively where the model supports it" do
      expect(body_for_history(turn2, "claude-fable-5")[:messages].last).to eq(role: "system", content: "live context for turn 2")
    end
  end

  describe "per-request beta headers" do
    it "sends the clear_at beta only when the body carries a turn-scoped system message" do
      scoped = { messages: [ { role: "system", content: "ctx", clear_at: "next_user_message" } ] }

      expect(adapter.send(:request_headers, scoped)["anthropic-beta"]).to eq(Ai::Llm::AnthropicMessages::CLEAR_AT_BETA)
      expect(adapter.send(:request_headers, { messages: messages })).not_to have_key("anthropic-beta")
    end
  end
end
