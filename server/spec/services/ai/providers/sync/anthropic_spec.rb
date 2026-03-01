# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Providers::Sync::Anthropic do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, :anthropic, account: account) }
  let(:credential) do
    create(:ai_provider_credential,
           provider: provider,
           account: account,
           credentials: { "api_key" => "sk-ant-test-key-1234567890abcdef" })
  end

  let(:api_url) { "https://api.anthropic.com/v1/models" }
  let(:api_response_body) do
    {
      data: [
        { id: "claude-opus-4-5-20251101", display_name: "Claude Opus 4.5", created_at: "2025-11-01T00:00:00Z" },
        { id: "claude-sonnet-4-5-20250929", display_name: "Claude Sonnet 4.5", created_at: "2025-09-29T00:00:00Z" },
        { id: "claude-haiku-4-5-20251001", display_name: "Claude Haiku 4.5", created_at: "2025-10-01T00:00:00Z" },
        { id: "claude-3-opus-20240229", display_name: "Claude 3 Opus", created_at: "2024-02-29T00:00:00Z" }
      ]
    }
  end

  before { credential }

  describe ".sync_anthropic_models" do
    context "with valid credentials and successful API response" do
      before do
        stub_request(:get, api_url)
          .with(headers: { "x-api-key" => "sk-ant-test-key-1234567890abcdef", "anthropic-version" => "2023-06-01" })
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "syncs models from the API" do
        result = Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        expect(result).to be true
      end

      it "updates provider supported_models" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload
        expect(provider.supported_models.length).to eq(4)
      end

      it "formats model names correctly" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload
        opus = provider.supported_models.find { |m| m["id"] == "claude-opus-4-5-20251101" }
        expect(opus["name"]).to be_present
        expect(opus["display_name"]).to eq("Claude Opus 4.5")
      end

      it "sets context_length to 200000 for all models" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload
        provider.supported_models.each do |model|
          expect(model["context_length"]).to eq(200_000)
        end
      end

      it "sets higher max_output_tokens for opus models" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload

        opus = provider.supported_models.find { |m| m["id"].include?("opus") }
        sonnet = provider.supported_models.find { |m| m["id"].include?("sonnet") }

        expect(opus["max_output_tokens"]).to eq(32_000)
        expect(sonnet["max_output_tokens"]).to eq(8192)
      end

      it "assigns capabilities including extended_thinking for opus" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload

        opus = provider.supported_models.find { |m| m["id"] == "claude-opus-4-5-20251101" }
        expect(opus["capabilities"]).to include("extended_thinking", "code_generation", "vision")

        haiku = provider.supported_models.find { |m| m["id"].include?("haiku") }
        expect(haiku["capabilities"]).not_to include("extended_thinking")
        expect(haiku["capabilities"]).not_to include("code_generation")
      end

      it "sorts by priority (opus 4.5 first)" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload
        expect(provider.supported_models.first["id"]).to eq("claude-opus-4-5-20251101")
      end

      it "includes cost_per_1k_tokens from pricing lookup" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload
        opus = provider.supported_models.find { |m| m["id"] == "claude-opus-4-5-20251101" }
        expect(opus).to have_key("cost_per_1k_tokens")
      end

      it "includes created_at metadata" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload
        opus = provider.supported_models.find { |m| m["id"] == "claude-opus-4-5-20251101" }
        expect(opus["created_at"]).to eq("2025-11-01T00:00:00Z")
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) { create(:ai_provider, :anthropic, account: account, name: "Anthropic No Creds", slug: "anthropic-no-creds") }

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_anthropic_models, provider_without_creds)
        }.to raise_error(StandardError, /Failed to sync Anthropic models/)
      end
    end

    context "with API returning non-success status" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 403, body: { error: "Forbidden" }.to_json)
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        }.to raise_error(StandardError, /Failed to sync Anthropic models/)
      end
    end

    context "with HTTP connection error" do
      before do
        stub_request(:get, api_url).to_raise(HTTP::ConnectionError.new("Connection refused"))
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        }.to raise_error(StandardError, /Failed to sync Anthropic models/)
      end
    end

    context "with malformed JSON response" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: "<html>error</html>", headers: { "Content-Type" => "text/html" })
      end

      it "calls handle_sync_failure" do
        expect {
          Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        }.to raise_error(StandardError, /Failed to sync Anthropic models/)
      end
    end
  end
end
