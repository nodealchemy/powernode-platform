# frozen_string_literal: true

# AlertingService
# Provides multi-channel alerting for critical system events
# Supports: Slack, Email, Webhook (PagerDuty, etc.)
class AlertingService
  class AlertError < StandardError; end

  # Alert severity levels
  SEVERITY_LEVELS = {
    info: 0,
    warning: 1,
    error: 2,
    critical: 3
  }.freeze

  # Alert channels
  CHANNELS = %w[slack email webhook].freeze

  def initialize(options = {})
    @options = options
    @config = load_config
  end

  # =============================================================================
  # PUBLIC API
  # =============================================================================

  # Send an alert to configured channels
  # @param title [String] Alert title
  # @param message [String] Alert message
  # @param severity [Symbol] :info, :warning, :error, :critical
  # @param context [Hash] Additional context data
  # @param channels [Array<String>] Override default channels
  def send_alert(title:, message:, severity: :error, context: {}, channels: nil)
    return unless alerting_enabled?

    channels_to_use = channels || determine_channels(severity)
    results = {}

    channels_to_use.each do |channel|
      results[channel] = send_to_channel(channel, title, message, severity, context)
    end

    log_alert_sent(title, severity, channels_to_use, results)
    results
  rescue StandardError => e
    Rails.logger.error("AlertingService error: #{e.message}")
    { error: e.message }
  end

  # Convenience methods for different severity levels
  def info(title, message, context = {})
    send_alert(title: title, message: message, severity: :info, context: context)
  end

  def warning(title, message, context = {})
    send_alert(title: title, message: message, severity: :warning, context: context)
  end

  def error(title, message, context = {})
    send_alert(title: title, message: message, severity: :error, context: context)
  end

  def critical(title, message, context = {})
    send_alert(title: title, message: message, severity: :critical, context: context)
  end

  # =============================================================================
  # AI/WORKFLOW ERROR ALERTS
  # =============================================================================

  # Alert for AI execution errors
  def ai_execution_error(error, operation, context = {})
    send_alert(
      title: "AI Execution Error: #{operation}",
      message: error.message,
      severity: :error,
      context: {
        operation: operation,
        error_class: error.class.name,
        backtrace: error.backtrace&.first(5)
      }.merge(context)
    )
  end

  # Alert for workflow failures
  def workflow_failure(workflow_id, run_id, error, context = {})
    send_alert(
      title: "Workflow Execution Failed",
      message: error.is_a?(String) ? error : error.message,
      severity: :error,
      context: {
        workflow_id: workflow_id,
        run_id: run_id,
        error_class: error.is_a?(String) ? nil : error.class.name
      }.merge(context)
    )
  end

  # Alert for provider failures
  def provider_failure(provider_name, error, context = {})
    send_alert(
      title: "AI Provider Failure: #{provider_name}",
      message: error.is_a?(String) ? error : error.message,
      severity: :warning,
      context: {
        provider: provider_name
      }.merge(context)
    )
  end

  # Alert for critical system errors
  def system_critical(title, error, context = {})
    send_alert(
      title: "CRITICAL: #{title}",
      message: error.is_a?(String) ? error : error.message,
      severity: :critical,
      context: context
    )
  end

  # =============================================================================
  # PRIVATE HELPERS
  # =============================================================================

  private

  def alerting_enabled?
    @config[:enabled] != false
  end

  def load_config
    {
      enabled: ENV["ALERTING_ENABLED"] != "false",
      slack_webhook_url: ENV["SLACK_WEBHOOK_URL"],
      slack_channel: ENV["SLACK_ALERT_CHANNEL"] || "#alerts",
      alert_email: ENV["ALERT_EMAIL"],
      webhook_url: ENV["ALERT_WEBHOOK_URL"],
      webhook_auth_token: ENV["ALERT_WEBHOOK_TOKEN"],
      min_severity_slack: (ENV["MIN_SEVERITY_SLACK"] || "warning").to_sym,
      min_severity_email: (ENV["MIN_SEVERITY_EMAIL"] || "error").to_sym,
      min_severity_webhook: (ENV["MIN_SEVERITY_WEBHOOK"] || "critical").to_sym
    }
  end

  def determine_channels(severity)
    channels = []
    severity_level = SEVERITY_LEVELS[severity] || 0

    if @config[:slack_webhook_url] && severity_level >= SEVERITY_LEVELS[@config[:min_severity_slack]]
      channels << "slack"
    end

    if @config[:alert_email] && severity_level >= SEVERITY_LEVELS[@config[:min_severity_email]]
      channels << "email"
    end

    if @config[:webhook_url] && severity_level >= SEVERITY_LEVELS[@config[:min_severity_webhook]]
      channels << "webhook"
    end

    channels
  end

  def send_to_channel(channel, title, message, severity, context)
    case channel
    when "slack"
      send_slack_alert(title, message, severity, context)
    when "email"
      send_email_alert(title, message, severity, context)
    when "webhook"
      send_webhook_alert(title, message, severity, context)
    else
      { success: false, error: "Unknown channel: #{channel}" }
    end
  end

  # =============================================================================
  # SLACK INTEGRATION
  # =============================================================================

  def send_slack_alert(title, message, severity, context)
    return { success: false, error: "Slack webhook not configured" } unless @config[:slack_webhook_url]

    payload = {
      channel: @config[:slack_channel],
      username: "Powernode Alerts",
      icon_emoji: severity_emoji(severity),
      attachments: [ {
        fallback: "#{title}: #{message}",
        color: severity_color(severity),
        title: title,
        text: message,
        fields: context_fields(context),
        footer: "Powernode AlertingService",
        ts: Time.current.to_i
      } ]
    }

    response = Faraday.post(@config[:slack_webhook_url]) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = payload.to_json
      req.options.timeout = 10
      req.options.open_timeout = 5
    end

    if response.success?
      { success: true }
    else
      { success: false, error: "Slack returned #{response.status}" }
    end
  rescue Faraday::Error => e
    { success: false, error: e.message }
  end

  def severity_emoji(severity)
    case severity
    when :critical then ":rotating_light:"
    when :error then ":x:"
    when :warning then ":warning:"
    else ":information_source:"
    end
  end

  def severity_color(severity)
    case severity
    when :critical then "#FF0000"
    when :error then "#E01E5A"
    when :warning then "#ECB22E"
    else "#36C5F0"
    end
  end

  def context_fields(context)
    context.map do |key, value|
      {
        title: key.to_s.titleize,
        value: value.is_a?(Array) ? value.join("\n") : value.to_s,
        short: value.to_s.length < 50
      }
    end
  end

  # =============================================================================
  # EMAIL INTEGRATION
  # =============================================================================

  def send_email_alert(title, message, severity, context)
    return { success: false, error: "Alert email not configured" } unless @config[:alert_email]

    begin
      # Enqueue email job via worker service
      WorkerJobService.enqueue_job(
        "SendNotificationEmailJob",
        args: [ {
          to: @config[:alert_email],
          subject: "[#{severity.to_s.upcase}] #{title}",
          body: format_email_body(title, message, severity, context)
        } ]
      )
      { success: true }
    rescue StandardError => e
      { success: false, error: e.message }
    end
  end

  def format_email_body(title, message, severity, context)
    <<~BODY
      Alert: #{title}
      Severity: #{severity.to_s.upcase}
      Time: #{Time.current.iso8601}

      #{message}

      Context:
      #{context.map { |k, v| "  #{k}: #{v}" }.join("\n")}

      ---
      Powernode AlertingService
    BODY
  end

  # =============================================================================
  # WEBHOOK INTEGRATION (PagerDuty, etc.)
  # =============================================================================

  def send_webhook_alert(title, message, severity, context)
    return { success: false, error: "Webhook URL not configured" } unless @config[:webhook_url]

    payload = {
      event_type: "alert",
      title: title,
      message: message,
      severity: severity.to_s,
      timestamp: Time.current.iso8601,
      source: "powernode",
      context: context
    }

    response = Faraday.post(@config[:webhook_url]) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["Authorization"] = "Bearer #{@config[:webhook_auth_token]}" if @config[:webhook_auth_token]
      req.body = payload.to_json
      req.options.timeout = 10
      req.options.open_timeout = 5
    end

    if response.success?
      { success: true }
    else
      { success: false, error: "Webhook returned #{response.status}" }
    end
  rescue Faraday::Error => e
    { success: false, error: e.message }
  end

  # =============================================================================
  # LOGGING
  # =============================================================================

  def log_alert_sent(title, severity, channels, results)
    success_count = results.values.count { |r| r[:success] }
    Rails.logger.info("[AlertingService] Alert sent: #{title} | Severity: #{severity} | Channels: #{channels.join(', ')} | Success: #{success_count}/#{channels.length}")
  end
end
