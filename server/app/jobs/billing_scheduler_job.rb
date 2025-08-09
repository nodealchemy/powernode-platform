class BillingSchedulerJob < ApplicationJob
  queue_as :billing_scheduler

  # This job runs daily to schedule billing and lifecycle events
  def perform(date = Date.current)
    Rails.logger.info "Running billing scheduler for #{date}"
    
    begin
      # Schedule billing automation for subscriptions ending today
      schedule_billing_automation(date)
      
      # Schedule trial ending reminders
      schedule_trial_ending_reminders(date)
      
      # Schedule renewal reminders
      schedule_renewal_reminders(date)
      
      # Schedule payment method expiration checks
      schedule_payment_method_checks(date)
      
      # Schedule subscription lifecycle maintenance
      schedule_lifecycle_maintenance(date)
      
      Rails.logger.info "Billing scheduler completed successfully for #{date}"
      
    rescue => e
      Rails.logger.error "Billing scheduler failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end

  private

  def schedule_billing_automation(date)
    # Find subscriptions that need renewal processing
    subscriptions_due = Subscription.joins(:account)
                                   .where(status: ['active', 'trialing', 'past_due'])
                                   .where('current_period_end::date = ?', date)
                                   .where(accounts: { status: 'active' })

    Rails.logger.info "Scheduling billing automation for #{subscriptions_due.count} subscriptions"

    subscriptions_due.find_each do |subscription|
      # Schedule billing automation with slight delay to spread load
      delay = rand(0..3600) # Random delay up to 1 hour
      BillingAutomationJob.set(wait: delay.seconds).perform_later(subscription.id)
    end
  end

  def schedule_trial_ending_reminders(date)
    # Schedule reminders for trials ending in 7, 3, and 1 days
    [7, 3, 1].each do |days_ahead|
      reminder_date = date + days_ahead.days
      
      trials_ending = Subscription.joins(:account)
                                 .where(status: 'trialing')
                                 .where('trial_end::date = ?', reminder_date)
                                 .where(accounts: { status: 'active' })

      Rails.logger.info "Scheduling #{trials_ending.count} trial ending reminders for #{days_ahead} days ahead"

      trials_ending.find_each do |subscription|
        SubscriptionLifecycleJob.perform_later('trial_ending_reminder', subscription.id)
      end
    end
  end

  def schedule_renewal_reminders(date)
    # Schedule reminders for renewals in 7, 3, and 1 days
    [7, 3, 1].each do |days_ahead|
      renewal_date = date + days_ahead.days
      
      subscriptions_renewing = Subscription.joins(:account)
                                          .where(status: ['active', 'past_due'])
                                          .where('current_period_end::date = ?', renewal_date)
                                          .where(accounts: { status: 'active' })

      Rails.logger.info "Scheduling #{subscriptions_renewing.count} renewal reminders for #{days_ahead} days ahead"

      subscriptions_renewing.find_each do |subscription|
        SubscriptionLifecycleJob.perform_later('renewal_reminder', subscription.id)
      end
    end
  end

  def schedule_payment_method_checks(date)
    # Check for payment methods expiring in the next 30 days
    expiring_soon = PaymentMethod.joins(account: :subscriptions)
                                 .where(status: 'active')
                                 .where('expires_at BETWEEN ? AND ?', date, date + 30.days)
                                 .where(subscriptions: { status: ['active', 'trialing', 'past_due'] })

    Rails.logger.info "Found #{expiring_soon.count} payment methods expiring in next 30 days"

    expiring_soon.find_each do |payment_method|
      days_until_expiry = (payment_method.expires_at.to_date - date).to_i
      
      # Send reminder at 30, 14, and 7 days before expiry
      if [30, 14, 7].include?(days_until_expiry)
        payment_method.account.subscriptions.active.each do |subscription|
          SubscriptionLifecycleJob.perform_later(
            'payment_method_update_required',
            subscription.id,
            reason: 'expiring_soon',
            days_until_expiry: days_until_expiry
          )
        end
      end
    end

    # Handle expired payment methods
    expired_today = PaymentMethod.joins(account: :subscriptions)
                                 .where(status: 'active')
                                 .where('expires_at::date = ?', date)
                                 .where(subscriptions: { status: ['active', 'trialing', 'past_due'] })

    Rails.logger.info "Found #{expired_today.count} payment methods expiring today"

    expired_today.find_each do |payment_method|
      # Mark as expired
      payment_method.update!(
        status: 'expired',
        expired_at: Time.current
      )

      # Notify affected subscriptions
      payment_method.account.subscriptions.active.each do |subscription|
        SubscriptionLifecycleJob.perform_later(
          'payment_method_update_required',
          subscription.id,
          reason: 'expired'
        )
      end
    end
  end

  def schedule_lifecycle_maintenance(date)
    # Handle subscriptions in grace period
    grace_period_ending = Subscription.joins(:account)
                                     .where(status: 'past_due')
                                     .where(accounts: { status: 'active' })
                                     .where("metadata->>'payment_method_grace_period_end' IS NOT NULL")
                                     .where("(metadata->>'payment_method_grace_period_end')::timestamp <= ?", date.end_of_day)

    Rails.logger.info "Found #{grace_period_ending.count} subscriptions with grace period ending"

    grace_period_ending.find_each do |subscription|
      SubscriptionLifecycleJob.perform_later('grace_period_ending', subscription.id)
    end

    # Handle long-overdue subscriptions (past due for more than 14 days)
    overdue_subscriptions = Subscription.joins(:account)
                                       .where(status: 'past_due')
                                       .where('current_period_end < ?', date - 14.days)
                                       .where(accounts: { status: 'active' })

    Rails.logger.info "Found #{overdue_subscriptions.count} long-overdue subscriptions"

    overdue_subscriptions.find_each do |subscription|
      SubscriptionLifecycleJob.perform_later('subscription_expired', subscription.id, reason: 'long_overdue')
    end

    # Attempt reactivation for unpaid subscriptions with new payment methods
    reactivation_candidates = Subscription.joins(:account)
                                         .joins("JOIN payment_methods ON payment_methods.account_id = accounts.id")
                                         .where(status: 'unpaid')
                                         .where(payment_methods: { status: 'active' })
                                         .where('payment_methods.created_at > subscriptions.updated_at')

    Rails.logger.info "Found #{reactivation_candidates.count} subscriptions eligible for reactivation"

    reactivation_candidates.find_each do |subscription|
      SubscriptionLifecycleJob.set(wait: rand(0..3600).seconds)
                             .perform_later('reactivation_attempt', subscription.id)
    end
  end

  class << self
    def schedule_daily_run(date = Date.current)
      # Schedule this job to run daily at 2 AM UTC
      run_time = date.beginning_of_day + 2.hours
      
      if run_time > Time.current
        BillingSchedulerJob.set(wait_until: run_time).perform_later(date)
      else
        # If we've passed 2 AM today, schedule for tomorrow
        BillingSchedulerJob.set(wait_until: run_time + 1.day).perform_later(date + 1.day)
      end
    end

    def schedule_weekly_cleanup
      # Schedule weekly cleanup tasks for Sundays at 3 AM UTC
      next_sunday = Date.current.beginning_of_week + 6.days
      cleanup_time = next_sunday.beginning_of_day + 3.hours
      
      BillingCleanupJob.set(wait_until: cleanup_time).perform_later
    end
  end
end