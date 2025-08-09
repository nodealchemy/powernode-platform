class PaymentRetryJob < ApplicationJob
  queue_as :billing_retries
  
  # Retry failed payments with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(payment_id, retry_attempt = 1)
    payment = Payment.find(payment_id)
    
    Rails.logger.info "Retrying payment #{payment.id} (attempt #{retry_attempt})"
    
    # Don't retry if payment has succeeded in the meantime
    return if payment.succeeded?
    
    # Don't retry beyond maximum attempts
    return if retry_attempt > max_retry_attempts
    
    # Don't retry if subscription has been cancelled
    return if payment.subscription&.cancelled?
    
    billing_service = BillingService.new(payment.subscription)
    success = billing_service.retry_failed_payment(payment, retry_attempt)
    
    if success
      Rails.logger.info "Payment retry successful: #{payment.id} on attempt #{retry_attempt}"
      handle_successful_retry(payment)
    else
      Rails.logger.warn "Payment retry failed: #{payment.id} on attempt #{retry_attempt}"
      handle_failed_retry(payment, retry_attempt)
    end
    
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Payment #{payment_id} not found for retry attempt #{retry_attempt}"
  rescue => e
    Rails.logger.error "Payment retry job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def max_retry_attempts
    Rails.application.config.powernode&.dig(:billing, :max_payment_retries) || 4
  end

  def handle_successful_retry(payment)
    subscription = payment.subscription
    return unless subscription

    # Reactivate subscription if it was past due
    if subscription.past_due? || subscription.unpaid?
      subscription.update!(status: 'active')
      
      # Advance billing period if this was a renewal payment
      if payment.invoice&.invoice_type == 'subscription'
        advance_billing_period(subscription)
      end
    end

    # Send success notification
    send_retry_success_notification(payment)
    
    # Update payment method status if it was marked as failed
    payment_method = payment.payment_method
    if payment_method&.status == 'failed'
      payment_method.update!(status: 'active', last_used_at: Time.current)
    end
  end

  def handle_failed_retry(payment, retry_attempt)
    subscription = payment.subscription
    
    if retry_attempt >= max_retry_attempts
      # Final attempt failed
      handle_final_retry_failure(payment)
    else
      # Schedule next retry
      schedule_next_retry(payment, retry_attempt + 1)
    end
    
    # Update dunning status
    update_dunning_status(subscription, retry_attempt)
  end

  def handle_final_retry_failure(payment)
    Rails.logger.error "Final payment retry failed for payment #{payment.id}"
    
    subscription = payment.subscription
    return unless subscription

    # Mark subscription as unpaid and suspend account
    subscription.update!(status: 'unpaid') if subscription.may_mark_unpaid?
    
    account = subscription.account
    account.update!(
      status: 'suspended',
      suspended_at: Time.current,
      suspension_reason: 'payment_failure'
    )

    # Mark payment method as failed
    payment_method = payment.payment_method
    payment_method&.update!(
      status: 'failed',
      failure_reason: 'multiple_payment_failures',
      failed_at: Time.current
    )

    # Send final failure notifications
    send_final_failure_notification(payment)
    send_account_suspension_notification(account)
    
    # Alert admin team
    send_admin_failure_alert(payment)
  end

  def schedule_next_retry(payment, next_attempt)
    # Exponential backoff: 1 day, 3 days, 5 days, 7 days
    retry_delays = [1.day, 3.days, 5.days, 7.days]
    delay = retry_delays[next_attempt - 1] || 7.days
    
    PaymentRetryJob.set(wait: delay).perform_later(payment.id, next_attempt)
    
    Rails.logger.info "Scheduled payment retry #{next_attempt} for payment #{payment.id} in #{delay.inspect}"
  end

  def advance_billing_period(subscription)
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
  end

  def update_dunning_status(subscription, retry_attempt)
    return unless subscription

    dunning_level = case retry_attempt
                   when 1
                     'soft_dunning'
                   when 2..3
                     'hard_dunning'
                   else
                     'final_dunning'
                   end

    subscription.update!(
      metadata: subscription.metadata.merge(
        dunning_level: dunning_level,
        last_dunning_attempt: Time.current.iso8601
      )
    )
  end

  # Notification methods
  def send_retry_success_notification(payment)
    Rails.logger.info "Sending payment retry success notification for payment #{payment.id}"
    # Implementation would integrate with email service
  end

  def send_final_failure_notification(payment)
    Rails.logger.info "Sending final payment failure notification for payment #{payment.id}"
    # Implementation would integrate with email service
  end

  def send_account_suspension_notification(account)
    Rails.logger.info "Sending account suspension notification for account #{account.id}"
    # Implementation would integrate with email service
  end

  def send_admin_failure_alert(payment)
    Rails.logger.error "ADMIN ALERT: Final payment failure for payment #{payment.id}"
    # Implementation would send urgent alert to admin team
  end
end