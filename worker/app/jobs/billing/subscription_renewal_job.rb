# frozen_string_literal: true

require_relative '../base_job'

# Job for processing subscription renewals
# Handles automated billing cycles and renewal processing
class Billing::SubscriptionRenewalJob < BaseJob
  sidekiq_options queue: 'billing',
                  retry: 3

  def execute(subscription_id)
    # Idempotency check - prevent duplicate renewals on same day
    idempotency_key = "renewal:#{subscription_id}:#{Date.current}"
    if already_processed?(idempotency_key)
      log_info("Renewal already processed for subscription #{subscription_id} today, skipping")
      return { success: true, skipped: true, reason: 'already_processed' }
    end

    log_info("Processing renewal for subscription #{subscription_id}")
    
    # Get subscription details from backend
    subscription_data = begin
      with_api_retry do
        api_client.get("/api/v1/subscriptions/#{subscription_id}")
      end
    rescue BackendApiClient::ApiError => e
      if e.status == 404
        log_error("Subscription #{subscription_id} not found")
        raise ArgumentError, "Subscription not found: #{subscription_id}"
      end
      raise
    end

    unless subscription_data
      log_error("Subscription #{subscription_id} not found")
      raise ArgumentError, "Subscription not found: #{subscription_id}"
    end
    
    # Verify subscription is eligible for renewal
    unless eligible_for_renewal?(subscription_data)
      log_info("Subscription #{subscription_id} not eligible for renewal, skipping")
      return
    end
    
    account_data = with_api_retry do
      api_client.get_account(subscription_data['account_id'])
    end
    
    log_info("Processing renewal for account '#{account_data['name']}' (#{subscription_data['plan_name']})")
    
    # Process the renewal
    renewal_result = process_renewal(subscription_data, account_data)
    
    if renewal_result['success']
      log_info("Successfully renewed subscription #{subscription_id}")
      # Mark as processed to prevent duplicate renewals
      mark_processed(idempotency_key)
      schedule_next_renewal(subscription_id, renewal_result)
    else
      log_error("Failed to renew subscription #{subscription_id}: #{renewal_result['error']}")
      handle_renewal_failure(subscription_data, renewal_result)
    end

    renewal_result
  end
  
  private
  
  def eligible_for_renewal?(subscription_data)
    return false unless subscription_data['status'] == 'active'
    return false unless subscription_data['next_billing_date']
    
    next_billing_date = Date.parse(subscription_data['next_billing_date'])
    
    # Process renewals up to 1 day early
    next_billing_date <= Date.today + 1
  end
  
  def process_renewal(subscription_data, account_data)
    renewal_params = {
      subscription_id: subscription_data['id'],
      account_id: subscription_data['account_id'],
      amount_cents: subscription_data['price_cents'],
      currency: subscription_data['currency'] || 'USD',
      billing_cycle: subscription_data['billing_cycle'],
      metadata: {
        renewal_type: 'automated',
        processed_by: 'worker_service',
        processed_at: Time.now.iso8601
      }
    }
    
    with_api_retry(max_attempts: 2) do
      api_client.post('/api/v1/internal/billing/process_renewal', renewal_params)
    end
  rescue BackendApiClient::ApiError => e
    log_error("Renewal processing failed: #{e.message}")
    {
      'success' => false,
      'error' => e.message,
      'error_code' => e.status
    }
  end
  
  def schedule_next_renewal(subscription_id, renewal_result)
    return unless renewal_result['next_billing_date']
    
    next_billing_date = Date.parse(renewal_result['next_billing_date'])
    
    # Schedule the next renewal job for the billing date at 9 AM
    renewal_time = next_billing_date.to_time + 9.hours
    
    Billing::SubscriptionRenewalJob.perform_at(renewal_time, subscription_id)
    
    log_info("Scheduled next renewal for subscription #{subscription_id} at #{renewal_time}")
  rescue StandardError => e
    log_error("Failed to schedule next renewal for subscription #{subscription_id}: #{e.message}")
    # Don't fail the current renewal for scheduling errors
  end
  
  def handle_renewal_failure(subscription_data, renewal_result)
    # Determine failure type and appropriate action
    case renewal_result['error_code']
    when 402, 403 # Payment failed or insufficient funds
      schedule_payment_retry(subscription_data)
    when 404 # Payment method not found
      notify_payment_method_required(subscription_data)
    when 422 # Validation error
      log_error("Subscription renewal validation failed: #{renewal_result['error']}")
      # Don't retry validation errors
    else
      # Generic failure - schedule retry
      schedule_renewal_retry(subscription_data)
    end
  end
  
  def schedule_payment_retry(subscription_data)
    # Schedule payment retry in 3 days
    retry_time = Time.now + (3 * 24 * 60 * 60) + (9 * 60 * 60) # 3 days + 9 hours
    
    Billing::PaymentRetryJob.perform_at(retry_time, subscription_data['id'], 'renewal_failure')
    
    log_info("Scheduled payment retry for subscription #{subscription_data['id']} at #{retry_time}")
  end
  
  def notify_payment_method_required(subscription_data)
    notification_params = {
      type: 'payment_method_required',
      account_id: subscription_data['account_id'],
      subscription_id: subscription_data['id'],
      message: 'Payment method required for subscription renewal',
      severity: 'high'
    }
    
    # Send notification via backend API
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    log_info("Sent payment method required notification for subscription #{subscription_data['id']}")
  rescue StandardError => e
    log_error("Failed to send payment method notification: #{e.message}")
  end
  
  def schedule_renewal_retry(subscription_data)
    # Retry in 1 hour for generic failures
    retry_time = Time.now + (60 * 60) # 1 hour
    
    Billing::SubscriptionRenewalJob.perform_at(retry_time, subscription_data['id'])
    
    log_info("Scheduled renewal retry for subscription #{subscription_data['id']} at #{retry_time}")
  end
end