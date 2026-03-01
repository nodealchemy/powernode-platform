# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Azure do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Azure OpenAI",
           slug: "azure",
           provider_type: "azure",
           api_base_url: "https://myinstance.openai.azure.com")
  end

  describe ".sync_azure_models" do
    it "returns true" do
      result = Ai::ProviderManagementService.send(:sync_azure_models, provider)
      expect(result).to be true
    end

    it "sets static model list with 3 models" do
      Ai::ProviderManagementService.send(:sync_azure_models, provider)
      provider.reload
      expect(provider.supported_models.length).to eq(3)
    end

    it "includes gpt-4o model" do
      Ai::ProviderManagementService.send(:sync_azure_models, provider)
      provider.reload
      gpt4o = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
      expect(gpt4o).to be_present
      expect(gpt4o["name"]).to eq("GPT-4o")
      expect(gpt4o["context_length"]).to eq(128_000)
      expect(gpt4o["max_output_tokens"]).to eq(16_384)
      expect(gpt4o["capabilities"]).to include("vision", "function_calling")
    end

    it "includes gpt-4o-mini model" do
      Ai::ProviderManagementService.send(:sync_azure_models, provider)
      provider.reload
      mini = provider.supported_models.find { |m| m["id"] == "gpt-4o-mini" }
      expect(mini).to be_present
      expect(mini["name"]).to eq("GPT-4o Mini")
      expect(mini["context_length"]).to eq(128_000)
    end

    it "includes gpt-4-turbo model" do
      Ai::ProviderManagementService.send(:sync_azure_models, provider)
      provider.reload
      turbo = provider.supported_models.find { |m| m["id"] == "gpt-4-turbo" }
      expect(turbo).to be_present
      expect(turbo["name"]).to eq("GPT-4 Turbo")
      expect(turbo["max_output_tokens"]).to eq(4096)
    end

    it "includes cost_per_1k_tokens from pricing lookup" do
      Ai::ProviderManagementService.send(:sync_azure_models, provider)
      provider.reload
      provider.supported_models.each do |model|
        expect(model).to have_key("cost_per_1k_tokens")
      end
    end

    it "does not require credentials" do
      # No credentials created - should still work
      result = Ai::ProviderManagementService.send(:sync_azure_models, provider)
      expect(result).to be true
      provider.reload
      expect(provider.supported_models.length).to eq(3)
    end

    it "does not make any HTTP requests" do
      Ai::ProviderManagementService.send(:sync_azure_models, provider)
      # WebMock will raise if any unstubbed request is made
      # This test passes if no HTTP error is raised
    end
  end
end
