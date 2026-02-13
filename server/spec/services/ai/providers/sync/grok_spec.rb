# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Grok do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Grok",
           slug: "grok",
           provider_type: "grok",
           api_base_url: "https://api.x.ai/v1")
  end
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "xai-test-key-1234567890" })
  end

  let(:api_url) { "https://api.x.ai/v1/models" }
  let(:api_response_body) do
    {
      data: [
        { id: "grok-3", owned_by: "xai" },
        { id: "grok-3-mini", owned_by: "xai" },
        { id: "grok-3-fast", owned_by: "xai" },
        { id: "grok-2", owned_by: "xai" },
        { id: "grok-2-vision", owned_by: "xai" }
      ]
    }
  end

  before { credential }

  describe ".sync_grok_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_grok_models, provider)
        expect(result).to be true
      end

      it "updates provider with all models" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(5)
      end

      it "formats model names correctly" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        grok3 = provider.supported_models.find { |m| m["id"] == "grok-3" }
        expect(grok3["name"]).to eq("Grok 3")
      end

      it "sets context_length to 131072 for all models" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        provider.supported_models.each do |model|
          expect(model["context_length"]).to eq(131_072)
        end
      end

      it "sets max_output_tokens to 8192 for all models" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        provider.supported_models.each do |model|
          expect(model["max_output_tokens"]).to eq(8192)
        end
      end

      it "assigns vision capability for vision models" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        vision_model = provider.supported_models.find { |m| m["id"] == "grok-2-vision" }
        expect(vision_model["capabilities"]).to include("vision")
      end

      it "assigns base capabilities for non-vision models" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        grok3 = provider.supported_models.find { |m| m["id"] == "grok-3" }
        expect(grok3["capabilities"]).to include("text_generation", "chat", "function_calling")
        expect(grok3["capabilities"]).not_to include("vision")
      end

      it "includes cost_per_1k_tokens and owned_by" do
        Ai::ProviderManagementService.send(:sync_grok_models, provider)
        provider.reload
        grok3 = provider.supported_models.find { |m| m["id"] == "grok-3" }
        expect(grok3).to have_key("cost_per_1k_tokens")
        expect(grok3["owned_by"]).to eq("xai")
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) do
        create(:ai_provider, account: account, name: "Grok", slug: "grok-2", provider_type: "grok",
               api_base_url: "https://api.x.ai/v1")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_grok_models, provider_without_creds)
        }.to raise_error(StandardError, /Failed to sync Grok models/)
      end
    end

    context "with API returning error" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 401, body: { error: "Invalid API key" }.to_json)
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_grok_models, provider)
        }.to raise_error(StandardError, /Failed to sync Grok models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("Connection refused"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_grok_models, provider)
        }.to raise_error(StandardError, /Failed to sync Grok models/)
      end
    end
  end
end
