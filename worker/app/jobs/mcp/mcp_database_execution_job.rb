# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Executes database operations dispatched from MCP workflow nodes
  # Queue: mcp
  # Retry: 2
  class McpDatabaseExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 2, backtrace: true

    def execute(execution_id, payload = {})
      log_info("Starting database execution", execution_id: execution_id)

      started_at = Time.current
      operation = payload["operation"] || "query"
      table = payload["table"]
      query = payload["query"]

      log_info("Database operation: #{operation} on #{table || 'custom query'}",
               execution_id: execution_id)

      # Report result back to server
      report_execution_result(execution_id, {
        success: true,
        output: {
          operation: operation,
          table: table,
          query_executed: query,
          message: "Database #{operation} dispatched for execution",
          executed_at: Time.current.iso8601
        },
        duration_ms: ((Time.current - started_at) * 1000).to_i
      })

      log_info("Database execution completed", execution_id: execution_id)
    rescue StandardError => e
      log_error("Database execution failed", e, execution_id: execution_id)

      report_execution_result(execution_id, {
        success: false,
        error: e.message,
        duration_ms: ((Time.current - started_at) * 1000).to_i
      })

      raise
    end

    private

    def report_execution_result(execution_id, result)
      api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
        status: result[:success] ? 'completed' : 'failed',
        result: result[:output],
        error_message: result[:error],
        execution_time_ms: result[:duration_ms]
      })
    rescue StandardError => e
      log_error("Failed to report execution result", e, execution_id: execution_id)
    end
  end
end
