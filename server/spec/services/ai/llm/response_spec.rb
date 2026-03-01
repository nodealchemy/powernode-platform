# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Response do
  describe "#initialize" do
    it "sets attributes from hash" do
      response = described_class.new(
        content: "Hello",
        tool_calls: [{ id: "1", name: "test", arguments: {} }],
        finish_reason: "stop",
        model: "gpt-4.1",
        provider: "openai",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
        cost: 0.001
      )

      expect(response.content).to eq("Hello")
      expect(response.tool_calls).to have_attributes(size: 1)
      expect(response.finish_reason).to eq("stop")
      expect(response.model).to eq("gpt-4.1")
      expect(response.provider).to eq("openai")
      expect(response.cost).to eq(0.001)
    end

    it "defaults empty values" do
      response = described_class.new
      expect(response.content).to be_nil
      expect(response.tool_calls).to eq([])
      expect(response.cost).to eq(0.0)
      expect(response.total_tokens).to eq(0)
    end
  end

  describe "#success?" do
    it "returns true when content present" do
      response = described_class.new(content: "Hello")
      expect(response).to be_success
    end

    it "returns true when tool calls present" do
      response = described_class.new(tool_calls: [{ id: "1", name: "t", arguments: {} }])
      expect(response).to be_success
    end

    it "returns false when empty" do
      response = described_class.new
      expect(response).not_to be_success
    end
  end

  describe "#has_tool_calls?" do
    it "returns true when tool calls exist" do
      response = described_class.new(tool_calls: [{ id: "1", name: "t", arguments: {} }])
      expect(response).to have_tool_calls
    end

    it "returns false when no tool calls" do
      response = described_class.new(content: "Hello")
      expect(response).not_to have_tool_calls
    end
  end

  describe "usage normalization" do
    it "normalizes OpenAI-style usage" do
      response = described_class.new(usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
      expect(response.prompt_tokens).to eq(10)
      expect(response.completion_tokens).to eq(5)
      expect(response.total_tokens).to eq(15)
    end

    it "normalizes Anthropic-style usage" do
      response = described_class.new(usage: { input_tokens: 10, output_tokens: 5 })
      expect(response.prompt_tokens).to eq(10)
      expect(response.completion_tokens).to eq(5)
      expect(response.total_tokens).to eq(15)
    end

    it "handles cached tokens" do
      response = described_class.new(usage: { prompt_tokens: 10, completion_tokens: 5, cached_tokens: 3 })
      expect(response.cached_tokens).to eq(3)
    end

    it "handles Anthropic cache_read_input_tokens" do
      response = described_class.new(usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 7 })
      expect(response.cached_tokens).to eq(7)
    end
  end

  describe "#to_h" do
    it "returns serializable hash" do
      response = described_class.new(content: "Hello", model: "gpt-4.1", provider: "openai")
      hash = response.to_h

      expect(hash).to include(:content, :model, :provider, :usage)
      expect(hash[:content]).to eq("Hello")
    end

    it "excludes nil values" do
      response = described_class.new(content: "Hello")
      hash = response.to_h

      expect(hash).not_to have_key(:thinking_content)
    end
  end
end

RSpec.describe Ai::Llm::Chunk do
  describe "#initialize" do
    it "creates chunk with required type" do
      chunk = described_class.new(type: :content_delta, content: "Hello")
      expect(chunk.type).to eq(:content_delta)
      expect(chunk.content).to eq("Hello")
    end

    it "defaults optional fields" do
      chunk = described_class.new(type: :stream_start)
      expect(chunk.done).to be false
      expect(chunk.content).to be_nil
      expect(chunk.usage).to be_nil
    end

    it "creates stream_end with done and usage" do
      chunk = described_class.new(
        type: :stream_end,
        done: true,
        usage: { prompt_tokens: 10, completion_tokens: 5 }
      )
      expect(chunk.done).to be true
      expect(chunk.usage[:prompt_tokens]).to eq(10)
    end

    it "creates tool_call_start with tool info" do
      chunk = described_class.new(
        type: :tool_call_start,
        tool_call_id: "tc_1",
        tool_call_name: "get_weather"
      )
      expect(chunk.tool_call_id).to eq("tc_1")
      expect(chunk.tool_call_name).to eq("get_weather")
    end
  end
end
