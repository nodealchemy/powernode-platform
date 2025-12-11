# frozen_string_literal: true

require_relative '../mailers/notification_mailer'
require_relative '../services/email_configuration_service'
require_relative '../services/api_client'

class SendNotificationEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: 3

  # Define required parameters for each email type
  REQUIRED_PARAMS = {
    'welcome' => %w[user_id],
    'password_reset' => %w[user_id reset_token],
    'email_verification' => %w[user_id verification_token],
    'subscription_renewal' => %w[account_id],
    'payment_failed' => %w[account_id amount retry_date],
    'subscription_cancelled' => %w[account_id end_date],
    'invitation' => %w[invitation_id invitation_token]
  }.freeze

  def execute(args)
    email_type = args['type'] || args[:type]
    params = args['params'] || args[:params] || {}

    # Validate email type is present
    unless email_type.present?
      log_warn("SendNotificationEmailJob called without email type", args: args.inspect)
      return
    end

    # Validate email type is supported
    unless REQUIRED_PARAMS.key?(email_type.to_s)
      log_warn("Unknown email type: #{email_type}", args: args.inspect)
      return
    end

    # Validate required parameters
    missing_params = validate_required_params(email_type.to_s, params)
    if missing_params.any?
      log_error(
        "Missing required parameters for #{email_type} email",
        nil,
        missing_params: missing_params,
        provided_params: params.keys
      )
      raise ArgumentError, "Missing required parameters: #{missing_params.join(', ')}"
    end

    # Ensure we have the latest email configuration
    EmailConfigurationService.instance.fetch_settings

    # Route to appropriate mailer method with error handling
    send_email(email_type.to_s, params)

    # Log success to backend for tracking
    log_notification_status(email_type, params, 'sent')

  rescue Net::SMTPError, Net::OpenTimeout, Net::ReadTimeout => e
    # Network/SMTP errors - may be recoverable with retry
    log_error("Email delivery failed (network/SMTP error)", e, email_type: email_type)
    log_notification_status(email_type, params, 'failed', e.message)
    raise # Re-raise for Sidekiq retry

  rescue ArgumentError => e
    # Parameter validation errors - not recoverable, don't retry
    log_error("Email parameter validation failed", e, email_type: email_type)
    log_notification_status(email_type, params, 'failed', e.message)
    # Don't re-raise ArgumentError - retrying won't help

  rescue StandardError => e
    log_error("Email delivery failed", e, email_type: email_type)
    log_notification_status(email_type, params, 'failed', e.message)
    raise # Re-raise for Sidekiq retry
  end

  private

  def validate_required_params(email_type, params)
    required = REQUIRED_PARAMS[email_type] || []
    required.reject { |param| params[param].present? || params[param.to_sym].present? }
  end

  def send_email(email_type, params)
    case email_type
    when 'welcome'
      NotificationMailer.welcome_email(params['user_id']).deliver_now
    when 'password_reset'
      NotificationMailer.password_reset(params['user_id'], params['reset_token']).deliver_now
    when 'email_verification'
      NotificationMailer.email_verification(params['user_id'], params['verification_token']).deliver_now
    when 'subscription_renewal'
      NotificationMailer.subscription_renewal(params['account_id']).deliver_now
    when 'payment_failed'
      NotificationMailer.payment_failed(
        params['account_id'],
        params['amount'],
        params['retry_date']
      ).deliver_now
    when 'subscription_cancelled'
      NotificationMailer.subscription_cancelled(
        params['account_id'],
        params['end_date']
      ).deliver_now
    when 'invitation'
      NotificationMailer.invitation_email(
        params['invitation_id'],
        params['invitation_token']
      ).deliver_now
    end
  end

  def log_notification_status(email_type, params, status, error_message = nil)
    notification_data = {
      notification_type: 'email',
      email_type: email_type,
      status: status,
      params: params,
      timestamp: Time.current
    }
    notification_data[:error] = error_message if error_message.present?

    begin
      api_client.post("/api/v1/notifications", notification_data)
    rescue StandardError => api_error
      # Don't let API logging failure crash the job
      log_warn(
        "Failed to log notification status to backend",
        error: api_error.message,
        email_type: email_type,
        status: status
      )
    end
  end

  def api_client
    @api_client ||= ApiClient.new
  end
end