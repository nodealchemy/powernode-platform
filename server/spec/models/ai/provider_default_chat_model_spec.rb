# frozen_string_literal: true

require "rails_helper"

# The default model and the connection-test model must be CHAT-capable. A synced
# OpenAI list leads with completion-only, embedding and search/preview ids;
# picking one of those failed the credential test with "not a chat model".
RSpec.describe Ai::Provider, "default chat model" do
  def models(*ids) = ids.map { |id| { "id" => id, "name" => id } }

  let(:provider) do
    build(:ai_provider, provider_type: "openai", capabilities: %w[text_generation chat text_embedding],
                        supported_models: models("babbage-002", "text-embedding-3-small",
                                                 "gpt-4o-mini-search-preview-2025-03-11",
                                                 "gpt-4o-mini-audio-preview", "omni-moderation-latest",
                                                 "gpt-4o-mini-2024-07-18", "gpt-4o"))
  end

  it "excludes completion-only, embedding, search, preview, audio and moderation ids" do
    expect(provider.default_model).to eq("gpt-4o-mini-2024-07-18")
  end

  it "prefers the catalog's per-type chat default, exact id first" do
    provider.supported_models = models("babbage-002", "gpt-4o", "gpt-4o-mini", "gpt-4o-mini-2024-07-18")

    expect(provider.default_model).to eq(Ai::ProviderCatalog.for("openai")[:default_chat_model])
  end

  it "falls back to the lightest chat-capable model when the catalog default was not synced" do
    provider.supported_models = models("text-embedding-3-small", "gpt-4o-search-preview", "gpt-4o")

    expect(provider.default_model).to eq("gpt-4o")
  end

  it "is nil when no synced model can chat" do
    provider.supported_models = models("text-embedding-3-small", "babbage-002")

    expect(provider.default_model).to be_nil
  end

  it "keeps an explicitly configured default" do
    provider.configuration_schema = { "default_model" => "configured-model" }

    expect(provider.default_model).to eq("configured-model")
  end

  it "takes the embedding default from the catalog when none was synced" do
    provider.supported_models = models("gpt-4o-mini")

    expect(provider.default_embedding_model).to eq(Ai::ProviderCatalog.for("openai")[:default_embedding_model])
  end

  it "prefers a synced embedding model for the embedding default" do
    expect(provider.default_embedding_model).to eq("text-embedding-3-small")
  end
end
