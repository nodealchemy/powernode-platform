# frozen_string_literal: true

module Ai
  module Llm
    # Maps provider types to their appropriate adapter class
    # OpenAI-compatible providers (OpenAI, Groq, Mistral, Azure, Grok, Cohere) → OpenaiAdapter
    # Anthropic → AnthropicAdapter
    # Ollama → OllamaAdapter
    class AdapterFactory
      # Providers that use OpenAI-compatible /chat/completions API
      OPENAI_COMPATIBLE = %w[openai groq mistral azure grok cohere deepseek].freeze

      class << self
        # Build adapter from a provider record and its credentials
        # @param provider [Ai::Provider] provider record
        # @param credential [Ai::ProviderCredential] credential with api_key
        # @return [Ai::Llm::Adapters::BaseAdapter]
        def build(provider:, credential:)
          provider_type = provider.provider_type.to_s.downcase
          api_key = credential.credentials&.dig("api_key")
          base_url = provider.api_base_url

          build_for_type(provider_type, api_key: api_key, base_url: base_url,
                         provider_name: provider.name)
        end

        # Build adapter directly from type + credentials
        # @param provider_type [String] "openai", "anthropic", "ollama", etc.
        # @param api_key [String] API key
        # @param base_url [String] API base URL
        # @param provider_name [String] human-readable provider name
        # @return [Ai::Llm::Adapters::BaseAdapter]
        def build_for_type(provider_type, api_key:, base_url:, provider_name: nil)
          type = provider_type.to_s.downcase
          name = provider_name || type

          if type == "anthropic"
            Adapters::AnthropicAdapter.new(
              api_key: api_key,
              base_url: base_url || "https://api.anthropic.com/v1",
              provider_name: name
            )
          elsif type == "ollama"
            Adapters::OllamaAdapter.new(
              api_key: api_key,
              base_url: base_url || "http://localhost:11434",
              provider_name: name
            )
          elsif OPENAI_COMPATIBLE.include?(type) || openai_compatible_url?(base_url)
            Adapters::OpenaiAdapter.new(
              api_key: api_key,
              base_url: base_url || "https://api.openai.com/v1",
              provider_name: name
            )
          else
            # Default to OpenAI-compatible for unknown providers
            Rails.logger.warn "[LLM] Unknown provider type '#{type}', defaulting to OpenAI adapter"
            Adapters::OpenaiAdapter.new(
              api_key: api_key,
              base_url: base_url,
              provider_name: name
            )
          end
        end

        # List all supported provider types
        def supported_types
          OPENAI_COMPATIBLE + %w[anthropic ollama]
        end

        private

        def openai_compatible_url?(url)
          return false unless url

          url.to_s.include?("/v1") && !url.to_s.include?("anthropic")
        end
      end
    end
  end
end
