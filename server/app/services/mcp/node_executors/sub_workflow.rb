# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Sub_workflow node executor - stub implementation
    class SubWorkflow < Base
      protected

      def perform_execution
        log_info "Executing sub_workflow node (stub)"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: {},
          result: {
            sub_workflow_completed: false,
            sub_workflow_id: nil
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'sub_workflow',
            executed_at: Time.current.iso8601,
            implementation_status: 'stub'
          }
        }
      end
    end
  end
end
