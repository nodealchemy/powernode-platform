# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Start node executor - workflow entry point
    class Start < Base
      protected

      def perform_execution
        log_info "Starting workflow execution"

        # Start nodes pass through input variables to execution context
        workflow_input = input_data || {}

        log_debug "Workflow input: #{workflow_input.keys.join(', ')}"

        # Set input variables in execution context for downstream nodes
        workflow_input.each do |key, value|
          set_variable(key, value)
        end

        # Industry-standard output format (v1.0)
        # See: docs/platform/WORKFLOW_IO_STANDARD.md
        workflow_run = @node_context.workflow_run

        {
          output: {
            workflow_id: workflow_run.workflow_id,
            run_id: workflow_run.run_id,
            triggered_at: Time.current.iso8601
          },
          data: {
            input_variables: workflow_input
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "start",
            executed_at: Time.current.iso8601,
            trigger_type: configuration["start_type"] || "manual"
          }
        }
      end
    end
  end
end
