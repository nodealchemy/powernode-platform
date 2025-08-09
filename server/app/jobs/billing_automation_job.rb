class BillingAutomationJob < ApplicationJob
  queue_as :billing

  def perform(subscription_id = nil)
    Rails.logger.info "Starting billing automation cycle at #{Time.current}"
    
    if subscription_id
      # Process specific subscription
      process_subscription(subscription_id)
    else
      # Process all subscriptions that need renewal
      process_subscriptions_needing_renewal
    end
    
    Rails.logger.info "Completed billing automation cycle at #{Time.current}"
  rescue => e
    Rails.logger.error "Billing automation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def process_subscriptions_needing_renewal
    # Find subscriptions ending today or in the past that haven't been renewed
    subscriptions = Subscription.joins(:account)
                               .where(status: ['active', 'trialing', 'past_due'])
                               .where('current_period_end <= ?', Time.current.end_of_day)
                               .where(accounts: { status: 'active' })
                               .includes(:plan, :account, account: :users)

    Rails.logger.info "Found #{subscriptions.count} subscriptions needing renewal"

    subscriptions.find_each(batch_size: 50) do |subscription|
      process_subscription(subscription.id)
    end
  end

  def process_subscription(subscription_id)
    subscription = Subscription.find(subscription_id)
    return unless subscription

    Rails.logger.info "Processing subscription #{subscription.id} for account #{subscription.account.name}"

    begin
      case subscription.status
      when 'trialing'
        handle_trial_ending(subscription)
      when 'active', 'past_due'
        handle_subscription_renewal(subscription)
      end
    rescue => e
      Rails.logger.error "Failed to process subscription #{subscription.id}: #{e.message}"
      
      # Schedule retry for later
      BillingAutomationJob.set(wait: 1.hour).perform_later(subscription.id)
      
      # Send alert to admin
      send_billing_failure_alert(subscription, e.message)
    end
  end

  def handle_trial_ending(subscription)
    return unless subscription.trial_end && subscription.trial_end <= Time.current

    Rails.logger.info "Trial ending for subscription #{subscription.id}"

    billing_service = BillingService.new(subscription)
    
    # Check if account has valid payment method
    payment_method = subscription.account.payment_methods.default.first
    
    if payment_method.nil?
      # No payment method - convert trial to grace period
      subscription.update!(
        status: 'past_due',
        current_period_start: Time.current,
        current_period_end: 3.days.from_now, # Grace period
        metadata: subscription.metadata.merge(
          trial_ended_at: Time.current.iso8601,
          grace_period_ends: 3.days.from_now.iso8601
        )
      )
      
      send_payment_method_required_notification(subscription)
      return
    end

    # Generate first invoice and attempt payment
    begin
      invoice = billing_service.generate_subscription_invoice
      payment_result = attempt_payment_collection(invoice, payment_method)
      
      if payment_result[:success]
        # Successful payment - convert to active
        advance_subscription_period(subscription)
        subscription.update!(status: 'active')
        send_trial_conversion_success_notification(subscription)
      else
        # Payment failed - handle according to retry policy
        subscription.update!(status: 'past_due')
        billing_service.handle_failed_payment(payment_result[:payment])
      end
    rescue => e
      Rails.logger.error "Failed to process trial ending for subscription #{subscription.id}: #{e.message}"
      subscription.update!(status: 'past_due')
      raise
    end
  end

  def handle_subscription_renewal(subscription)
    Rails.logger.info "Processing renewal for subscription #{subscription.id}"

    billing_service = BillingService.new(subscription)
    payment_method = subscription.account.payment_methods.default.first

    return unless payment_method

    begin
      # Generate renewal invoice
      invoice = billing_service.generate_subscription_invoice
      
      # Attempt payment collection
      payment_result = attempt_payment_collection(invoice, payment_method)
      
      if payment_result[:success]
        # Successful payment - advance billing period
        advance_subscription_period(subscription)
        
        # Reactivate if was past due
        if subscription.past_due?
          subscription.update!(status: 'active')
          send_reactivation_notification(subscription)
        end
        
        send_renewal_success_notification(subscription, invoice)
        
      else
        # Payment failed - handle according to retry policy
        billing_service.handle_failed_payment(payment_result[:payment])
        send_payment_failure_notification(subscription, payment_result[:payment])
      end
      
    rescue => e
      Rails.logger.error "Failed to process renewal for subscription #{subscription.id}: #{e.message}"
      raise
    end
  end

  def attempt_payment_collection(invoice, payment_method)
    payment_processor = PaymentProcessingService.new(
      account: invoice.subscription.account,
      user: invoice.subscription.account.users.first
    )

    payment_processor.process_payment(
      amount: invoice.total_cents,
      currency: invoice.currency,
      payment_method: payment_method,
      invoice: invoice,
      description: "Subscription renewal for #{invoice.subscription.plan.name}"
    )
  end

  def advance_subscription_period(subscription)
    current_end = subscription.current_period_end
    
    new_period_start = current_end
    new_period_end = case subscription.plan.billing_cycle
                     when 'monthly'
                       current_end + 1.month
                     when 'quarterly'
                       current_end + 3.months
                     when 'yearly'
                       current_end + 1.year
                     else
                       current_end + 1.month
                     end

    subscription.update!(
      current_period_start: new_period_start,
      current_period_end: new_period_end,
      last_billing_date: Time.current
    )

    Rails.logger.info "Advanced billing period for subscription #{subscription.id}: #{new_period_start} - #{new_period_end}"
  end

  # Notification methods
  def send_payment_method_required_notification(subscription)
    Rails.logger.info "Sending payment method required notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_trial_conversion_success_notification(subscription)
    Rails.logger.info "Sending trial conversion success notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_renewal_success_notification(subscription, invoice)
    Rails.logger.info "Sending renewal success notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_payment_failure_notification(subscription, payment)
    Rails.logger.info "Sending payment failure notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_reactivation_notification(subscription)
    Rails.logger.info "Sending reactivation notification for subscription #{subscription.id}"
    # Implementation would integrate with email service
  end

  def send_billing_failure_alert(subscription, error_message)
    Rails.logger.error "ADMIN ALERT: Billing failure for subscription #{subscription.id}: #{error_message}"
    # Implementation would send alert to admin team
  end
end