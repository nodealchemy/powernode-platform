# frozen_string_literal: true

class Ai::ProviderManagementService
  # Custom exception classes
  class ValidationError < StandardError; end
  class CredentialError < StandardError; end

  # Cache TTLs for model sync
  PROVIDER_MODELS_CACHE_TTL = 24.hours
  PROVIDER_USAGE_CACHE_TTL = 15.minutes

  # Model pricing per 1K tokens (in USD)
  # Authoritative reference used during syncs to populate cost_per_1k_tokens in supported_models
  MODEL_PRICING = {
    # OpenAI
    "gpt-3.5-turbo"              => { "input" => 0.0005,  "output" => 0.0015 },
    "gpt-4"                      => { "input" => 0.03,    "output" => 0.06 },
    "gpt-4-turbo"                => { "input" => 0.01,    "output" => 0.03 },
    "gpt-4o"                     => { "input" => 0.0025,  "output" => 0.01 },
    "gpt-4o-mini"                => { "input" => 0.00015, "output" => 0.0006 },
    "o1"                         => { "input" => 0.015,   "output" => 0.06 },
    "o1-mini"                    => { "input" => 0.003,   "output" => 0.012 },
    "o3-mini"                    => { "input" => 0.00115, "output" => 0.0044 },
    # Anthropic
    "claude-3-haiku-20240307"    => { "input" => 0.00025, "output" => 0.00125 },
    "claude-3-sonnet-20240229"   => { "input" => 0.003,   "output" => 0.015 },
    "claude-3-opus-20240229"     => { "input" => 0.015,   "output" => 0.075 },
    "claude-3-5-sonnet"          => { "input" => 0.003,   "output" => 0.015 },
    "claude-3-5-haiku"           => { "input" => 0.0008,  "output" => 0.004 },
    "claude-sonnet-4"            => { "input" => 0.003,   "output" => 0.015 },
    "claude-haiku-4-5"           => { "input" => 0.0008,  "output" => 0.004 },
    "claude-opus-4-5"            => { "input" => 0.015,   "output" => 0.075 },
    # X.AI (Grok)
    "grok-3"                     => { "input" => 0.003,   "output" => 0.015 },
    "grok-3-mini"                => { "input" => 0.0003,  "output" => 0.0005 },
    "grok-3-mini-fast"           => { "input" => 0.0001,  "output" => 0.0004 },
    "grok-3-fast"                => { "input" => 0.005,   "output" => 0.025 },
    "grok-2"                     => { "input" => 0.002,   "output" => 0.01 },
    # Google
    "gemini-2.0-flash"           => { "input" => 0.0001,  "output" => 0.0004 },
    "gemini-1.5-pro"             => { "input" => 0.00125, "output" => 0.005 },
    "gemini-1.5-flash"           => { "input" => 0.000075, "output" => 0.0003 },
    # Groq (hosted models)
    "llama-3.3-70b-versatile"    => { "input" => 0.00059, "output" => 0.00079 },
    "llama-3.1-8b-instant"       => { "input" => 0.00005, "output" => 0.00008 },
    "mixtral-8x7b-32768"         => { "input" => 0.00024, "output" => 0.00024 },
    # Mistral
    "mistral-large"              => { "input" => 0.002,   "output" => 0.006 },
    "mistral-small"              => { "input" => 0.0002,  "output" => 0.0006 },
    "codestral"                  => { "input" => 0.0003,  "output" => 0.0009 },
    # Cohere
    "command-r-plus"             => { "input" => 0.0025,  "output" => 0.01 },
    "command-r"                  => { "input" => 0.00015, "output" => 0.0006 }
  }.freeze

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

    # Provider-specific model sync methods
    def sync_ollama_models(provider)
      base_url = provider.api_base_url.to_s.chomp("/")
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      # Build possible endpoint URLs (try multiple patterns)
      # Standard Ollama: http://localhost:11434/api/tags
      # Open WebUI: https://host/ollama/api/tags (requires auth)
      # Open WebUI alt: https://host/api/tags (with /api base)
      endpoints = []

      if base_url.end_with?("/api")
        # Base URL already includes /api
        endpoints << { url: "#{base_url}/tags", auth: false }
        endpoints << { url: "#{base_url}/tags", auth: true }
      else
        # Standard Ollama endpoint first
        endpoints << { url: "#{base_url}/api/tags", auth: false }
        # Open WebUI endpoint (requires auth)
        endpoints << { url: "#{base_url}/ollama/api/tags", auth: true }
        # Retry standard with auth
        endpoints << { url: "#{base_url}/api/tags", auth: true }
      end

      api_data = nil

      endpoints.each do |endpoint|
        begin
          http_client = HTTP.timeout(10)

          # Add authentication if needed and credential exists
          if endpoint[:auth] && credential
            api_key = credential.credentials&.dig("api_key")
            if api_key.present?
              http_client = http_client.headers("Authorization" => "Bearer #{api_key}")
            end
          end

          response = http_client.get(endpoint[:url])

          if response.status.success?
            body = response.body.to_s
            # Verify it's JSON, not HTML
            if body.start_with?("{") || body.start_with?("[")
              api_data = JSON.parse(body)
              Rails.logger.info "Ollama sync succeeded with endpoint: #{endpoint[:url]}"
              break
            end
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.debug "Ollama endpoint #{endpoint[:url]} failed: #{e.message}"
          next
        end
      end

      if api_data
        models = api_data["models"] || []

        # Transform Ollama API response to our model format
        supported_models = models.map do |model|
          details = model["details"] || {}
          {
            "name" => model["name"]&.split(":")&.first&.capitalize || model["name"],
            "id" => model["name"],
            "context_length" => details["parameter_size"] || 4096,
            "description" => "#{model['name']} - Size: #{format_model_size(model['size'])}",
            "cost_per_1k_tokens" => { "input" => 0, "output" => 0 },
            "size_bytes" => model["size"],
            "family" => details["family"],
            "parameter_size" => details["parameter_size"],
            "quantization_level" => details["quantization_level"],
            "modified_at" => model["modified_at"],
            "digest" => model["digest"],
            "format" => details["format"]
          }
        end

        provider.update(supported_models: supported_models)
        Rails.logger.info "Successfully synced #{supported_models.length} models for Ollama provider #{provider.id}"
      else
        Rails.logger.error "Failed to fetch models from any Ollama endpoint for provider #{provider.id} (base_url: #{base_url})"
        handle_sync_failure(provider, "Could not connect to Ollama API at #{base_url}")
      end
    rescue HTTP::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
      Rails.logger.error "Error syncing Ollama models: #{e.message}"
      handle_sync_failure(provider, "Could not connect to Ollama API: #{e.message}")
    end

    def sync_openai_models(provider)
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          response = HTTP.headers(
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          ).timeout(15).get("https://api.openai.com/v1/models")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["data"] || []

            # Filter to only chat/completion models (exclude embeddings, whisper, dall-e, etc.)
            chat_models = models.select { |m| openai_chat_model?(m["id"]) }

            supported_models = chat_models.map do |model|
              {
                "name" => format_openai_model_name(model["id"]),
                "id" => model["id"],
                "context_length" => openai_context_length(model["id"]),
                "max_output_tokens" => openai_max_output(model["id"]),
                "description" => openai_model_description(model["id"]),
                "capabilities" => openai_capabilities(model["id"]),
                "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                "owned_by" => model["owned_by"],
                "created_at" => model["created"] ? Time.at(model["created"]).iso8601 : nil
              }
            end

            supported_models.sort_by! { |m| -openai_model_priority(m["id"]) }

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from OpenAI API for provider #{provider.id}"
            return true
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching OpenAI models: #{e.message}, falling back to static models"
        end
      end

      handle_sync_failure(provider, "Failed to sync OpenAI models: no valid credentials or API error")
    end

    def openai_chat_model?(model_id)
      model_id.match?(/^(gpt-4|gpt-3\.5|o1|o3|chatgpt)/i) && !model_id.include?("instruct")
    end

    def format_openai_model_name(model_id)
      model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
        .gsub("Gpt", "GPT").gsub("4o", "4o").gsub("3.5", "3.5")
    end

    def openai_context_length(model_id)
      return 200000 if model_id.include?("o1") || model_id.include?("o3")
      return 128000 if model_id.include?("gpt-4o") || model_id.include?("gpt-4-turbo")
      return 16385 if model_id.include?("gpt-3.5")
      8192
    end

    def openai_max_output(model_id)
      return 100000 if model_id.include?("o1") || model_id.include?("o3")
      return 16384 if model_id.include?("gpt-4o")
      4096
    end

    def openai_capabilities(model_id)
      caps = %w[text_generation chat function_calling]
      caps << "vision" if model_id.include?("gpt-4o") || model_id.include?("gpt-4-turbo") || model_id.include?("o1") || model_id.include?("o3")
      caps << "reasoning" if model_id.include?("o1") || model_id.include?("o3")
      caps
    end

    def openai_model_description(model_id)
      return "Advanced reasoning model" if model_id.include?("o1") || model_id.include?("o3")
      return "Most advanced multimodal model" if model_id == "gpt-4o"
      return "Affordable and intelligent small model" if model_id.include?("gpt-4o-mini")
      return "GPT-4 Turbo with vision" if model_id.include?("gpt-4-turbo")
      return "Fast and efficient model" if model_id.include?("gpt-3.5")
      "OpenAI language model"
    end

    def openai_model_priority(model_id)
      return 100 if model_id == "gpt-4o"
      return 95 if model_id.include?("o3")
      return 90 if model_id.include?("o1") && !model_id.include?("mini")
      return 85 if model_id.include?("o1-mini")
      return 80 if model_id.include?("gpt-4o-mini")
      return 70 if model_id.include?("gpt-4-turbo")
      return 60 if model_id.include?("gpt-4")
      return 50 if model_id.include?("gpt-3.5")
      0
    end

    def sync_anthropic_models(provider)
      # Try to fetch models from Anthropic API dynamically
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          response = HTTP.headers(
            "x-api-key" => api_key,
            "anthropic-version" => "2023-06-01",
            "Content-Type" => "application/json"
          ).timeout(15).get("https://api.anthropic.com/v1/models")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["data"] || []

            supported_models = models.map do |model|
              {
                "name" => format_anthropic_model_name(model["id"]),
                "id" => model["id"],
                "context_length" => 200000,
                "max_output_tokens" => extract_max_output_tokens(model["id"]),
                "description" => model["display_name"] || format_anthropic_model_name(model["id"]),
                "capabilities" => extract_anthropic_capabilities(model["id"]),
                "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                "display_name" => model["display_name"],
                "created_at" => model["created_at"]
              }
            end

            # Sort by model name (newest first based on naming convention)
            supported_models.sort_by! { |m| -model_sort_priority(m["id"]) }

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from Anthropic API for provider #{provider.id}"
            return true
          else
            Rails.logger.warn "Anthropic API returned #{response.status}, falling back to static models"
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching Anthropic models: #{e.message}, falling back to static models"
        end
      end

      # Sync failed - deactivate provider and clear models
      handle_sync_failure(provider, "Failed to sync Anthropic models: no valid credentials or API error")
    end

    def format_anthropic_model_name(model_id)
      # Convert model ID to human-readable name
      # e.g., "claude-opus-4-5-20251101" -> "Claude Opus 4.5"
      return model_id unless model_id.is_a?(String)

      name = model_id
        .gsub(/-\d{8}$/, "")           # Remove date suffix
        .gsub("-", " ")                 # Replace dashes with spaces
        .gsub(/(\d) (\d)/, '\1.\2')     # "4 5" -> "4.5"
        .split.map(&:capitalize).join(" ")

      name.gsub("Claude", "Claude")     # Ensure proper casing
    end

    def extract_max_output_tokens(model_id)
      # Opus models have higher output limits
      return 32000 if model_id.include?("opus")
      8192
    end

    def extract_anthropic_capabilities(model_id)
      capabilities = [ "text_generation", "chat", "vision" ]
      capabilities << "code_generation" if model_id.include?("opus") || model_id.include?("sonnet")
      capabilities << "extended_thinking" if model_id.include?("opus")
      capabilities
    end

    def model_sort_priority(model_id)
      # Higher priority = listed first
      return 100 if model_id.include?("opus-4-5")
      return 90 if model_id.include?("opus-4")
      return 80 if model_id.include?("sonnet-4-5")
      return 70 if model_id.include?("sonnet-4")
      return 60 if model_id.include?("sonnet-3")
      return 50 if model_id.include?("haiku-3-5")
      return 40 if model_id.include?("haiku-3")
      0
    end

    def sync_google_models(provider)
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          # Google AI Studio API endpoint for listing models
          response = HTTP.timeout(15).get("https://generativelanguage.googleapis.com/v1beta/models?key=#{api_key}")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["models"] || []

            # Filter to generative models only
            generative_models = models.select { |m| m["name"]&.include?("gemini") }

            supported_models = generative_models.map do |model|
              model_id = model["name"]&.split("/")&.last || model["name"]
              {
                "name" => model["displayName"] || format_google_model_name(model_id),
                "id" => model_id,
                "context_length" => model["inputTokenLimit"] || 1048576,
                "max_output_tokens" => model["outputTokenLimit"] || 8192,
                "description" => model["description"] || model["displayName"],
                "capabilities" => google_capabilities(model_id),
                "cost_per_1k_tokens" => model_pricing_for(model_id),
                "supports_thinking" => model["supportThinking"] || false,
                "max_temperature" => model["maxTemperature"],
                "supported_methods" => model["supportedGenerationMethods"]
              }
            end

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from Google API for provider #{provider.id}"
            return true
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching Google models: #{e.message}, falling back to static models"
        end
      end

      handle_sync_failure(provider, "Failed to sync Google models: no valid credentials or API error")
    end

    def format_google_model_name(model_id)
      model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
    end

    def google_capabilities(model_id)
      caps = %w[text_generation chat vision]
      caps << "audio" if model_id.include?("1.5") || model_id.include?("2.0")
      caps << "code_execution" if model_id.include?("2.0")
      caps
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
          "capabilities" => %w[text_generation chat vision function_calling],
          "cost_per_1k_tokens" => model_pricing_for("gpt-4o")
        },
        {
          "name" => "GPT-4o Mini",
          "id" => "gpt-4o-mini",
          "context_length" => 128000,
          "max_output_tokens" => 16384,
          "description" => "Affordable and intelligent small model on Azure",
          "capabilities" => %w[text_generation chat vision function_calling],
          "cost_per_1k_tokens" => model_pricing_for("gpt-4o-mini")
        },
        {
          "name" => "GPT-4 Turbo",
          "id" => "gpt-4-turbo",
          "context_length" => 128000,
          "max_output_tokens" => 4096,
          "description" => "GPT-4 Turbo with Vision on Azure",
          "capabilities" => %w[text_generation chat vision function_calling],
          "cost_per_1k_tokens" => model_pricing_for("gpt-4-turbo")
        }
      ]

      provider.update(supported_models: current_models)
      Rails.logger.info "Successfully synced #{current_models.length} models for Azure provider #{provider.id}"
      true
    end

    def sync_groq_models(provider)
      # Groq uses OpenAI-compatible API
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          response = HTTP.headers(
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          ).timeout(15).get("https://api.groq.com/openai/v1/models")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["data"] || []

            supported_models = models.map do |model|
              {
                "name" => format_groq_model_name(model["id"]),
                "id" => model["id"],
                "context_length" => model["context_window"] || 8192,
                "max_output_tokens" => 8192,
                "description" => model["id"],
                "capabilities" => %w[text_generation chat],
                "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                "owned_by" => model["owned_by"],
                "context_window" => model["context_window"]
              }
            end

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from Groq API for provider #{provider.id}"
            return true
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching Groq models: #{e.message}, falling back to static models"
        end
      end

      handle_sync_failure(provider, "Failed to sync Groq models: no valid credentials or API error")
    end

    def format_groq_model_name(model_id)
      model_id.split("-").map(&:capitalize).join(" ").gsub(/(\d)b/i, '\1B')
    end

    def sync_mistral_models(provider)
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          response = HTTP.headers(
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          ).timeout(15).get("https://api.mistral.ai/v1/models")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["data"] || []

            supported_models = models.map do |model|
              {
                "name" => format_mistral_model_name(model["id"]),
                "id" => model["id"],
                "context_length" => model["max_context_length"] || 32000,
                "max_output_tokens" => 8192,
                "description" => model["description"] || model["id"],
                "capabilities" => mistral_capabilities(model["id"]),
                "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                "owned_by" => model["owned_by"]
              }
            end

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from Mistral API for provider #{provider.id}"
            return true
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching Mistral models: #{e.message}, falling back to static models"
        end
      end

      handle_sync_failure(provider, "Failed to sync Mistral models: no valid credentials or API error")
    end

    def format_mistral_model_name(model_id)
      model_id.gsub("-latest", "").gsub("-", " ").split.map(&:capitalize).join(" ")
    end

    def mistral_capabilities(model_id)
      caps = %w[text_generation chat]
      caps << "function_calling" if model_id.include?("large") || model_id.include?("small")
      caps << "vision" if model_id.include?("pixtral")
      caps << "code_generation" if model_id.include?("codestral")
      caps
    end

    def sync_cohere_models(provider)
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          response = HTTP.headers(
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          ).timeout(15).get("https://api.cohere.com/v1/models")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["models"] || []

            supported_models = models.map do |model|
              model_id = model["id"] || model["name"]
              {
                "name" => model["name"] || format_cohere_model_name(model_id),
                "id" => model_id,
                "context_length" => model["context_length"] || 4096,
                "max_output_tokens" => model["max_output_tokens"] || 4096,
                "description" => model["description"] || model["name"],
                "capabilities" => cohere_capabilities(model_id),
                "cost_per_1k_tokens" => model_pricing_for(model_id),
                "endpoints" => model["endpoints"]
              }
            end

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from Cohere API for provider #{provider.id}"
            return true
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching Cohere models: #{e.message}, falling back to static models"
        end
      end

      handle_sync_failure(provider, "Failed to sync Cohere models: no valid credentials or API error")
    end

    def format_cohere_model_name(model_id)
      return model_id unless model_id.is_a?(String)
      model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
    end

    def cohere_capabilities(model_id)
      return %w[embeddings] if model_id.to_s.include?("embed")
      return %w[rerank] if model_id.to_s.include?("rerank")
      %w[text_generation chat function_calling]
    end

    def sync_grok_models(provider)
      # X.AI uses OpenAI-compatible API
      credential = provider.provider_credentials.active.where(account_id: provider.account_id).first

      if credential
        begin
          api_key = credential.credentials["api_key"]
          response = HTTP.headers(
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          ).timeout(15).get("https://api.x.ai/v1/models")

          if response.status.success?
            api_data = JSON.parse(response.body.to_s)
            models = api_data["data"] || []

            supported_models = models.map do |model|
              {
                "name" => format_grok_model_name(model["id"]),
                "id" => model["id"],
                "context_length" => 131072,
                "max_output_tokens" => 8192,
                "description" => model["id"],
                "capabilities" => grok_capabilities(model["id"]),
                "cost_per_1k_tokens" => model_pricing_for(model["id"]),
                "owned_by" => model["owned_by"]
              }
            end

            provider.update(supported_models: supported_models)
            Rails.logger.info "Successfully synced #{supported_models.length} models from X.AI API for provider #{provider.id}"
            return true
          end
        rescue HTTP::Error, JSON::ParserError => e
          Rails.logger.error "Error fetching Grok models: #{e.message}, falling back to static models"
        end
      end

      handle_sync_failure(provider, "Failed to sync Grok models: no valid credentials or API error")
    end

    def format_grok_model_name(model_id)
      model_id.gsub("-", " ").split.map(&:capitalize).join(" ")
    end

    def grok_capabilities(model_id)
      caps = %w[text_generation chat function_calling]
      caps << "vision" if model_id.include?("vision")
      caps
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
