# frozen_string_literal: true

# AI MCP Agent Executor - Executes AI agents via MCP protocol
# Handles tool invocation, parameter validation, and response formatting
class Ai::McpAgentExecutor
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ProviderExecution
  include ValidationAndGuardrails
  include ContextAndFormatting
  include MemoryWriteback
  include SecurityGateIntegration

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

  # Execute agent with MCP protocol
  def execute(input_parameters)
    # Normalize to string keys — callers may pass symbol keys (Agent#execute)
    # while internal code expects string keys (JSON-style)
    input_parameters = input_parameters.stringify_keys if input_parameters.respond_to?(:stringify_keys)

    @logger.info "[MCP_AGENT_EXECUTOR] Starting execution for agent #{@agent.id}"

    # Validate input parameters against agent's input schema
    validate_input_parameters!(input_parameters)

    # Run pre-execution security gate (OWASP security stack)
    input_text = input_parameters["input"].to_s
    security_block = run_pre_execution_security_gate(input_text, input_parameters)
    return security_block if security_block

    # Run guardrail input check (non-security rails)
    guardrail_result = run_input_guardrails(input_text)
    if guardrail_result[:blocked]
      return format_guardrail_block(guardrail_result, stage: :input)
    end

    # Get AI provider client
    provider_client = get_provider_client

    # Prepare execution context
    execution_context = build_execution_context(input_parameters)

    # Execute agent via provider
    begin
      result = execute_with_provider(provider_client, execution_context)

      # Run post-execution security gate (PII redaction + output safety)
      output_text = result["output"].to_s
      post_gate = run_post_execution_security_gate(output_text)
      if post_gate.is_a?(Hash)
        if post_gate.key?("error")
          return post_gate # Output blocked by security gate
        elsif post_gate[:redacted_text]
          result["output"] = post_gate[:redacted_text]
        end
      end

      # Run guardrail output check (non-security rails)
      output_guardrail = run_output_guardrails(result["output"].to_s, input_text: input_text)
      if output_guardrail[:blocked]
        return format_guardrail_block(output_guardrail, stage: :output)
      end

      # Validate output against agent's output schema
      validate_output!(result)

      # Post-execution memory write-back (non-blocking)
      write_back_to_memory(execution_context, result)

      # Record security telemetry (fire-and-forget)
      record_security_telemetry(result)

      # Format MCP-compliant response
      format_mcp_response(result)

    rescue Timeout::Error => e
      handle_timeout_error(e)
    rescue StandardError => e
      handle_execution_error(e)
    end
  end

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
