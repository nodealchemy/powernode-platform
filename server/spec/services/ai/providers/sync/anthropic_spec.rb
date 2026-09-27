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
        { id: "claude-opus-4-1-20250805", display_name: "Claude Opus 4.1", created_at: "2025-08-05T00:00:00Z" }
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

      it "sets context_length to 200000 for all legacy models" do
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
        expect(sonnet["max_output_tokens"]).to eq(64_000)
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

    context "with current-generation models in the API response" do
      let(:api_response_body) do
        {
          data: [
            { id: "claude-haiku-4-5-20251001", display_name: "Claude Haiku 4.5", created_at: "2025-10-01T00:00:00Z" },
            { id: "claude-sonnet-5", display_name: "Claude Sonnet 5", created_at: "2026-03-01T00:00:00Z" },
            { id: "claude-fable-5", display_name: "Claude Fable 5", created_at: "2026-07-01T00:00:00Z" },
            { id: "claude-opus-4-8", display_name: "Claude Opus 4.8", created_at: "2026-05-01T00:00:00Z" }
          ]
        }
      end

      before do
        stub_request(:get, api_url)
          .with(headers: { "x-api-key" => "sk-ant-test-key-1234567890abcdef", "anthropic-version" => "2023-06-01" })
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "gives current-generation models the 1M-context / 128K-output envelope" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload

        %w[claude-fable-5 claude-opus-4-8 claude-sonnet-5].each do |id|
          model = provider.supported_models.find { |m| m["id"] == id }
          expect(model["context_length"]).to eq(1_000_000), "#{id} context"
          expect(model["max_output_tokens"]).to eq(128_000), "#{id} max output"
        end
      end

      it "keeps Haiku 4.5 at 200K context / 64K output" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload

        haiku = provider.supported_models.find { |m| m["id"] == "claude-haiku-4-5-20251001" }
        expect(haiku["context_length"]).to eq(200_000)
        expect(haiku["max_output_tokens"]).to eq(64_000)
      end

      it "sorts Fable first, then Opus, then Sonnet, then Haiku" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload

        expect(provider.supported_models.map { |m| m["id"] }).to eq(
          %w[claude-fable-5 claude-opus-4-8 claude-sonnet-5 claude-haiku-4-5-20251001]
        )
      end
    end

    context "with Claude releases newer than the listed families" do
      let(:api_response_body) do
        {
          data: [
            { id: "claude-opus-5", display_name: "Claude Opus 5", created_at: "2026-08-01T00:00:00Z" },
            { id: "claude-opus-5-5", display_name: "Claude Opus 5.5", created_at: "2026-09-01T00:00:00Z" }
          ]
        }
      end

      before do
        stub_request(:get, api_url)
          .with(headers: { "x-api-key" => "sk-ant-test-key-1234567890abcdef", "anthropic-version" => "2023-06-01" })
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "gives them the 1M-context / 128K-output envelope, not the old-Opus 200K / 32K" do
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        provider.reload

        %w[claude-opus-5 claude-opus-5-5].each do |id|
          model = provider.supported_models.find { |m| m["id"] == id }
          expect(model["context_length"]).to eq(1_000_000), "#{id} context"
          expect(model["max_output_tokens"]).to eq(128_000), "#{id} max output"
        end
      end
    end

    # Re-audit trigger (prompt-audit guardrail): a synced id whose family is in
    # neither ModelCapabilities::LEGACY_CLAUDE_PREFIXES nor ModelTiers::TIERS
    # files one improvement offer per family through ImprovementTool. The ids
    # below are synthetic; they name no real or announced model.
    context "with a model family the platform does not know" do
      let(:unknown_family) { "claude-zephyr" }
      let(:fingerprint) { "new_model_family|claude-zephyr" }
      let(:api_response_body) do
        {
          data: [
            { id: "claude-zephyr-1-20990101", display_name: "Synthetic Zephyr 1", created_at: "2099-01-01T00:00:00Z" },
            { id: "claude-zephyr-1-20990601", display_name: "Synthetic Zephyr 1", created_at: "2099-06-01T00:00:00Z" },
            { id: "claude-opus-4-5-20251101", display_name: "Claude Opus 4.5", created_at: "2025-11-01T00:00:00Z" },
            { id: "claude-sonnet-5", display_name: "Claude Sonnet 5", created_at: "2026-03-01T00:00:00Z" },
            { id: "claude-fable-5", display_name: "Claude Fable 5", created_at: "2026-07-01T00:00:00Z" },
            { id: "claude-3-5-sonnet-20241022", display_name: "Claude 3.5 Sonnet", created_at: "2024-10-22T00:00:00Z" }
          ]
        }
      end

      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      def sync!
        Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
      end

      it "files exactly one pending offer for the new family, and none for the known families" do
        expect { sync! }.to change { Ai::ImprovementRecommendation.where(account: account).count }.by(1)

        rec = Ai::ImprovementRecommendation.find_by!(account: account)
        expect(rec.fingerprint).to eq(fingerprint)
        expect(rec.status).to eq("pending")
        expect(rec.target_type).to eq("Account")
        expect(rec.evidence["title"]).to include(unknown_family, "prompt audit", "effort sweep")
        expect(rec.evidence["description"]).to include("claude-zephyr-1-20990101", "claude-zephyr-1-20990601")
      end

      it "does not file another offer on a second sync" do
        sync!
        expect { sync! }.not_to(change { Ai::ImprovementRecommendation.where(account: account).count })
      end

      it "does not re-file once the offer has been dismissed" do
        sync!
        Ai::ImprovementRecommendation.find_by!(account: account, fingerprint: fingerprint)
                                     .update!(status: "dismissed")

        expect { sync! }.not_to(change { Ai::ImprovementRecommendation.where(account: account).count })
      end

      it "still completes the sync when filing the offer raises" do
        tool = instance_double(Ai::Tools::ImprovementTool)
        allow(Ai::Tools::ImprovementTool).to receive(:new).and_return(tool)
        expect(tool).to receive(:execute).and_raise(StandardError, "offer store unavailable")

        expect(sync!).to be true
        expect(provider.reload.supported_models.map { |m| m["id"] }).to include("claude-zephyr-1-20990101")
        expect(Ai::ImprovementRecommendation.where(account: account)).to be_empty
      end
    end

    context "with only known model families" do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: api_response_body.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "files no offer" do
        expect(Ai::Tools::ImprovementTool).not_to receive(:new)

        expect {
          Ai::ProviderManagementService.send(:sync_anthropic_models, provider)
        }.not_to(change { Ai::ImprovementRecommendation.count })
      end
    end

    context "with no credentials" do
      let(:provider_without_creds) { create(:ai_provider, :anthropic, account: account, name: "Anthropic No Creds", slug: "anthropic-no-creds") }

      it "skips the sync and returns false (defers until credentials exist)" do
        result = nil
        expect {
          result = Ai::ProviderManagementService.send(:sync_anthropic_models, provider_without_creds)
        }.not_to raise_error
        expect(result).to be false
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
