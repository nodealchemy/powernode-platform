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

  it "falls back to the lightest of ALL ids when the filter leaves nothing, never nil" do
    provider.supported_models = models("text-embedding-3-small", "babbage-002")

    expect(provider.default_model).to be_present
  end

  it "keeps Ollama instruct-tuned tags (only OpenAI's completion-only instruct id is excluded)" do
    provider.provider_type = "ollama"
    provider.supported_models = models("text-embedding-3-small", "llama3.1:8b-instruct-q4_K_M", "qwen2.5:14b-instruct")

    expect(provider.default_model).to match(/instruct/)
    expect(Ai::ModelTiers.chat_capable?("llama3.1:8b-instruct-q4_K_M")).to be(true)
    expect(Ai::ModelTiers.chat_capable?("qwen2.5-coder:7b-instruct")).to be(true)
    expect(Ai::ModelTiers.chat_capable?("gpt-3.5-turbo-instruct")).to be(false)
  end

  it "keeps Gemini preview ids and other chat previews" do
    %w[gemini-2.5-pro-preview-05-06 gemini-2.0-flash-lite-preview gpt-4-turbo-preview o1-preview].each do |id|
      expect(Ai::ModelTiers.chat_capable?(id)).to be(true), id
    end
    %w[gpt-4o-mini-search-preview gpt-4o-audio-preview gpt-4o-realtime-preview gemini-2.0-flash-preview-image-generation].each do |id|
      expect(Ai::ModelTiers.chat_capable?(id)).to be(false), id
    end
  end

  it "still excludes OpenAI's completion-only ids" do
    %w[babbage-002 davinci-002 gpt-3.5-turbo-instruct text-embedding-3-small omni-moderation-latest].each do |id|
      expect(Ai::ModelTiers.chat_capable?(id)).to be(false), id
    end
  end

  it "keeps an explicitly configured default" do
    provider.configuration_schema = { "default_model" => "configured-model" }

    expect(provider.default_model).to eq("configured-model")
  end
end
