# frozen_string_literal: true

module Monitoring
  # Monitoring::AlertingService
  # Provides multi-channel alerting for critical system events
  # Supports: Slack, Email, Webhook (PagerDuty, etc.)
  #
  # CONFIGURATION comes from Monitoring::AlertChannels (design E8): the three
  # credentials from Security::SecretStore, the email address and severity
  # floors from SiteSettings. There is no ENV fallback and no master switch —
  # a channel is live if and only if it is configured.
  #
  # CREDENTIALS ARE NEVER HELD. Each send method reads its secret into a local
  # and hands it straight to the HTTP client; nothing stores one in an ivar
  # (where `inspect` would print it) or passes one through our own methods.
  #
  # DELIVERY ERRORS LOG THEIR CLASS, NEVER THEIR MESSAGE. A malformed stored
  # URL raises URI::InvalidURIError, and Ruby puts the offending URI in that
  # message verbatim — so logging `e.message` would write the Slack webhook
  # into the log. The same holds for connection errors that name the host.
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

  # Written to a result, and to the log, when the credential store cannot be
  # read. Fail CLOSED and VISIBLY: never deliver through a downgraded path, and
  # never let an outage read as "no channel configured".
  STORE_UNAVAILABLE = "secret_store_unavailable"

  def initialize(options = {})
    @options = options
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
    results = {}
    channels_to_use = channels || determine_channels(severity, results)

    channels_to_use.each do |channel|
      results[channel] = send_to_channel(channel, title, message, severity, context)
    end

    log_alert_sent(title, severity, channels_to_use, results)
    results
  rescue StandardError => e
    # Class only: see the class comment on delivery errors.
    Rails.logger.error("[Monitoring::AlertingService] alert failed: #{e.class}")
    { error: e.class.name }
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

  # Channels at or above their floor that are configured. A channel whose
  # credential cannot be read is NOT silently dropped: its result records
  # STORE_UNAVAILABLE, so the outage is visible in what send_alert returns.
  def determine_channels(severity, results)
    level = SEVERITY_LEVELS[severity.to_s.to_sym] || 0

    AlertChannels::CHANNELS.select do |channel|
      next false if level < SEVERITY_LEVELS.fetch(AlertChannels.min_severity(channel))

      channel_configured?(channel, results)
    end
  end

  def channel_configured?(channel, results)
    case channel
    when "email" then AlertChannels.email.present?
    when "slack" then AlertChannels.secret_configured?(AlertChannels::SLACK_WEBHOOK_URL)
    when "webhook" then AlertChannels.secret_configured?(AlertChannels::WEBHOOK_URL)
    else false
    end
  rescue ::Security::SecretStore::BackendUnavailable
    results[channel] = store_unavailable(channel)
    false
  end

  def store_unavailable(channel)
    Rails.logger.error("[Monitoring::AlertingService] #{channel} not delivered: #{STORE_UNAVAILABLE}")
    { success: false, error: STORE_UNAVAILABLE }
  end

  def delivery_failed(channel, error)
    Rails.logger.error("[Monitoring::AlertingService] #{channel} delivery failed: #{error.class}")
    { success: false, error: "delivery_failed", error_class: error.class.name }
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
    webhook_url = AlertChannels.read_secret(AlertChannels::SLACK_WEBHOOK_URL)
    return { success: false, error: "not_configured" } if webhook_url.blank?

    # No `channel:` override: an incoming webhook posts to the channel it was
    # created for, and current Slack apps ignore the field.
    payload = {
      username: "Powernode Alerts",
      icon_emoji: severity_emoji(severity),
      attachments: [ {
        fallback: "#{title}: #{message}",
        color: severity_color(severity),
        title: title,
        text: message,
        fields: context_fields(context),
        footer: "Powernode Monitoring::AlertingService",
        ts: Time.current.to_i
      } ]
    }

    response = Faraday.post(webhook_url) do |req|
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
  rescue ::Security::SecretStore::BackendUnavailable
    store_unavailable("slack")
  rescue StandardError => e
    delivery_failed("slack", e)
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
    recipient = AlertChannels.email
    return { success: false, error: "not_configured" } if recipient.blank?

    subject = "[#{severity.to_s.upcase}] #{title}"

    begin
      # Pattern B, mirroring SecurityAlertService#dispatch_to: the server owns
      # the EmailDelivery ledger, the worker renders + delivers and POSTs the
      # outcome back to /api/v1/internal/emails/:id/delivered.
      #
      # Deliberately NOT Notifications::EmailDeliveryJob, despite its #execute
      # accepting this exact to/subject/body/email_type shape: that job routes
      # through EmailDeliveryWorkerService, whose create_email_delivery_record
      # POSTs /api/v1/email_deliveries — a route this server does not define
      # (EmailDelivery has a model but no controller). The 404 is non-retryable,
      # the job logs and returns, and Sidekiq marks it SUCCEEDED. Matching the
      # argument shape is not enough; the target's terminal function has to work.
      delivery = EmailDelivery.create!(
        recipient_email: recipient,
        subject: subject,
        email_type: "notification",
        status: "pending",
        metadata: {
          category: "monitoring_alert",
          severity: severity.to_s,
          title: title,
          context: context
        }
      )

      WorkerJobService.enqueue_alert_email({
        email_delivery_id: delivery.id,
        recipient: recipient,
        subject: subject,
        heading: "Monitoring Alert",
        body: format_email_body(title, message, severity, context),
        details: { severity: severity.to_s, title: title }
      })

      { success: true, email_delivery_id: delivery.id }
    rescue StandardError => e
      # Record the genuine failure on the ledger when the row exists, so a
      # failed dispatch is visible rather than inferred from an absent email.
      delivery&.update(status: "failed", error_message: "Failed to enqueue send: #{e.message}")
      Rails.logger.error("[Monitoring::AlertingService] alert email dispatch failed: #{e.message}")
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
      Powernode Monitoring::AlertingService
    BODY
  end

  # =============================================================================
  # WEBHOOK INTEGRATION (PagerDuty, etc.)
  # =============================================================================

  def send_webhook_alert(title, message, severity, context)
    webhook_url = AlertChannels.read_secret(AlertChannels::WEBHOOK_URL)
    return { success: false, error: "not_configured" } if webhook_url.blank?

    payload = {
      event_type: "alert",
      title: title,
      message: message,
      severity: severity.to_s,
      timestamp: Time.current.iso8601,
      source: "powernode",
      context: context
    }

    auth_token = AlertChannels.read_secret(AlertChannels::WEBHOOK_AUTH_TOKEN)
    response = Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["Authorization"] = "Bearer #{auth_token}" if auth_token.present?
      req.body = payload.to_json
      req.options.timeout = 10
      req.options.open_timeout = 5
    end

    if response.success?
      { success: true }
    else
      { success: false, error: "Webhook returned #{response.status}" }
    end
  rescue ::Security::SecretStore::BackendUnavailable
    store_unavailable("webhook")
  rescue StandardError => e
    delivery_failed("webhook", e)
  end

  # =============================================================================
  # LOGGING
  # =============================================================================

  def log_alert_sent(title, severity, channels, results)
    success_count = results.values.count { |r| r[:success] }
    Rails.logger.info("[Monitoring::AlertingService] Alert sent: #{title} | Severity: #{severity} | Channels: #{channels.join(', ')} | Success: #{success_count}/#{channels.length}")
  end
  end
end
