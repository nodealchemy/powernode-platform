# frozen_string_literal: true

class Ai::McpAgentExecutor
  module ValidationAndGuardrails
    extend ActiveSupport::Concern

    private

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

    def run_input_guardrails(text)
      guardrail_pipeline.check_input(text: text)
    rescue StandardError => e
      @logger.warn "[MCP_AGENT_EXECUTOR] Input guardrail check failed: #{e.message}"
      { allowed: true, violations: [], blocked: false }
    end

    def run_output_guardrails(text, input_text: nil)
      guardrail_pipeline.check_output(text: text, input_text: input_text)
    rescue StandardError => e
      @logger.warn "[MCP_AGENT_EXECUTOR] Output guardrail check failed: #{e.message}"
      { allowed: true, violations: [], blocked: false }
    end

    def guardrail_pipeline
      @guardrail_pipeline ||= Ai::Guardrails::Pipeline.new(account: @account, agent: @agent)
    end

    def format_guardrail_block(result, stage:)
      {
        "error" => {
          "code" => -32600,
          "message" => "Blocked by #{stage} guardrail: #{result[:violations]&.first&.dig(:message) || 'policy violation'}",
          "type" => "GuardrailViolation",
          "timestamp" => Time.current.iso8601,
          "violations" => result[:violations]
        },
        "tool_id" => @agent.mcp_tool_id,
        "execution_id" => @execution&.execution_id || SecureRandom.uuid
      }
    end
  end
end
