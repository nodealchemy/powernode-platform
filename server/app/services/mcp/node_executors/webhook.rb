# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Webhook node executor - stub implementation
    class Webhook < Base
      protected

      def perform_execution
        log_info "Executing webhook node (stub)"

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: {
            status: "pending",
            webhook_id: nil
          },
          result: {
            delivered: false,
            response_code: nil
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "webhook",
            executed_at: Time.current.iso8601,
            implementation_status: "stub"
          }
        }
      end
    end
  end
end
