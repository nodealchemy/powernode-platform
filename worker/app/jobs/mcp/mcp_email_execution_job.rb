# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Executes email delivery dispatched from MCP workflow nodes
  # Delegates to server's notification/email endpoint
  # Queue: mcp
  # Retry: 3
  class McpEmailExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(execution_id, payload = {})
      log_info("Starting email execution", execution_id: execution_id)

      started_at = Time.current
      to = payload["to"]
      subject = payload["subject"]

      raise ArgumentError, "to is required" if to.blank?
      raise ArgumentError, "subject is required" if subject.blank?

      log_info("Sending email to: #{Array(to).join(', ')}", execution_id: execution_id)

      # Delegate to server's email/notification endpoint
      response = api_client.post("/api/v1/internal/notifications/send", {
        type: "email",
        to: to,
        cc: payload["cc"],
        bcc: payload["bcc"],
        from: payload["from"],
        subject: subject,
        body_html: payload["body_html"],
        body_text: payload["body_text"],
        template_id: payload["template_id"],
        template_data: payload["template_data"],
        attachments: payload["attachments"]
      })

      message_id = response.dig("data", "message_id") || "msg_#{SecureRandom.hex(8)}"

      report_execution_result(execution_id, {
        success: true,
        output: {
          message_id: message_id,
          status: "sent",
          recipients_count: Array(to).length,
          sent_at: Time.current.iso8601
        },
        duration_ms: ((Time.current - started_at) * 1000).to_i
      })

      log_info("Email execution completed", execution_id: execution_id)
    rescue StandardError => e
      log_error("Email execution failed", e, execution_id: execution_id)

      report_execution_result(execution_id, {
        success: false,
        error: e.message,
        duration_ms: ((Time.current - (started_at || Time.current)) * 1000).to_i
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
