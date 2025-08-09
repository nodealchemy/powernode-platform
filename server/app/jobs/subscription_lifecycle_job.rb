class SubscriptionLifecycleJob < ApplicationJob
  queue_as :subscription_lifecycle

  def perform(action, subscription_id, **options)
    subscription = Subscription.find(subscription_id)
    
    Rails.logger.info "Processing subscription lifecycle action '#{action}' for subscription #{subscription.id}"
    
    case action.to_s
    when 'trial_ending_reminder'
      handle_trial_ending_reminder(subscription, options)
    when 'trial_ended'
      handle_trial_ended(subscription, options)
    when 'renewal_reminder'
      handle_renewal_reminder(subscription, options)
    when 'payment_method_update_required'
      handle_payment_method_update_required(subscription, options)
    when 'subscription_expired'
      handle_subscription_expired(subscription, options)
    when 'reactivation_attempt'
      handle_reactivation_attempt(subscription, options)
    when 'grace_period_ending'
      handle_grace_period_ending(subscription, options)
    else
      Rails.logger.error "Unknown subscription lifecycle action: #{action}"
    end
    
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Subscription #{subscription_id} not found for lifecycle action #{action}"
  rescue => e
    Rails.logger.error "Subscription lifecycle job failed for action '#{action}': #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def handle_trial_ending_reminder(subscription, options)
    return unless subscription.trialing? && subscription.trial_end

    days_until_end = (subscription.trial_end.to_date - Date.current).to_i
    return unless [7, 3, 1].include?(days_until_end)

    Rails.logger.info "Sending trial ending reminder for subscription #{subscription.id} (#{days_until_end} days)"

    # Check if account has payment method
    has_payment_method = subscription.account.payment_methods.active.exists?

    send_trial_ending_notification(subscription, days_until_end, has_payment_method)

    # Schedule trial conversion if this is the final reminder
    if days_until_end == 1
      BillingAutomationJob.set(wait: 1.day).perform_later(subscription.id)
    end
  end

  def handle_trial_ended(subscription, options)
    return unless subscription.trial_end && subscription.trial_end <= Time.current

    Rails.logger.info "Processing trial end for subscription #{subscription.id}"

    # This will be handled by BillingAutomationJob
    BillingAutomationJob.perform_later(subscription.id)
  end

  def handle_renewal_reminder(subscription, options)
    return unless subscription.active? || subscription.past_due?
    return unless subscription.current_period_end

    days_until_renewal = (subscription.current_period_end.to_date - Date.current).to_i
    return unless [7, 3, 1].include?(days_until_renewal)

    Rails.logger.info "Sending renewal reminder for subscription #{subscription.id} (#{days_until_renewal} days)"

    # Check payment method status
    payment_method = subscription.account.payment_methods.default.first
    payment_method_valid = payment_method&.active?

    send_renewal_reminder_notification(subscription, days_until_renewal, payment_method_valid)

    # Schedule renewal processing if this is the final reminder
    if days_until_renewal == 1
      BillingAutomationJob.set(wait: 1.day).perform_later(subscription.id)
    end
  end

  def handle_payment_method_update_required(subscription, options)
    Rails.logger.info "Processing payment method update requirement for subscription #{subscription.id}"

    reason = options[:reason] || 'expired'
    
    send_payment_method_update_notification(subscription, reason)

    # If subscription is past due, give grace period for payment method update
    if subscription.past_due?
      grace_period_end = 7.days.from_now
      
      subscription.update!(
        metadata: subscription.metadata.merge(
          payment_method_grace_period_end: grace_period_end.iso8601
        )
      )

      # Schedule grace period ending job
      SubscriptionLifecycleJob.set(wait: 7.days)
                             .perform_later('grace_period_ending', subscription.id)
    end
  end

  def handle_subscription_expired(subscription, options)
    Rails.logger.info "Processing subscription expiration for subscription #{subscription.id}"

    # Cancel subscription
    subscription.update!(
      status: 'cancelled',
      ended_at: Time.current,
      metadata: subscription.metadata.merge(
        expiration_reason: options[:reason] || 'payment_failure'
      )
    )

    # Cancel in payment gateway
    billing_service = BillingService.new(subscription)
    billing_service.cancel_subscription(at_period_end: false, reason: 'expired')

    send_subscription_expired_notification(subscription)

    # Schedule data retention job
    DataRetentionJob.set(wait: 30.days).perform_later(subscription.account.id)
  end

  def handle_reactivation_attempt(subscription, options)
    return unless subscription.unpaid? || subscription.cancelled?

    Rails.logger.info "Attempting subscription reactivation for subscription #{subscription.id}"

    payment_method = subscription.account.payment_methods.default.first
    return unless payment_method&.active?

    # Attempt to collect outstanding payment
    billing_service = BillingService.new(subscription)
    outstanding_invoice = subscription.invoices.unpaid.first

    if outstanding_invoice
      payment_result = PaymentProcessingService.new(
        account: subscription.account,
        user: subscription.account.users.first
      ).process_payment(
        amount: outstanding_invoice.total_cents,
        currency: outstanding_invoice.currency,
        payment_method: payment_method,
        invoice: outstanding_invoice,
        description: "Reactivation payment for #{subscription.plan.name}"
      )

      if payment_result[:success]
        # Reactivate subscription
        subscription.update!(
          status: 'active',
          current_period_start: Time.current,
          current_period_end: calculate_new_period_end(subscription),
          metadata: subscription.metadata.merge(
            reactivated_at: Time.current.iso8601
          )
        )

        send_reactivation_success_notification(subscription)
        
        # Schedule next renewal
        schedule_renewal_reminders(subscription)
      else
        send_reactivation_failure_notification(subscription, payment_result[:error])
      end
    end
  end

  def handle_grace_period_ending(subscription, options)
    Rails.logger.info "Processing grace period end for subscription #{subscription.id}"

    # Check if payment method was added during grace period
    payment_method = subscription.account.payment_methods.default.first

    if payment_method&.active?
      # Attempt reactivation
      SubscriptionLifecycleJob.perform_later('reactivation_attempt', subscription.id)
    else
      # Expire subscription
      SubscriptionLifecycleJob.perform_later('subscription_expired', subscription.id, reason: 'no_payment_method')
    end
  end

  def calculate_new_period_end(subscription)
    case subscription.plan.billing_cycle
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

  def schedule_renewal_reminders(subscription)
    return unless subscription.current_period_end

    # Schedule renewal reminders
    [7, 3, 1].each do |days_before|
      reminder_date = subscription.current_period_end - days_before.days
      next if reminder_date <= Time.current

      SubscriptionLifecycleJob.set(wait_until: reminder_date)
                             .perform_later('renewal_reminder', subscription.id)
    end
  end

  # Notification methods
  def send_trial_ending_notification(subscription, days_until_end, has_payment_method)
    Rails.logger.info "Sending trial ending notification (#{days_until_end} days) for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_renewal_reminder_notification(subscription, days_until_renewal, payment_method_valid)
    Rails.logger.info "Sending renewal reminder (#{days_until_renewal} days) for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_payment_method_update_notification(subscription, reason)
    Rails.logger.info "Sending payment method update notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_subscription_expired_notification(subscription)
    Rails.logger.info "Sending subscription expired notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_reactivation_success_notification(subscription)
    Rails.logger.info "Sending reactivation success notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_reactivation_failure_notification(subscription, error)
    Rails.logger.info "Sending reactivation failure notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end
end