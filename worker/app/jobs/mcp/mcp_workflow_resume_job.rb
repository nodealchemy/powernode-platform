# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Resumes a paused workflow after delay/schedule expiration
  # Called by delay and scheduler node executors
  # Queue: mcp
  # Retry: 3
  class McpWorkflowResumeJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(execution_id, payload = {})
      log_info("Starting workflow resume", execution_id: execution_id)

      workflow_run_id = payload["workflow_run_id"]
      node_id = payload["node_id"]
      delay_seconds = (payload["delay_seconds"] || 0).to_i

      raise ArgumentError, "workflow_run_id is required" if workflow_run_id.blank?

      # If there's a delay, re-enqueue with delay
      if delay_seconds > 0
        log_info("Scheduling resume in #{delay_seconds}s",
                 execution_id: execution_id,
                 workflow_run_id: workflow_run_id)

        # Re-enqueue this job with the delay removed (it will fire at the right time)
        self.class.perform_in(
          delay_seconds,
          execution_id,
          payload.merge("delay_seconds" => 0, "_resumed" => true).deep_stringify_keys
        )

        return
      end

      # Resume the workflow via server API
      log_info("Resuming workflow",
               execution_id: execution_id,
               workflow_run_id: workflow_run_id,
               node_id: node_id)

      api_client.post("/api/v1/internal/ai/workflow_runs/#{workflow_run_id}/resume", {
        node_id: node_id,
        execution_id: execution_id,
        resumed_at: Time.current.iso8601
      })

      # Update execution status
      report_execution_result(execution_id, {
        success: true,
        output: {
          workflow_run_id: workflow_run_id,
          node_id: node_id,
          resumed_at: Time.current.iso8601,
          status: "resumed"
        }
      })

      log_info("Workflow resume completed",
               execution_id: execution_id,
               workflow_run_id: workflow_run_id)
    rescue StandardError => e
      log_error("Workflow resume failed", e,
                execution_id: execution_id,
                workflow_run_id: payload&.dig("workflow_run_id"))

      report_execution_result(execution_id, {
        success: false,
        error: e.message
      })

      raise
    end

    private

    def report_execution_result(execution_id, result)
      api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
        status: result[:success] ? 'completed' : 'failed',
        result: result[:output],
        error_message: result[:error]
      })
    rescue StandardError => e
      log_error("Failed to report execution result", e, execution_id: execution_id)
    end
  end
end
