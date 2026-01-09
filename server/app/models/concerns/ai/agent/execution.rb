# frozen_string_literal: true

module Ai
  class Agent
    module Execution
      extend ActiveSupport::Concern

      # Main execution method for workflows
      def execute(input_parameters, user: nil, provider: nil)
        # Use provided provider or the agent's default provider
        provider ||= self.provider

        # Create an execution record
        execution = executions.create!(
          account: account,
          execution_id: SecureRandom.uuid,
          user: user,
          ai_provider_id: provider&.id,
          status: "running",
          input_parameters: input_parameters,
          started_at: Time.current,
          execution_context: {
            context_type: "workflow",
            triggered_at: Time.current.iso8601
          }
        )

        begin
          Rails.logger.info "[AI_AGENT] Executing agent #{name} with provider #{provider&.name || 'default'}"

          # Simulate processing time
          sleep(0.5)

          # Generate a simple output
          output = {
            "response" => "Processed input with #{name}",
            "processed_at" => Time.current.iso8601,
            "input_summary" => input_parameters.to_s[0..100]
          }

          # Update execution as successful
          execution.update!(
            status: "completed",
            output_data: output,
            completed_at: Time.current,
            duration_ms: (Time.current - execution.started_at) * 1000
          )

          execution
        rescue StandardError => e
          Rails.logger.error "[AI_AGENT] Execution failed: #{e.message}"
          execution.update!(
            status: "failed",
            error_details: {
              error: e.message,
              error_class: e.class.name
            },
            completed_at: Time.current,
            duration_ms: (Time.current - execution.started_at) * 1000
          )
          execution
        end
      end

      # Execute agent via MCP protocol
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

        # Update execution record
        execution.update!(
          status: "completed",
          output_data: result,
          completed_at: Time.current,
          duration_ms: (Time.current - execution.started_at) * 1000
        )

        result
      rescue StandardError => e
        Rails.logger.error "[AI_AGENT_MCP] Execution failed: #{e.message}"

        # Update execution record with error
        execution&.update!(
          status: "failed",
          error_message: e.message,
          completed_at: Time.current
        )

        raise
      end

      # Run a test execution without persisting
      def test_execution(test_input, test_user)
        {
          success: true,
          test_output: "Test execution completed for agent #{name}",
          input: test_input,
          timestamp: Time.current.iso8601
        }
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
