# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Delay node executor - stub implementation
    class Delay < Base
      protected

      def perform_execution
        log_info "Executing delay node (stub)"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: "Delay completed",
          result: {
            delayed_seconds: configuration["delay_seconds"] || 0
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "delay",
            executed_at: Time.current.iso8601,
            implementation_status: "stub"
          }
        }
      end
    end
  end
end
