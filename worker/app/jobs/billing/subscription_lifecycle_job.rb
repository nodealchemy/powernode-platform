# frozen_string_literal: true

require_relative '../base_job'

# Converted from SubscriptionLifecycleJob to use API-only connectivity
# Handles subscription lifecycle events and notifications
class Billing::SubscriptionLifecycleJob < BaseJob
  sidekiq_options queue: 'subscription_lifecycle',
                  retry: 2

  def execute(action, subscription_id, **options)
    log_info("Processing subscription lifecycle action '#{action}' for subscription #{subscription_id}")
    
    case action.to_s
    when 'trial_ending_reminder'
      handle_trial_ending_reminder(subscription_id, options)
    when 'trial_ended'
      handle_trial_ended(subscription_id, options)
    when 'renewal_reminder'
      handle_renewal_reminder(subscription_id, options)
    when 'payment_method_update_required'
      handle_payment_method_update_required(subscription_id, options)
    when 'subscription_expired'
      handle_subscription_expired(subscription_id, options)
    when 'reactivation_attempt'
      handle_reactivation_attempt(subscription_id, options)
    when 'grace_period_ending'
      handle_grace_period_ending(subscription_id, options)
    else
      log_error("Unknown subscription lifecycle action: #{action}")
    end
  end

  private

  def handle_trial_ending_reminder(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription && subscription['status'] == 'trialing'

    days_until_end = options[:days_until_end] || 
                     calculate_days_until_trial_end(subscription)
    
    return unless [7, 3, 1].include?(days_until_end)

    log_info("Sending trial ending reminder for subscription #{subscription_id} (#{days_until_end} days)")

    # Check if account has payment method
    payment_methods = get_account_payment_methods(subscription['account_id'], active: true)
    has_payment_method = payment_methods.any?

    send_trial_ending_notification(subscription, days_until_end, has_payment_method)

    # Schedule trial conversion if this is the final reminder
    if days_until_end == 1
      Billing::BillingAutomationJob.perform_in(1.day, subscription_id)
    end
  end

  def handle_trial_ended(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription

    trial_end = subscription['trial_end'] ? Time.parse(subscription['trial_end']) : nil
    return unless trial_end && trial_end <= Time.current

    log_info("Processing trial end for subscription #{subscription_id}")

    # Delegate to billing automation
    Billing::BillingAutomationJob.perform_async(subscription_id)
  end

  def handle_renewal_reminder(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription && ['active', 'past_due'].include?(subscription['status'])

    days_until_renewal = options[:days_until_renewal] ||
                         calculate_days_until_renewal(subscription)
    
    return unless [7, 3, 1].include?(days_until_renewal)

    log_info("Sending renewal reminder for subscription #{subscription_id} (#{days_until_renewal} days)")

    # Check payment method status
    payment_methods = get_account_payment_methods(subscription['account_id'], default: true, active: true)
    payment_method_valid = payment_methods.any?

    send_renewal_reminder_notification(subscription, days_until_renewal, payment_method_valid)

    # Schedule renewal processing if this is the final reminder
    if days_until_renewal == 1
      Billing::BillingAutomationJob.perform_in(1.day, subscription_id)
    end
  end

  def handle_payment_method_update_required(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription

    log_info("Processing payment method update requirement for subscription #{subscription_id}")

    reason = options[:reason] || 'expired'
    
    send_payment_method_update_notification(subscription, reason, options)

    # If subscription is past due, give grace period for payment method update
    if subscription['status'] == 'past_due'
      grace_period_end = 7.days.from_now
      
      update_params = {
        metadata: subscription['metadata'].merge(
          'payment_method_grace_period_end' => grace_period_end.iso8601
        )
      }
      
      with_api_retry do
        api_client.patch("/api/v1/subscriptions/#{subscription_id}", update_params)
      end

      # Schedule grace period ending job
      Billing::SubscriptionLifecycleJob.perform_in(
        7.days,
        'grace_period_ending',
        subscription_id
      )
    end
  end

  def handle_subscription_expired(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription

    log_info("Processing subscription expiration for subscription #{subscription_id}")

    # Request subscription cancellation via API
    cancellation_params = {
      status: 'cancelled',
      ended_at: Time.current.iso8601,
      metadata: subscription['metadata'].merge(
        'expiration_reason' => options[:reason] || 'payment_failure',
        'expired_by_worker' => true
      )
    }
    
    with_api_retry do
      api_client.patch("/api/v1/subscriptions/#{subscription_id}", cancellation_params)
    end

    # Request cancellation in payment gateway via API
    gateway_params = {
      subscription_id: subscription_id,
      at_period_end: false,
      reason: 'expired'
    }
    
    with_api_retry do
      api_client.post('/api/v1/billing/cancel_subscription', gateway_params)
    end

    send_subscription_expired_notification(subscription, options[:reason])

    # Schedule data retention job for 30 days
    # DataRetentionJob.perform_in(30.days, subscription['account_id'])
  end

  def handle_reactivation_attempt(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription && ['unpaid', 'cancelled'].include?(subscription['status'])

    log_info("Attempting subscription reactivation for subscription #{subscription_id}")

    payment_methods = get_account_payment_methods(subscription['account_id'], default: true, active: true)
    return if payment_methods.empty?

    # Get outstanding invoices via API
    invoices_params = {
      subscription_id: subscription_id,
      status: 'unpaid'
    }
    
    outstanding_invoices = with_api_retry do
      api_client.get('/api/v1/invoices', invoices_params)
    end

    outstanding_invoice = outstanding_invoices.first
    return unless outstanding_invoice

    # Attempt payment via API
    payment_params = {
      invoice_id: outstanding_invoice['id'],
      payment_method_id: payment_methods.first['id'],
      description: "Reactivation payment for #{subscription.dig('plan', 'name')}"
    }
    
    payment_result = with_api_retry do
      api_client.post('/api/v1/billing/process_payment', payment_params)
    end

    if payment_result['success']
      # Reactivate subscription
      new_period_end = calculate_new_period_end(subscription)
      reactivation_params = {
        status: 'active',
        current_period_start: Time.current.iso8601,
        current_period_end: new_period_end.iso8601,
        metadata: subscription['metadata'].merge(
          'reactivated_at' => Time.current.iso8601,
          'reactivated_by_worker' => true
        )
      }
      
      with_api_retry do
        api_client.patch("/api/v1/subscriptions/#{subscription_id}", reactivation_params)
      end

      send_reactivation_success_notification(subscription)
      
      # Schedule next renewal reminders
      schedule_renewal_reminders(subscription_id, new_period_end)
    else
      send_reactivation_failure_notification(subscription, payment_result['error'])
    end
  end

  def handle_grace_period_ending(subscription_id, options)
    subscription = get_subscription(subscription_id)
    return unless subscription

    log_info("Processing grace period end for subscription #{subscription_id}")

    # Check if payment method was added during grace period
    payment_methods = get_account_payment_methods(subscription['account_id'], default: true, active: true)

    if payment_methods.any?
      # Attempt reactivation
      Billing::SubscriptionLifecycleJob.perform_async('reactivation_attempt', subscription_id)
    else
      # Expire subscription
      Billing::SubscriptionLifecycleJob.perform_async(
        'subscription_expired',
        subscription_id,
        reason: 'no_payment_method'
      )
    end
  end

  # Helper methods
  def get_subscription(subscription_id)
    with_api_retry do
      api_client.get("/api/v1/subscriptions/#{subscription_id}")
    end
  rescue BackendApiClient::ApiError => e
    if e.status == 404
      log_warn("Subscription #{subscription_id} not found: #{e.message}")
      nil
    else
      raise # Re-raise for retry
    end
  end

  def get_account_payment_methods(account_id, **filters)
    with_api_retry do
      api_client.get("/api/v1/accounts/#{account_id}/payment_methods", filters)
    end
  rescue BackendApiClient::ApiError
    []
  end

  def calculate_days_until_trial_end(subscription)
    return 0 unless subscription['trial_end']
    
    trial_end = Date.parse(subscription['trial_end'])
    (trial_end - Date.current).to_i
  end

  def calculate_days_until_renewal(subscription)
    return 0 unless subscription['current_period_end']
    
    period_end = Date.parse(subscription['current_period_end'])
    (period_end - Date.current).to_i
  end

  def calculate_new_period_end(subscription)
    case subscription.dig('plan', 'billing_cycle')
    when 'monthly'
      Time.current + 1.month
    when 'quarterly'
      Time.current + 3.months
    when 'yearly'
      Time.current + 1.year
    else
      Time.current + 1.month
    end
  end

  def schedule_renewal_reminders(subscription_id, period_end)
    # Schedule renewal reminders
    [7, 3, 1].each do |days_before|
      reminder_date = period_end - days_before.days
      next if reminder_date <= Time.current

      Billing::SubscriptionLifecycleJob.perform_at(
        reminder_date,
        'renewal_reminder',
        subscription_id
      )
    end
  end

  # Notification methods
  def send_trial_ending_notification(subscription, days_until_end, has_payment_method)
    notification_params = {
      type: 'trial_ending',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Trial expires in #{days_until_end} day#{'s' unless days_until_end == 1}",
      severity: days_until_end == 1 ? 'warning' : 'info',
      metadata: {
        days_until_end: days_until_end,
        has_payment_method: has_payment_method
      }
    }

    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end

    log_info("Sent trial ending notification (#{days_until_end} days) for subscription #{subscription['id']}")
  rescue StandardError => e
    log_error("Failed to send trial ending notification: #{e.message}")
    # Re-raise to ensure notification delivery is retried
    raise BillingExceptions::SubscriptionError.new(
      "Failed to send trial ending notification: #{e.message}",
      subscription_id: subscription['id'],
      action: 'send_trial_ending_notification',
      details: { original_error: e.class.name }
    )
  end

  def send_renewal_reminder_notification(subscription, days_until_renewal, payment_method_valid)
    notification_params = {
      type: 'renewal_reminder',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Subscription renews in #{days_until_renewal} day#{'s' unless days_until_renewal == 1}",
      severity: payment_method_valid ? 'info' : 'warning',
      metadata: {
        days_until_renewal: days_until_renewal,
        payment_method_valid: payment_method_valid
      }
    }

    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end

    log_info("Sent renewal reminder (#{days_until_renewal} days) for subscription #{subscription['id']}")
  rescue StandardError => e
    log_error("Failed to send renewal reminder: #{e.message}")
    # Re-raise to ensure notification delivery is retried
    raise BillingExceptions::SubscriptionError.new(
      "Failed to send renewal reminder: #{e.message}",
      subscription_id: subscription['id'],
      action: 'send_renewal_reminder_notification',
      details: { original_error: e.class.name }
    )
  end

  def send_payment_method_update_notification(subscription, reason, options)
    notification_params = {
      type: 'payment_method_update_required',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Payment method update required: #{reason}",
      severity: 'warning',
      metadata: {
        reason: reason,
        days_until_expiry: options[:days_until_expiry]
      }.compact
    }

    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end

    log_info("Sent payment method update notification for subscription #{subscription['id']}")
  rescue StandardError => e
    log_error("Failed to send payment method update notification: #{e.message}")
    # Re-raise to ensure notification delivery is retried
    raise BillingExceptions::SubscriptionError.new(
      "Failed to send payment method update notification: #{e.message}",
      subscription_id: subscription['id'],
      action: 'send_payment_method_update_notification',
      details: { original_error: e.class.name }
    )
  end

  def send_subscription_expired_notification(subscription, reason)
    notification_params = {
      type: 'subscription_expired',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Subscription has been cancelled: #{reason}",
      severity: 'critical',
      metadata: {
        expiration_reason: reason,
        expired_at: Time.current.iso8601
      }
    }

    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end

    log_info("Sent subscription expired notification for subscription #{subscription['id']}")
  rescue StandardError => e
    log_error("Failed to send subscription expired notification: #{e.message}")
    # Re-raise to ensure critical notification delivery is retried
    raise BillingExceptions::SubscriptionError.new(
      "Failed to send subscription expired notification: #{e.message}",
      subscription_id: subscription['id'],
      action: 'send_subscription_expired_notification',
      details: { original_error: e.class.name }
    )
  end

  def send_reactivation_success_notification(subscription)
    notification_params = {
      type: 'subscription_reactivated',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: 'Subscription has been reactivated successfully',
      severity: 'info',
      metadata: {
        reactivated_at: Time.current.iso8601
      }
    }

    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end

    log_info("Sent reactivation success notification for subscription #{subscription['id']}")
  rescue StandardError => e
    log_error("Failed to send reactivation success notification: #{e.message}")
    # Re-raise to ensure notification delivery is retried
    raise BillingExceptions::SubscriptionError.new(
      "Failed to send reactivation success notification: #{e.message}",
      subscription_id: subscription['id'],
      action: 'send_reactivation_success_notification',
      details: { original_error: e.class.name }
    )
  end

  def send_reactivation_failure_notification(subscription, error)
    notification_params = {
      type: 'reactivation_failed',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Subscription reactivation failed: #{error}",
      severity: 'warning',
      metadata: {
        error: error,
        attempted_at: Time.current.iso8601
      }
    }

    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end

    log_info("Sent reactivation failure notification for subscription #{subscription['id']}")
  rescue StandardError => e
    log_error("Failed to send reactivation failure notification: #{e.message}")
    # Re-raise to ensure notification delivery is retried
    raise BillingExceptions::SubscriptionError.new(
      "Failed to send reactivation failure notification: #{e.message}",
      subscription_id: subscription['id'],
      action: 'send_reactivation_failure_notification',
      details: { original_error: e.class.name }
    )
  end
end