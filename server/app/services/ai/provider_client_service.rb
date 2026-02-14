# frozen_string_literal: true

class Ai::ProviderClientService
  include HTTParty
  include OpenaiAdapter
  include AnthropicAdapter
  include OllamaAdapter
  include Streaming
  include ResponseHandling

  # Custom exception for validation errors
  class ValidationError < StandardError; end

  # Default pricing when no DB pricing is available (per 1K tokens)
  DEFAULT_PRICING = { prompt: 0.002, completion: 0.008, cached: 0.0005 }.freeze

  VALID_ROLES = %w[system user assistant function tool].freeze
  HEALTH_CHECK_CACHE_TTL = 10.minutes

  attr_reader :provider, :credential, :credentials_data

  def initialize(ai_provider_credential)
    @credential = ai_provider_credential
    @provider = credential.provider
    @credentials_data = credential.credentials
    @circuit_breaker = Ai::ProviderCircuitBreakerService.new(@provider)
    @rate_limit_tracker = {}
    @consecutive_failures = 0
    @usage_metrics = {
      total_requests: 0,
      failed_requests: 0,
      total_tokens: 0,
      prompt_tokens: 0,
      completion_tokens: 0,
      total_response_time: 0,
      avg_response_time: 0.0,
      success_rate: 100.0
    }
    setup_client_options
  end

  def generate_text(prompt, model: nil, **options)
    model_name = model || default_model_for_capability("text_generation")
    raise ArgumentError, "No compatible model found" unless model_name

    @circuit_breaker.call do
      case provider.provider_type
      when "openai"
        openai_generate_text(prompt, model_name, **options)
      when "anthropic"
        anthropic_generate_text(prompt, model_name, **options)
      when "ollama"
        ollama_generate_text(prompt, model_name, **options)
      else
        capability_not_supported("text_generation")
      end
    end
  rescue Ai::ProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Circuit breaker is open for provider #{provider.name}",
      error_type: "circuit_breaker_open",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true,
      circuit_breaker_state: "open",
      retry_after: calculate_backoff_time
    }
  end

  def generate_image(prompt, model: nil, **options)
    model_name = model || default_model_for_capability("image_generation")
    raise ArgumentError, "No compatible model found" unless model_name

    @circuit_breaker.call do
      case provider.provider_type
      when "openai"
        openai_generate_image(prompt, model_name, **options)
      else
        capability_not_supported("image_generation")
      end
    end
  rescue Ai::ProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Circuit breaker is open for provider #{provider.name}",
      error_type: "circuit_breaker_open",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true,
      circuit_breaker_state: "open",
      retry_after: calculate_backoff_time
    }
  end

  def execute_code(code, language: "python", **options)
    model_name = default_model_for_capability("code_execution")
    raise ArgumentError, "No compatible model found" unless model_name

    case provider.provider_type
    when "replit"
      replit_execute_code(code, language, **options)
    else
      capability_not_supported("code_execution")
    end
  end

  def stream_text(prompt, model: nil, **options, &block)
    model_name = model || default_model_for_capability("text_generation")
    raise ArgumentError, "No compatible model found" unless model_name
    raise ArgumentError, "Provider does not support streaming" unless provider.supports_streaming?

    case provider.provider_type
    when "openai"
      openai_stream_text(prompt, model_name, **options, &block)
    when "anthropic"
      anthropic_stream_text(prompt, model_name, **options, &block)
    when "ollama"
      ollama_stream_text(prompt, model_name, **options, &block)
    else
      capability_not_supported("streaming")
    end
  end

  # Send a chat message to the AI provider
  # @param messages [Array<Hash>] Array of message objects with role and content
  # @param options [Hash] Options including model, temperature, max_tokens, etc.
  # @return [Hash] Response with success status, response data, and metadata
  def send_message(messages, options = {})
    validate_message_format(messages)

    model_name = options[:model] || default_model_for_capability("text_generation")

    @circuit_breaker.call do
      start_time = Time.current

      begin
        result = case provider.provider_type
        when "openai"
                   openai_send_message(messages, model_name, **options)
        when "anthropic"
                   anthropic_send_message(messages, model_name, **options)
        when "ollama"
                   ollama_send_message(messages, model_name, **options)
        else
                   capability_not_supported("send_message")
        end

        response_time_ms = ((Time.current - start_time) * 1000).round
        track_usage(result[:response] || {}, response_time_ms, result[:success])

        if result[:success]
          usage = extract_usage(result[:response])
          result.merge(
            metadata: {
              tokens_used: usage[:total_tokens],
              usage: usage,
              response_time_ms: response_time_ms,
              model_used: model_name,
              stream_enabled: options[:stream] || false,
              parameters_used: options.except(:model)
            }
          )
        else
          result.merge(
            retry_after: extract_retry_after(result),
            retry_recommended: result[:error_type] == "server_error"
          )
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        response_time_ms = ((Time.current - start_time) * 1000).round
        track_usage({}, response_time_ms, false)

        {
          success: false,
          error: "Request timeout: #{e.message}",
          error_type: "network_error",
          retry_after: calculate_backoff_time,
          retry_recommended: true
        }
      rescue JSON::ParserError => e
        response_time_ms = ((Time.current - start_time) * 1000).round
        track_usage({}, response_time_ms, false)

        {
          success: false,
          error: "Failed to parse response: #{e.message}",
          error_type: "parse_error",
          retry_recommended: false
        }
      end
    end
  rescue Ai::ProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Circuit breaker is open for provider #{provider.name}",
      error_type: "circuit_breaker_open",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true,
      circuit_breaker_state: "open",
      retry_after: calculate_backoff_time
    }
  end

  # Perform a health check on the AI provider (cached for 10 minutes)
  # @param force_refresh [Boolean] Skip cache and perform fresh check
  # @return [Hash] Health status with metrics
  def health_check(force_refresh: false)
    cache_key = "ai:provider_health:#{provider.id}:#{credential.id}"

    # Return cached result unless force refresh
    unless force_refresh
      cached = Rails.cache.read(cache_key)
      return cached if cached.present?
    end

    start_time = Time.current
    test_messages = [ { role: "user", content: "Hello" } ]

    begin
      result = send_message(test_messages, { model: default_model_for_capability("text_generation"), max_tokens: 5 })
      response_time = ((Time.current - start_time) * 1000).round

      health_result = {
        healthy: result[:success],
        response_time_ms: response_time,
        last_checked_at: Time.current.iso8601,
        error_rate: calculate_error_rate,
        circuit_breaker_state: @circuit_breaker.circuit_state,
        last_error: result[:success] ? nil : result[:error]
      }

      # Cache successful checks longer, failed checks shorter
      cache_ttl = result[:success] ? HEALTH_CHECK_CACHE_TTL : 2.minutes
      Rails.cache.write(cache_key, health_result, expires_in: cache_ttl)

      health_result
    rescue StandardError => e
      health_result = {
        healthy: false,
        response_time_ms: ((Time.current - start_time) * 1000).round,
        last_checked_at: Time.current.iso8601,
        error_rate: calculate_error_rate,
        circuit_breaker_state: @circuit_breaker.circuit_state,
        last_error: e.message
      }

      # Cache failed checks for shorter duration
      Rails.cache.write(cache_key, health_result, expires_in: 2.minutes)

      health_result
    end
  end

  # Invalidate health check cache
  def self.invalidate_health_cache(provider_id, credential_id)
    Rails.cache.delete("ai:provider_health:#{provider_id}:#{credential_id}")
  end

  # Batch completion for multiple prompts - optimizes API calls
  def batch_completion(prompts, model: nil, **options)
    model_name = model || default_model_for_capability("text_generation")
    raise ArgumentError, "No compatible model found" unless model_name
    raise ArgumentError, "Prompts must be an array" unless prompts.is_a?(Array)
    return { success: true, results: [] } if prompts.empty?

    batch_size = options[:batch_size] || 5
    results = []

    # Process in batches to avoid overwhelming the provider
    prompts.each_slice(batch_size) do |batch_prompts|
      batch_results = process_batch_prompts(batch_prompts, model_name, **options)
      results.concat(batch_results)
    end

    {
      success: true,
      results: results,
      total_processed: prompts.size,
      batches_processed: (prompts.size.to_f / batch_size).ceil
    }
  rescue StandardError => e
    Rails.logger.error "Batch completion failed: #{e.message}"
    {
      success: false,
      error: "Batch completion failed: #{e.message}",
      results: results, # Return partial results if any
      total_processed: results.size
    }
  end

  private

  def setup_client_options
    self.class.base_uri(provider.api_base_url)
    # Increased timeout for content generation tasks (blog writing, editing, etc.)
    # 120 seconds should be sufficient for generating 1000-1500 word articles
    self.class.default_timeout(120)

    # Set up common headers
    @headers = {
      "User-Agent" => "Powernode-AI/1.0",
      "Content-Type" => "application/json"
    }

    # Provider-specific authentication
    case provider.provider_type
    when "openai"
      @headers["Authorization"] = "Bearer #{credentials_data['api_key']}"
      @headers["OpenAI-Organization"] = credentials_data["organization"] if credentials_data["organization"]
    when "anthropic"
      @headers["x-api-key"] = credentials_data["api_key"]
      @headers["anthropic-version"] = "2023-06-01"
    else
      @headers["Authorization"] = "Bearer #{credentials_data['api_key']}" if credentials_data["api_key"]
    end
  end

  def default_model_for_capability(capability)
    compatible_models = provider.supported_models.select do |model|
      provider.capabilities.include?(capability)
    end
    first_model = compatible_models.first
    # Handle both Hash ({"id": "model"}) and String ("model") formats
    first_model.is_a?(Hash) ? first_model.dig("id") || first_model["name"] : first_model
  end
end
