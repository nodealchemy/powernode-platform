# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Client do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account, provider_type: "openai", api_base_url: "https://api.openai.com/v1") }
  let(:credential) { create(:ai_provider_credential, provider: provider, account: account, credentials: { "api_key" => "sk-test-key-that-is-long-enough-for-validation-1234567890" }) }
  let(:client) { described_class.new(provider: provider, credential: credential) }

  describe "#initialize" do
    it "creates an adapter via AdapterFactory" do
      expect(client.adapter).to be_a(Ai::Llm::Adapters::OpenaiAdapter)
    end

    it "sets provider and credential" do
      expect(client.provider).to eq(provider)
      expect(client.credential).to eq(credential)
    end
  end

  describe ".for_type" do
    it "creates client without DB records" do
      client = described_class.for_type("anthropic", api_key: "test-key")
      expect(client.adapter).to be_a(Ai::Llm::Adapters::AnthropicAdapter)
      expect(client.provider).to be_nil
    end
  end

  describe ".for_account" do
    it "returns nil when no credentials exist" do
      expect(described_class.for_account(account)).to be_nil
    end

    it "returns client when credential exists" do
      credential # ensure it's created
      result = described_class.for_account(account)
      expect(result).to be_a(described_class)
    end
  end

  describe "#complete" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4.1" }
    let(:mock_response) do
      Ai::Llm::Response.new(
        content: "Hello! How can I help?",
        finish_reason: "stop",
        model: model,
        provider: "openai",
        usage: { prompt_tokens: 5, completion_tokens: 10, total_tokens: 15 }
      )
    end

    before do
      allow(client.adapter).to receive(:complete).and_return(mock_response)
      allow(Ai::CircuitBreakerRegistry).to receive(:protect).and_yield
    end

    it "delegates to adapter" do
      response = client.complete(messages: messages, model: model)
      expect(response.content).to eq("Hello! How can I help?")
      expect(response).to be_success
    end

    it "uses circuit breaker protection" do
      expect(Ai::CircuitBreakerRegistry).to receive(:protect)
        .with(service_name: /llm_/)
        .and_yield

      client.complete(messages: messages, model: model)
    end

    it "returns error response when circuit is open" do
      allow(Ai::CircuitBreakerRegistry).to receive(:protect)
        .and_raise(CircuitBreakerCore::CircuitOpenError.new("Circuit open"))

      response = client.complete(messages: messages, model: model)
      expect(response).not_to be_success
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "claude-sonnet-4-5" }
    let(:mock_response) do
      Ai::Llm::Response.new(
        content: "Hi there!",
        finish_reason: "stop",
        model: model,
        provider: "anthropic",
        usage: { prompt_tokens: 5, completion_tokens: 8, total_tokens: 13 }
      )
    end

    before do
      allow(client.adapter).to receive(:stream).and_return(mock_response)
      allow(Ai::CircuitBreakerRegistry).to receive(:protect).and_yield
    end

    it "delegates to adapter with block" do
      chunks = []
      allow(client.adapter).to receive(:stream) do |**_args, &block|
        block.call(Ai::Llm::Chunk.new(type: :content_delta, content: "Hi"))
        mock_response
      end

      response = client.stream(messages: messages, model: model) { |c| chunks << c }
      expect(response.content).to eq("Hi there!")
      expect(chunks.first.type).to eq(:content_delta)
    end
  end

  describe "#complete_with_tools" do
    let(:messages) { [{ role: "user", content: "What's the weather?" }] }
    let(:tools) do
      [{ name: "get_weather", description: "Get weather", parameters: { type: "object", properties: { city: { type: "string" } } } }]
    end
    let(:model) { "gpt-4.1" }
    let(:mock_response) do
      Ai::Llm::Response.new(
        content: nil,
        tool_calls: [{ id: "tc_1", name: "get_weather", arguments: { "city" => "NYC" } }],
        finish_reason: "tool_calls",
        model: model,
        provider: "openai",
        usage: { prompt_tokens: 20, completion_tokens: 15, total_tokens: 35 }
      )
    end

    before do
      allow(client.adapter).to receive(:complete_with_tools).and_return(mock_response)
      allow(Ai::CircuitBreakerRegistry).to receive(:protect).and_yield
    end

    it "returns tool calls" do
      response = client.complete_with_tools(messages: messages, tools: tools, model: model)
      expect(response.has_tool_calls?).to be true
      expect(response.tool_calls.first[:name]).to eq("get_weather")
    end
  end

  describe "#complete_structured" do
    let(:messages) { [{ role: "user", content: "Extract the name" }] }
    let(:schema) { { name: "person", schema: { type: "object", properties: { name: { type: "string" } } } } }
    let(:model) { "gpt-4.1" }
    let(:mock_response) do
      Ai::Llm::Response.new(
        content: '{"name": "John"}',
        finish_reason: "stop",
        model: model,
        provider: "openai",
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
      )
    end

    before do
      allow(client.adapter).to receive(:complete_structured).and_return(mock_response)
      allow(Ai::CircuitBreakerRegistry).to receive(:protect).and_yield
    end

    it "returns structured response" do
      response = client.complete_structured(messages: messages, schema: schema, model: model)
      expect(response.content).to include("John")
    end
  end
end
