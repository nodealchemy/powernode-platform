# frozen_string_literal: true

class Ai::McpAgentExecutor
  module ContextAndFormatting
    extend ActiveSupport::Concern

    private

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
  end
end
