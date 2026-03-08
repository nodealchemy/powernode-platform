# frozen_string_literal: true

module Ai
  module Providers
    class DefaultConfig
      PROVIDER_TYPES = %w[openai anthropic google azure_openai groq mistral cohere grok].freeze

      def self.types
        PROVIDER_TYPES
      end

      def self.for(provider_type)
        configs[provider_type]
      end

      def self.configs
        {
          "openai" => {
            name: "OpenAI",
            configuration: {
              api_base_url: "https://api.openai.com/v1",
              default_model: "gpt-4.1-mini",
              supported_models: %w[gpt-4.1 gpt-4.1-mini gpt-4.1-nano o3 o4-mini gpt-4o gpt-4o-mini gpt-4-turbo gpt-3.5-turbo],
              capabilities: %w[chat completions embeddings images]
            }
          },
          "anthropic" => {
            name: "Anthropic",
            configuration: {
              api_base_url: "https://api.anthropic.com/v1",
              default_model: "claude-haiku-4-5-20251001",
              supported_models: %w[claude-haiku-4-5-20251001 claude-sonnet-4-5-20250929 claude-opus-4-1-20250805 claude-3-5-sonnet-20241022],
              capabilities: %w[chat completions]
            }
          },
          "google" => {
            name: "Google AI (Gemini)",
            configuration: {
              api_base_url: "https://generativelanguage.googleapis.com/v1beta",
              default_model: "gemini-2.0-flash",
              supported_models: %w[gemini-2.0-flash gemini-1.5-pro gemini-1.5-flash],
              capabilities: %w[chat completions embeddings]
            }
          },
          "azure_openai" => {
            name: "Azure OpenAI",
            configuration: {
              api_base_url: nil,
              default_model: "gpt-4o",
              supported_models: %w[gpt-4o gpt-4o-mini gpt-4-turbo],
              capabilities: %w[chat completions embeddings]
            }
          },
          "groq" => {
            name: "Groq",
            configuration: {
              api_base_url: "https://api.groq.com/openai/v1",
              default_model: "llama-3.3-70b-versatile",
              supported_models: %w[llama-3.3-70b-versatile llama-3.1-8b-instant mixtral-8x7b-32768],
              capabilities: %w[chat completions]
            }
          },
          "mistral" => {
            name: "Mistral AI",
            configuration: {
              api_base_url: "https://api.mistral.ai/v1",
              default_model: "mistral-large-latest",
              supported_models: %w[mistral-large-latest mistral-medium-latest mistral-small-latest],
              capabilities: %w[chat completions embeddings]
            }
          },
          "cohere" => {
            name: "Cohere",
            configuration: {
              api_base_url: "https://api.cohere.ai/v1",
              default_model: "command-r-plus",
              supported_models: %w[command-r-plus command-r command-light],
              capabilities: %w[chat completions embeddings]
            }
          },
          "grok" => {
            name: "Grok (X.AI)",
            configuration: {
              api_base_url: "https://api.x.ai/v1",
              default_model: "grok-3-mini",
              supported_models: %w[grok-3 grok-3-mini grok-3-fast grok-3-mini-fast grok-2],
              capabilities: %w[chat completions function_calling]
            }
          }
        }
      end
    end
  end
end
