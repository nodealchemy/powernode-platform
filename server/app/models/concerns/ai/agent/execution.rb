# frozen_string_literal: true

module Ai
  class Agent
    module Execution
      extend ActiveSupport::Concern

      # Main execution method - calls AI provider via MCP protocol
      def execute(input_parameters, user: nil, provider: nil)
        # Guard: prevent execution if agent is not active
        unless status == "active"
          raise StandardError, "Agent '#{name}' is not active (status: #{status}). Cannot execute."
        end

        # Use provided provider or the agent's default provider
        effective_provider = provider || self.provider

        # Create an execution record
        execution = executions.create!(
          account: account,
          execution_id: SecureRandom.uuid,
          user: user,
          ai_provider_id: effective_provider&.id,
          status: "running",
          input_parameters: input_parameters,
          started_at: Time.current,
          execution_context: {
            context_type: "workflow",
            triggered_at: Time.current.iso8601
          }
        )

        begin
          Rails.logger.info "[AI_AGENT] Executing agent #{name} with provider #{effective_provider&.name || 'default'}"

          # Execute via MCP protocol to get real AI response
          executor = Ai::McpAgentExecutor.new(
            agent: self,
            execution: execution,
            account: account
          )

          result = executor.execute(input_parameters)

          # Extract output from MCP result format
          output = if result["error"]
                     {
                       "error" => result["error"]["message"],
                       "error_type" => result["error"]["type"],
                       "processed_at" => Time.current.iso8601
                     }
          else
                     {
                       "response" => result.dig("result", "output"),
                       "metadata" => result.dig("result", "metadata"),
                       "telemetry" => result["telemetry"],
                       "processed_at" => Time.current.iso8601
                     }
          end

          # Update execution as successful (or failed if there was an error)
          final_status = result["error"] ? "failed" : "completed"
          execution.update!(
            status: final_status,
            output_data: output,
            error_message: result.dig("error", "message"),
            completed_at: Time.current,
            duration_ms: ((Time.current - execution.started_at) * 1000).round,
            tokens_used: result.dig("telemetry", "tokens_used") || 0
          )

          execution
        rescue StandardError => e
          Rails.logger.error "[AI_AGENT] Execution failed: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")

          execution.update!(
            status: "failed",
            error_message: e.message,
            error_details: {
              error: e.message,
              error_class: e.class.name
            },
            completed_at: Time.current,
            duration_ms: ((Time.current - execution.started_at) * 1000).round
          )
          execution
        end
      end

      # Execute agent via MCP protocol (returns raw MCP result)
      def execute_via_mcp(input_parameters, execution_options = {})
        Rails.logger.info "[AI_AGENT_MCP] Executing agent #{id} via MCP"

        # Validate that agent is available
        raise StandardError, "Agent not available for MCP execution" unless mcp_available?

        # Create execution record
        execution = create_mcp_execution(input_parameters, execution_options)

        # Delegate to AI MCP agent executor
        executor = Ai::McpAgentExecutor.new(
          agent: self,
          execution: execution,
          account: account
        )

        result = executor.execute(input_parameters)

        # Determine status based on result
        has_error = result["error"].present?
        final_status = has_error ? "failed" : "completed"

        # Update execution record
        execution.update!(
          status: final_status,
          output_data: result,
          error_message: result.dig("error", "message"),
          completed_at: Time.current,
          duration_ms: ((Time.current - execution.started_at) * 1000).round,
          tokens_used: result.dig("telemetry", "tokens_used") || 0
        )

        result
      rescue StandardError => e
        Rails.logger.error "[AI_AGENT_MCP] Execution failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        # Update execution record with error (use update_columns to skip validations)
        if execution&.persisted?
          execution.update_columns(
            status: "failed",
            error_message: e.message.truncate(1000),
            completed_at: Time.current
          )
        end

        raise
      end

      # Run a test execution without persisting - actually calls the AI
      def test_execution(test_input, test_user)
        return { success: false, error: "Agent not available" } unless mcp_available?

        begin
          executor = Ai::McpAgentExecutor.new(
            agent: self,
            execution: nil,
            account: account
          )

          # Use a simple test prompt
          test_params = test_input.is_a?(Hash) ? test_input : { "input" => test_input.to_s }
          result = executor.execute(test_params)

          if result["error"]
            {
              success: false,
              error: result["error"]["message"],
              error_type: result["error"]["type"],
              timestamp: Time.current.iso8601
            }
          else
            {
              success: true,
              test_output: result.dig("result", "output"),
              model_used: result.dig("result", "metadata", "model_used"),
              processing_time_ms: result.dig("telemetry", "execution_time_ms"),
              input: test_input,
              timestamp: Time.current.iso8601
            }
          end
        rescue StandardError => e
          {
            success: false,
            error: e.message,
            error_class: e.class.name,
            timestamp: Time.current.iso8601
          }
        end
      end

      private

      # Create MCP execution record
      def create_mcp_execution(input_parameters, execution_options)
        executions.create!(
          account: account,
          user: execution_options[:user] || creator,
          provider: provider,
          input_parameters: input_parameters,
          status: "running",
          execution_id: SecureRandom.uuid,
          started_at: Time.current,
          execution_context: {
            "mcp_execution" => true,
            "tool_id" => mcp_tool_id,
            "connection_id" => execution_options[:connection_id],
            "protocol_version" => "2025-06-18",
            "execution_options" => execution_options.except(:user, :connection_id)
          }
        )
      end
    end
  end
end
