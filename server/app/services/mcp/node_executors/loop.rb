# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Loop node executor - stub implementation
    class Loop < Base
      protected

      def perform_execution
        log_info "Executing loop node (stub)"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: [],
          result: {
            iterations_completed: 0,
            loop_status: 'not_implemented'
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'loop',
            executed_at: Time.current.iso8601,
            implementation_status: 'stub'
          }
        }
      end
    end
  end
end
