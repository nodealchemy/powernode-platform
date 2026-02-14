# frozen_string_literal: true

class Ai::ProviderManagementService
  module ProviderSpecs
    extend ActiveSupport::Concern

    class_methods do
      # Get providers available for a specific account
      def get_available_providers_for_account(account)
        Ai::Provider.active.includes(:provider_credentials)
      end

      # Setup default AI providers
      def setup_default_providers(account = nil)
        account ||= Account.find_or_create_by(name: "System Account") do |acc|
          acc.subdomain = "system"
          acc.status = "active"
        end

        created_count = 0

        default_providers = [
          {
            name: "Ollama",
            slug: "ollama",
            provider_type: "custom",
            description: "Local AI models with privacy-first approach",
            api_base_url: "http://localhost:11434",
            api_endpoint: "http://localhost:11434",
            capabilities: [ "text_generation", "chat", "code_execution" ],
            requires_auth: false,
            supports_streaming: true,
            priority_order: 1,
            supported_models: [
              {
                "name" => "llama2",
                "id" => "llama2",
                "context_length" => 4096,
                "description" => "Meta's Llama 2 model"
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                base_url: {
                  type: "string",
                  description: "Ollama server base URL",
                  default: "http://localhost:11434"
                }
              }
            }
          },
          {
            name: "OpenAI",
            slug: "openai",
            provider_type: "openai",
            description: "GPT models for text generation and chat",
            api_base_url: "https://api.openai.com/v1",
            api_endpoint: "https://api.openai.com/v1",
            capabilities: [ "text_generation", "chat", "vision", "function_calling" ],
            requires_auth: true,
            supports_streaming: true,
            supports_functions: true,
            supports_vision: true,
            priority_order: 2,
            documentation_url: "https://platform.openai.com/docs",
            supported_models: [
              {
                "name" => "GPT-4",
                "id" => "gpt-4",
                "context_length" => 8192,
                "description" => "Latest GPT-4 model"
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                api_key: {
                  type: "string",
                  description: "OpenAI API key",
                  required: true
                },
                organization: {
                  type: "string",
                  description: "OpenAI Organization ID (optional)"
                }
              },
              required: [ "api_key" ]
            }
          },
          {
            name: "Anthropic",
            slug: "anthropic",
            provider_type: "anthropic",
            description: "Claude models for advanced reasoning",
            api_base_url: "https://api.anthropic.com",
            api_endpoint: "https://api.anthropic.com",
            capabilities: [ "text_generation", "chat", "vision" ],
            requires_auth: true,
            supports_streaming: true,
            supports_vision: true,
            priority_order: 3,
            documentation_url: "https://docs.anthropic.com/claude/reference",
            supported_models: [
              {
                "name" => "Claude 3 Opus",
                "id" => "claude-3-opus-20240229",
                "context_length" => 200000,
                "description" => "Most capable Claude model"
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                api_key: {
                  type: "string",
                  description: "Anthropic API key",
                  required: true
                }
              },
              required: [ "api_key" ]
            }
          },
          {
            name: "Hugging Face",
            slug: "huggingface",
            provider_type: "huggingface",
            description: "Open-source model marketplace",
            api_base_url: "https://api-inference.huggingface.co",
            api_endpoint: "https://api-inference.huggingface.co",
            capabilities: [ "text_generation", "embeddings" ],
            requires_auth: true,
            priority_order: 4,
            documentation_url: "https://huggingface.co/docs",
            supported_models: [
              {
                "name" => "Default Model",
                "id" => "gpt2",
                "context_length" => 1024,
                "description" => "Default Hugging Face model"
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                api_key: {
                  type: "string",
                  description: "Hugging Face API token",
                  required: true
                }
              },
              required: [ "api_key" ]
            }
          },
          {
            name: "Cohere",
            slug: "cohere",
            provider_type: "custom",
            description: "Enterprise-grade language models",
            api_base_url: "https://api.cohere.ai/v1",
            api_endpoint: "https://api.cohere.ai/v1",
            capabilities: [ "text_generation", "chat", "embeddings" ],
            requires_auth: true,
            supports_streaming: true,
            priority_order: 5,
            documentation_url: "https://docs.cohere.com",
            supported_models: [
              {
                "name" => "Command",
                "id" => "command",
                "context_length" => 4096,
                "description" => "Cohere's flagship model"
              }
            ],
            configuration_schema: {
              type: "object",
              properties: {
                api_key: {
                  type: "string",
                  description: "Cohere API key",
                  required: true
                }
              },
              required: [ "api_key" ]
            }
          }
        ]

        default_providers.each do |provider_data|
          existing_provider = Ai::Provider.find_by(slug: provider_data[:slug])

          if existing_provider
            Rails.logger.info "Provider #{provider_data[:slug]} already exists, skipping creation"
          else
            begin
              complete_provider_data = provider_data.merge(
                account: account,
                is_active: true,
                api_endpoint: provider_data[:api_base_url]
              )

              provider = Ai::Provider.create!(complete_provider_data)

              sync_provider_models(provider)
              created_count += 1
              Rails.logger.info "Created provider #{provider_data[:slug]} for account #{account.name}"
            rescue ActiveRecord::RecordInvalid => e
              Rails.logger.error "Failed to create provider #{provider_data[:name]} (#{provider_data[:slug]}): #{e.message}"
              Rails.logger.error "Validation errors: #{e.record.errors.full_messages.join(', ')}"
            end
          end
        end

        created_count
      end
    end
  end
end
