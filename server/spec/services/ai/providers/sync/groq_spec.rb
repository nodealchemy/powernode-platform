# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Groq do
  let(:account) { create(:account) }
  let(:provider) do
    create(:ai_provider,
           account: account,
           name: "Groq",
           slug: "groq",
           provider_type: "groq",
           api_base_url: "https://api.groq.com/openai/v1")
  end
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "gsk_test-groq-key-1234567890" })
  end

  let(:api_url) { "https://api.groq.com/openai/v1/models" }
  let(:api_response_body) do
    {
      data: [
        { id: "llama-3.3-70b-versatile", owned_by: "Meta", context_window: 131_072 },
        { id: "llama-3.1-8b-instant", owned_by: "Meta", context_window: 131_072 },
        { id: "mixtral-8x7b-32768", owned_by: "Mistral AI", context_window: 32_768 }
      ]
    }
  end

  before { credential }

  describe ".sync_groq_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_groq_models, provider)
        expect(result).to be true
      end

      it "updates provider with all models" do
        Ai::ProviderManagementService.send(:sync_groq_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(3)
      end

      it "formats model names with capitalization and B suffix" do
        Ai::ProviderManagementService.send(:sync_groq_models, provider)
        provider.reload
        llama70 = provider.supported_models.find { |m| m["id"] == "llama-3.3-70b-versatile" }
        expect(llama70["name"]).to include("70B")
      end

      it "sets context_length from context_window response field" do
        Ai::ProviderManagementService.send(:sync_groq_models, provider)
        provider.reload
        llama70 = provider.supported_models.find { |m| m["id"] == "llama-3.3-70b-versatile" }
        expect(llama70["context_length"]).to eq(131_072)

        mixtral = provider.supported_models.find { |m| m["id"] == "mixtral-8x7b-32768" }
        expect(mixtral["context_length"]).to eq(32_768)
      end

      it "defaults context_length to 8192 when context_window not provided" do
        response_without_ctx = { data: [{ id: "test-model", owned_by: "test" }] }
        stub_request(:get, api_url)
          .to_return(status: 200, body: response_without_ctx.to_json, headers: { "Content-Type" => "application/json" })

        Ai::ProviderManagementService.send(:sync_groq_models, provider)
        provider.reload
        test_model = provider.supported_models.first
        expect(test_model["context_length"]).to eq(8192)
      end

      it "assigns text_generation and chat capabilities" do
        Ai::ProviderManagementService.send(:sync_groq_models, provider)
        provider.reload
        provider.supported_models.each do |model|
          expect(model["capabilities"]).to eq(%w[text_generation chat])
        end
      end

      it "includes cost_per_1k_tokens, owned_by, and context_window" do
        Ai::ProviderManagementService.send(:sync_groq_models, provider)
        provider.reload
        llama70 = provider.supported_models.find { |m| m["id"] == "llama-3.3-70b-versatile" }
        expect(llama70).to have_key("cost_per_1k_tokens")
        expect(llama70["owned_by"]).to eq("Meta")
        expect(llama70["context_window"]).to eq(131_072)
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) do
        create(:ai_provider, account: account, name: "Groq No Creds", slug: "groq-no-creds", provider_type: "groq",
               api_base_url: "https://api.groq.com/openai/v1")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_groq_models, provider_without_creds)
        }.to raise_error(StandardError, /Failed to sync Groq models/)
      end
    end

    context "with API returning error" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 503, body: "Service Unavailable")
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_groq_models, provider)
        }.to raise_error(StandardError, /Failed to sync Groq models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("Socket error"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_groq_models, provider)
        }.to raise_error(StandardError, /Failed to sync Groq models/)
      end
    end
  end
end
