# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ProviderCatalog do
  describe ".all" do
    it "returns every built-in provider config" do
      types = described_class.all.map { |c| c[:provider_type] }
      expect(types).to contain_exactly("openai", "grok", "ollama", "anthropic")
    end
  end

  # E3b: three entries used to carry a literal configuration_schema
  # "default_model", which bootstrap then stored on every new account's
  # providers. The model now comes from each provider's synced catalog.
  it "names no default_model in any built-in entry" do
    described_class.all.each do |entry|
      expect(entry[:configuration_schema].to_h.stringify_keys).not_to have_key("default_model"), entry[:provider_type]
    end
  end

  describe ".for" do
    it "returns the catalog entry for a known provider_type" do
      entry = described_class.for("openai")
      expect(entry[:provider_type]).to eq("openai")
      expect(entry[:api_endpoint]).to be_present
      expect(entry[:capabilities]).to be_present
      expect(entry[:supported_models]).to be_present
    end

    it "returns nil for an unknown or blank provider_type" do
      expect(described_class.for("nope")).to be_nil
      expect(described_class.for(nil)).to be_nil
      expect(described_class.for("")).to be_nil
    end
  end

  describe ".merge_defaults" do
    it "fills the required fields the wizard omits, preserving the caller's name" do
      result = described_class.merge_defaults("provider_type" => "openai", "name" => "My OpenAI")

      expect(result[:name]).to eq("My OpenAI")
      expect(result[:api_endpoint]).to be_present
      expect(result[:capabilities]).to be_present
      expect(result[:supported_models]).to be_present
      expect(result[:configuration_schema]).to be_present
    end

    it "preserves an explicit false boolean (does not treat it as blank)" do
      result = described_class.merge_defaults("provider_type" => "openai", "supports_vision" => false)
      expect(result[:supports_vision]).to eq(false)
    end

    it "fills an empty array or blank string from the catalog" do
      result = described_class.merge_defaults("provider_type" => "openai", "capabilities" => [])
      expect(result[:capabilities]).to be_present
    end

    it "returns attrs unchanged for an unknown provider_type" do
      attrs = { "provider_type" => "mystery", "name" => "X" }
      expect(described_class.merge_defaults(attrs)).to eq(attrs)
    end

    it "returns attrs unchanged when provider_type is blank" do
      attrs = { "name" => "X" }
      expect(described_class.merge_defaults(attrs)).to eq(attrs)
    end
  end
end
