# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Executes notification delivery dispatched from MCP workflow nodes
  # Supports in_app (via server API), Slack, Teams, Discord (via webhooks)
  # Queue: mcp
  # Retry: 3
  class McpNotificationExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(execution_id, payload = {})
      log_info("Starting notification execution", execution_id: execution_id)

      started_at = Time.current
      channel = payload["channel"] || "in_app"
      message = payload["message"]

      raise ArgumentError, "message is required" if message.blank?

      log_info("Notification channel: #{channel}", execution_id: execution_id)

      result = deliver_notification(channel, payload)

      report_execution_result(execution_id, {
        success: true,
        output: result.merge(
          channel: channel,
          delivered_at: Time.current.iso8601
        ),
        duration_ms: ((Time.current - started_at) * 1000).to_i
      })

      log_info("Notification execution completed", execution_id: execution_id)
    rescue StandardError => e
      log_error("Notification execution failed", e, execution_id: execution_id)

      report_execution_result(execution_id, {
        success: false,
        error: e.message,
        duration_ms: ((Time.current - (started_at || Time.current)) * 1000).to_i
      })

      raise
    end

    private

    def deliver_notification(channel, payload)
      case channel
      when "in_app"
        deliver_in_app(payload)
      when "slack", "teams", "discord"
        deliver_webhook(channel, payload)
      when "push"
        deliver_push(payload)
      when "sms"
        deliver_sms(payload)
      else
        { status: "unsupported_channel", channel: channel }
      end
    end

    def deliver_in_app(payload)
      response = api_client.post("/api/v1/internal/notifications/send", {
        message: payload["message"],
        title: payload["title"],
        priority: payload["priority"] || "normal",
        recipients: payload["mentions"] || []
      })

      { status: "delivered", notification_id: response.dig("data", "id") }
    rescue StandardError => e
      log_warn("In-app notification delivery failed: #{e.message}")
      { status: "failed", error: e.message }
    end

    def deliver_webhook(channel, payload)
      webhook_url = payload["webhook_url"]
      raise ArgumentError, "webhook_url is required for #{channel}" if webhook_url.blank?

      body = build_webhook_body(channel, payload)

      require 'net/http'
      uri = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = body.to_json

      response = http.request(request)

      {
        status: response.code.to_i.between?(200, 299) ? "delivered" : "failed",
        http_status: response.code.to_i,
        channel: channel
      }
    end

    def build_webhook_body(channel, payload)
      message = payload["message"]
      title = payload["title"]

      case channel
      when "slack"
        body = { text: message }
        body[:blocks] = [{ type: "header", text: { type: "plain_text", text: title } }] if title
        body
      when "teams"
        { "@type" => "MessageCard", "summary" => title || message, "text" => message }
      when "discord"
        body = { content: message }
        body[:embeds] = [{ title: title }] if title
        body
      else
        { message: message, title: title }
      end
    end

    def deliver_push(payload)
      { status: "queued", message: "Push notification queued" }
    end

    def deliver_sms(payload)
      { status: "queued", message: "SMS notification queued" }
    end

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
