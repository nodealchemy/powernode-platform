# frozen_string_literal: true

require_relative '../base_job'

# Converted from BillingSchedulerJob to use API-only connectivity
# Schedules daily billing and lifecycle events
class Billing::BillingSchedulerJob < BaseJob
  sidekiq_options queue: 'billing_scheduler',
                  retry: 1

  def execute(date = Date.current)
    date = Date.parse(date) if date.is_a?(String)
    logger.info "Running billing scheduler for #{date}"
    
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
      
      logger.info "Billing scheduler completed successfully for #{date}"
      
    rescue StandardError => e
      logger.error "Billing scheduler failed: #{e.message}"
      raise
    end
  end

  private

  def schedule_billing_automation(date)
    # Get subscriptions due for renewal via API
    params = {
      status: ['active', 'trialing', 'past_due'],
      current_period_end_date: date.iso8601,
      account_status: 'active'
    }
    
    subscriptions_due = with_api_retry do
      api_client.get('/api/v1/subscriptions', params)
    end

    logger.info "Scheduling billing automation for #{subscriptions_due.size} subscriptions"

    subscriptions_due.each do |subscription|
      # Schedule billing automation with slight delay to spread load
      delay = rand(0..3600) # Random delay up to 1 hour
      Billing::BillingAutomationJob.perform_in(delay, subscription['id'])
    end
  end

  def schedule_trial_ending_reminders(date)
    # Schedule reminders for trials ending in 7, 3, and 1 days
    [7, 3, 1].each do |days_ahead|
      reminder_date = date + days_ahead.days
      
      params = {
        status: 'trialing',
        trial_end_date: reminder_date.iso8601,
        account_status: 'active'
      }
      
      trials_ending = with_api_retry do
        api_client.get('/api/v1/subscriptions', params)
      end

      logger.info "Scheduling #{trials_ending.size} trial ending reminders for #{days_ahead} days ahead"

      trials_ending.each do |subscription|
        Billing::SubscriptionLifecycleJob.perform_async(
          'trial_ending_reminder',
          subscription['id'],
          days_until_end: days_ahead
        )
      end
    end
  end

  def schedule_renewal_reminders(date)
    # Schedule reminders for renewals in 7, 3, and 1 days
    [7, 3, 1].each do |days_ahead|
      renewal_date = date + days_ahead.days
      
      params = {
        status: ['active', 'past_due'],
        current_period_end_date: renewal_date.iso8601,
        account_status: 'active'
      }
      
      subscriptions_renewing = with_api_retry do
        api_client.get('/api/v1/subscriptions', params)
      end

      logger.info "Scheduling #{subscriptions_renewing.size} renewal reminders for #{days_ahead} days ahead"

      subscriptions_renewing.each do |subscription|
        Billing::SubscriptionLifecycleJob.perform_async(
          'renewal_reminder',
          subscription['id'],
          days_until_renewal: days_ahead
        )
      end
    end
  end

  def schedule_payment_method_checks(date)
    # Get payment methods expiring in the next 30 days via API
    params = {
      expires_between: {
        start: date.iso8601,
        end: (date + 30.days).iso8601
      },
      status: 'active',
      has_active_subscriptions: true
    }
    
    expiring_soon = with_api_retry do
      api_client.get('/api/v1/payment_methods', params)
    end

    logger.info "Found #{expiring_soon.size} payment methods expiring in next 30 days"

    expiring_soon.each do |payment_method|
      expires_at = Date.parse(payment_method['expires_at'])
      days_until_expiry = (expires_at - date).to_i
      
      # Send reminder at 30, 14, and 7 days before expiry
      if [30, 14, 7].include?(days_until_expiry)
        # Get active subscriptions for this payment method
        subscription_params = {
          account_id: payment_method['account_id'],
          status: 'active'
        }
        
        subscriptions = with_api_retry do
          api_client.get('/api/v1/subscriptions', subscription_params)
        end
        
        subscriptions.each do |subscription|
          Billing::SubscriptionLifecycleJob.perform_async(
            'payment_method_update_required',
            subscription['id'],
            reason: 'expiring_soon',
            days_until_expiry: days_until_expiry
          )
        end
      end
    end

    # Handle payment methods expiring today via API
    expiring_today_params = {
      expires_on_date: date.iso8601,
      status: 'active',
      has_active_subscriptions: true
    }
    
    expired_today = with_api_retry do
      api_client.get('/api/v1/payment_methods', expiring_today_params)
    end

    logger.info "Found #{expired_today.size} payment methods expiring today"

    expired_today.each do |payment_method|
      # Request API to mark as expired
      with_api_retry do
        api_client.patch("/api/v1/payment_methods/#{payment_method['id']}", {
          status: 'expired',
          expired_at: Time.current.iso8601
        })
      end

      # Get affected subscriptions
      subscription_params = {
        account_id: payment_method['account_id'],
        status: 'active'
      }
      
      subscriptions = with_api_retry do
        api_client.get('/api/v1/subscriptions', subscription_params)
      end
      
      subscriptions.each do |subscription|
        Billing::SubscriptionLifecycleJob.perform_async(
          'payment_method_update_required',
          subscription['id'],
          reason: 'expired'
        )
      end
    end
  end

  def schedule_lifecycle_maintenance(date)
    # Handle subscriptions in grace period ending today
    grace_period_params = {
      status: 'past_due',
      account_status: 'active',
      grace_period_ending_on: date.iso8601
    }
    
    grace_period_ending = with_api_retry do
      api_client.get('/api/v1/subscriptions', grace_period_params)
    end

    logger.info "Found #{grace_period_ending.size} subscriptions with grace period ending"

    grace_period_ending.each do |subscription|
      Billing::SubscriptionLifecycleJob.perform_async('grace_period_ending', subscription['id'])
    end

    # Handle long-overdue subscriptions (past due for more than 14 days)
    overdue_params = {
      status: 'past_due',
      current_period_end_before: (date - 14.days).iso8601,
      account_status: 'active'
    }
    
    overdue_subscriptions = with_api_retry do
      api_client.get('/api/v1/subscriptions', overdue_params)
    end

    logger.info "Found #{overdue_subscriptions.size} long-overdue subscriptions"

    overdue_subscriptions.each do |subscription|
      Billing::SubscriptionLifecycleJob.perform_async(
        'subscription_expired',
        subscription['id'],
        reason: 'long_overdue'
      )
    end

    # Find subscriptions eligible for reactivation
    reactivation_params = {
      status: 'unpaid',
      account_has_new_payment_method: true
    }
    
    reactivation_candidates = with_api_retry do
      api_client.get('/api/v1/subscriptions', reactivation_params)
    end

    logger.info "Found #{reactivation_candidates.size} subscriptions eligible for reactivation"

    reactivation_candidates.each do |subscription|
      delay = rand(0..3600) # Random delay up to 1 hour
      Billing::SubscriptionLifecycleJob.perform_in(
        delay,
        'reactivation_attempt',
        subscription['id']
      )
    end
  end
end