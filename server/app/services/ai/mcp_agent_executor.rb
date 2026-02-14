# frozen_string_literal: true

# AI MCP Agent Executor - Executes AI agents via MCP protocol
# Handles tool invocation, parameter validation, and response formatting
class Ai::McpAgentExecutor
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ProviderExecution
  include ValidationAndGuardrails
  include ContextAndFormatting

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
    @logger.info "[MCP_AGENT_EXECUTOR] Starting execution for agent #{@agent.id}"

    # Validate input parameters against agent's input schema
    validate_input_parameters!(input_parameters)

    # Run guardrail input check
    input_text = input_parameters["input"].to_s
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

      # Run guardrail output check
      output_text = result["output"].to_s
      output_guardrail = run_output_guardrails(output_text, input_text: input_text)
      if output_guardrail[:blocked]
        return format_guardrail_block(output_guardrail, stage: :output)
      end

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
