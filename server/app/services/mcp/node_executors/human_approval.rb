# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Human_approval node executor - stub implementation
    class HumanApproval < Base
      protected

      def perform_execution
        log_info "Executing human_approval node (stub)"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Pending approval",
          result: {
            approved: false,
            approval_status: 'pending'
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'human_approval',
            executed_at: Time.current.iso8601,
            implementation_status: 'stub'
          }
        }
      end
    end
  end
end
