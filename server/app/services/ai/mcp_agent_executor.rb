# frozen_string_literal: true

# AI MCP Agent Executor - Executes AI agents via MCP protocol
# Handles tool invocation, parameter validation, and response formatting
class Ai::McpAgentExecutor
  include ActiveModel::Model
  include ActiveModel::Attributes

  class ExecutionError < StandardError; end
  class ValidationError < ExecutionError; end
  class ProviderError < ExecutionError; end
  class TimeoutError < ExecutionError; end

  attr_accessor :agent, :execution, :account

  def initialize(agent:, execution: nil, account: nil)
    @agent = agent
    @execution = execution
    @account = account || agent.account
    @logger = Rails.logger
    @start_time = Time.current
  end

  # =============================================================================
  # MAIN EXECUTION METHOD
  # =============================================================================

  # Execute agent with MCP protocol
  def execute(input_parameters)
    @logger.info "[MCP_AGENT_EXECUTOR] Starting execution for agent #{@agent.id}"

    # Validate input parameters against agent's input schema
    validate_input_parameters!(input_parameters)

    # Get AI provider client
    provider_client = get_provider_client

    # Prepare execution context
    execution_context = build_execution_context(input_parameters)

    # Execute agent via provider
    begin
      result = execute_with_provider(provider_client, execution_context)

      # Validate output against agent's output schema
      validate_output!(result)

      # Format MCP-compliant response
      format_mcp_response(result)

    rescue Timeout::Error => e
      handle_timeout_error(e)
    rescue StandardError => e
      handle_execution_error(e)
    end
  end

  # =============================================================================
  # PROVIDER EXECUTION
  # =============================================================================

  private

  def execute_with_provider(provider_client, execution_context)
    @logger.info "[MCP_AGENT_EXECUTOR] Executing with provider #{@agent.provider.provider_type}"

    # Build prompt from context
    prompt = build_prompt_from_context(execution_context)

    # Get model configuration
    model = @agent.mcp_tool_manifest["model"] || @agent.provider.supported_models.first&.dig("id")
    max_tokens = execution_context.dig(:context, "max_tokens") || @agent.mcp_tool_manifest["max_tokens"] || 2000
    temperature = execution_context.dig(:context, "temperature") || @agent.mcp_tool_manifest["temperature"] || 0.7

    # Execute via provider client service
    # Note: generate_text expects prompt as positional argument
    result = provider_client.generate_text(
      prompt,
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      system_prompt: @agent.mcp_tool_manifest["system_prompt"]
    )

    # 🔍 DIAGNOSTIC: Log the raw provider response
    @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Provider response received:"
    @logger.info "[MCP_AGENT_EXECUTOR]    Result class: #{result.class.name}"
    @logger.info "[MCP_AGENT_EXECUTOR]    Result keys: #{result.keys.inspect}"
    @logger.info "[MCP_AGENT_EXECUTOR]    Result[:success]: #{result[:success]}"
    @logger.info "[MCP_AGENT_EXECUTOR]    Result[:data].present?: #{result[:data].present?}"
    @logger.info "[MCP_AGENT_EXECUTOR]    Result preview: #{result.inspect[0..300]}"

    # ✅ FIX: Check for provider errors before processing
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

      @logger.error "[MCP_AGENT_EXECUTOR] ❌ Provider error: #{error_message} (#{error_type}, status: #{status_code})"
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

    # 🔍 DIAGNOSTIC: Log the extracted response_data
    @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Extracted response_data:"
    @logger.info "[MCP_AGENT_EXECUTOR]    response_data class: #{response_data.class.name}"
    @logger.info "[MCP_AGENT_EXECUTOR]    response_data keys: #{response_data.keys.inspect}"
    @logger.info "[MCP_AGENT_EXECUTOR]    response_data['content'].present?: #{response_data['content'].present?}"
    @logger.info "[MCP_AGENT_EXECUTOR]    response_data['content'] class: #{response_data['content'].class.name if response_data['content']}"

    # For Anthropic, content is an array of content blocks
    content_text = if response_data["content"].is_a?(Array)
                     @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Content is array with #{response_data['content'].length} blocks"
                     response_data["content"].map { |block| block.is_a?(Hash) ? block["text"] : block.to_s }.join
    elsif raw_data.is_a?(String)
                     # Handle case where provider returned a raw string
                     @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Raw data is a string, using directly"
                     raw_data
    else
                     @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Content is not array, trying alternate extraction"
                     response_data["content"] || response_data["text"] || result[:content] || result[:text]
    end

    # 🔍 DIAGNOSTIC: Log the extracted content
    @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Extracted content_text:"
    @logger.info "[MCP_AGENT_EXECUTOR]    content_text.present?: #{content_text.present?}"
    @logger.info "[MCP_AGENT_EXECUTOR]    content_text class: #{content_text.class.name if content_text}"
    @logger.info "[MCP_AGENT_EXECUTOR]    content_text length: #{content_text&.length}"
    @logger.info "[MCP_AGENT_EXECUTOR]    content_text preview: #{content_text&.[](0..100)}"

    # Log warning if no output was extracted
    if content_text.nil?
      @logger.warn "[MCP_AGENT_EXECUTOR] ⚠️  No output extracted from provider response"
      @logger.warn "[MCP_AGENT_EXECUTOR] Full result structure: #{result.inspect}"
    end

    final_result = {
      "output" => content_text,
      "metadata" => {
        "tokens_used" => response_data.dig("usage", "total_tokens") || response_data[:tokens_used] || result[:tokens_used],
        "processing_time_ms" => ((Time.current - @start_time) * 1000).round,
        "model_used" => model,
        "provider" => @agent.provider.provider_type
      }
    }

    # 🔍 DIAGNOSTIC: Log the final formatted result
    @logger.info "[MCP_AGENT_EXECUTOR] 🔍 Final formatted result:"
    @logger.info "[MCP_AGENT_EXECUTOR]    output present: #{final_result['output'].present?}"
    @logger.info "[MCP_AGENT_EXECUTOR]    output preview: #{final_result['output']&.[](0..100)}"

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

  # =============================================================================
  # CONTEXT AND PROMPT BUILDING
  # =============================================================================

  def build_execution_context(input_parameters)
    base_context = {
      agent_id: @agent.id,
      agent_name: @agent.name,
      agent_type: @agent.agent_type,
      account_id: @account.id,
      execution_id: @execution&.execution_id || SecureRandom.uuid,
      input: input_parameters["input"],
      started_at: @start_time
    }

    # Merge context from input parameters
    if input_parameters["context"].is_a?(Hash)
      base_context.merge!(input_parameters["context"].symbolize_keys)
    end

    # Add agent-specific configuration
    agent_config = @agent.mcp_tool_manifest["configuration"] || {}
    base_context.merge!(agent_config.symbolize_keys)

    base_context
  end

  def build_prompt_from_context(context)
    base_prompt = context[:input]

    # NOTE: system_prompt is passed separately via API parameter (line 82)
    # DO NOT duplicate it in the user message

    # Add conversation history if available for multi-turn context
    if context[:conversation_history].is_a?(Array) && context[:conversation_history].any?
      history_text = context[:conversation_history].map do |msg|
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        "[#{role.upcase}]: #{content}"
      end.join("\n\n")

      base_prompt = "Previous conversation:\n#{history_text}\n\n[USER]: #{base_prompt}"
    end

    # Add context information if available
    if context[:additional_context].present?
      base_prompt += "\n\nAdditional Context: #{context[:additional_context]}"
    end

    # Agent role/behavior is already defined in system_prompt
    # No need to add role-based prefixes here

    base_prompt
  end

  # =============================================================================
  # VALIDATION METHODS
  # =============================================================================

  def validate_input_parameters!(input_parameters)
    @logger.debug "[MCP_AGENT_EXECUTOR] Validating input parameters"

    # Validate against agent's input schema
    schema = @agent.mcp_input_schema
    validator = JsonSchemaValidator.new(schema)

    unless validator.valid?(input_parameters)
      error_details = validator.detailed_errors.map { |e| "#{e[:path]}: #{e[:message]}" }.join(", ")
      raise ValidationError, "Input validation failed: #{error_details}"
    end

    # Additional business logic validations
    validate_input_size!(input_parameters)
    validate_rate_limits!
  end

  def validate_output!(result)
    @logger.debug "[MCP_AGENT_EXECUTOR] Validating output"

    # Validate against agent's output schema
    schema = @agent.mcp_output_schema
    validator = JsonSchemaValidator.new(schema)

    unless validator.valid?(result)
      @logger.warn "[MCP_AGENT_EXECUTOR] Output validation failed: #{validator.errors}"
      # Don't fail execution for output validation errors, just log them
    end
  end

  def validate_input_size!(input_parameters)
    input_text = input_parameters["input"].to_s
    max_size = 100_000 # 100KB limit

    if input_text.bytesize > max_size
      raise ValidationError, "Input size (#{input_text.bytesize} bytes) exceeds maximum (#{max_size} bytes)"
    end
  end

  def validate_rate_limits!
    # Check rate limits for the account/user
    recent_executions = @account.ai_agent_executions
                               .where("created_at >= ?", 1.hour.ago)
                               .count

    hourly_limit = @account.subscription&.plan&.features&.dig("ai_executions_per_hour") || 100

    if recent_executions >= hourly_limit
      raise ValidationError, "Rate limit exceeded: #{recent_executions}/#{hourly_limit} executions this hour"
    end
  end

  # =============================================================================
  # PROVIDER CLIENT MANAGEMENT
  # =============================================================================

  def get_provider_client
    @logger.debug "[MCP_AGENT_EXECUTOR] Getting provider client"

    provider = @agent.provider

    unless provider&.is_active?
      raise ProviderError, "AI provider is not active"
    end

    # Get active credential for this provider
    credential = provider.provider_credentials
                        .where(account: @account)
                        .active
                        .first

    unless credential
      raise ProviderError, "No active credentials found for provider: #{provider.name}"
    end

    # Use Ai::ProviderClientService for provider communication
    Ai::ProviderClientService.new(credential)
  rescue StandardError => e
    raise ProviderError, "Failed to initialize provider client: #{e.message}"
  end

  # =============================================================================
  # RESPONSE FORMATTING
  # =============================================================================

  def format_mcp_response(result)
    @logger.debug "[MCP_AGENT_EXECUTOR] Formatting MCP response"

    # Ensure response follows MCP tool response format
    mcp_response = {
      "result" => result,
      "tool_id" => @agent.mcp_tool_id,
      "execution_id" => @execution&.execution_id || SecureRandom.uuid,
      "timestamp" => Time.current.iso8601,
      "agent_info" => {
        "agent_id" => @agent.id,
        "agent_name" => @agent.name,
        "agent_version" => @agent.version
      }
    }

    # Add telemetry data
    mcp_response["telemetry"] = {
      "execution_time_ms" => ((Time.current - @start_time) * 1000).round,
      "tokens_used" => result.dig("metadata", "tokens_used") || 0,
      "provider_used" => @agent.provider.provider_type
    }

    mcp_response
  end

  # =============================================================================
  # ERROR HANDLING
  # =============================================================================

  def handle_execution_error(error)
    @logger.error "[MCP_AGENT_EXECUTOR] Execution error: #{error.message}"
    @logger.error error.backtrace.join("\n") if error.backtrace

    # Update execution record if available
    if @execution
      @execution.update!(
        status: "failed",
        error_message: error.message,
        completed_at: Time.current
      )
    end

    # Return MCP error response
    {
      "error" => {
        "code" => map_error_code(error),
        "message" => error.message,
        "type" => error.class.name,
        "timestamp" => Time.current.iso8601
      },
      "tool_id" => @agent.mcp_tool_id,
      "execution_id" => @execution&.execution_id || SecureRandom.uuid
    }
  end

  def handle_timeout_error(error)
    @logger.error "[MCP_AGENT_EXECUTOR] Timeout error: #{error.message}"

    # Update execution record if available
    if @execution
      @execution.update!(
        status: "timeout",
        error_message: "Execution timed out",
        completed_at: Time.current
      )
    end

    {
      "error" => {
        "code" => -32603, # Internal error
        "message" => "Execution timed out",
        "type" => "TimeoutError",
        "timestamp" => Time.current.iso8601
      },
      "tool_id" => @agent.mcp_tool_id,
      "execution_id" => @execution&.execution_id || SecureRandom.uuid
    }
  end

  def map_error_code(error)
    case error
    when ValidationError
      -32602 # Invalid params
    when ProviderError
      -32603 # Internal error
    when TimeoutError
      -32603 # Internal error
    else
      -32603 # Internal error
    end
  end

  # =============================================================================
  # UTILITY CLASSES FOR PROVIDER CLIENTS
  # =============================================================================

  # Simple Ollama client wrapper
  class OllamaClient
    def initialize(base_url)
      @base_url = base_url
      @http_client = Net::HTTP
    end

    def generate(model:, prompt:, options: {})
      uri = URI("#{@base_url}/api/generate")

      request_body = {
        model: model,
        prompt: prompt,
        stream: false,
        options: options
      }

      response = @http_client.post(uri, request_body.to_json, {
        "Content-Type" => "application/json"
      })

      JSON.parse(response.body)
    rescue StandardError => e
      raise ProviderError, "Ollama API error: #{e.message}"
    end
  end

  # Custom provider client wrapper
  class CustomProviderClient
    def initialize(credentials)
      @credentials = credentials
      @base_url = credentials["base_url"]
      @api_key = credentials["api_key"]
    end

    def call_custom_endpoint(prompt:, parameters: {})
      uri = URI("#{@base_url}/generate")

      request_body = {
        prompt: prompt,
        parameters: parameters
      }

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      }

      response = Net::HTTP.post(uri, request_body.to_json, headers)
      JSON.parse(response.body)
    rescue StandardError => e
      raise ProviderError, "Custom provider API error: #{e.message}"
    end
  end
end
