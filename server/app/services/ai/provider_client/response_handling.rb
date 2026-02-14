# frozen_string_literal: true

class Ai::ProviderClientService
  module ResponseHandling
    extend ActiveSupport::Concern

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
      success ? @consecutive_failures = 0 : @consecutive_failures += 1
      @usage_metrics[:avg_response_time] = @usage_metrics[:total_response_time].to_f / @usage_metrics[:total_requests]

      if success && response_data[:usage]
        normalized = extract_usage(response_data)
        @usage_metrics[:total_tokens] += normalized[:total_tokens]
        @usage_metrics[:prompt_tokens] += normalized[:prompt_tokens]
        @usage_metrics[:completion_tokens] += normalized[:completion_tokens]
      end

      total = @usage_metrics[:total_requests]
      failed = @usage_metrics[:failed_requests]
      @usage_metrics[:success_rate] = total.positive? ? ((total - failed).to_f / total * 100) : 100.0
    end

    # Estimate the cost of a request using DB-stored pricing from provider's supported_models
    # @param tokens_used [Hash] Hash with prompt_tokens, completion_tokens, and optional cached_tokens
    # @param model [String] Model name
    # @return [BigDecimal] Estimated cost in USD
    def estimate_cost(tokens_used, model)
      pricing = lookup_model_pricing(model) || DEFAULT_PRICING
      prompt_tokens = tokens_used[:prompt_tokens] || tokens_used["prompt_tokens"] || 0
      completion_tokens = tokens_used[:completion_tokens] || tokens_used["completion_tokens"] || 0
      cached_tokens = tokens_used[:cached_tokens] || tokens_used["cached_tokens"] || 0

      (BigDecimal(prompt_tokens.to_s) / 1000 * BigDecimal(pricing[:prompt].to_s)) +
        (BigDecimal(completion_tokens.to_s) / 1000 * BigDecimal(pricing[:completion].to_s)) +
        (BigDecimal(cached_tokens.to_s) / 1000 * BigDecimal((pricing[:cached] || 0).to_s))
    end

    # Look up model pricing, delegating to the authoritative ProviderManagementService
    def lookup_model_pricing(model_name)
      mgmt_pricing = Ai::ProviderManagementService.model_pricing_for(model_name)
      if mgmt_pricing
        return {
          prompt: mgmt_pricing["input"].to_f,
          completion: mgmt_pricing["output"].to_f,
          cached: mgmt_pricing["cached_input"].to_f
        }
      end

      # Fallback to provider's supported_models JSONB column
      return nil unless provider&.supported_models.is_a?(Array)

      model_info = provider.get_model_info(model_name)
      cost = model_info&.dig("cost_per_1k_tokens")
      return nil unless cost.is_a?(Hash)

      { prompt: cost["input"].to_f, completion: cost["output"].to_f, cached: (cost["cached_input"] || 0).to_f }
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

    # Calculate error rate
    # @return [Float]
    def calculate_error_rate
      return 0.0 if @usage_metrics[:total_requests].zero?

      (@usage_metrics[:failed_requests].to_f / @usage_metrics[:total_requests] * 100).round(2)
    end

    # Extract normalized usage data from provider response
    # Handles OpenAI (prompt_tokens/completion_tokens), Anthropic (input_tokens/output_tokens),
    # and Ollama (prompt_eval_count/eval_count) response formats
    # @param response [Hash]
    # @return [Hash] { prompt_tokens:, completion_tokens:, total_tokens: }
    def extract_usage(response)
      empty = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      return empty unless response.is_a?(Hash)

      usage = response[:usage] || response["usage"]
      return empty unless usage

      prompt = usage[:prompt_tokens] || usage["prompt_tokens"] ||
               usage[:input_tokens] || usage["input_tokens"] || 0
      completion = usage[:completion_tokens] || usage["completion_tokens"] ||
                   usage[:output_tokens] || usage["output_tokens"] || 0
      total = usage[:total_tokens] || usage["total_tokens"] || (prompt + completion)

      { prompt_tokens: prompt, completion_tokens: completion, total_tokens: total }
    end

    # Extract retry-after from response or calculate default
    # @param result [Hash]
    # @return [Integer]
    def extract_retry_after(result)
      result[:retry_after] || calculate_backoff_time
    end

    # Return a graceful error when a capability is not supported by the provider
    def capability_not_supported(capability)
      Rails.logger.info("[AI::ProviderClient] #{capability} not supported by provider #{provider.name} (#{provider.provider_type})")
      {
        success: false,
        error: "#{capability} is not supported by provider #{provider.name}",
        error_type: "capability_not_supported",
        capability: capability,
        provider: provider.name,
        provider_type: provider.provider_type
      }
    end

    # Handle chat response from API
    def handle_chat_response(response)
      case response.code
      when 200, 201
        parsed = response.parsed_response
        unless parsed.is_a?(Hash)
          return {
            success: false,
            error: "Malformed response from provider",
            error_type: "parse_error",
            status_code: response.code,
            provider: provider.name
          }
        end
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
        # Safely extract error message - parsed_response could be String, Hash, or nil
        parsed = response.parsed_response
        error_msg = if parsed.is_a?(Hash)
                      parsed.dig("error") || parsed["message"] || "Unknown error"
                    elsif parsed.is_a?(String)
                      parsed
                    else
                      "Unknown error"
                    end
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

    # Handle generic response from API
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
        # Safely extract error message - parsed_response could be String, Hash, or nil
        parsed = response.parsed_response
        error_msg = if parsed.is_a?(Hash)
                      parsed.dig("error") || parsed["message"] || "Unknown error occurred"
                    elsif parsed.is_a?(String)
                      parsed
                    else
                      "Unknown error occurred"
                    end
        {
          success: false,
          error: error_msg.is_a?(Hash) ? error_msg.to_json : error_msg.to_s,
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

    # Batch prompt processing dispatcher
    def process_batch_prompts(prompts, model_name, **options)
      case provider.provider_type
      when "openai"
        process_openai_batch(prompts, model_name, **options)
      when "anthropic"
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
  end
end
