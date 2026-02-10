# frozen_string_literal: true

class Ai::ProviderManagementService
  # Custom exception classes
  class ValidationError < StandardError; end
  class CredentialError < StandardError; end

  # Include extracted provider testing modules (instance-level)
  include ProviderTesting::Initialization
  include ProviderTesting::ConnectionTesting
  include ProviderTesting::HealthChecks
  include ProviderTesting::LoadTesting
  include ProviderTesting::ProviderAdapters
  include ProviderTesting::Reporting

  # Include extracted per-provider sync modules (class-level via class_methods)
  include Ai::Providers::Sync::Ollama
  include Ai::Providers::Sync::Openai
  include Ai::Providers::Sync::Anthropic
  include Ai::Providers::Sync::Google
  include Ai::Providers::Sync::Azure
  include Ai::Providers::Sync::Groq
  include Ai::Providers::Sync::Grok
  include Ai::Providers::Sync::Mistral
  include Ai::Providers::Sync::Cohere
  include Ai::Providers::Sync::Generic

  # Cache TTLs for model sync
  PROVIDER_MODELS_CACHE_TTL = 24.hours
  PROVIDER_USAGE_CACHE_TTL = 15.minutes

  # Model pricing per 1K tokens (in USD) - Updated Feb 2026
  # Authoritative reference used during syncs to populate cost_per_1k_tokens in supported_models
  MODEL_PRICING = {
    # OpenAI (Feb 2026)
    "gpt-4.1"                    => { "input" => 0.002,   "output" => 0.008,   "cached_input" => 0.0005,  "tier" => "premium" },
    "gpt-4.1-mini"               => { "input" => 0.0004,  "output" => 0.0016,  "cached_input" => 0.0001,  "tier" => "standard" },
    "gpt-4.1-nano"               => { "input" => 0.0001,  "output" => 0.0004,  "cached_input" => 0.000025, "tier" => "economy" },
    "o3"                         => { "input" => 0.002,   "output" => 0.008,   "cached_input" => 0.0005,  "tier" => "premium" },
    "o4-mini"                    => { "input" => 0.0011,  "output" => 0.0044,  "cached_input" => 0.000275, "tier" => "standard" },
    "gpt-4o"                     => { "input" => 0.0025,  "output" => 0.01,    "cached_input" => 0.00125, "tier" => "standard" },
    "gpt-4o-mini"                => { "input" => 0.00015, "output" => 0.0006,  "cached_input" => 0.000075, "tier" => "economy" },
    "gpt-4-turbo"                => { "input" => 0.01,    "output" => 0.03,    "cached_input" => 0.005,   "tier" => "premium" },
    "gpt-3.5-turbo"              => { "input" => 0.0005,  "output" => 0.0015,  "cached_input" => 0.00025, "tier" => "economy" },
    # Anthropic (Feb 2026)
    "claude-opus-4-6"            => { "input" => 0.005,   "output" => 0.025,   "cached_input" => 0.0005,  "tier" => "premium" },
    "claude-opus-4-5"            => { "input" => 0.005,   "output" => 0.025,   "cached_input" => 0.0005,  "tier" => "premium" },
    "claude-sonnet-4-5"          => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-sonnet-4"            => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-haiku-4-5"           => { "input" => 0.001,   "output" => 0.005,   "cached_input" => 0.0001,  "tier" => "economy" },
    "claude-3-5-sonnet"          => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-3-5-haiku"           => { "input" => 0.0008,  "output" => 0.004,   "cached_input" => 0.00008, "tier" => "economy" },
    "claude-3-haiku-20240307"    => { "input" => 0.00025, "output" => 0.00125, "cached_input" => 0.00003, "tier" => "economy" },
    "claude-3-sonnet-20240229"   => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-3-opus-20240229"     => { "input" => 0.015,   "output" => 0.075,   "cached_input" => 0.0015,  "tier" => "premium" },
    # X.AI (Grok)
    "grok-3"                     => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "premium" },
    "grok-3-mini"                => { "input" => 0.0003,  "output" => 0.0005,  "cached_input" => 0.00003, "tier" => "economy" },
    "grok-3-mini-fast"           => { "input" => 0.0001,  "output" => 0.0004,  "cached_input" => 0.00001, "tier" => "economy" },
    "grok-3-fast"                => { "input" => 0.005,   "output" => 0.025,   "cached_input" => 0.0005,  "tier" => "premium" },
    "grok-2"                     => { "input" => 0.002,   "output" => 0.01,    "cached_input" => 0.0002,  "tier" => "standard" },
    # Google
    "gemini-2.0-flash"           => { "input" => 0.0001,  "output" => 0.0004,  "cached_input" => 0.000025, "tier" => "economy" },
    "gemini-1.5-pro"             => { "input" => 0.00125, "output" => 0.005,   "cached_input" => 0.000315, "tier" => "standard" },
    "gemini-1.5-flash"           => { "input" => 0.000075, "output" => 0.0003, "cached_input" => 0.00002,  "tier" => "economy" },
    # Groq (hosted models)
    "llama-3.3-70b-versatile"    => { "input" => 0.00059, "output" => 0.00079, "cached_input" => 0.00029, "tier" => "standard" },
    "llama-3.1-8b-instant"       => { "input" => 0.00005, "output" => 0.00008, "cached_input" => 0.000025, "tier" => "economy" },
    "mixtral-8x7b-32768"         => { "input" => 0.00024, "output" => 0.00024, "cached_input" => 0.00012, "tier" => "economy" },
    # Mistral
    "mistral-large"              => { "input" => 0.002,   "output" => 0.006,   "cached_input" => 0.001,   "tier" => "standard" },
    "mistral-small"              => { "input" => 0.0002,  "output" => 0.0006,  "cached_input" => 0.0001,  "tier" => "economy" },
    "codestral"                  => { "input" => 0.0003,  "output" => 0.0009,  "cached_input" => 0.00015, "tier" => "economy" },
    # Cohere
    "command-r-plus"             => { "input" => 0.0025,  "output" => 0.01,    "cached_input" => 0.00125, "tier" => "standard" },
    "command-r"                  => { "input" => 0.00015, "output" => 0.0006,  "cached_input" => 0.000075, "tier" => "economy" }
  }.freeze

  # Helper class to wrap HTTP responses with success? method
  class ResponseWrapper
    attr_reader :body, :code, :message

    def initialize(response, error: nil)
      if response
        @body = response.body
        @code = response.code.to_i
        @message = response.message
        @success = response.is_a?(Net::HTTPSuccess)
      else
        @body = ""
        @code = 0
        @message = error || "Connection failed"
        @success = false
      end
    end

    def success?
      @success
    end
  end

  # Instance-level initialization for provider testing
  def initialize(credential_or_provider)
    if credential_or_provider.is_a?(Ai::Provider)
      @provider = credential_or_provider
      @credential = credential_or_provider.provider_credentials.active.first
    else
      @credential = credential_or_provider
      @provider = credential_or_provider.provider
    end
    @test_config = {
      timeout: 10,
      max_retries: 3,
      test_message: "Hello, this is a test message."
    }
    @test_results = {}
    @health_check_results = []
  end

  # Instance method for simplified provider-level connection test
  def test_provider_connection
    result = test_connection
    {
      success: result[:success],
      message: result[:success] ? "Connection successful" : (result[:error_details] || result[:error_type]),
      response_time_ms: result[:response_time_ms]
    }
  end

  class << self
    # Look up pricing for a model by exact match, then prefix match
    def model_pricing_for(model_id)
      return nil unless model_id.is_a?(String)

      # Exact match first
      return MODEL_PRICING[model_id] if MODEL_PRICING.key?(model_id)

      # Prefix match (e.g. "gpt-4o-mini-2024-07-18" matches "gpt-4o-mini")
      MODEL_PRICING.each do |key, pricing|
        return pricing if model_id.start_with?(key)
      end

      nil
    end

    # Sync models for all active providers
    def sync_all_providers(force_refresh: false)
      results = { synced: 0, failed: 0, skipped: 0, errors: [] }

      Ai::Provider.where(is_active: true).find_each do |provider|
        if sync_provider_models(provider, force_refresh: force_refresh)
          results[:synced] += 1
        else
          results[:failed] += 1
          results[:errors] << { provider_id: provider.id, name: provider.name }
        end
      rescue StandardError => e
        Rails.logger.error "Failed to sync provider #{provider.id}: #{e.message}"
        results[:failed] += 1
        results[:errors] << { provider_id: provider.id, name: provider.name, error: e.message }
      end

      results
    end

    # Get providers available for a specific account
    def get_available_providers_for_account(account)
      Ai::Provider.active.includes(:provider_credentials)
    end

    # Sync models for a specific provider (cached for 24 hours)
    def sync_provider_models(provider, force_refresh: false)
      return false unless provider.is_active?

      cache_key = "ai:provider_models:#{provider.id}"

      # Use cache unless force refresh is requested
      unless force_refresh
        cached = Rails.cache.read(cache_key)
        return true if cached.present?
      end

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
        # Cache the successful sync
        Rails.cache.write(cache_key, true, expires_in: PROVIDER_MODELS_CACHE_TTL)
        true
      rescue StandardError => e
        Rails.logger.error "Failed to sync models for provider #{provider.id}: #{e.message}"
        false
      end
    end

    # Invalidate provider models cache
    def invalidate_provider_models_cache(provider_id)
      Rails.cache.delete("ai:provider_models:#{provider_id}")
    end

    # Get usage summary for a provider within a specific account
    # Queries real Ai::AgentExecution data for accurate metrics
    def provider_usage_summary(provider, account, period)
      end_date = Time.current
      start_date = end_date - period

      # Query real execution data from agents using this provider
      executions = fetch_provider_executions(provider, account, start_date, end_date)

      # Calculate aggregated metrics
      total_requests = executions.count
      successful_requests = executions.where(status: "completed").count
      failed_requests = executions.where(status: "failed").count

      # Token and cost calculations from execution metadata
      token_stats = calculate_token_stats(executions)
      cost_stats = calculate_cost_stats(executions)

      # Response time calculations
      response_time_stats = calculate_response_time_stats(executions)

      # Calculate success rate safely
      success_rate = total_requests > 0 ? (successful_requests.to_f / total_requests * 100).round(1) : 0.0

      {
        provider_id: provider.id,
        provider_name: provider.name,
        period_start: start_date,
        period_end: end_date,
        period_days: (period.to_i / 1.day.to_i),
        total_requests: total_requests,
        successful_requests: successful_requests,
        failed_requests: failed_requests,
        total_tokens: token_stats[:total],
        prompt_tokens: token_stats[:prompt],
        completion_tokens: token_stats[:completion],
        total_cost: cost_stats[:total].round(2),
        average_response_time_ms: response_time_stats[:average].round,
        min_response_time_ms: response_time_stats[:min],
        max_response_time_ms: response_time_stats[:max],
        success_rate: success_rate,
        daily_breakdown: generate_real_daily_breakdown(provider, account, start_date, end_date)
      }
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

    # Create a new provider credential with validation and encryption
    def create_provider_credential(provider, account, credentials_data, name: nil, is_active: nil, is_default: nil, expires_at: nil)
      raise ValidationError, "Provider is required" unless provider
      raise ValidationError, "Account is required" unless account
      raise ValidationError, "Credentials data is required" if credentials_data.blank? || (credentials_data.is_a?(Hash) && credentials_data.empty?)

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
          test_service = new(credential)
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
          test_service = new(credential)
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

    # Class methods from former ProviderTestService
    def summarize_test_results(results)
      successful = results.count { |r| r[:success] }
      response_times = results.filter_map { |r| r[:response_time_ms] }

      sorted_by_time = results.select { |r| r[:response_time_ms] }.sort_by { |r| r[:response_time_ms] }

      {
        total_credentials: results.size,
        successful_tests: successful,
        failed_tests: results.size - successful,
        average_response_time: response_times.any? ? response_times.sum / response_times.size.to_f : 0,
        fastest_provider: sorted_by_time.first&.dig(:provider_name),
        slowest_provider: sorted_by_time.last&.dig(:provider_name)
      }
    end

    def health_check_all_providers
      Ai::Provider.active.map do |provider|
        {
          provider_id: provider.id,
          provider_name: provider.name,
          status: "active"
        }
      end
    end

    private

    # Fetch executions for a provider within an account
    def fetch_provider_executions(provider, account, start_date, end_date)
      # Get agents that use this provider within the account
      agent_ids = ::Ai::Agent.where(account: account, provider: provider).pluck(:id)

      return ::Ai::AgentExecution.none if agent_ids.empty?

      ::Ai::AgentExecution.where(ai_agent_id: agent_ids)
                         .where(created_at: start_date..end_date)
    end

    # Calculate token statistics from executions
    def calculate_token_stats(executions)
      return { total: 0, prompt: 0, completion: 0 } if executions.empty?

      # Sum tokens from execution metadata (stored in result or metadata columns)
      stats = { total: 0, prompt: 0, completion: 0 }

      executions.find_each do |execution|
        # Try to extract token usage from result or metadata
        metadata = execution.output_data.is_a?(Hash) ? execution.output_data : {}
        usage = metadata["usage"] || metadata["token_usage"] || {}

        stats[:prompt] += (usage["prompt_tokens"] || usage["input_tokens"] || 0).to_i
        stats[:completion] += (usage["completion_tokens"] || usage["output_tokens"] || 0).to_i
      end

      stats[:total] = stats[:prompt] + stats[:completion]
      stats
    end

    # Calculate cost statistics from executions
    def calculate_cost_stats(executions)
      return { total: 0.0 } if executions.empty?

      total_cost = 0.0

      executions.find_each do |execution|
        metadata = execution.output_data.is_a?(Hash) ? execution.output_data : {}
        cost = metadata["cost"] || metadata["cost_estimate"] || 0.0
        total_cost += cost.to_f
      end

      { total: total_cost }
    end

    # Calculate response time statistics
    def calculate_response_time_stats(executions)
      return { average: 0, min: 0, max: 0 } if executions.empty?

      # Use duration_ms if available, otherwise calculate from timestamps
      durations = []

      executions.find_each do |execution|
        duration = if execution.respond_to?(:duration_ms) && execution.duration_ms.present?
                    execution.duration_ms
        elsif execution.started_at && execution.completed_at
                    ((execution.completed_at - execution.started_at) * 1000).to_i
        end

        durations << duration if duration && duration > 0
      end

      return { average: 0, min: 0, max: 0 } if durations.empty?

      {
        average: durations.sum.to_f / durations.size,
        min: durations.min,
        max: durations.max
      }
    end

    # Generate real daily breakdown from actual execution data
    def generate_real_daily_breakdown(provider, account, start_date, end_date)
      breakdown = []
      current_date = start_date.beginning_of_day

      # Get all agent IDs for this provider/account combo once
      agent_ids = ::Ai::Agent.where(account: account, provider: provider).pluck(:id)

      while current_date <= end_date
        day_end = current_date.end_of_day

        if agent_ids.any?
          day_executions = ::Ai::AgentExecution.where(ai_agent_id: agent_ids)
                                              .where(created_at: current_date..day_end)

          day_requests = day_executions.count
          day_token_stats = calculate_token_stats(day_executions)
          day_cost_stats = calculate_cost_stats(day_executions)
          day_response_stats = calculate_response_time_stats(day_executions)

          breakdown << {
            date: current_date.to_date,
            requests: day_requests,
            successful: day_executions.where(status: "completed").count,
            failed: day_executions.where(status: "failed").count,
            tokens: day_token_stats[:total],
            cost: day_cost_stats[:total].round(2),
            avg_response_time: day_response_stats[:average].round
          }
        else
          # No agents configured - return zero values
          breakdown << {
            date: current_date.to_date,
            requests: 0,
            successful: 0,
            failed: 0,
            tokens: 0,
            cost: 0.0,
            avg_response_time: 0
          }
        end

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

    # Handle sync failure: clear models, deactivate provider, raise error
    def handle_sync_failure(provider, error_message)
      Rails.logger.error "[ProviderSync] #{error_message} (provider: #{provider.id} / #{provider.name})"

      # Store the sync error in metadata for visibility
      current_metadata = provider.metadata || {}
      current_metadata["last_sync_error"] = error_message
      current_metadata["last_sync_failed_at"] = Time.current.iso8601

      # Use update_all to bypass supported_models presence validation
      # (we intentionally want 0 models on failure)
      Ai::Provider.where(id: provider.id).update_all(
        supported_models: [],
        is_active: false,
        metadata: current_metadata
      )
      provider.reload

      raise StandardError, error_message
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
