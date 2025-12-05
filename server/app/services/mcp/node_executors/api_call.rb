# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # API Call node executor - makes HTTP API calls
    class ApiCall < Base
      protected

      def perform_execution
        log_info "Making API call"

        # Stub implementation - will be fully implemented in future phase
        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        {
          output: {
            status: 200,
            body: {}
          },
          data: {
            headers: {},
            response_time_ms: 0
          },
          metadata: {
            node_id: @node.node_id,
            node_type: 'api_call',
            executed_at: Time.current.iso8601,
            implementation_status: 'stub'
          }
        }
      end
    end
  end
end
