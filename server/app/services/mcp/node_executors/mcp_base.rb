# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Base class for MCP server-related node executors
    # Provides shared functionality for mcp_tool, mcp_resource, mcp_prompt nodes
    class McpBase < Base
      protected

      # Get the MCP server from configuration
      def mcp_server
        @mcp_server ||= find_mcp_server
      end

      # Get the MCP tool from configuration
      def mcp_tool
        @mcp_tool ||= find_mcp_tool
      end

      # Validate user permissions for MCP tool execution
      def validate_mcp_permissions!
        return unless mcp_tool

        validator = McpPermissionValidator.new(
          tool: mcp_tool,
          user: @orchestrator.user,
          account: @orchestrator.account
        )

        unless validator.authorized?
          result = validator.authorization_result
          error_messages = result[:errors]&.map { |e| e[:message] }&.join("; ") || "Permission denied"
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP permission denied: #{error_messages}"
        end
      end

      # Build MCP parameters from configuration and workflow variables
      def build_mcp_parameters
        # Start with static parameters
        parameters = (configuration["parameters"] || {}).deep_dup

        # Apply parameter mappings from workflow variables
        parameter_mappings = configuration["parameter_mappings"] || []
        parameter_mappings.each do |mapping|
          param_name = mapping["parameter_name"]
          mapping_type = mapping["mapping_type"]

          value = case mapping_type
          when "static"
                    mapping["static_value"]
          when "variable"
                    get_variable(mapping["variable_path"])
          when "expression"
                    evaluate_expression(mapping["expression"])
          else
                    nil
          end

          parameters[param_name] = value if value.present?
        end

        # Render any template values in parameters
        render_parameters(parameters)
      end

      # Render template expressions in parameters
      def render_parameters(params)
        case params
        when Hash
          params.transform_values { |v| render_parameters(v) }
        when Array
          params.map { |v| render_parameters(v) }
        when String
          render_template(params)
        else
          params
        end
      end

      # Render template with variable substitution
      def render_template(template)
        return template unless template.is_a?(String)

        template.gsub(/\{\{(\w+(?:\.\w+)*)\}\}/) do |match|
          variable_path = $1
          value = resolve_variable_path(variable_path)
          value.present? ? value.to_s : match
        end
      end

      # Resolve a variable path like "node_output.result.data"
      def resolve_variable_path(path)
        parts = path.split(".")
        value = get_variable(parts.first)

        parts[1..].each do |part|
          break unless value.respond_to?(:[])

          value = value[part] || value[part.to_sym]
        end

        value
      end

      # Evaluate a simple expression
      def evaluate_expression(expression)
        # For now, just treat expressions as templates
        render_template(expression)
      end

      # Execute MCP tool synchronously
      def execute_sync(server, tool, parameters)
        service = McpSyncExecutionService.new(
          server: server,
          tool: tool,
          parameters: parameters,
          user: @orchestrator.user,
          account: @orchestrator.account
        )
        service.execute
      end

      # Execute MCP tool asynchronously via worker
      def execute_async(server, tool, parameters)
        # Create execution record
        execution = create_tool_execution_record(tool, parameters)

        # Enqueue worker job
        WorkerJobService.enqueue_mcp_tool_execution(execution.id)

        # Return pending result
        {
          pending: true,
          execution_id: execution.id,
          message: "MCP tool execution queued"
        }
      end

      # Create McpToolExecution record for tracking
      def create_tool_execution_record(tool, parameters)
        McpToolExecution.create!(
          mcp_tool: tool,
          user: @orchestrator.user,
          status: "pending",
          parameters: parameters
        )
      end

      # Wait for async execution to complete
      def wait_for_execution(execution_id, timeout_seconds = nil)
        timeout = timeout_seconds || configuration["timeout_seconds"] || 300
        deadline = Time.current + timeout
        execution = McpToolExecution.find(execution_id)

        while Time.current < deadline
          execution.reload

          case execution.status
          when "completed"
            return {
              success: true,
              output: execution.result,
              execution_time_ms: execution.execution_time_ms
            }
          when "failed"
            return {
              success: false,
              error: execution.error_message
            }
          when "cancelled"
            return {
              success: false,
              error: "Execution cancelled"
            }
          else
            sleep(0.5) # Poll interval
          end
        end

        {
          success: false,
          error: "MCP execution timed out after #{timeout} seconds"
        }
      end

      # Check if execution should be async
      def should_execute_async?
        configuration["execution_mode"] == "async"
      end

      # Transform MCP result to standard node output format
      def transform_mcp_result(mcp_result, extra_data = {})
        {
          output: mcp_result[:output] || mcp_result[:result],
          data: {
            mcp_server_id: mcp_server&.id,
            mcp_server_name: mcp_server&.name,
            raw_result: mcp_result
          }.merge(extra_data),
          result: mcp_result[:output] || mcp_result[:result],
          metadata: {
            node_id: @node.node_id,
            node_type: @node.node_type,
            executed_at: Time.current.iso8601,
            mcp_execution_time_ms: mcp_result[:execution_time_ms],
            async_execution: mcp_result[:async] || false
          }
        }
      end

      # Store output variable if configured
      def store_output_variable(output)
        if configuration["output_variable"].present?
          set_variable(configuration["output_variable"], output)
        end
      end

      private

      def find_mcp_server
        server_id = configuration["mcp_server_id"] || configuration["server_id"]
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "No mcp_server_id configured" unless server_id

        server = @orchestrator.account.mcp_servers.find_by(id: server_id)
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "MCP server not found: #{server_id}" unless server

        unless server.connected?
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "MCP server not connected: #{server.name} (status: #{server.status})"
        end

        server
      end

      def find_mcp_tool
        tool_id = configuration["mcp_tool_id"] || configuration["tool_id"]
        tool_name = configuration["mcp_tool_name"] || configuration["tool_name"]

        if tool_id.present?
          mcp_server.mcp_tools.find_by(id: tool_id)
        elsif tool_name.present?
          mcp_server.mcp_tools.find_by(name: tool_name)
        else
          nil
        end
      end
    end
  end
end
