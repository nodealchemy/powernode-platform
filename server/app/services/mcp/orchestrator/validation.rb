# frozen_string_literal: true

module Mcp
  module Orchestrator
    module Validation
      def validate_workflow!
        @logger.info "[MCP_ORCHESTRATOR] Validating workflow structure"

        unless @workflow.can_execute?
          raise Mcp::AiWorkflowOrchestrator::WorkflowExecutionError, "Workflow cannot be executed in current state: #{@workflow.status}"
        end

        unless @workflow.has_valid_structure?
          raise Mcp::AiWorkflowOrchestrator::WorkflowExecutionError, "Workflow structure is invalid"
        end

        start_nodes = find_start_nodes
        if start_nodes.empty?
          raise Mcp::AiWorkflowOrchestrator::WorkflowExecutionError, "No start nodes found in workflow"
        end

        @event_store.record_event(
          event_type: "workflow.validation.completed",
          event_data: {
            start_nodes_count: start_nodes.count,
            total_nodes: @workflow.node_count,
            total_edges: @workflow.edge_count
          }
        )
      end

      def validate_mcp_requirements!
        @logger.info "[MCP_ORCHESTRATOR] Validating MCP tool requirements"

        mcp_config = @workflow.mcp_orchestration_config || {}
        tool_requirements = mcp_config["tool_requirements"] || []

        tool_requirements.each do |requirement|
          tool_id = requirement["tool_id"]
          min_version = requirement["min_version"]

          tool_manifest = @mcp_registry.get_tool(tool_id)
          unless tool_manifest
            raise Mcp::AiWorkflowOrchestrator::WorkflowExecutionError, "Required MCP tool not found: #{tool_id}"
          end

          if min_version.present?
            tool_version = Gem::Version.new(tool_manifest["version"])
            required_version = Gem::Version.new(min_version)

            unless tool_version >= required_version
              raise Mcp::AiWorkflowOrchestrator::WorkflowExecutionError,
                    "Tool #{tool_id} version #{tool_manifest['version']} is below required #{min_version}"
            end
          end
        end

        @event_store.record_event(
          event_type: "workflow.mcp_validation.completed",
          event_data: {
            tools_validated: tool_requirements.count
          }
        )
      end
    end
  end
end
