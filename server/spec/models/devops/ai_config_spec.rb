# frozen_string_literal: true

require "rails_helper"

# Specs for Devops::AiConfig#resolved_model — the #37 dynamic-resolution branch.
# An explicit model string is honored as a pin; the "auto"/"default" sentinels
# resolve a model at runtime, staying WITHIN the config's own provider:
# code/chat configs route through the shared Ai::AgentModelSelector (provider-
# constrained), embedding configs pick a text_embedding model directly, and a
# missing provider yields nil (no sentinel/blank leak).
RSpec.describe Devops::AiConfig, type: :model do
  let(:account) { create(:account) }

  describe "#resolved_model with an explicit (pinned) model" do
    it "returns the pinned model verbatim" do
      config = create(:devops_ai_config, account: account, config_type: "code_review",
                                         provider: "openai", model: "gpt-4o")

      expect(config.resolved_model).to eq("gpt-4o")
    end

    it "does not consult the selector for an explicit model" do
      config = create(:devops_ai_config, account: account, config_type: "code_review",
                                         provider: "openai", model: "gpt-4o")

      expect(Ai::AgentModelSelector).not_to receive(:recommend)
      config.resolved_model
    end
  end

  describe "#resolved_model with model \"auto\" (code_review) and the provider present" do
    let!(:provider) do
      create(:ai_provider, :openai, account: account, provider_type: "openai")
    end
    let(:config) do
      create(:devops_ai_config, account: account, config_type: "code_review",
                                provider: "openai", model: "auto")
    end

    it "routes through AgentModelSelector constrained to the config's provider, as a code_assistant" do
      expect(Ai::AgentModelSelector).to receive(:recommend)
        .with(hash_including(provider: provider, agent_type: "code_assistant"))
        .and_return({ provider: provider, model: "gpt-4o", provider_type: "openai" })

      expect(config.resolved_model).to eq("gpt-4o")
    end

    it "resolves to a model from that provider's catalog (real selection)" do
      catalog_ids = provider.supported_models.map { |m| m["id"] || m["name"] }

      expect(catalog_ids).to include(config.resolved_model)
    end
  end

  describe "#resolved_model with model \"auto\" (embedding)" do
    # The provider exposes both a chat model and a text_embedding-capable model;
    # an embedding config must pick the embedding-capable one, NOT a chat model.
    let!(:provider) do
      create(:ai_provider, account: account, provider_type: "openai",
                           capabilities: %w[text_generation chat text_embedding],
                           supported_models: [
                             { "id" => "gpt-4o", "name" => "gpt-4o",
                               "capabilities" => %w[text_generation chat] },
                             { "id" => "text-embedding-3-small", "name" => "text-embedding-3-small",
                               "capabilities" => %w[text_embedding] }
                           ])
    end
    let(:config) do
      create(:devops_ai_config, account: account, config_type: "embedding",
                                provider: "openai", model: "auto",
                                max_tokens: nil, temperature: nil)
    end

    it "returns the text_embedding-capable model" do
      expect(config.resolved_model).to eq("text-embedding-3-small")
    end

    it "does not return a chat-only model" do
      expect(config.resolved_model).not_to eq("gpt-4o")
    end

    it "does not route an embedding config through the chat selector" do
      expect(Ai::AgentModelSelector).not_to receive(:recommend)
      config.resolved_model
    end
  end

  describe "#resolved_model with model \"auto\" but the declared provider absent" do
    it "returns nil (no sentinel or blank leak) when no matching provider exists" do
      # No Ai::Provider with provider_type "openai" in this account.
      config = create(:devops_ai_config, account: account, config_type: "code_review",
                                         provider: "openai", model: "auto")

      expect(config.resolved_model).to be_nil
    end

    it "returns nil when the only matching provider is inactive" do
      create(:ai_provider, :openai, account: account, provider_type: "openai", is_active: false)
      config = create(:devops_ai_config, account: account, config_type: "code_review",
                                         provider: "openai", model: "auto")

      expect(config.resolved_model).to be_nil
    end
  end
end
