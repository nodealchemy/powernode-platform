# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Openai do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, :openai, account: account) }
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "sk-test-key-long-enough-1234567890123456" })
  end

  let(:api_url) { "https://api.openai.com/v1/models" }
  let(:api_response_body) do
    {
      data: [
        { id: "gpt-4o", owned_by: "openai", created: Time.current.to_i },
        { id: "gpt-4o-mini", owned_by: "openai", created: Time.current.to_i },
        { id: "gpt-3.5-turbo", owned_by: "openai", created: Time.current.to_i },
        { id: "o3", owned_by: "openai", created: Time.current.to_i },
        { id: "text-embedding-3-small", owned_by: "openai", created: Time.current.to_i },
        { id: "text-embedding-3-large", owned_by: "openai", created: Time.current.to_i },
        { id: "text-embedding-ada-002", owned_by: "openai", created: Time.current.to_i },
        { id: "dall-e-3", owned_by: "openai", created: Time.current.to_i },
        { id: "gpt-4-instruct", owned_by: "openai", created: Time.current.to_i }
      ]
    }
  end

  before { credential }

  describe ".sync_openai_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_openai_models, provider)
        expect(result).to be true
      end

      it "updates provider supported_models" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        expect(provider.supported_models).to be_present
      end

      it "includes embedding models tagged with the text_embedding capability ONLY" do
        # Embedding models are registered in the catalog (durable, since the daily
        # sync overwrites supported_models) so capability-based embedding
        # resolution can find them. They carry the text_embedding capability and
        # MUST NOT carry chat/text_generation — otherwise Ai::AgentModelSelector,
        # which hard-gates chat candidates on those capabilities, could offer an
        # embedding-only model for a chat task.
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload

        small = provider.supported_models.find { |m| m["id"] == "text-embedding-3-small" }
        expect(small).to be_present
        expect(small["capabilities"]).to eq(%w[text_embedding])
        expect(small["capabilities"]).not_to include("chat", "text_generation", "function_calling")
      end

      it "registers all three OpenAI embedding models with sensible dimensions" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload

        by_id = provider.supported_models.index_by { |m| m["id"] }
        expect(by_id).to include("text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002")
        expect(by_id["text-embedding-3-small"]["dimensions"]).to eq(1536)
        expect(by_id["text-embedding-3-large"]["dimensions"]).to eq(3072)
        expect(by_id["text-embedding-ada-002"]["dimensions"]).to eq(1536)

        # Every embedding entry is text_embedding-only (never chat-gated).
        %w[text-embedding-3-small text-embedding-3-large text-embedding-ada-002].each do |id|
          expect(by_id[id]["capabilities"]).to eq(%w[text_embedding])
        end
      end

      it "includes image generation models with the image_generation capability" do
        # DALL-E models are intentionally collected (since the image-generation
        # feature, 4efba9f4) and carry the image_generation capability rather
        # than being filtered out as non-chat models.
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        dalle = provider.supported_models.find { |m| m["id"] == "dall-e-3" }
        expect(dalle).to be_present
        expect(dalle["capabilities"]).to include("image_generation")
      end

      it "filters out instruct models" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        model_ids = provider.supported_models.map { |m| m["id"] }
        expect(model_ids).not_to include("gpt-4-instruct")
      end

      it "includes chat-compatible models" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        model_ids = provider.supported_models.map { |m| m["id"] }
        expect(model_ids).to include("gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo", "o3")
      end

      it "formats model names correctly" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        gpt4o_model = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
        expect(gpt4o_model["name"]).to be_present
        expect(gpt4o_model["name"]).to include("GPT")
      end

      it "sets context length based on model type" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload

        gpt4o = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
        expect(gpt4o["context_length"]).to eq(128_000)

        o3_model = provider.supported_models.find { |m| m["id"] == "o3" }
        expect(o3_model["context_length"]).to eq(200_000)

        gpt35 = provider.supported_models.find { |m| m["id"] == "gpt-3.5-turbo" }
        expect(gpt35["context_length"]).to eq(16_385)
      end

      it "sets max_output_tokens based on model type" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload

        gpt4o = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
        expect(gpt4o["max_output_tokens"]).to eq(16_384)

        o3_model = provider.supported_models.find { |m| m["id"] == "o3" }
        expect(o3_model["max_output_tokens"]).to eq(100_000)
      end

      it "assigns capabilities including vision for supported models" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload

        gpt4o = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
        expect(gpt4o["capabilities"]).to include("vision", "text_generation", "chat", "function_calling")

        o3_model = provider.supported_models.find { |m| m["id"] == "o3" }
        expect(o3_model["capabilities"]).to include("reasoning", "vision")
      end

      it "sorts models by priority (gpt-4o first)" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        expect(provider.supported_models.first["id"]).to eq("gpt-4o")
      end

      it "includes cost_per_1k_tokens from pricing lookup" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        gpt4o = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
        expect(gpt4o).to have_key("cost_per_1k_tokens")
      end

      it "includes owned_by and created_at metadata" do
        Ai::ProviderManagementService.send(:sync_openai_models, provider)
        provider.reload
        gpt4o = provider.supported_models.find { |m| m["id"] == "gpt-4o" }
        expect(gpt4o["owned_by"]).to eq("openai")
        expect(gpt4o["created_at"]).to be_present
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) { create(:ai_provider, :openai, account: account, name: "OpenAI No Creds", slug: "openai-no-creds") }

      it "skips the sync and returns false (defers until credentials exist)" do
        result = nil
        expect {
          result = Ai::ProviderManagementService.send(:sync_openai_models, provider_without_creds)
        }.not_to raise_error
        expect(result).to be false
      end
    end

    context "with API returning error status" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 401, body: { error: { message: "Invalid API key" } }.to_json)
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_openai_models, provider)
        }.to raise_error(StandardError, /Failed to sync OpenAI models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("Connection refused"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_openai_models, provider)
        }.to raise_error(StandardError, /Failed to sync OpenAI models/)
      end
    end

    context "with malformed JSON response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: "not valid json{{{", headers: { "Content-Type" => "application/json" })
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_openai_models, provider)
        }.to raise_error(StandardError, /Failed to sync OpenAI models/)
      end
    end

    context "with empty model list" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: { data: [] }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns true from sync" do
        result = Ai::ProviderManagementService.send(:sync_openai_models, provider)
        expect(result).to be true
      end
    end
  end
end
