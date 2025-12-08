# frozen_string_literal: true

require_relative '../base_job'

# Job for sending SMS notifications via Twilio
class Notifications::SmsDeliveryJob < BaseJob
  sidekiq_options queue: 'notifications',
                  retry: 3

  def execute(notification_id, options = {})
    log_info("Processing SMS notification #{notification_id}")

    # Get notification details from backend
    notification = fetch_notification(notification_id)
    return log_error("Notification #{notification_id} not found") unless notification

    # Validate SMS preferences
    unless sms_enabled_for_user?(notification)
      log_info("SMS disabled for user, skipping")
      return mark_notification_skipped(notification_id, 'sms_disabled')
    end

    # Get phone number
    phone_number = get_phone_number(notification)
    unless phone_number.present?
      log_warn("No phone number for notification #{notification_id}")
      return mark_notification_failed(notification_id, 'no_phone_number')
    end

    # Build and send SMS
    message_body = build_message(notification, options)

    begin
      twilio = TwilioService.new
      result = twilio.send_sms(
        to: phone_number,
        body: message_body
      )

      if result[:success]
        log_info("SMS sent successfully: #{result[:message_sid]}")
        mark_notification_delivered(notification_id, {
          channel: 'sms',
          message_sid: result[:message_sid],
          segments: result[:segments]
        })
      else
        log_error("SMS delivery failed: #{result[:error]}")
        mark_notification_failed(notification_id, result[:error])
      end

      result
    rescue TwilioService::ConfigurationError => e
      log_error("Twilio configuration error: #{e.message}")
      mark_notification_failed(notification_id, "configuration_error: #{e.message}")
      raise # Retry won't help, but we should surface the error
    rescue TwilioService::InvalidPhoneError => e
      log_error("Invalid phone number: #{e.message}")
      mark_notification_failed(notification_id, "invalid_phone: #{e.message}")
      # Don't retry - phone number is invalid
    rescue TwilioService::DeliveryError => e
      log_error("SMS delivery error: #{e.message}")
      mark_notification_failed(notification_id, e.message)
      raise # Allow retry
    end
  end

  private

  def fetch_notification(notification_id)
    with_api_retry do
      api_client.get("/api/v1/notifications/#{notification_id}")
    end
  end

  def sms_enabled_for_user?(notification)
    user_id = notification['user_id']
    return true unless user_id

    # Check user SMS preferences
    preferences = with_api_retry do
      api_client.get("/api/v1/users/#{user_id}/notification_preferences")
    end

    preferences && preferences['sms_enabled'] != false
  end

  def get_phone_number(notification)
    # First try notification-specific phone
    return notification['phone_number'] if notification['phone_number'].present?

    # Then try user's phone
    user_id = notification['user_id']
    return nil unless user_id

    user = with_api_retry do
      api_client.get("/api/v1/users/#{user_id}")
    end

    user&.dig('phone_number')
  end

  def build_message(notification, options = {})
    template_type = notification['template_type'] || notification['type']
    data = notification['data'] || {}

    case template_type
    when 'trial_ending'
      days = data['days_remaining'] || 3
      "Your trial ends in #{days} days. Update your payment method to continue service."
    when 'payment_failed'
      "Payment failed for your subscription. Please update your payment method to avoid service interruption."
    when 'payment_successful'
      amount = format_amount(data['amount'])
      "Payment of #{amount} received. Thank you!"
    when 'subscription_renewed'
      "Your subscription has been renewed successfully."
    when 'subscription_canceled'
      "Your subscription has been canceled. We're sorry to see you go."
    when 'password_reset'
      code = data['code'] || data['reset_code']
      "Your password reset code is: #{code}. Valid for 15 minutes."
    when 'two_factor_code'
      code = data['code'] || data['otp_code']
      "Your verification code is: #{code}"
    when 'account_verification'
      code = data['code'] || data['verification_code']
      "Your verification code is: #{code}"
    when 'general', 'custom'
      data['message'] || notification['body'] || notification['message']
    else
      # Default message from notification content
      notification['body'] || notification['message'] || "You have a new notification from Powernode"
    end
  end

  def format_amount(amount)
    return "$0.00" unless amount
    cents = amount.is_a?(Integer) ? amount : (amount * 100).to_i
    "$#{format('%.2f', cents / 100.0)}"
  end

  def mark_notification_delivered(notification_id, metadata = {})
    with_api_retry do
      api_client.patch("/api/v1/notifications/#{notification_id}", {
        status: 'delivered',
        delivered_at: Time.now.iso8601,
        delivery_metadata: metadata
      })
    end
  end

  def mark_notification_failed(notification_id, error)
    with_api_retry do
      api_client.patch("/api/v1/notifications/#{notification_id}", {
        status: 'failed',
        failed_at: Time.now.iso8601,
        error_message: error
      })
    end
  end

  def mark_notification_skipped(notification_id, reason)
    with_api_retry do
      api_client.patch("/api/v1/notifications/#{notification_id}", {
        status: 'skipped',
        skip_reason: reason
      })
    end
  end
end
