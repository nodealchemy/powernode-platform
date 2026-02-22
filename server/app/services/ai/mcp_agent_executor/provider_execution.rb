# frozen_string_literal: true

class Ai::McpAgentExecutor
  module ProviderExecution
    extend ActiveSupport::Concern

    private

    def execute_with_provider(provider_client, execution_context)
      @logger.info "[MCP_AGENT_EXECUTOR] Executing with provider #{@agent.provider.provider_type}"

      # Build prompt from context
      prompt = build_prompt_from_context(execution_context)

      # Get model configuration from mcp_metadata (primary) or mcp_tool_manifest (fallback)
      model_config = @agent.mcp_metadata&.dig("model_config") || {}
      model = model_config["model"] ||
              @agent.mcp_tool_manifest&.dig("model") ||
              @agent.provider.supported_models.first&.dig("id")
      max_tokens = execution_context.dig(:context, "max_tokens") ||
                   model_config["max_tokens"] ||
                   2000
      temperature = execution_context.dig(:context, "temperature") ||
                    model_config["temperature"] ||
                    0.7

      # System prompt: mcp_metadata is the primary source
      system_prompt = @agent.mcp_metadata&.dig("system_prompt") ||
                      @agent.mcp_tool_manifest&.dig("system_prompt")

      # Execute via provider client service
      # Note: generate_text expects prompt as positional argument
      result = provider_client.generate_text(
        prompt,
        model: model,
        max_tokens: max_tokens,
        temperature: temperature,
        system_prompt: system_prompt
      )

      @logger.debug "[MCP_AGENT_EXECUTOR] Provider response received: class=#{result.class.name} keys=#{result.keys.inspect} success=#{result[:success]}"

      # Check for provider errors before processing
      # Provider client returns either:
      # - Success: { success: true, data: { content: [...], usage: {...} } }
      # - Failure: { success: false, error: "message string", status_code: 404 }
      # - Failure: { success: false, error: { type: '...', message: '...' }, status_code: 404 }
      unless result[:success]
        # Handle both String and Hash error formats
        error_data = result[:error]
        if error_data.is_a?(Hash)
          error_message = error_data["message"] || error_data[:message] || "Unknown provider error"
          error_type = error_data["type"] || error_data[:type] || "unknown_error"
        else
          error_message = error_data.to_s.presence || "Unknown provider error"
          error_type = "provider_error"
        end
        status_code = result[:status_code] || 500

        @logger.error "[MCP_AGENT_EXECUTOR] Provider error: #{error_message} (#{error_type}, status: #{status_code})"
        @logger.error "[MCP_AGENT_EXECUTOR] Full error response: #{result.inspect}"

        # Raise appropriate error based on error type
        case error_type.to_s
        when "not_found_error", "invalid_request_error"
          raise ValidationError, "Provider rejected request: #{error_message}"
        when "authentication_error", "permission_denied_error"
          raise ProviderError, "Provider authentication failed: #{error_message}"
        when "rate_limit_error"
          raise ProviderError, "Provider rate limit exceeded: #{error_message}"
        when "overloaded_error", "server_error"
          raise ProviderError, "Provider temporarily unavailable: #{error_message}"
        else
          raise ProviderError, "Provider error (#{error_type}): #{error_message}"
        end
      end

      # Provider client returns { success: true, data: { content: [...], usage: {...} } }
      # Extract the actual response data - ensure it's a Hash
      raw_data = result[:data] || result["data"]
      response_data = raw_data.is_a?(Hash) ? raw_data : {}

      @logger.debug "[MCP_AGENT_EXECUTOR] Extracted response_data: class=#{response_data.class.name} keys=#{response_data.keys.inspect}"

      # For Anthropic, content is an array of content blocks
      content_text = if response_data["content"].is_a?(Array)
                       @logger.debug "[MCP_AGENT_EXECUTOR] Content is array with #{response_data['content'].length} blocks"
                       response_data["content"].map { |block| block.is_a?(Hash) ? block["text"] : block.to_s }.join
      elsif response_data.dig("choices", 0, "message", "content").present?
                       @logger.debug "[MCP_AGENT_EXECUTOR] Content from OpenAI/Grok choices format"
                       response_data.dig("choices", 0, "message", "content")
      elsif raw_data.is_a?(String)
                       @logger.debug "[MCP_AGENT_EXECUTOR] Raw data is a string, using directly"
                       raw_data
      else
                       @logger.debug "[MCP_AGENT_EXECUTOR] Content is not array, trying alternate extraction"
                       response_data["content"] || response_data["text"] || result[:content] || result[:text]
      end

      @logger.debug "[MCP_AGENT_EXECUTOR] Extracted content: present=#{content_text.present?} length=#{content_text&.length}"

      # Log warning if no output was extracted
      if content_text.nil?
        @logger.warn "[MCP_AGENT_EXECUTOR] No output extracted from provider response"
        @logger.warn "[MCP_AGENT_EXECUTOR] Full result structure: #{result.inspect}"
      end

      final_result = {
        "output" => content_text,
        "metadata" => {
          "tokens_used" => response_data.dig("usage", "total_tokens") ||
            (response_data.dig("usage", "input_tokens").to_i + response_data.dig("usage", "output_tokens").to_i).then { |t| t > 0 ? t : nil } ||
            (response_data["prompt_eval_count"].to_i + response_data["eval_count"].to_i).then { |t| t > 0 ? t : nil } ||
            0,
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round,
          "model_used" => model,
          "provider" => @agent.provider.provider_type
        }
      }

      @logger.debug "[MCP_AGENT_EXECUTOR] Final result: output_present=#{final_result['output'].present?} model=#{model}"

      final_result
    end

    def execute_with_openai(client, context)
      prompt = build_prompt_from_context(context)

      response = client.completions(
        parameters: {
          model: @agent.provider.model_name || "gpt-3.5-turbo",
          messages: [ { role: "user", content: prompt } ],
          temperature: context[:temperature] || 0.7,
          max_tokens: context[:max_tokens] || 1000
        }
      )

      # Ensure response is a Hash before using dig
      response = {} unless response.is_a?(Hash)

      {
        "output" => response.dig("choices", 0, "message", "content"),
        "metadata" => {
          "tokens_used" => response.dig("usage", "total_tokens"),
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round,
          "model_used" => response["model"],
          "provider" => "openai"
        }
      }
    end

    def execute_with_anthropic(client, context)
      prompt = build_prompt_from_context(context)

      response = client.messages(
        parameters: {
          model: @agent.provider.model_name || "claude-3-sonnet-20240229",
          messages: [ { role: "user", content: prompt } ],
          temperature: context[:temperature] || 0.7,
          max_tokens: context[:max_tokens] || 1000
        }
      )

      # Ensure response is a Hash before using dig
      response = {} unless response.is_a?(Hash)

      {
        "output" => response.dig("content", 0, "text"),
        "metadata" => {
          "tokens_used" => response.dig("usage", "output_tokens")&.to_i || 0,
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round.to_f,
          "model_used" => response["model"],
          "provider" => "anthropic"
        }
      }
    end

    def execute_with_ollama(client, context)
      prompt = build_prompt_from_context(context)

      response = client.generate(
        model: @agent.provider.model_name || "llama2",
        prompt: prompt,
        options: {
          temperature: context[:temperature] || 0.7,
          num_predict: context[:max_tokens] || 1000
        }
      )

      # Ensure response is a Hash before using dig
      response = {} unless response.is_a?(Hash)

      {
        "output" => response["response"],
        "metadata" => {
          "tokens_used" => (response.dig("prompt_eval_count").to_i + response.dig("eval_count").to_i),
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round.to_f,
          "model_used" => response["model"],
          "provider" => "ollama"
        }
      }
    end

    def execute_with_custom_provider(client, context)
      # Custom provider execution logic
      prompt = build_prompt_from_context(context)

      # Call custom provider API
      response = client.call_custom_endpoint(
        prompt: prompt,
        parameters: context[:provider_params] || {}
      )

      # Format response according to custom provider format
      {
        "output" => response["generated_text"] || response["output"],
        "metadata" => {
          "tokens_used" => (response["token_count"] || 0).to_i,
          "processing_time_ms" => ((Time.current - @start_time) * 1000).round.to_f,
          "model_used" => response["model_name"] || "custom",
          "provider" => "custom"
        }
      }
    end
  end
end
