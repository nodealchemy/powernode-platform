# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # MCP Tool node executor - invokes tools from MCP servers
    class McpTool < McpBase
      protected

      def perform_execution
        tool_name = configuration['mcp_tool_name'] || configuration['tool_name']
        log_info "Executing MCP Tool: #{tool_name}"

        # Validate server and tool exist
        server = mcp_server
        tool = mcp_tool

        unless tool
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP tool not found. Please configure mcp_tool_id or mcp_tool_name"
        end

        # Validate permissions
        validate_mcp_permissions!

        # Build parameters from configuration and workflow variables
        parameters = build_mcp_parameters

        # Validate parameters against tool schema
        if tool.input_schema.present?
          validation = tool.validate_parameters(parameters)
          unless validation[:valid]
            errors = validation[:errors]&.join(', ') || 'Invalid parameters'
            raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                  "Invalid parameters for tool '#{tool.name}': #{errors}"
          end
        end

        log_debug "MCP Tool parameters: #{parameters.inspect}"

        # Execute based on mode (sync or async)
        if should_execute_async?
          handle_async_execution(server, tool, parameters)
        else
          handle_sync_execution(server, tool, parameters)
        end
      end

      private

      def handle_sync_execution(server, tool, parameters)
        result = execute_sync(server, tool, parameters)

        if result[:success]
          # Store output in workflow variable if configured
          store_output_variable(result[:output])

          transform_mcp_result(result, {
            mcp_tool_id: tool.id,
            mcp_tool_name: tool.name,
            execution_mode: 'sync'
          })
        else
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP tool execution failed: #{result[:error]}"
        end
      end

      def handle_async_execution(server, tool, parameters)
        # Create execution record and queue job
        pending_result = execute_async(server, tool, parameters)

        # Wait for execution to complete
        execution_id = pending_result[:execution_id]
        timeout = configuration['timeout_seconds'] || 300

        log_info "Waiting for async execution #{execution_id} (timeout: #{timeout}s)"

        result = wait_for_execution(execution_id, timeout)

        if result[:success]
          store_output_variable(result[:output])

          transform_mcp_result(result.merge(async: true), {
            mcp_tool_id: tool.id,
            mcp_tool_name: tool.name,
            execution_id: execution_id,
            execution_mode: 'async'
          })
        else
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP tool async execution failed: #{result[:error]}"
        end
      end
    end
  end
end
