class BillingCleanupJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "Starting billing cleanup and maintenance"
    
    begin
      # Clean up old failed payments
      cleanup_old_failed_payments
      
      # Clean up expired invoices
      cleanup_expired_invoices
      
      # Update subscription metrics
      update_subscription_metrics
      
      # Cleanup orphaned payment methods
      cleanup_orphaned_payment_methods
      
      # Update account suspension status
      update_account_suspension_status
      
      # Generate billing health report
      generate_billing_health_report
      
      Rails.logger.info "Billing cleanup completed successfully"
      
    rescue => e
      Rails.logger.error "Billing cleanup failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end

  private

  def cleanup_old_failed_payments
    # Remove failed payment records older than 90 days
    cutoff_date = 90.days.ago
    
    old_failed_payments = Payment.where(status: 'failed')
                                 .where('created_at < ?', cutoff_date)
    
    count = old_failed_payments.count
    old_failed_payments.delete_all
    
    Rails.logger.info "Cleaned up #{count} old failed payments"
  end

  def cleanup_expired_invoices
    # Mark invoices as expired if they're 60+ days overdue
    cutoff_date = 60.days.ago
    
    expired_invoices = Invoice.where(status: 'open')
                             .where('due_date < ?', cutoff_date)
    
    expired_invoices.find_each do |invoice|
      invoice.update!(
        status: 'void',
        voided_at: Time.current,
        void_reason: 'expired_overdue'
      )
    end
    
    Rails.logger.info "Marked #{expired_invoices.count} invoices as expired"
  end

  def update_subscription_metrics
    # Calculate and cache subscription metrics for faster reporting
    
    # Active subscriptions by plan
    active_by_plan = Subscription.joins(:plan)
                                .where(status: 'active')
                                .group('plans.name')
                                .count
    
    # MRR by plan
    mrr_by_plan = Subscription.joins(:plan)
                             .where(status: 'active')
                             .group('plans.name')
                             .sum('plans.price_cents * subscriptions.quantity')
    
    # Trial conversion rates
    trial_conversions = calculate_trial_conversion_rates
    
    # Cache metrics
    Rails.cache.write('subscription_metrics', {
      active_by_plan: active_by_plan,
      mrr_by_plan: mrr_by_plan,
      trial_conversions: trial_conversions,
      updated_at: Time.current
    }, expires_in: 24.hours)
    
    Rails.logger.info "Updated subscription metrics cache"
  end

  def cleanup_orphaned_payment_methods
    # Remove payment methods for cancelled accounts older than 30 days
    cutoff_date = 30.days.ago
    
    orphaned_payment_methods = PaymentMethod.joins(:account)
                                           .where(accounts: { status: 'cancelled' })
                                           .where('accounts.updated_at < ?', cutoff_date)
    
    count = orphaned_payment_methods.count
    
    orphaned_payment_methods.find_each do |payment_method|
      # Cancel in payment gateway first
      cancel_payment_method_in_gateway(payment_method)
      # Then remove from database
      payment_method.destroy
    end
    
    Rails.logger.info "Cleaned up #{count} orphaned payment methods"
  end

  def update_account_suspension_status
    # Check accounts that have been suspended for payment issues
    # and have since added valid payment methods
    
    suspended_accounts = Account.where(status: 'suspended', suspension_reason: 'payment_failure')
    
    suspended_accounts.find_each do |account|
      # Check if account now has valid payment method and active subscription
      has_valid_payment = account.payment_methods.active.exists?
      has_active_subscription = account.subscriptions.active.exists?
      
      if has_valid_payment && has_active_subscription
        # Reactivate account
        account.update!(
          status: 'active',
          suspended_at: nil,
          suspension_reason: nil,
          reactivated_at: Time.current
        )
        
        Rails.logger.info "Reactivated account #{account.id} after payment resolution"
        
        # Send reactivation notification
        send_account_reactivation_notification(account)
      end
    end
  end

  def generate_billing_health_report
    # Generate comprehensive billing system health report
    
    report_data = {
      timestamp: Time.current,
      
      # Payment success rates
      payment_success_rate: calculate_payment_success_rate,
      
      # Subscription health
      subscription_health: calculate_subscription_health,
      
      # Revenue metrics
      revenue_metrics: calculate_revenue_metrics,
      
      # Failed payment analysis
      failed_payment_analysis: analyze_failed_payments,
      
      # Trial conversion metrics
      trial_metrics: calculate_trial_metrics,
      
      # Dunning effectiveness
      dunning_metrics: calculate_dunning_metrics
    }
    
    # Store report
    Rails.cache.write('billing_health_report', report_data, expires_in: 7.days)
    
    # Send to admin if there are issues
    if report_data[:payment_success_rate] < 0.95 || 
       report_data[:subscription_health][:churn_rate] > 0.10
      send_billing_health_alert(report_data)
    end
    
    Rails.logger.info "Generated billing health report"
  end

  def calculate_trial_conversion_rates
    # Calculate conversion rates for trials that ended in the last 30 days
    cutoff_date = 30.days.ago
    
    ended_trials = Subscription.where('trial_end BETWEEN ? AND ?', cutoff_date, Time.current)
    converted_trials = ended_trials.where(status: ['active', 'past_due'])
    
    total = ended_trials.count
    converted = converted_trials.count
    
    {
      total_trials_ended: total,
      converted_to_paid: converted,
      conversion_rate: total > 0 ? (converted.to_f / total * 100).round(2) : 0
    }
  end

  def cancel_payment_method_in_gateway(payment_method)
    case payment_method.provider
    when 'stripe'
      if payment_method.provider_payment_method_id
        begin
          Stripe::PaymentMethod.detach(payment_method.provider_payment_method_id)
        rescue Stripe::StripeError => e
          Rails.logger.warn "Failed to detach Stripe payment method #{payment_method.id}: #{e.message}"
        end
      end
    when 'paypal'
      # PayPal payment method cancellation would go here
      Rails.logger.info "PayPal payment method cleanup not implemented"
    end
  end

  def calculate_payment_success_rate
    last_30_days = Payment.where('created_at > ?', 30.days.ago)
    total_payments = last_30_days.count
    successful_payments = last_30_days.where(status: 'succeeded').count
    
    return 1.0 if total_payments == 0
    
    (successful_payments.to_f / total_payments).round(4)
  end

  def calculate_subscription_health
    total_subscriptions = Subscription.count
    active_subscriptions = Subscription.where(status: 'active').count
    past_due_subscriptions = Subscription.where(status: 'past_due').count
    cancelled_last_month = Subscription.where(status: 'cancelled')
                                      .where('updated_at > ?', 30.days.ago)
                                      .count
    
    churn_rate = total_subscriptions > 0 ? (cancelled_last_month.to_f / total_subscriptions).round(4) : 0
    
    {
      total: total_subscriptions,
      active: active_subscriptions,
      past_due: past_due_subscriptions,
      churn_rate: churn_rate
    }
  end

  def calculate_revenue_metrics
    current_month_start = Date.current.beginning_of_month
    last_month_start = 1.month.ago.beginning_of_month
    last_month_end = last_month_start.end_of_month
    
    current_mrr = Subscription.joins(:plan)
                             .where(status: 'active')
                             .sum('plans.price_cents * subscriptions.quantity')
    
    last_month_revenue = Payment.where(status: 'succeeded')
                               .where(created_at: last_month_start..last_month_end)
                               .sum(:amount_cents)
    
    {
      current_mrr_cents: current_mrr,
      last_month_revenue_cents: last_month_revenue
    }
  end

  def analyze_failed_payments
    last_30_days = Payment.where('created_at > ?', 30.days.ago)
    failed_payments = last_30_days.where(status: 'failed')
    
    failure_reasons = failed_payments.group(:failure_reason).count
    failure_by_gateway = failed_payments.joins(:payment_method)
                                       .group('payment_methods.provider')
                                       .count
    
    {
      total_failed: failed_payments.count,
      failure_reasons: failure_reasons,
      failure_by_gateway: failure_by_gateway
    }
  end

  def calculate_trial_metrics
    active_trials = Subscription.where(status: 'trialing').count
    trials_ending_soon = Subscription.where(status: 'trialing')
                                    .where('trial_end BETWEEN ? AND ?', Time.current, 7.days.from_now)
                                    .count
    
    {
      active_trials: active_trials,
      ending_in_7_days: trials_ending_soon
    }
  end

  def calculate_dunning_metrics
    past_due_subs = Subscription.where(status: 'past_due')
    
    # Group by dunning level from metadata
    dunning_levels = past_due_subs.group("metadata->>'dunning_level'").count
    
    {
      total_past_due: past_due_subs.count,
      by_dunning_level: dunning_levels
    }
  end

  def send_account_reactivation_notification(account)
    Rails.logger.info "Sending account reactivation notification for account #{account.id}"
    # Implementation would integrate with email service
  end

  def send_billing_health_alert(report_data)
    Rails.logger.warn "ADMIN ALERT: Billing health issues detected"
    Rails.logger.warn "Payment success rate: #{report_data[:payment_success_rate]}"
    Rails.logger.warn "Churn rate: #{report_data[:subscription_health][:churn_rate]}"
    # Implementation would send alert to admin team
  end
end