# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Google do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Google",
           slug: "google",
           provider_type: "google",
           api_base_url: "https://generativelanguage.googleapis.com/v1beta")
  end
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "AIzaSy-test-google-key-12345" })
  end

  let(:api_url) { "https://generativelanguage.googleapis.com/v1beta/models?key=AIzaSy-test-google-key-12345" }
  let(:api_response_body) do
    {
      models: [
        {
          name: "models/gemini-2.0-flash",
          displayName: "Gemini 2.0 Flash",
          description: "Fast and versatile multimodal model",
          inputTokenLimit: 1_048_576,
          outputTokenLimit: 8192,
          supportThinking: false,
          maxTemperature: 2.0,
          supportedGenerationMethods: %w[generateContent countTokens]
        },
        {
          name: "models/gemini-1.5-pro",
          displayName: "Gemini 1.5 Pro",
          description: "Advanced reasoning model",
          inputTokenLimit: 2_097_152,
          outputTokenLimit: 8192,
          supportThinking: true,
          maxTemperature: 2.0,
          supportedGenerationMethods: %w[generateContent countTokens]
        },
        {
          name: "models/text-embedding-004",
          displayName: "Text Embedding 004",
          description: "Embedding model",
          inputTokenLimit: 2048,
          supportedGenerationMethods: ["embedContent"]
        }
      ]
    }
  end

  before { credential }

  describe ".sync_google_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_google_models, provider)
        expect(result).to be true
      end

      it "filters to gemini models only" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        model_ids = provider.supported_models.map { |m| m["id"] }
        expect(model_ids).to include("gemini-2.0-flash", "gemini-1.5-pro")
        expect(model_ids).not_to include("text-embedding-004")
      end

      it "extracts model ID from full name path" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        expect(provider.supported_models.first["id"]).not_to include("models/")
      end

      it "uses displayName for the model name" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        flash = provider.supported_models.find { |m| m["id"] == "gemini-2.0-flash" }
        expect(flash["name"]).to eq("Gemini 2.0 Flash")
      end

      it "sets context length from inputTokenLimit" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        flash = provider.supported_models.find { |m| m["id"] == "gemini-2.0-flash" }
        expect(flash["context_length"]).to eq(1_048_576)
      end

      it "sets max_output_tokens from outputTokenLimit" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        flash = provider.supported_models.find { |m| m["id"] == "gemini-2.0-flash" }
        expect(flash["max_output_tokens"]).to eq(8192)
      end

      it "includes supports_thinking field" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        pro = provider.supported_models.find { |m| m["id"] == "gemini-1.5-pro" }
        expect(pro["supports_thinking"]).to be true
      end

      it "assigns capabilities including audio for 1.5+ and code_execution for 2.0" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload

        flash = provider.supported_models.find { |m| m["id"] == "gemini-2.0-flash" }
        expect(flash["capabilities"]).to include("audio", "code_execution", "vision")

        pro = provider.supported_models.find { |m| m["id"] == "gemini-1.5-pro" }
        expect(pro["capabilities"]).to include("audio")
        expect(pro["capabilities"]).not_to include("code_execution")
      end

      it "includes cost_per_1k_tokens from pricing lookup" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        flash = provider.supported_models.find { |m| m["id"] == "gemini-2.0-flash" }
        expect(flash).to have_key("cost_per_1k_tokens")
      end

      it "includes supported_methods metadata" do
        Ai::ProviderManagementService.send(:sync_google_models, provider)
        provider.reload
        flash = provider.supported_models.find { |m| m["id"] == "gemini-2.0-flash" }
        expect(flash["supported_methods"]).to include("generateContent")
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) do
        create(:ai_provider, account: account, name: "Google No Creds", slug: "google-no-creds", provider_type: "google",
               api_base_url: "https://generativelanguage.googleapis.com/v1beta")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_google_models, provider_without_creds)
        }.to raise_error(StandardError, /Failed to sync Google models/)
      end
    end

    context "with API returning error status" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 400, body: { error: { message: "API key not valid" } }.to_json)
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_google_models, provider)
        }.to raise_error(StandardError, /Failed to sync Google models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("DNS resolution failed"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_google_models, provider)
        }.to raise_error(StandardError, /Failed to sync Google models/)
      end
    end
  end
end
