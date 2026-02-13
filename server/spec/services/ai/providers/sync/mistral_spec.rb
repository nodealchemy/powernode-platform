# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Mistral do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Mistral",
           slug: "mistral",
           provider_type: "mistral",
           api_base_url: "https://api.mistral.ai/v1")
  end
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "test-mistral-key-1234567890" })
  end

  let(:api_url) { "https://api.mistral.ai/v1/models" }
  let(:api_response_body) do
    {
      data: [
        { id: "mistral-large-latest", owned_by: "mistralai", max_context_length: 128_000, description: "Most capable Mistral model" },
        { id: "mistral-small-latest", owned_by: "mistralai", max_context_length: 32_000, description: "Efficient small model" },
        { id: "codestral-latest", owned_by: "mistralai", max_context_length: 32_000, description: "Code-focused model" },
        { id: "pixtral-large-latest", owned_by: "mistralai", max_context_length: 128_000, description: "Vision model" }
      ]
    }
  end

  before { credential }

  describe ".sync_mistral_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        expect(result).to be true
      end

      it "updates provider with all models" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(4)
      end

      it "formats model names by removing -latest suffix" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        large = provider.supported_models.find { |m| m["id"] == "mistral-large-latest" }
        expect(large["name"]).to eq("Mistral Large")
      end

      it "sets context length from max_context_length" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        large = provider.supported_models.find { |m| m["id"] == "mistral-large-latest" }
        expect(large["context_length"]).to eq(128_000)
      end

      it "defaults context length to 32000 when not provided" do
        response_without_context = { data: [{ id: "mistral-tiny", owned_by: "mistralai" }] }
        stub_request(:get, api_url)
          .to_return(status: 200, body: response_without_context.to_json, headers: { "Content-Type" => "application/json" })

        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        tiny = provider.supported_models.find { |m| m["id"] == "mistral-tiny" }
        expect(tiny["context_length"]).to eq(32_000)
      end

      it "assigns function_calling capability for large and small models" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload

        large = provider.supported_models.find { |m| m["id"] == "mistral-large-latest" }
        expect(large["capabilities"]).to include("function_calling")

        small = provider.supported_models.find { |m| m["id"] == "mistral-small-latest" }
        expect(small["capabilities"]).to include("function_calling")
      end

      it "assigns vision capability for pixtral models" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        pixtral = provider.supported_models.find { |m| m["id"] == "pixtral-large-latest" }
        expect(pixtral["capabilities"]).to include("vision")
      end

      it "assigns code_generation capability for codestral models" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        codestral = provider.supported_models.find { |m| m["id"] == "codestral-latest" }
        expect(codestral["capabilities"]).to include("code_generation")
      end

      it "includes cost_per_1k_tokens and description" do
        Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        provider.reload
        large = provider.supported_models.find { |m| m["id"] == "mistral-large-latest" }
        expect(large).to have_key("cost_per_1k_tokens")
        expect(large["description"]).to eq("Most capable Mistral model")
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) do
        create(:ai_provider, account: account, name: "Mistral", slug: "mistral-2", provider_type: "mistral",
               api_base_url: "https://api.mistral.ai/v1")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_mistral_models, provider_without_creds)
        }.to raise_error(StandardError, /Failed to sync Mistral models/)
      end
    end

    context "with API returning error" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        }.to raise_error(StandardError, /Failed to sync Mistral models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("Timeout"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_mistral_models, provider)
        }.to raise_error(StandardError, /Failed to sync Mistral models/)
      end
    end
  end
end
