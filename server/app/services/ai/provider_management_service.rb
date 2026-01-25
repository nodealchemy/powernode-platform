# frozen_string_literal: true

class Ai::ProviderManagementService
  # Custom exception classes
  class ValidationError < StandardError; end
  class CredentialError < StandardError; end

  class << self
    # Get providers available for a specific account
    def get_available_providers_for_account(account)
      Ai::Provider.active.includes(:provider_credentials)
    end

    # Sync models for a specific provider
    def sync_provider_models(provider)
      return false unless provider.is_active?

      begin
        # Use provider_type for reliable matching (slug can vary)
        case provider.provider_type&.downcase
        when "ollama"
          sync_ollama_models(provider)
        when "openai"
          sync_openai_models(provider)
        when "anthropic"
          sync_anthropic_models(provider)
        when "google"
          sync_google_models(provider)
        when "azure", "azure_openai"
          sync_azure_models(provider)
        when "groq"
          sync_groq_models(provider)
        when "grok", "xai", "x.ai", "x-ai"
          sync_grok_models(provider)
        when "mistral"
          sync_mistral_models(provider)
        when "cohere"
          sync_cohere_models(provider)
        else
          # Also check slug for custom providers that might use standard slugs
          case provider.slug&.downcase
          when "ollama", "remote-ollama-server"
            sync_ollama_models(provider)
          when "openai"
            sync_openai_models(provider)
          when "anthropic"
            sync_anthropic_models(provider)
          when "grok", "grok-xai", "xai", "x-ai", "x.ai"
            sync_grok_models(provider)
          when "google", "gemini"
            sync_google_models(provider)
          when "groq"
            sync_groq_models(provider)
          when "mistral"
            sync_mistral_models(provider)
          when "cohere"
            sync_cohere_models(provider)
          when "azure", "azure-openai"
            sync_azure_models(provider)
          else
            sync_generic_models(provider)
          end
        end

        # Health status is now computed via the model's health_status method
        true
      rescue StandardError => e
        Rails.logger.error "Failed to sync models for provider #{provider.id}: #{e.message}"
        false
      end
    end

    # Get usage summary for a provider within a specific account
    def provider_usage_summary(provider, account, period)
      end_date = Time.current
      start_date = end_date - period

      # Mock usage data - in real implementation, this would query usage logs
      {
        provider_id: provider.id,
        provider_name: provider.name,
        period_start: start_date,
        period_end: end_date,
        period_days: period.to_i / 1.day,
        total_requests: rand(1000..5000),
        successful_requests: rand(800..4800),
        failed_requests: rand(50..200),
        total_tokens: rand(50000..500000),
        total_cost: rand(10.0..100.0).round(2),
        average_response_time_ms: rand(500..2000),
        success_rate: ((rand(85..98) * 100) / 100.0).round(1),
        daily_breakdown: generate_daily_breakdown(start_date, end_date)
      }
    end

    # Setup default AI providers
    def setup_default_providers(account = nil)
      # If no account provided, create providers for system use
      # In a real implementation, you might want to create for all accounts
      # or have a system account. For tests, we'll create a system account.
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
        # Check if provider already exists globally (since slug is globally unique)
        existing_provider = Ai::Provider.find_by(slug: provider_data[:slug])

        if existing_provider
          Rails.logger.info "Provider #{provider_data[:slug]} already exists, skipping creation"
        else
          begin
            # Provider data is missing required fields for validation
            complete_provider_data = provider_data.merge(
              account: account,
              is_active: true,
              api_endpoint: provider_data[:api_base_url] # Fix missing api_endpoint
            )

            provider = Ai::Provider.create!(complete_provider_data)

            # Add some default models for each provider
            sync_provider_models(provider)
            created_count += 1
            Rails.logger.info "Created provider #{provider_data[:slug]} for account #{account.name}"
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.error "Failed to create provider #{provider_data[:name]} (#{provider_data[:slug]}): #{e.message}"
            Rails.logger.error "Validation errors: #{e.record.errors.full_messages.join(', ')}"
            # Don't re-raise - continue with other providers
          end
        end
      end

      created_count
    end

    # Create a new provider credential with validation and encryption
    def create_provider_credential(provider, account, credentials_data, name: nil, is_active: nil, is_default: nil, expires_at: nil)
      raise ValidationError, "Provider is required" unless provider
      raise ValidationError, "Account is required" unless account
      raise ValidationError, "Credentials data is required" unless credentials_data.present?

      # Validate credentials against provider schema
      validate_ai_provider_credentials(provider, credentials_data)

      # Generate a name if not provided
      credential_name = name || "#{provider.name} Credentials"

      # Check for duplicate names within the account
      existing = account.ai_provider_credentials.where(name: credential_name).exists?
      if existing
        credential_name = "#{credential_name} (#{Time.current.strftime('%Y%m%d%H%M%S')})"
      end

      # Build credential attributes
      credential_attrs = {
        provider: provider,
        name: credential_name,
        credentials: credentials_data,
        is_active: is_active.nil? ? true : is_active
      }

      # Add optional attributes if provided
      credential_attrs[:is_default] = is_default unless is_default.nil?
      credential_attrs[:expires_at] = expires_at if expires_at.present?

      # Create the credential
      credential = account.ai_provider_credentials.build(credential_attrs)

      if credential.save
        # Test the credential to ensure it works
        begin
          test_service = Ai::ProviderTestService.new(credential)
          # Use simple format for flat response with :success and :error at top level
          test_result = test_service.test_with_details_simple

          if test_result[:success]
            credential.record_success!
          else
            credential.record_failure!(test_result[:error])
            Rails.logger.warn "Created credential #{credential.id} but initial test failed: #{test_result[:error]}"
          end
        rescue StandardError => e
          Rails.logger.error "Failed to test newly created credential #{credential.id}: #{e.message}"
          credential.record_failure!(e.message)
        end

        credential
      else
        raise CredentialError, "Failed to create credential: #{credential.errors.full_messages.join(', ')}"
      end
    end

    # Validate provider credentials against the provider's schema
    def validate_ai_provider_credentials(provider, credentials_data)
      raise ValidationError, "Provider is required" unless provider
      raise ValidationError, "Credentials data is required" unless credentials_data.present?

      schema = provider.configuration_schema

      # Check schema-defined required fields if present
      if schema.present? && schema["required"].present?
        required_fields = schema["required"] || []
        missing_fields = required_fields - credentials_data.keys.map(&:to_s)

        if missing_fields.any?
          raise ValidationError, "Missing required credentials: #{missing_fields.join(', ')}"
        end
      end

      # Basic validation for known provider types (always runs regardless of schema)
      case provider.provider_type&.downcase
      when "openai"
        validate_openai_credentials(credentials_data)
      when "anthropic"
        validate_anthropic_credentials(credentials_data)
      when "huggingface"
        validate_huggingface_credentials(credentials_data)
      end

      true
    end

    # Test all credentials for an account
    def test_all_credentials(account)
      credentials = account.ai_provider_credentials.active.includes(:provider)
      results = []

      credentials.find_each do |credential|
        begin
          test_service = Ai::ProviderTestService.new(credential)
          # Use simple format for flat response with :success and :error at top level
          test_result = test_service.test_with_details_simple

          # Update credential status based on test result
          if test_result[:success]
            credential.record_success!
          else
            credential.record_failure!(test_result[:error])
          end

          results << {
            credential_id: credential.id,
            credential_name: credential.name,
            provider_name: credential.provider.name,
            success: test_result[:success],
            error: test_result[:error],
            response_time_ms: test_result[:response_time_ms]
          }
        rescue StandardError => e
          credential.record_failure!(e.message)
          results << {
            credential_id: credential.id,
            credential_name: credential.name,
            provider_name: credential.provider.name,
            success: false,
            error: e.message,
            response_time_ms: nil
          }
        end
      end

      results
    end

    private

    def generate_daily_breakdown(start_date, end_date)
      breakdown = []
      current_date = start_date.beginning_of_day

      while current_date <= end_date
        breakdown << {
          date: current_date.to_date,
          requests: rand(10..200),
          tokens: rand(1000..10000),
          cost: rand(1.0..10.0).round(2),
          avg_response_time: rand(500..2000)
        }
        current_date += 1.day
      end

      breakdown
    end

    # Provider-specific credential validation methods
    def validate_openai_credentials(credentials_data)
      api_key = credentials_data["api_key"] || credentials_data[:api_key]
      raise ValidationError, "OpenAI API key is required" unless api_key.present?
      raise ValidationError, "OpenAI API key must start with 'sk-'" unless api_key.start_with?("sk-")
      raise ValidationError, "OpenAI API key appears to be invalid format" unless api_key.length > 20
    end

    def validate_anthropic_credentials(credentials_data)
      api_key = credentials_data["api_key"] || credentials_data[:api_key]
      raise ValidationError, "Anthropic API key is required" unless api_key.present?
      raise ValidationError, "Anthropic API key must start with 'sk-ant-'" unless api_key.start_with?("sk-ant-")
    end

    def validate_huggingface_credentials(credentials_data)
      api_key = credentials_data["api_key"] || credentials_data[:api_key]
      raise ValidationError, "Hugging Face API token is required" unless api_key.present?
      raise ValidationError, "Hugging Face API token appears to be too short" unless api_key.length > 10
    end

    # Provider-specific model sync methods
    def sync_ollama_models(provider)
      begin
        # Make API call to Ollama server to get available models
        response = HTTP.timeout(10).get("#{provider.api_base_url}/api/tags")

        if response.status.success?
          api_data = JSON.parse(response.body.to_s)
          models = api_data["models"] || []

          # Transform Ollama API response to our model format
          supported_models = models.map do |model|
            {
              "name" => model["name"]&.split(":")&.first&.capitalize || model["name"],
              "id" => model["name"],
              "context_length" => model["details"]&.dig("parameter_size") || 4096,
              "description" => "#{model['name']} - Size: #{format_model_size(model['size'])}",
              "size_bytes" => model["size"],
              "family" => model["details"]&.dig("family"),
              "parameter_size" => model["details"]&.dig("parameter_size"),
              "quantization_level" => model["details"]&.dig("quantization_level")
            }
          end

          provider.update(supported_models: supported_models)
          Rails.logger.info "Successfully synced #{supported_models.length} models for Ollama provider #{provider.id}"
        else
          Rails.logger.error "Failed to fetch models from Ollama API: HTTP #{response.status}"
          sync_fallback_ollama_models(provider)
        end
      rescue HTTP::Error, JSON::ParserError => e
        Rails.logger.error "Error connecting to Ollama API: #{e.message}"
        sync_fallback_ollama_models(provider)
      end
    end

    def sync_openai_models(provider)
      # OpenAI models as of October 2025
      # In the future, this could use the OpenAI API with credentials to fetch dynamically
      current_models = [
        {
          "name" => "GPT-4o",
          "id" => "gpt-4o",
          "context_length" => 128000,
          "max_output_tokens" => 16384,
          "description" => "Most advanced multimodal model",
          "capabilities" => [ "text_generation", "chat", "vision", "function_calling" ],
          "pricing" => {
            "input_per_mtok" => 2.50,
            "output_per_mtok" => 10.00
          }
        },
        {
          "name" => "GPT-4o Mini",
          "id" => "gpt-4o-mini",
          "context_length" => 128000,
          "max_output_tokens" => 16384,
          "description" => "Affordable and intelligent small model",
          "capabilities" => [ "text_generation", "chat", "vision", "function_calling" ],
          "pricing" => {
            "input_per_mtok" => 0.15,
            "output_per_mtok" => 0.60
          }
        },
        {
          "name" => "GPT-4 Turbo",
          "id" => "gpt-4-turbo",
          "context_length" => 128000,
          "max_output_tokens" => 4096,
          "description" => "Latest GPT-4 Turbo with vision",
          "capabilities" => [ "text_generation", "chat", "vision", "function_calling" ],
          "pricing" => {
            "input_per_mtok" => 10.00,
            "output_per_mtok" => 30.00
          }
        },
        {
          "name" => "GPT-4",
          "id" => "gpt-4",
          "context_length" => 8192,
          "max_output_tokens" => 8192,
          "description" => "Classic GPT-4 model",
          "capabilities" => [ "text_generation", "chat", "function_calling" ],
          "pricing" => {
            "input_per_mtok" => 30.00,
            "output_per_mtok" => 60.00
          }
        },
        {
          "name" => "GPT-3.5 Turbo",
          "id" => "gpt-3.5-turbo",
          "context_length" => 16385,
          "max_output_tokens" => 4096,
          "description" => "Fast and efficient model for most tasks",
          "capabilities" => [ "text_generation", "chat", "function_calling" ],
          "pricing" => {
            "input_per_mtok" => 0.50,
            "output_per_mtok" => 1.50
          }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for OpenAI provider #{provider.id}"
      true
    end

    def sync_anthropic_models(provider)
      # Anthropic doesn't provide a public models API endpoint
      # Update with current Claude models as of October 2025
      # Source: https://docs.claude.com/en/docs/about-claude/models/overview
      current_models = [
        {
          "name" => "Claude Sonnet 4.5",
          "id" => "claude-sonnet-4-5-20250929",
          "context_length" => 200000,
          "max_output_tokens" => 8192,
          "description" => "Best model for agents, coding, and computer use",
          "capabilities" => [ "text_generation", "chat", "vision", "code_generation", "computer_use" ],
          "pricing" => {
            "input_per_mtok" => 3.00,
            "output_per_mtok" => 15.00
          },
          "knowledge_cutoff" => "Jan 2025"
        },
        {
          "name" => "Claude Sonnet 4",
          "id" => "claude-sonnet-4-20250514",
          "context_length" => 200000,
          "max_output_tokens" => 8192,
          "description" => "Balanced performance and speed",
          "capabilities" => [ "text_generation", "chat", "vision", "code_generation" ],
          "pricing" => {
            "input_per_mtok" => 3.00,
            "output_per_mtok" => 15.00
          },
          "knowledge_cutoff" => "Jan 2025"
        },
        {
          "name" => "Claude Sonnet 3.7",
          "id" => "claude-3-7-sonnet-20250219",
          "context_length" => 200000,
          "max_output_tokens" => 8192,
          "description" => "Enhanced Sonnet with improved capabilities",
          "capabilities" => [ "text_generation", "chat", "vision", "code_generation" ],
          "pricing" => {
            "input_per_mtok" => 3.00,
            "output_per_mtok" => 15.00
          },
          "knowledge_cutoff" => "Oct 2024"
        },
        {
          "name" => "Claude Opus 4.1",
          "id" => "claude-opus-4-1-20250805",
          "context_length" => 200000,
          "max_output_tokens" => 4096,
          "description" => "Exceptional model for specialized complex tasks",
          "capabilities" => [ "text_generation", "chat", "vision", "code_generation", "extended_thinking" ],
          "pricing" => {
            "input_per_mtok" => 15.00,
            "output_per_mtok" => 75.00
          },
          "knowledge_cutoff" => "Jan 2025"
        },
        {
          "name" => "Claude Opus 4",
          "id" => "claude-opus-4-20250514",
          "context_length" => 200000,
          "max_output_tokens" => 4096,
          "description" => "Most powerful Claude model for advanced reasoning",
          "capabilities" => [ "text_generation", "chat", "vision", "code_generation" ],
          "pricing" => {
            "input_per_mtok" => 15.00,
            "output_per_mtok" => 75.00
          },
          "knowledge_cutoff" => "Jan 2025"
        },
        {
          "name" => "Claude Haiku 3.5",
          "id" => "claude-3-5-haiku-20241022",
          "context_length" => 200000,
          "max_output_tokens" => 8192,
          "description" => "Fastest Claude model - optimized for speed",
          "capabilities" => [ "text_generation", "chat", "vision" ],
          "pricing" => {
            "input_per_mtok" => 0.80,
            "output_per_mtok" => 4.00
          }
        },
        {
          "name" => "Claude Haiku 3",
          "id" => "claude-3-haiku-20240307",
          "context_length" => 200000,
          "max_output_tokens" => 4096,
          "description" => "Fast and compact model",
          "capabilities" => [ "text_generation", "chat", "vision" ],
          "pricing" => {
            "input_per_mtok" => 0.25,
            "output_per_mtok" => 1.25
          }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Anthropic provider #{provider.id}"
      true
    end

    def sync_google_models(provider)
      # Google AI (Gemini) models as of December 2025
      current_models = [
        {
          "name" => "Gemini 2.0 Flash",
          "id" => "gemini-2.0-flash-exp",
          "context_length" => 1048576,
          "max_output_tokens" => 8192,
          "description" => "Next generation features, speed, and multimodal generation",
          "capabilities" => %w[text_generation chat vision audio code_execution],
          "pricing" => { "input_per_mtok" => 0.0, "output_per_mtok" => 0.0 }
        },
        {
          "name" => "Gemini 1.5 Pro",
          "id" => "gemini-1.5-pro",
          "context_length" => 2097152,
          "max_output_tokens" => 8192,
          "description" => "Best performing multimodal model with features for a wide variety of reasoning tasks",
          "capabilities" => %w[text_generation chat vision audio],
          "pricing" => { "input_per_mtok" => 1.25, "output_per_mtok" => 5.00 }
        },
        {
          "name" => "Gemini 1.5 Flash",
          "id" => "gemini-1.5-flash",
          "context_length" => 1048576,
          "max_output_tokens" => 8192,
          "description" => "Fast and versatile performance across a diverse variety of tasks",
          "capabilities" => %w[text_generation chat vision audio],
          "pricing" => { "input_per_mtok" => 0.075, "output_per_mtok" => 0.30 }
        },
        {
          "name" => "Gemini 1.5 Flash-8B",
          "id" => "gemini-1.5-flash-8b",
          "context_length" => 1048576,
          "max_output_tokens" => 8192,
          "description" => "High volume and lower intelligence tasks",
          "capabilities" => %w[text_generation chat vision audio],
          "pricing" => { "input_per_mtok" => 0.0375, "output_per_mtok" => 0.15 }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Google provider #{provider.id}"
      true
    end

    def sync_azure_models(provider)
      # Azure OpenAI models - these depend on user's deployed models
      # Using common deployment names as defaults
      current_models = [
        {
          "name" => "GPT-4o",
          "id" => "gpt-4o",
          "context_length" => 128000,
          "max_output_tokens" => 16384,
          "description" => "Most advanced multimodal model on Azure",
          "capabilities" => %w[text_generation chat vision function_calling]
        },
        {
          "name" => "GPT-4o Mini",
          "id" => "gpt-4o-mini",
          "context_length" => 128000,
          "max_output_tokens" => 16384,
          "description" => "Affordable and intelligent small model on Azure",
          "capabilities" => %w[text_generation chat vision function_calling]
        },
        {
          "name" => "GPT-4 Turbo",
          "id" => "gpt-4-turbo",
          "context_length" => 128000,
          "max_output_tokens" => 4096,
          "description" => "GPT-4 Turbo with Vision on Azure",
          "capabilities" => %w[text_generation chat vision function_calling]
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Azure provider #{provider.id}"
      true
    end

    def sync_groq_models(provider)
      # Groq models as of December 2025
      current_models = [
        {
          "name" => "Llama 3.3 70B Versatile",
          "id" => "llama-3.3-70b-versatile",
          "context_length" => 128000,
          "max_output_tokens" => 32768,
          "description" => "Meta's latest Llama 3.3 model - versatile and powerful",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 0.59, "output_per_mtok" => 0.79 }
        },
        {
          "name" => "Llama 3.1 70B Versatile",
          "id" => "llama-3.1-70b-versatile",
          "context_length" => 128000,
          "max_output_tokens" => 32768,
          "description" => "Meta's Llama 3.1 70B model",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 0.59, "output_per_mtok" => 0.79 }
        },
        {
          "name" => "Llama 3.1 8B Instant",
          "id" => "llama-3.1-8b-instant",
          "context_length" => 128000,
          "max_output_tokens" => 8192,
          "description" => "Fast and efficient Llama 3.1 8B model",
          "capabilities" => %w[text_generation chat],
          "pricing" => { "input_per_mtok" => 0.05, "output_per_mtok" => 0.08 }
        },
        {
          "name" => "Mixtral 8x7B",
          "id" => "mixtral-8x7b-32768",
          "context_length" => 32768,
          "max_output_tokens" => 32768,
          "description" => "Mistral's Mixture of Experts model",
          "capabilities" => %w[text_generation chat],
          "pricing" => { "input_per_mtok" => 0.24, "output_per_mtok" => 0.24 }
        },
        {
          "name" => "Gemma 2 9B",
          "id" => "gemma2-9b-it",
          "context_length" => 8192,
          "max_output_tokens" => 8192,
          "description" => "Google's Gemma 2 instruction-tuned model",
          "capabilities" => %w[text_generation chat],
          "pricing" => { "input_per_mtok" => 0.20, "output_per_mtok" => 0.20 }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Groq provider #{provider.id}"
      true
    end

    def sync_mistral_models(provider)
      # Mistral AI models as of December 2025
      current_models = [
        {
          "name" => "Mistral Large",
          "id" => "mistral-large-latest",
          "context_length" => 128000,
          "max_output_tokens" => 8192,
          "description" => "Top-tier reasoning model for high-complexity tasks",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 2.00, "output_per_mtok" => 6.00 }
        },
        {
          "name" => "Mistral Small",
          "id" => "mistral-small-latest",
          "context_length" => 32000,
          "max_output_tokens" => 8192,
          "description" => "Cost-efficient model for simple tasks",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 0.20, "output_per_mtok" => 0.60 }
        },
        {
          "name" => "Codestral",
          "id" => "codestral-latest",
          "context_length" => 32000,
          "max_output_tokens" => 8192,
          "description" => "Specialized model for code generation",
          "capabilities" => %w[text_generation chat code_generation],
          "pricing" => { "input_per_mtok" => 0.20, "output_per_mtok" => 0.60 }
        },
        {
          "name" => "Ministral 8B",
          "id" => "ministral-8b-latest",
          "context_length" => 128000,
          "max_output_tokens" => 8192,
          "description" => "Compact model optimized for edge computing",
          "capabilities" => %w[text_generation chat],
          "pricing" => { "input_per_mtok" => 0.10, "output_per_mtok" => 0.10 }
        },
        {
          "name" => "Pixtral Large",
          "id" => "pixtral-large-latest",
          "context_length" => 128000,
          "max_output_tokens" => 8192,
          "description" => "Multimodal model with vision capabilities",
          "capabilities" => %w[text_generation chat vision],
          "pricing" => { "input_per_mtok" => 2.00, "output_per_mtok" => 6.00 }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Mistral provider #{provider.id}"
      true
    end

    def sync_cohere_models(provider)
      # Cohere models as of December 2025
      current_models = [
        {
          "name" => "Command R+",
          "id" => "command-r-plus",
          "context_length" => 128000,
          "max_output_tokens" => 4096,
          "description" => "Advanced model optimized for complex RAG and multi-step tool use",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 2.50, "output_per_mtok" => 10.00 }
        },
        {
          "name" => "Command R",
          "id" => "command-r",
          "context_length" => 128000,
          "max_output_tokens" => 4096,
          "description" => "Optimized for long context tasks and RAG",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 0.15, "output_per_mtok" => 0.60 }
        },
        {
          "name" => "Command Light",
          "id" => "command-light",
          "context_length" => 4096,
          "max_output_tokens" => 4096,
          "description" => "Smaller, faster version of Command for simple tasks",
          "capabilities" => %w[text_generation chat],
          "pricing" => { "input_per_mtok" => 0.30, "output_per_mtok" => 0.60 }
        },
        {
          "name" => "Embed English v3",
          "id" => "embed-english-v3.0",
          "context_length" => 512,
          "description" => "English text embeddings model",
          "capabilities" => %w[embeddings],
          "pricing" => { "input_per_mtok" => 0.10 }
        },
        {
          "name" => "Embed Multilingual v3",
          "id" => "embed-multilingual-v3.0",
          "context_length" => 512,
          "description" => "Multilingual text embeddings model",
          "capabilities" => %w[embeddings],
          "pricing" => { "input_per_mtok" => 0.10 }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Cohere provider #{provider.id}"
      true
    end

    def sync_grok_models(provider)
      # Grok (X.AI) models as of December 2025
      # Source: https://docs.x.ai/docs/models
      current_models = [
        {
          "name" => "Grok 2",
          "id" => "grok-2-1212",
          "context_length" => 131072,
          "max_output_tokens" => 8192,
          "description" => "Latest and most capable Grok model with improved reasoning",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 2.00, "output_per_mtok" => 10.00 }
        },
        {
          "name" => "Grok 2 Vision",
          "id" => "grok-2-vision-1212",
          "context_length" => 32768,
          "max_output_tokens" => 8192,
          "description" => "Multimodal Grok model with image understanding",
          "capabilities" => %w[text_generation chat vision function_calling],
          "pricing" => { "input_per_mtok" => 2.00, "output_per_mtok" => 10.00 }
        },
        {
          "name" => "Grok Beta",
          "id" => "grok-beta",
          "context_length" => 131072,
          "max_output_tokens" => 8192,
          "description" => "Beta version of Grok with experimental features",
          "capabilities" => %w[text_generation chat function_calling],
          "pricing" => { "input_per_mtok" => 5.00, "output_per_mtok" => 15.00 }
        },
        {
          "name" => "Grok Vision Beta",
          "id" => "grok-vision-beta",
          "context_length" => 8192,
          "max_output_tokens" => 8192,
          "description" => "Beta multimodal Grok with vision capabilities",
          "capabilities" => %w[text_generation chat vision],
          "pricing" => { "input_per_mtok" => 5.00, "output_per_mtok" => 15.00 }
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Grok (X.AI) provider #{provider.id}"
      true
    end

    def sync_generic_models(provider)
      # Generic fallback for unknown providers
      provider.update(supported_models: [
        {
          "name" => "Default Model",
          "id" => "default",
          "context_length" => 4096,
          "description" => "Default model for #{provider.name}"
        }
      ])
    end

    def sync_fallback_ollama_models(provider)
      # Fallback static models when API is unavailable
      provider.update(supported_models: [
        {
          "name" => "Llama2",
          "id" => "llama2",
          "context_length" => 4096,
          "description" => "Meta's Llama 2 model"
        },
        {
          "name" => "CodeLlama",
          "id" => "codellama",
          "context_length" => 4096,
          "description" => "Code-specialized language model"
        }
      ])
    end

    def format_model_size(size_bytes)
      return "Unknown" unless size_bytes

      # Convert bytes to human-readable format
      units = [ "B", "KB", "MB", "GB", "TB" ]
      size = size_bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(1)} #{units[unit_index]}"
    end
  end
end
