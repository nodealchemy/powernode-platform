# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Base class for all MCP node executors
    #
    # Provides common execution infrastructure for all node types including:
    # - Timing and cost tracking
    # - Error handling and retries
    # - Input/output data management
    # - Context propagation
    #
    class Base
      attr_reader :node, :node_execution, :node_context, :orchestrator

      def initialize(node:, node_execution:, node_context:, orchestrator:)
        @node = node
        @node_execution = node_execution
        @node_context = node_context
        @orchestrator = orchestrator
        @logger = Rails.logger
      end

      # Main execution method - must be implemented by subclasses
      def execute
        start_time = Time.current

        begin
          # Execute node-specific logic
          result = perform_execution

          # Calculate execution time
          execution_time_ms = ((Time.current - start_time) * 1000).round

          # Return standardized result (v1.0 format)
          # The result from perform_execution already contains: output, data, result, metadata
          # We add success flag (unless already explicitly set to false) and execution metadata
          result.merge(
            success: result[:success] != false,  # Preserve explicit false
            execution_time_ms: execution_time_ms
          )

        rescue StandardError => e
          execution_time_ms = ((Time.current - start_time) * 1000).round

          @logger.error "[NODE_EXECUTOR] #{node.node_type} execution failed: #{e.message}"

          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "#{node.node_type} execution failed: #{e.message}"
        end
      end

      protected

      # Subclasses must implement this method
      def perform_execution
        raise NotImplementedError, "#{self.class} must implement perform_execution"
      end

      # Get input data for this node
      def input_data
        @node_context.input_data
      end

      # Get variables from execution context
      # FIX: Use node context scoped variables instead of orchestrator global variables
      # This ensures template rendering can access auto-wired predecessor outputs
      def get_variable(name)
        @node_context.get_variable(name)
      end

      # Set variables in execution context
      def set_variable(name, value)
        @orchestrator.set_variable(name, value)
      end

      # Get previous node results
      def previous_results
        @node_context.previous_results
      end

      # Get node configuration
      def configuration
        @node.configuration || {}
      end

      # Log execution info
      def log_info(message)
        @logger.info "[#{node.node_type.upcase}_EXECUTOR] #{message}"
      end

      # Log execution debug
      def log_debug(message)
        @logger.debug "[#{node.node_type.upcase}_EXECUTOR] #{message}"
      end

      # Log execution error
      def log_error(message)
        @logger.error "[#{node.node_type.upcase}_EXECUTOR] #{message}"
      end
    end
  end
end
