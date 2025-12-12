# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Split node executor - stub implementation
    class Split < Base
      protected

      def perform_execution
        log_info "Executing split node (stub)"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: [],
          result: {
            branches_created: 0,
            split_status: "not_implemented"
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "split",
            executed_at: Time.current.iso8601,
            implementation_status: "stub"
          }
        }
      end
    end
  end
end
