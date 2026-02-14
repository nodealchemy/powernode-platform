# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::DefaultConfig do
  describe ".types" do
    it "returns all supported provider types" do
      types = described_class.types

      expect(types).to be_an(Array)
      expect(types).to include("openai", "anthropic", "google", "azure_openai", "groq", "mistral", "cohere")
      expect(types.size).to eq(7)
    end
  end

  describe ".for" do
    it "returns config for openai" do
      config = described_class.for("openai")

      expect(config[:name]).to eq("OpenAI")
      expect(config[:configuration][:api_base_url]).to eq("https://api.openai.com/v1")
      expect(config[:configuration][:default_model]).to eq("gpt-4o")
      expect(config[:configuration][:supported_models]).to include("gpt-4o", "gpt-4o-mini")
      expect(config[:configuration][:capabilities]).to include("chat", "completions")
    end

    it "returns config for anthropic" do
      config = described_class.for("anthropic")

      expect(config[:name]).to eq("Anthropic")
      expect(config[:configuration][:api_base_url]).to eq("https://api.anthropic.com/v1")
      expect(config[:configuration][:capabilities]).to include("chat", "completions")
    end

    it "returns config for google" do
      config = described_class.for("google")

      expect(config[:name]).to eq("Google AI (Gemini)")
      expect(config[:configuration][:supported_models]).to include("gemini-2.0-flash")
    end

    it "returns config for azure_openai with nil base URL" do
      config = described_class.for("azure_openai")

      expect(config[:name]).to eq("Azure OpenAI")
      expect(config[:configuration][:api_base_url]).to be_nil
    end

    it "returns config for groq" do
      config = described_class.for("groq")

      expect(config[:name]).to eq("Groq")
      expect(config[:configuration][:api_base_url]).to include("groq.com")
    end

    it "returns config for mistral" do
      config = described_class.for("mistral")

      expect(config[:name]).to eq("Mistral AI")
      expect(config[:configuration][:default_model]).to eq("mistral-large-latest")
    end

    it "returns config for cohere" do
      config = described_class.for("cohere")

      expect(config[:name]).to eq("Cohere")
      expect(config[:configuration][:default_model]).to eq("command-r-plus")
    end

    it "returns nil for unknown provider type" do
      config = described_class.for("nonexistent")

      expect(config).to be_nil
    end
  end

  describe ".configs" do
    it "returns a hash of all provider configs" do
      configs = described_class.configs

      expect(configs).to be_a(Hash)
      expect(configs.keys).to match_array(described_class.types)
    end

    it "each config has name and configuration keys" do
      described_class.configs.each do |type, config|
        expect(config).to have_key(:name), "#{type} missing :name"
        expect(config).to have_key(:configuration), "#{type} missing :configuration"
        expect(config[:configuration]).to have_key(:default_model), "#{type} missing :default_model"
        expect(config[:configuration]).to have_key(:supported_models), "#{type} missing :supported_models"
        expect(config[:configuration]).to have_key(:capabilities), "#{type} missing :capabilities"
      end
    end
  end
end
