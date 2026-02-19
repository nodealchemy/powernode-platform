# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Delay node executor - dispatches a delayed workflow resume to worker
    #
    # Configuration:
    # - delay_seconds: Number of seconds to wait before resuming
    #
    class Delay < Base
      include Concerns::WorkerDispatch

      protected

      def perform_execution
        log_info "Executing delay node"

        delay_seconds = (configuration["delay_seconds"] || 0).to_i

        if delay_seconds <= 0
          log_info "No delay configured, continuing immediately"
          return {
            output: "Delay completed (0 seconds)",
            result: { delayed_seconds: 0 },
            metadata: {
              node_id: @node.node_id,
              node_type: "delay",
              executed_at: Time.current.iso8601
            }
          }
        end

        workflow_run = @orchestrator&.workflow_run
        payload = {
          workflow_run_id: workflow_run&.id,
          node_id: @node.node_id,
          delay_seconds: delay_seconds,
          resume_at: (Time.current + delay_seconds.seconds).iso8601
        }

        log_info "Dispatching delay: #{delay_seconds}s"

        dispatch_to_worker("Mcp::McpWorkflowResumeJob", payload)
      end
    end
  end
end
