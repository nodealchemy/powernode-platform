# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Cohere do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Cohere",
           slug: "cohere",
           provider_type: "cohere",
           api_base_url: "https://api.cohere.com/v1")
  end
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "test-cohere-key-1234567890" })
  end

  let(:api_url) { "https://api.cohere.com/v1/models" }
  let(:api_response_body) do
    {
      models: [
        {
          id: "command-r-plus",
          name: "Command R Plus",
          context_length: 128_000,
          max_output_tokens: 4096,
          description: "Most capable Cohere model",
          endpoints: %w[chat generate]
        },
        {
          id: "command-r",
          name: "Command R",
          context_length: 128_000,
          max_output_tokens: 4096,
          description: "Balanced model for enterprise use",
          endpoints: %w[chat generate]
        },
        {
          id: "embed-english-v3.0",
          name: "Embed English v3.0",
          context_length: 512,
          description: "English embedding model",
          endpoints: ["embed"]
        },
        {
          id: "rerank-english-v3.0",
          name: "Rerank English v3.0",
          description: "English reranking model",
          endpoints: ["rerank"]
        }
      ]
    }
  end

  before { credential }

  describe ".sync_cohere_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        expect(result).to be true
      end

      it "includes all model types" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(4)
      end

      it "uses model name from API response" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        cmd_r_plus = provider.supported_models.find { |m| m["id"] == "command-r-plus" }
        expect(cmd_r_plus["name"]).to eq("Command R Plus")
      end

      it "sets context_length from API response" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        cmd_r_plus = provider.supported_models.find { |m| m["id"] == "command-r-plus" }
        expect(cmd_r_plus["context_length"]).to eq(128_000)
      end

      it "defaults context_length to 4096 when not provided" do
        response_without_ctx = { models: [{ id: "test-model", name: "Test" }] }
        stub_request(:get, api_url)
          .to_return(status: 200, body: response_without_ctx.to_json, headers: { "Content-Type" => "application/json" })

        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        test_model = provider.supported_models.find { |m| m["id"] == "test-model" }
        expect(test_model["context_length"]).to eq(4096)
      end

      it "assigns embeddings capability for embed models" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        embed = provider.supported_models.find { |m| m["id"] == "embed-english-v3.0" }
        expect(embed["capabilities"]).to eq(%w[embeddings])
      end

      it "assigns rerank capability for rerank models" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        rerank = provider.supported_models.find { |m| m["id"] == "rerank-english-v3.0" }
        expect(rerank["capabilities"]).to eq(%w[rerank])
      end

      it "assigns chat capabilities for command models" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        cmd_r = provider.supported_models.find { |m| m["id"] == "command-r" }
        expect(cmd_r["capabilities"]).to include("text_generation", "chat", "function_calling")
      end

      it "includes endpoints metadata" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        cmd_r_plus = provider.supported_models.find { |m| m["id"] == "command-r-plus" }
        expect(cmd_r_plus["endpoints"]).to eq(%w[chat generate])
      end

      it "includes cost_per_1k_tokens from pricing lookup" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        cmd_r_plus = provider.supported_models.find { |m| m["id"] == "command-r-plus" }
        expect(cmd_r_plus).to have_key("cost_per_1k_tokens")
      end
    end

    context "with model lacking id but having name" do
      before do
        response = { models: [{ name: "command-r-plus", context_length: 128_000 }] }
        stub_request(:get, api_url)
          .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "uses name as fallback for id" do
        Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        provider.reload
        model = provider.supported_models.first
        expect(model["id"]).to eq("command-r-plus")
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) do
        create(:ai_provider, account: account, name: "Cohere No Creds", slug: "cohere-no-creds", provider_type: "cohere",
               api_base_url: "https://api.cohere.com/v1")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_cohere_models, provider_without_creds)
        }.to raise_error(StandardError, /Failed to sync Cohere models/)
      end
    end

    context "with API returning error" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 429, body: { message: "Rate limited" }.to_json)
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        }.to raise_error(StandardError, /Failed to sync Cohere models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("Connection reset"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_cohere_models, provider)
        }.to raise_error(StandardError, /Failed to sync Cohere models/)
      end
    end
  end
end
