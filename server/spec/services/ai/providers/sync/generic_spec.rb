# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Generic do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Custom Provider",
           slug: "custom-provider",
           provider_type: "custom",
           api_base_url: "https://custom-llm.example.com/v1")
  end

  describe ".sync_generic_models" do
    it "sets a single default model" do
      Ai::ProviderManagementService.send(:sync_generic_models, provider)
      provider.reload
      expect(provider.supported_models.length).to eq(1)
    end

    it "uses 'default' as the model id" do
      Ai::ProviderManagementService.send(:sync_generic_models, provider)
      provider.reload
      model = provider.supported_models.first
      expect(model["id"]).to eq("default")
    end

    it "names the model 'Default Model'" do
      Ai::ProviderManagementService.send(:sync_generic_models, provider)
      provider.reload
      model = provider.supported_models.first
      expect(model["name"]).to eq("Default Model")
    end

    it "sets context_length to 4096" do
      Ai::ProviderManagementService.send(:sync_generic_models, provider)
      provider.reload
      model = provider.supported_models.first
      expect(model["context_length"]).to eq(4096)
    end

    it "includes provider name in description" do
      Ai::ProviderManagementService.send(:sync_generic_models, provider)
      provider.reload
      model = provider.supported_models.first
      expect(model["description"]).to include("Custom Provider")
    end

    it "does not require credentials" do
      result = Ai::ProviderManagementService.send(:sync_generic_models, provider)
      provider.reload
      expect(provider.supported_models).to be_present
    end

    it "does not make any HTTP requests" do
      Ai::ProviderManagementService.send(:sync_generic_models, provider)
      # WebMock will raise if any unstubbed request is made
    end
  end
end
