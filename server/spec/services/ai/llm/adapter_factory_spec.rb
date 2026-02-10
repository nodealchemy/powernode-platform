# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::AdapterFactory do
  describe ".build_for_type" do
    it "returns OpenaiAdapter for openai" do
      adapter = described_class.build_for_type("openai", api_key: "key", base_url: "https://api.openai.com/v1")
      expect(adapter).to be_a(Ai::Llm::Adapters::OpenaiAdapter)
    end

    it "returns AnthropicAdapter for anthropic" do
      adapter = described_class.build_for_type("anthropic", api_key: "key", base_url: "https://api.anthropic.com/v1")
      expect(adapter).to be_a(Ai::Llm::Adapters::AnthropicAdapter)
    end

    it "returns OllamaAdapter for ollama" do
      adapter = described_class.build_for_type("ollama", api_key: nil, base_url: "http://localhost:11434")
      expect(adapter).to be_a(Ai::Llm::Adapters::OllamaAdapter)
    end

    Ai::Llm::AdapterFactory::OPENAI_COMPATIBLE.each do |provider_type|
      it "returns OpenaiAdapter for #{provider_type}" do
        adapter = described_class.build_for_type(provider_type, api_key: "key", base_url: "https://api.example.com/v1")
        expect(adapter).to be_a(Ai::Llm::Adapters::OpenaiAdapter)
        expect(adapter.provider_name).to eq(provider_type)
      end
    end

    it "defaults to OpenaiAdapter for unknown types" do
      adapter = described_class.build_for_type("unknown", api_key: "key", base_url: "https://api.example.com/v1")
      expect(adapter).to be_a(Ai::Llm::Adapters::OpenaiAdapter)
    end

    it "is case-insensitive" do
      adapter = described_class.build_for_type("ANTHROPIC", api_key: "key", base_url: "https://api.anthropic.com/v1")
      expect(adapter).to be_a(Ai::Llm::Adapters::AnthropicAdapter)
    end
  end

  describe ".build" do
    let(:account) { create(:account) }
    let(:provider) { create(:ai_provider, account: account, provider_type: "openai", api_base_url: "https://api.openai.com/v1") }
    let(:credential) { create(:ai_provider_credential, provider: provider, account: account, credentials: { "api_key" => "sk-test-key-that-is-long-enough-for-validation-1234567890" }) }

    it "builds adapter from provider and credential records" do
      adapter = described_class.build(provider: provider, credential: credential)
      expect(adapter).to be_a(Ai::Llm::Adapters::OpenaiAdapter)
    end
  end

  describe ".supported_types" do
    it "includes all provider types" do
      types = described_class.supported_types
      expect(types).to include("openai", "anthropic", "ollama", "groq", "mistral")
    end
  end
end
