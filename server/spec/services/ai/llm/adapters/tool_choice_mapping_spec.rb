# frozen_string_literal: true

require "rails_helper"

# tool_choice is a provider-neutral intent ("auto" | "none" | "required" | "any" |
# <tool name>). Anthropic never gets a forced shape: current Claude models 400 on
# tool_choice type "any"/"tool". OpenAI keeps forcing. Mirrors
# worker/spec/services/ai/llm/client_tool_choice_spec.rb.
RSpec.describe "tool_choice mapping on the wire" do # rubocop:disable RSpec/DescribeClass
  let(:messages) { [ { role: "user", content: "ask claude to review" } ] }
  let(:tools) { [ { name: "send_message", description: "Send", parameters: { type: "object" } } ] }

  describe Ai::Llm::Adapters::AnthropicAdapter do
    subject(:adapter) do
      described_class.new(api_key: "test-key", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic")
    end

    def sent_tool_choice(choice)
      captured = nil
      allow(adapter).to receive(:http_post) do |_path, body|
        captured = body
        [ 200, { "content" => [] }, {} ]
      end
      opts = choice.nil? ? {} : { tool_choice: choice }
      adapter.complete_with_tools(messages: messages, tools: tools, model: "claude-fable-5", **opts)
      captured[:tool_choice]
    end

    it "sends auto when no choice is given" do
      expect(sent_tool_choice(nil)).to eq(type: "auto")
    end

    it "keeps none" do
      expect(sent_tool_choice("none")).to eq(type: "none")
    end

    [ "required", "any", "send_message",
      { "type" => "function", "function" => { "name" => "send_message" } } ].each do |forced|
      it "degrades the forcing intent #{forced.inspect} to auto" do
        expect(sent_tool_choice(forced)).to eq(type: "auto")
      end
    end
  end

  describe Ai::Llm::Adapters::OpenaiAdapter do
    subject(:adapter) { described_class.new(api_key: "sk-test", base_url: "https://api.openai.com/v1") }

    def sent_tool_choice(choice)
      captured = nil
      allow(adapter).to receive(:http_post) do |_path, body|
        captured = body
        [ 200, { "choices" => [ { "message" => { "content" => "ok" }, "finish_reason" => "stop" } ] }, {} ]
      end
      opts = choice.nil? ? {} : { tool_choice: choice }
      adapter.complete_with_tools(messages: messages, tools: tools, model: "gpt-test", **opts)
      captured[:tool_choice]
    end

    it "sends auto when no choice is given" do
      expect(sent_tool_choice(nil)).to eq("auto")
    end

    it "passes auto/none/required through" do
      expect([ "auto", "none", "required" ].map { |c| sent_tool_choice(c) }).to eq([ "auto", "none", "required" ])
    end

    it "maps any to required" do
      expect(sent_tool_choice("any")).to eq("required")
    end

    it "forces a named tool with the function shape" do
      expect(sent_tool_choice("send_message")).to eq(type: "function", function: { name: "send_message" })
    end
  end
end
