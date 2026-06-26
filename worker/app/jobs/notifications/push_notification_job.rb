# frozen_string_literal: true

require_relative '../base_job'

# Job for sending push notifications via Firebase Cloud Messaging
class Notifications::PushNotificationJob < BaseJob
  sidekiq_options queue: 'notifications',
                  retry: 3

  def execute(notification_id, options = {})
    log_info("Processing push notification #{notification_id}")

    # Idempotency guard: if a previous attempt already dispatched the push, a
    # Sidekiq retry (e.g. triggered by a failed delivery-mark PATCH) must NOT
    # dispatch it again — that would deliver a duplicate push to the device(s).
    idempotency_key = "push_delivery:#{notification_id}"
    if already_processed?(idempotency_key)
      log_info("Push already sent for notification #{notification_id}, skipping duplicate send")
      return { skipped: true, reason: 'already_processed' }
    end

    # Get notification details from backend
    notification = fetch_notification(notification_id)
    return log_error("Notification #{notification_id} not found") unless notification

    # Validate push preferences
    unless push_enabled_for_user?(notification)
      log_info("Push notifications disabled for user, skipping")
      return mark_notification_skipped(notification_id, 'push_disabled')
    end

    # Get device tokens
    device_tokens = get_device_tokens(notification)
    if device_tokens.empty?
      log_warn("No device tokens for notification #{notification_id}")
      return mark_notification_failed(notification_id, 'no_device_tokens')
    end

    # Build notification content
    title = notification['title'] || build_title(notification)
    body = notification['body'] || build_body(notification)
    data = build_data_payload(notification, options)

    begin
      firebase = FirebaseService.new

      if device_tokens.length == 1
        # Single device
        result = firebase.send_notification(
          device_token: device_tokens.first,
          title: title,
          body: body,
          data: data,
          options: notification_options(notification)
        )

        # The push has been dispatched to Firebase. Mark it processed BEFORE the
        # bookkeeping PATCH so a retry (e.g. from a failed delivery-mark) can't
        # re-dispatch a duplicate push.
        mark_processed(idempotency_key)

        handle_single_result(notification_id, result)
      else
        # Multiple devices
        result = firebase.send_multicast(
          device_tokens: device_tokens,
          title: title,
          body: body,
          data: data
        )

        # Multicast dispatched — guard against a duplicate re-send on retry.
        mark_processed(idempotency_key)

        handle_multicast_result(notification_id, result, notification)
      end

    rescue FirebaseService::ConfigurationError => e
      log_error("Firebase configuration error: #{e.message}")
      mark_notification_failed(notification_id, "configuration_error: #{e.message}")
      raise # Surface the error
    rescue FirebaseService::DeliveryError => e
      log_error("Firebase delivery error: #{e.message}")
      mark_notification_failed(notification_id, e.message)
      raise # Allow retry
    rescue BackendApiClient::ApiError => e
      # Raised by the status-update PATCH (mark_notification_delivered/failed/
      # partial) AFTER the push was already dispatched and guarded above. Don't
      # bubble into a Sidekiq retry that would just no-op on the guard.
      log_error("Failed to update notification status after push dispatch", e,
                notification_id: notification_id)
      nil
    end
  end

  private

  def fetch_notification(notification_id)
    with_api_retry do
      api_client.get("/api/v1/notifications/#{notification_id}")
    end
  end

  def push_enabled_for_user?(notification)
    user_id = notification['user_id']
    return true unless user_id

    preferences = with_api_retry do
      api_client.get("/api/v1/users/#{user_id}/notification_preferences")
    end

    preferences && preferences['push_enabled'] != false
  end

  def get_device_tokens(notification)
    user_id = notification['user_id']
    return [] unless user_id

    # Get user's registered device tokens
    devices = with_api_retry do
      api_client.get("/api/v1/users/#{user_id}/devices")
    end

    return [] unless devices

    # Filter to active devices with push tokens
    devices
      .select { |d| d['push_token'].present? && d['push_enabled'] != false }
      .map { |d| d['push_token'] }
  end

  def build_title(notification)
    template_type = notification['template_type'] || notification['type']

    case template_type
    when 'trial_ending'
      'Trial Ending Soon'
    when 'payment_failed'
      'Payment Failed'
    when 'payment_successful'
      'Payment Received'
    when 'subscription_renewed'
      'Subscription Renewed'
    when 'subscription_canceled'
      'Subscription Canceled'
    when 'password_reset'
      'Password Reset'
    when 'two_factor_code'
      'Verification Code'
    when 'new_feature'
      'New Feature Available'
    when 'system_update'
      'System Update'
    else
      notification['title'] || 'Powernode'
    end
  end

  def build_body(notification)
    template_type = notification['template_type'] || notification['type']
    data = notification['data'] || {}

    case template_type
    when 'trial_ending'
      days = data['days_remaining'] || 3
      "Your trial ends in #{days} days. Tap to update your payment method."
    when 'payment_failed'
      "Your payment couldn't be processed. Tap to update your payment method."
    when 'payment_successful'
      amount = format_amount(data['amount'])
      "Payment of #{amount} received successfully."
    when 'subscription_renewed'
      "Your subscription has been renewed."
    when 'subscription_canceled'
      "Your subscription has been canceled."
    when 'new_feature'
      data['feature_name'] || 'Check out our latest feature!'
    else
      notification['body'] || notification['message'] || 'You have a new notification'
    end
  end

  def build_data_payload(notification, options)
    {
      notification_id: notification['id'].to_s,
      type: notification['type'] || notification['template_type'],
      created_at: notification['created_at'],
      deep_link: notification['deep_link'] || build_deep_link(notification),
      action: notification['action']
    }.compact.transform_values(&:to_s)
  end

  def build_deep_link(notification)
    template_type = notification['template_type'] || notification['type']

    case template_type
    when 'trial_ending', 'payment_failed'
      'powernode://billing'
    when 'subscription_renewed', 'subscription_canceled'
      'powernode://subscription'
    when 'password_reset'
      'powernode://security'
    else
      'powernode://notifications'
    end
  end

  def notification_options(notification)
    {
      sound: notification['sound'] || 'default',
      badge: notification['badge'],
      icon: notification['icon'],
      color: notification['color'],
      click_action: notification['click_action'],
      channel_id: notification['channel_id'] || 'default'
    }.compact
  end

  def format_amount(amount)
    return "$0.00" unless amount
    cents = amount.is_a?(Integer) ? amount : (amount * 100).to_i
    "$#{format('%.2f', cents / 100.0)}"
  end

  def handle_single_result(notification_id, result)
    if result[:success]
      log_info("Push sent successfully: #{result[:message_id]}")
      mark_notification_delivered(notification_id, {
        channel: 'push',
        message_id: result[:message_id]
      })
    elsif result[:invalid_token]
      log_warn("Invalid device token - marking for removal")
      remove_invalid_token(result[:device_token])
      mark_notification_failed(notification_id, 'invalid_device_token')
    else
      log_error("Push delivery failed: #{result[:error]}")
      mark_notification_failed(notification_id, result[:error])
    end

    result
  end

  def handle_multicast_result(notification_id, result, notification)
    log_info("Push multicast complete: #{result[:sent]}/#{result[:total]} sent")

    # Remove invalid tokens
    if result[:invalid_tokens].any?
      result[:invalid_tokens].each { |token| remove_invalid_token(token) }
    end

    if result[:success]
      mark_notification_delivered(notification_id, {
        channel: 'push',
        devices_sent: result[:sent],
        devices_failed: result[:failed],
        invalid_tokens_removed: result[:invalid_tokens].count
      })
    else
      mark_notification_partial(notification_id, {
        sent: result[:sent],
        failed: result[:failed]
      })
    end

    result
  end

  def remove_invalid_token(device_token)
    with_api_retry do
      api_client.delete("/api/v1/devices/by_token/#{device_token}")
    end
  rescue StandardError => e
    log_warn("Failed to remove invalid token: #{e.message}")
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

  def mark_notification_partial(notification_id, metadata)
    with_api_retry do
      api_client.patch("/api/v1/notifications/#{notification_id}", {
        status: 'partial',
        delivery_metadata: metadata
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
