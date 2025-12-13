# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module Broadcasting
      # Broadcast node execution update
      #
      # @param node [AiWorkflowNode] Node
      # @param status [String] Execution status
      # @param data [Hash] Additional data
      def broadcast_node_execution(node, status, data = {})
        # Get the node execution record to use the channel's proper broadcast method
        node_execution = @workflow_run.ai_workflow_node_executions
                                      .find_by(node_id: node.node_id)

        if node_execution
          # Use the channel's class method which sets the correct 'event' field
          # and broadcasts to all appropriate streams (run, workflow, account)
          AiOrchestrationChannel.broadcast_node_execution(
            node_execution,
            "workflow.node.execution.updated"
          )
        else
          log_warn "Node execution not found for broadcast", {
            node_id: node.node_id,
            node_name: node.name
          }
        end
      rescue StandardError => e
        log_error "Failed to broadcast node execution", {
          node_id: node.node_id,
          error: e.message
        }
      end
    end
  end
end
