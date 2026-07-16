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
            "ollama" => { name: "Ollama", description: "LLM hosting with Ollama", website: "https://ollama.ai" },
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

        # Both default configs derive their field values from
        # Ai::ProviderCatalog — the single source of truth for provider
        # data — so nothing here duplicates catalog values. Only the
        # bootstrap-specific shape setup_default_providers consumes
        # (:slug, :configuration) is assembled locally.
        def openai_default_config
          default_config_from_catalog("openai", slug: "openai")
        end

        def anthropic_default_config
          default_config_from_catalog("anthropic", slug: "anthropic")
        end

        def default_config_from_catalog(provider_type, slug:)
          catalog = ::Ai::ProviderCatalog.for(provider_type)

          {
            name: catalog[:name],
            slug: slug,
            provider_type: catalog[:provider_type],
            api_base_url: catalog[:api_base_url],
            api_endpoint: catalog[:api_endpoint],
            capabilities: catalog[:capabilities],
            supported_models: catalog[:supported_models],
            configuration_schema: catalog[:configuration_schema],
            configuration: bootstrap_configuration(catalog),
            rate_limits: catalog[:rate_limits],
            priority_order: catalog[:priority_order]
          }
        end

        # setup_default_providers stores this (not configuration_schema) as
        # the provider's actual runtime configuration — see Configurable#configuration=.
        def bootstrap_configuration(catalog)
          model_ids = catalog[:supported_models].map { |model| model["id"] }
          default_model = catalog[:configuration_schema]["default_model"] || model_ids.first

          {
            models: model_ids,
            default_model: default_model
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
