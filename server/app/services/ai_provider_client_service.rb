# frozen_string_literal: true

class AiProviderClientService
  include HTTParty

  # Custom exception for validation errors
  class ValidationError < StandardError; end

  # Model pricing per 1K tokens (in USD)
  MODEL_PRICING = {
    "gpt-3.5-turbo" => { prompt: 0.0015, completion: 0.002 },
    "gpt-3.5-turbo-16k" => { prompt: 0.003, completion: 0.004 },
    "gpt-4" => { prompt: 0.03, completion: 0.06 },
    "gpt-4-32k" => { prompt: 0.06, completion: 0.12 },
    "gpt-4-turbo" => { prompt: 0.01, completion: 0.03 },
    "gpt-4o" => { prompt: 0.005, completion: 0.015 },
    "claude-3-sonnet-20240229" => { prompt: 0.003, completion: 0.015 },
    "claude-3-opus-20240229" => { prompt: 0.015, completion: 0.075 },
    "claude-3-haiku-20240307" => { prompt: 0.00025, completion: 0.00125 }
  }.freeze

  VALID_ROLES = %w[system user assistant function tool].freeze
  CIRCUIT_BREAKER_THRESHOLD = 5
  CIRCUIT_BREAKER_TIMEOUT = 60 # seconds

  attr_reader :provider, :credential, :credentials_data

  def initialize(ai_provider_credential)
    @credential = ai_provider_credential
    @provider = credential.ai_provider
    @credentials_data = credential.credentials
    @circuit_breaker = AiProviderCircuitBreakerService.new(@provider)
    @rate_limit_tracker = {}
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
    @consecutive_failures = 0
    setup_client_options
  end

  def generate_text(prompt, model: nil, **options)
    model_name = model || default_model_for_capability("text_generation")
    raise ArgumentError, "No compatible model found" unless model_name

    @circuit_breaker.call do
      case provider.slug
      when "openai"
        openai_generate_text(prompt, model_name, **options)
      when "anthropic", "claude-ai-anthropic"
        anthropic_generate_text(prompt, model_name, **options)
      when "ollama", "remote-ollama-server"
        ollama_generate_text(prompt, model_name, **options)
      else
        raise NotImplementedError, "Text generation not implemented for #{provider.name}"
      end
    end
  rescue AiProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Provider #{provider.name} is temporarily unavailable",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true
    }
  end

  def generate_image(prompt, model: nil, **options)
    model_name = model || default_model_for_capability("image_generation")
    raise ArgumentError, "No compatible model found" unless model_name

    @circuit_breaker.call do
      case provider.slug
      when "stability-ai"
        stability_generate_image(prompt, model_name, **options)
      when "openai"
        openai_generate_image(prompt, model_name, **options)
      else
        raise NotImplementedError, "Image generation not implemented for #{provider.name}"
      end
    end
  rescue AiProviderCircuitBreakerService::CircuitBreakerOpenError => e
    {
      success: false,
      error: "Provider #{provider.name} is temporarily unavailable",
      status_code: 503,
      provider: provider.name,
      circuit_breaker_open: true
    }
  end

  def execute_code(code, language: "python", **options)
    model_name = default_model_for_capability("code_execution")
    raise ArgumentError, "No compatible model found" unless model_name

    case provider.slug
    when "replit"
      replit_execute_code(code, language, **options)
    else
      raise NotImplementedError, "Code execution not implemented for #{provider.name}"
    end
  end

  def stream_text(prompt, model: nil, **options, &block)
    model_name = model || default_model_for_capability("text_generation")
    raise ArgumentError, "No compatible model found" unless model_name
    raise ArgumentError, "Provider does not support streaming" unless provider.supports_streaming?

    case provider.slug
    when "openai"
      openai_stream_text(prompt, model_name, **options, &block)
    when "anthropic", "claude-ai-anthropic"
      anthropic_stream_text(prompt, model_name, **options, &block)
    when "ollama", "remote-ollama-server"
      ollama_stream_text(prompt, model_name, **options, &block)
    else
      raise NotImplementedError, "Streaming not implemented for #{provider.name}"
    end
  end

  # Send a chat message to the AI provider
  # @param messages [Array<Hash>] Array of message objects with role and content
  # @param options [Hash] Options including model, temperature, max_tokens, etc.
  # @return [Hash] Response with success status, response data, and metadata
  def send_message(messages, options = {})
    validate_message_format(messages)

    # Check circuit breaker state
    if circuit_breaker_open?
      return {
        success: false,
        error: "Circuit breaker is open - provider temporarily unavailable",
        error_type: "circuit_breaker_open",
        retry_after: calculate_circuit_breaker_timeout,
        circuit_breaker_state: "open"
      }
    end

    model_name = options[:model] || default_model_for_capability("text_generation")
    start_time = Time.current

    begin
      result = case provider.slug
      when "openai"
                 openai_send_message(messages, model_name, **options)
      when "anthropic", "claude-ai-anthropic"
                 anthropic_send_message(messages, model_name, **options)
      when "ollama", "remote-ollama-server"
                 ollama_send_message(messages, model_name, **options)
      else
                 raise NotImplementedError, "send_message not implemented for #{provider.name}"
      end

      response_time_ms = ((Time.current - start_time) * 1000).round
      track_usage(result[:response] || {}, response_time_ms, result[:success])

      if result[:success]
        @consecutive_failures = 0
        result.merge(
          metadata: {
            tokens_used: extract_token_count(result[:response]),
            response_time_ms: response_time_ms,
            model_used: model_name,
            stream_enabled: options[:stream] || false,
            parameters_used: options.except(:model)
          }
        )
      else
        @consecutive_failures += 1
        check_circuit_breaker_threshold
        result.merge(
          retry_after: extract_retry_after(result),
          retry_recommended: result[:error_type] == "server_error"
        )
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      response_time_ms = ((Time.current - start_time) * 1000).round
      @consecutive_failures += 1
      check_circuit_breaker_threshold
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
    rescue StandardError => e
      response_time_ms = ((Time.current - start_time) * 1000).round
      track_usage({}, response_time_ms, false)

      {
        success: false,
        error: "Request failed: #{e.message}",
        error_type: "unknown_error",
        retry_recommended: true
      }
    end
  end

  # Perform a health check on the AI provider
  # @return [Hash] Health status with metrics
  def health_check
    start_time = Time.current
    test_messages = [ { role: "user", content: "Hello" } ]

    begin
      result = send_message(test_messages, { model: default_model_for_capability("text_generation"), max_tokens: 5 })
      response_time = ((Time.current - start_time) * 1000).round

      {
        healthy: result[:success],
        response_time_ms: response_time,
        last_checked_at: Time.current.iso8601,
        error_rate: calculate_error_rate,
        circuit_breaker_state: circuit_breaker_state,
        last_error: result[:success] ? nil : result[:error]
      }
    rescue StandardError => e
      {
        healthy: false,
        response_time_ms: ((Time.current - start_time) * 1000).round,
        last_checked_at: Time.current.iso8601,
        error_rate: calculate_error_rate,
        circuit_breaker_state: circuit_breaker_state,
        last_error: e.message
      }
    end
  end

  private

  # Validate message format
  # @param messages [Array<Hash>] Messages to validate
  # @raise [ValidationError] if validation fails
  def validate_message_format(messages)
    raise ValidationError, "Messages must contain at least one message" if messages.nil? || messages.empty?

    messages.each_with_index do |msg, index|
      raise ValidationError, "Message at index #{index}: role is required" unless msg[:role] || msg["role"]
      raise ValidationError, "Message at index #{index}: content is required" unless msg[:content] || msg["content"]

      role = msg[:role] || msg["role"]
      unless VALID_ROLES.include?(role.to_s)
        raise ValidationError, "Message at index #{index}: Invalid role '#{role}'. Must be one of: #{VALID_ROLES.join(', ')}"
      end
    end
  end

  # Track usage metrics
  # @param response_data [Hash] Response data from the API
  # @param response_time_ms [Integer] Response time in milliseconds
  # @param success [Boolean] Whether the request was successful
  def track_usage(response_data, response_time_ms, success)
    @usage_metrics[:total_requests] += 1
    @usage_metrics[:failed_requests] += 1 unless success
    @usage_metrics[:total_response_time] += response_time_ms
    @usage_metrics[:avg_response_time] = @usage_metrics[:total_response_time].to_f / @usage_metrics[:total_requests]

    if success && response_data[:usage]
      usage = response_data[:usage]
      @usage_metrics[:total_tokens] += usage[:total_tokens] || usage["total_tokens"] || 0
      @usage_metrics[:prompt_tokens] += usage[:prompt_tokens] || usage["prompt_tokens"] || 0
      @usage_metrics[:completion_tokens] += usage[:completion_tokens] || usage["completion_tokens"] || 0
    end

    total = @usage_metrics[:total_requests]
    failed = @usage_metrics[:failed_requests]
    @usage_metrics[:success_rate] = total.positive? ? ((total - failed).to_f / total * 100) : 100.0
  end

  # Estimate the cost of a request
  # @param tokens_used [Hash] Hash with prompt_tokens and completion_tokens
  # @param model [String] Model name
  # @return [BigDecimal] Estimated cost in USD
  def estimate_cost(tokens_used, model)
    pricing = MODEL_PRICING[model] || { prompt: 0.001, completion: 0.002 }
    prompt_tokens = tokens_used[:prompt_tokens] || tokens_used["prompt_tokens"] || 0
    completion_tokens = tokens_used[:completion_tokens] || tokens_used["completion_tokens"] || 0

    prompt_cost = BigDecimal(prompt_tokens.to_s) / 1000 * BigDecimal(pricing[:prompt].to_s)
    completion_cost = BigDecimal(completion_tokens.to_s) / 1000 * BigDecimal(pricing[:completion].to_s)

    prompt_cost + completion_cost
  end

  # Calculate exponential backoff time
  # @return [Integer] Backoff time in seconds
  def calculate_backoff_time
    base_delay = 2
    max_delay = 120
    jitter = rand(0.5..1.5)

    delay = [ base_delay * (2 ** @consecutive_failures) * jitter, max_delay ].min
    delay.ceil
  end

  # Check if circuit breaker should be opened
  def check_circuit_breaker_threshold
    if @consecutive_failures >= CIRCUIT_BREAKER_THRESHOLD
      @circuit_breaker_opened_at = Time.current
    end
  end

  # Check if circuit breaker is open
  # @return [Boolean]
  def circuit_breaker_open?
    return false unless @circuit_breaker_opened_at

    # Auto-recover after timeout
    if Time.current - @circuit_breaker_opened_at > CIRCUIT_BREAKER_TIMEOUT
      @circuit_breaker_opened_at = nil
      @consecutive_failures = 0
      return false
    end

    true
  end

  # Get circuit breaker state
  # @return [String]
  def circuit_breaker_state
    circuit_breaker_open? ? "open" : "closed"
  end

  # Calculate remaining timeout for circuit breaker
  # @return [Integer]
  def calculate_circuit_breaker_timeout
    return 0 unless @circuit_breaker_opened_at

    remaining = CIRCUIT_BREAKER_TIMEOUT - (Time.current - @circuit_breaker_opened_at)
    [ remaining.ceil, 0 ].max
  end

  # Calculate error rate
  # @return [Float]
  def calculate_error_rate
    return 0.0 if @usage_metrics[:total_requests].zero?

    (@usage_metrics[:failed_requests].to_f / @usage_metrics[:total_requests] * 100).round(2)
  end

  # Extract token count from response
  # @param response [Hash]
  # @return [Integer]
  def extract_token_count(response)
    return 0 unless response.is_a?(Hash)

    usage = response[:usage] || response["usage"]
    return 0 unless usage

    usage[:total_tokens] || usage["total_tokens"] || 0
  end

  # Extract retry-after from response or calculate default
  # @param result [Hash]
  # @return [Integer]
  def extract_retry_after(result)
    result[:retry_after] || calculate_backoff_time
  end

  # OpenAI chat message implementation
  def openai_send_message(messages, model, **options)
    url = "/chat/completions"

    body = {
      model: model,
      messages: messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
      max_tokens: options[:max_tokens] || 2000,
      temperature: options[:temperature] || 0.7
    }

    # Add optional parameters
    body[:stream] = options[:stream] if options[:stream]
    body[:presence_penalty] = options[:presence_penalty] if options[:presence_penalty]
    body[:frequency_penalty] = options[:frequency_penalty] if options[:frequency_penalty]
    body[:functions] = options[:functions] if options[:functions]
    body[:function_call] = options[:function_call] if options[:function_call]

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_chat_response(response)
  end

  # Anthropic chat message implementation
  def anthropic_send_message(messages, model, **options)
    url = "/messages"

    # Separate system messages from other messages for Anthropic
    system_content = messages.select { |m| (m[:role] || m["role"]) == "system" }
                            .map { |m| m[:content] || m["content"] }
                            .join("\n")

    user_messages = messages.reject { |m| (m[:role] || m["role"]) == "system" }

    body = {
      model: model,
      messages: user_messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
      max_tokens: options[:max_tokens] || 2000
    }

    body[:system] = system_content if system_content.present?
    body[:temperature] = options[:temperature] if options[:temperature]

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_chat_response(response)
  end

  # Ollama chat message implementation
  def ollama_send_message(messages, model, **options)
    url = "/api/chat"

    body = {
      model: model,
      messages: messages.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } },
      stream: options[:stream] || false
    }

    # Ollama uses different base URI
    base_url = credentials_data["base_url"] || "http://localhost:11434"
    full_url = "#{base_url}#{url}"

    response = HTTParty.post(full_url, headers: @headers, body: body.to_json)
    handle_ollama_chat_response(response)
  end

  # Handle chat response from API
  def handle_chat_response(response)
    case response.code
    when 200, 201
      parsed = response.parsed_response
      {
        success: true,
        response: parsed.deep_symbolize_keys,
        status_code: response.code,
        provider: provider.name
      }
    when 401
      {
        success: false,
        error: "invalid_api_key",
        error_type: "authentication_error",
        status_code: response.code,
        provider: provider.name
      }
    when 429
      error_body = JSON.parse(response.body) rescue {}
      error_code = error_body.dig("error", "code") || "rate_limit_exceeded"
      error_type = error_code.include?("quota") ? "quota_exceeded" : "rate_limit"

      {
        success: false,
        error: error_code,
        error_type: error_type,
        status_code: response.code,
        provider: provider.name,
        retry_after: response.headers["Retry-After"]&.to_i || 60
      }
    when 500..599
      {
        success: false,
        error: "Server error",
        error_type: "server_error",
        status_code: response.code,
        provider: provider.name
      }
    else
      error_msg = response.parsed_response&.dig("error") || "Unknown error"
      {
        success: false,
        error: error_msg.is_a?(Hash) ? error_msg.to_json : error_msg.to_s,
        error_type: "api_error",
        status_code: response.code,
        provider: provider.name
      }
    end
  rescue JSON::ParserError
    {
      success: false,
      error: "Failed to parse response",
      error_type: "parse_error",
      status_code: response.code,
      provider: provider.name
    }
  end

  # Handle Ollama-specific chat response
  def handle_ollama_chat_response(response)
    if response.code == 200
      data = JSON.parse(response.body).deep_symbolize_keys
      {
        success: true,
        response: {
          choices: [
            {
              message: data[:message],
              finish_reason: "stop"
            }
          ],
          model: data[:model]
        },
        status_code: response.code,
        provider: provider.name
      }
    else
      handle_chat_response(response)
    end
  rescue JSON::ParserError
    {
      success: false,
      error: "Failed to parse Ollama response",
      error_type: "parse_error",
      status_code: response.code,
      provider: provider.name
    }
  end

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
    case provider.slug
    when "openai"
      @headers["Authorization"] = "Bearer #{credentials_data['api_key']}"
      @headers["OpenAI-Organization"] = credentials_data["organization"] if credentials_data["organization"]
    when "anthropic", "claude-ai-anthropic"
      @headers["x-api-key"] = credentials_data["api_key"]
      @headers["anthropic-version"] = "2023-06-01"
    when "stability-ai"
      @headers["Authorization"] = "Bearer #{credentials_data['api_key']}"
    when "replit"
      @headers["Authorization"] = "Bearer #{credentials_data['api_key']}"
    end
  end

  def default_model_for_capability(capability)
    compatible_models = provider.supported_models.select do |model|
      provider.capabilities.include?(capability)
    end
    compatible_models.first&.dig("id")
  end

  # OpenAI implementations
  def openai_generate_text(prompt, model, **options)
    url = "/chat/completions"

    body = {
      model: model,
      messages: [ { role: "user", content: prompt } ],
      max_tokens: options[:max_tokens] || 2000,
      temperature: options[:temperature] || 0.7
    }

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  def openai_stream_text(prompt, model, **options, &block)
    url = "/chat/completions"

    body = {
      model: model,
      messages: [ { role: "user", content: prompt } ],
      max_tokens: options[:max_tokens] || 2000,
      temperature: options[:temperature] || 0.7,
      stream: true
    }

    # Streaming implementation would require special handling
    # This is a simplified version
    response = self.class.post(url, headers: @headers, body: body.to_json)
    result = handle_response(response)
    block.call(result) if block
    result
  end

  def openai_generate_image(prompt, model, **options)
    url = "/images/generations"

    body = {
      model: model,
      prompt: prompt,
      n: options[:n] || 1,
      size: options[:size] || "1024x1024"
    }

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  # Anthropic implementations
  def anthropic_generate_text(prompt, model, **options)
    url = "/messages"

    body = {
      model: model,
      messages: [ { role: "user", content: prompt } ],
      max_tokens: options[:max_tokens] || 2000
    }

    # Add system prompt if provided
    body[:system] = options[:system_prompt] if options[:system_prompt].present?

    # Add temperature if provided
    body[:temperature] = options[:temperature] if options[:temperature]

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  def anthropic_stream_text(prompt, model, **options, &block)
    # Similar to OpenAI but with Anthropic's streaming format
    anthropic_generate_text(prompt, model, **options)
  end

  # Ollama implementations
  def ollama_generate_text(prompt, model, **options)
    url = "/api/generate"

    body = {
      model: model,
      prompt: prompt,
      stream: false
    }

    # Ollama uses different base URI
    base_url = credentials_data["base_url"] || "http://localhost:11434"
    full_url = "#{base_url}#{url}"

    response = HTTParty.post(full_url, headers: @headers, body: body.to_json)

    # Handle Ollama-specific response format
    if response.code == 200
      data = JSON.parse(response.body)
      content = data["response"] || "No response generated"

      {
        success: true,
        content: content,
        text: content, # For backward compatibility
        data: data,
        status_code: response.code,
        provider: provider.name,
        cost: 0, # Ollama is typically free/local
        metadata: {
          model: model,
          done: data["done"],
          total_duration: data["total_duration"],
          load_duration: data["load_duration"],
          prompt_eval_count: data["prompt_eval_count"],
          eval_count: data["eval_count"]
        }
      }
    else
      handle_response(response)
    end
  rescue StandardError => e
    {
      success: false,
      error: "Ollama request failed: #{e.message}",
      status_code: nil,
      provider: provider.name
    }
  end

  def ollama_stream_text(prompt, model, **options, &block)
    # Ollama streaming implementation
    ollama_generate_text(prompt, model, **options)
  end

  # Stability AI implementations
  def stability_generate_image(prompt, model, **options)
    url = "/generation/#{model}/text-to-image"

    body = {
      text_prompts: [ { text: prompt } ],
      cfg_scale: options[:cfg_scale] || 7,
      height: options[:height] || 1024,
      width: options[:width] || 1024,
      samples: options[:samples] || 1,
      steps: options[:steps] || 30
    }

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  # Replit implementations
  def replit_execute_code(code, language, **options)
    url = "/repls"

    body = {
      title: "Code Execution - #{Time.current.to_i}",
      language: language,
      files: {
        "main.py" => code  # Simplified - would need language-specific files
      },
      is_private: true
    }

    response = self.class.post(url, headers: @headers, body: body.to_json)
    handle_response(response)
  end

  def handle_response(response)
    case response.code
    when 200, 201
      {
        success: true,
        data: response.parsed_response,
        status_code: response.code,
        provider: provider.name
      }
    when 401
      {
        success: false,
        error: "Authentication failed - check API credentials",
        status_code: response.code,
        provider: provider.name
      }
    when 429
      {
        success: false,
        error: "Rate limit exceeded - please try again later",
        status_code: response.code,
        provider: provider.name
      }
    when 500..599
      {
        success: false,
        error: "Provider service error - please try again",
        status_code: response.code,
        provider: provider.name
      }
    else
      {
        success: false,
        error: response.parsed_response&.dig("error") || "Unknown error occurred",
        status_code: response.code,
        provider: provider.name
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: "Request failed: #{e.message}",
      status_code: nil,
      provider: provider.name
    }
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

  def process_batch_prompts(prompts, model_name, **options)
    case provider.slug
    when "openai"
      process_openai_batch(prompts, model_name, **options)
    when "anthropic", "claude-ai-anthropic"
      process_anthropic_batch(prompts, model_name, **options)
    else
      # Fallback: process each prompt individually
      prompts.map do |prompt|
        result = generate_text(prompt, model: model_name, **options)
        {
          prompt: prompt,
          result: result[:success] ? result[:text] : nil,
          success: result[:success],
          error: result[:error],
          cost: result[:cost] || 0
        }
      end
    end
  end

  def process_openai_batch(prompts, model_name, **options)
    # OpenAI doesn't have native batch API for chat completions yet
    # Process individually with rate limiting
    prompts.map.with_index do |prompt, index|
      # Add small delay between requests to avoid rate limits
      sleep(0.1) if index > 0

      result = openai_generate_text(prompt, model_name, **options)
      {
        prompt: prompt,
        result: result[:success] ? result[:text] : nil,
        success: result[:success],
        error: result[:error],
        cost: result[:cost] || 0
      }
    end
  end

  def process_anthropic_batch(prompts, model_name, **options)
    # Anthropic also processes individually for now
    prompts.map.with_index do |prompt, index|
      sleep(0.1) if index > 0

      result = anthropic_generate_text(prompt, model_name, **options)
      {
        prompt: prompt,
        result: result[:success] ? result[:text] : nil,
        success: result[:success],
        error: result[:error],
        cost: result[:cost] || 0
      }
    end
  end
end
