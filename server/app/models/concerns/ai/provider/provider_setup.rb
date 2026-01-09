# frozen_string_literal: true

module Ai
  class Provider
    module ProviderSetup
      extend ActiveSupport::Concern

      included do
        after_create :setup_default_credentials
      end

      class_methods do
        def available_provider_types(include_metadata: false)
          types = %w[
            openai
            anthropic
            google
            azure
            huggingface
            custom
            ollama
            local
            api_gateway
          ]

          return types unless include_metadata

          type_metadata = {
            "openai" => { name: "OpenAI", description: "OpenAI API integration", website: "https://openai.com" },
            "anthropic" => { name: "Anthropic", description: "Claude AI integration", website: "https://anthropic.com" },
            "google" => { name: "Google", description: "Google AI integration", website: "https://ai.google" },
            "azure" => { name: "Azure OpenAI", description: "Microsoft Azure OpenAI Service", website: "https://azure.microsoft.com/en-us/products/ai-services/openai-service/" },
            "huggingface" => { name: "Hugging Face", description: "Hugging Face Hub models", website: "https://huggingface.co" },
            "custom" => { name: "Custom Provider", description: "Custom AI provider integration", website: nil },
            "ollama" => { name: "Ollama", description: "Local LLM hosting with Ollama", website: "https://ollama.ai" },
            "local" => { name: "Local Provider", description: "Local or self-hosted AI services", website: nil },
            "api_gateway" => { name: "API Gateway", description: "Multi-provider API gateway service", website: nil }
          }

          types.map do |type|
            metadata = type_metadata[type] || {}
            {
              type: type,
              name: metadata[:name],
              description: metadata[:description],
              website: metadata[:website]
            }
          end
        end

        def setup_default_providers(account)
          return [] unless account

          default_providers = [
            openai_default_config,
            anthropic_default_config
          ]

          created_providers = []
          default_providers.each do |provider_attrs|
            provider = account.ai_providers.find_or_create_by(slug: provider_attrs[:slug]) do |p|
              p.assign_attributes(provider_attrs.except(:supported_models, :configuration, :configuration_schema, :rate_limits))
              p.supported_models = provider_attrs[:supported_models]
              # Set configuration with models (this will also set configuration_schema)
              p.configuration = provider_attrs[:configuration] || {}
              p.rate_limits = provider_attrs[:rate_limits] || {}
              p.is_active = true
            end
            created_providers << provider
          end

          created_providers
        end

        def cleanup_inactive_providers(older_than = 90.days)
          # Find providers that are inactive and old, but don't have recent usage
          inactive_provider_ids = inactive.where("updated_at < ?", older_than.ago).pluck(:id)
          used_provider_ids = []

          # Check if any agents use these providers
          used_provider_ids += Ai::Agent.where(ai_provider_id: inactive_provider_ids).pluck(:ai_provider_id)

          # Check if any executions use these providers
          used_provider_ids += Ai::AgentExecution.where(ai_provider_id: inactive_provider_ids).pluck(:ai_provider_id)

          # Only destroy providers that aren't referenced
          safe_to_delete_ids = inactive_provider_ids - used_provider_ids.uniq
          where(id: safe_to_delete_ids).destroy_all
        end

        def provider_type_description(type)
          descriptions = {
            "text_generation" => "Generate text content, chat, and language tasks",
            "image_generation" => "Generate images from text descriptions",
            "video_generation" => "Generate video content",
            "audio_generation" => "Generate audio and speech",
            "code_execution" => "Execute code and programming tasks",
            "embedding" => "Generate text embeddings for similarity and search"
          }
          descriptions[type] || "AI provider capabilities"
        end

        private

        def openai_default_config
          {
            name: "OpenAI",
            slug: "openai",
            provider_type: "openai",
            api_base_url: "https://api.openai.com/v1",
            api_endpoint: "https://api.openai.com/v1",
            capabilities: %w[text_generation chat],
            supported_models: [
              {
                name: "gpt-4o",
                id: "gpt-4o",
                context_length: 128_000,
                cost_per_1k_tokens: { input: 0.0025, output: 0.01 }
              },
              {
                name: "gpt-3.5-turbo",
                id: "gpt-3.5-turbo",
                context_length: 16_385,
                cost_per_1k_tokens: { input: 0.0005, output: 0.0015 }
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                api_key: { type: "string", description: "OpenAI API key" },
                model: { type: "string", description: "Model to use" }
              },
              required: %w[api_key model]
            },
            configuration: {
              models: %w[gpt-3.5-turbo gpt-4],
              default_model: "gpt-3.5-turbo"
            },
            rate_limits: {
              requests_per_minute: 3500,
              tokens_per_minute: 90_000
            },
            priority_order: 1
          }
        end

        def anthropic_default_config
          {
            name: "Anthropic",
            slug: "anthropic",
            provider_type: "anthropic",
            api_base_url: "https://api.anthropic.com/v1",
            api_endpoint: "https://api.anthropic.com/v1",
            capabilities: %w[text_generation chat],
            supported_models: [
              {
                name: "claude-opus-4.5",
                id: "claude-opus-4-5-20251101",
                context_length: 200_000,
                max_output_tokens: 32_000,
                cost_per_1k_tokens: { input: 0.015, output: 0.075 }
              },
              {
                name: "claude-sonnet-4.5",
                id: "claude-sonnet-4-5-20250929",
                context_length: 200_000,
                max_output_tokens: 64_000,
                cost_per_1k_tokens: { input: 0.003, output: 0.015 }
              },
              {
                name: "claude-sonnet-4",
                id: "claude-sonnet-4-20250514",
                context_length: 200_000,
                max_output_tokens: 64_000,
                cost_per_1k_tokens: { input: 0.003, output: 0.015 }
              },
              {
                name: "claude-haiku-4.5",
                id: "claude-haiku-4-5-20251001",
                context_length: 200_000,
                max_output_tokens: 64_000,
                cost_per_1k_tokens: { input: 0.001, output: 0.005 }
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                api_key: { type: "string", description: "Anthropic API key" },
                model: { type: "string", description: "Model to use" }
              },
              required: %w[api_key model]
            },
            configuration: {
              models: %w[claude-opus-4.5 claude-sonnet-4.5 claude-sonnet-4 claude-haiku-4.5],
              default_model: "claude-sonnet-4.5"
            },
            rate_limits: {
              requests_per_minute: 1000,
              tokens_per_minute: 40_000
            },
            priority_order: 2
          }
        end
      end

      private

      def setup_default_credentials
        # For known providers, we might set up default credentials
        return unless %w[openai anthropic google azure].include?(provider_type)

        Rails.logger.info "Setting up default credentials for #{provider_type} provider: #{name}"
        true
      end
    end
  end
end
