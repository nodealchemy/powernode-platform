# frozen_string_literal: true

require_relative '../base_job'

# Job for retrying failed payments
# Implements dunning management with exponential backoff
class Billing::PaymentRetryJob < BaseJob
  sidekiq_options queue: 'billing',
                  retry: 1 # We handle retries manually

  MAX_RETRY_ATTEMPTS = 5
  RETRY_INTERVALS = [1.day, 3.days, 7.days, 14.days, 30.days].freeze

  def execute(subscription_id, failure_type = 'payment_failure', attempt_number = 1)
    logger.info "Payment retry attempt #{attempt_number}/#{MAX_RETRY_ATTEMPTS} for subscription #{subscription_id}"
    
    if attempt_number > MAX_RETRY_ATTEMPTS
      logger.error "Maximum retry attempts reached for subscription #{subscription_id}"
      handle_final_failure(subscription_id, failure_type)
      return
    end
    
    # Get subscription and account details
    subscription_data = with_api_retry do
      api_client.get("/api/v1/subscriptions/#{subscription_id}")
    end
    
    unless subscription_data
      logger.error "Subscription #{subscription_id} not found during retry"
      return
    end
    
    account_data = with_api_retry do
      api_client.get_account(subscription_data['account_id'])
    end
    
    logger.info "Retrying payment for account '#{account_data['name']}' (attempt #{attempt_number})"
    
    # Attempt payment retry
    retry_result = attempt_payment_retry(subscription_data, attempt_number)
    
    if retry_result['success']
      logger.info "Payment retry successful for subscription #{subscription_id}"
      handle_retry_success(subscription_data, retry_result, attempt_number)
    else
      logger.warn "Payment retry failed for subscription #{subscription_id}: #{retry_result['error']}"
      handle_retry_failure(subscription_id, failure_type, attempt_number, retry_result)
    end
    
    retry_result
  end
  
  private
  
  def attempt_payment_retry(subscription_data, attempt_number)
    retry_params = {
      subscription_id: subscription_data['id'],
      account_id: subscription_data['account_id'],
      amount_cents: subscription_data['price_cents'],
      currency: subscription_data['currency'] || 'USD',
      retry_attempt: attempt_number,
      metadata: {
        retry_type: 'dunning_management',
        attempt_number: attempt_number,
        processed_by: 'worker_service',
        processed_at: Time.current.iso8601
      }
    }
    
    with_api_retry(max_attempts: 1) do
      api_client.post('/api/v1/billing/retry_payment', retry_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Payment retry API call failed: #{e.message}"
    {
      'success' => false,
      'error' => e.message,
      'error_code' => e.status,
      'retryable' => retryable_payment_error?(e)
    }
  end
  
  def handle_retry_success(subscription_data, retry_result, attempt_number)
    # Log successful recovery
    logger.info "Subscription #{subscription_data['id']} recovered after #{attempt_number} attempts"
    
    # Send recovery notification
    send_recovery_notification(subscription_data, attempt_number)
    
    # If this was a renewal failure, schedule next renewal
    if retry_result['next_billing_date']
      schedule_next_renewal(subscription_data['id'], retry_result['next_billing_date'])
    end
  end
  
  def handle_retry_failure(subscription_id, failure_type, attempt_number, retry_result)
    # Check if error is retryable
    unless retry_result['retryable'] != false
      logger.info "Non-retryable error for subscription #{subscription_id}, stopping retries"
      handle_final_failure(subscription_id, failure_type)
      return
    end
    
    # Schedule next retry attempt
    next_attempt = attempt_number + 1
    
    if next_attempt <= MAX_RETRY_ATTEMPTS
      retry_interval = RETRY_INTERVALS[attempt_number - 1] || RETRY_INTERVALS.last
      next_retry_time = retry_interval.from_now
      
      Billing::PaymentRetryJob.perform_at(
        next_retry_time,
        subscription_id,
        failure_type,
        next_attempt
      )
      
      logger.info "Scheduled retry #{next_attempt} for subscription #{subscription_id} at #{next_retry_time}"
      
      # Send dunning email for this attempt
      send_dunning_notification(subscription_id, next_attempt)
    else
      handle_final_failure(subscription_id, failure_type)
    end
  end
  
  def handle_final_failure(subscription_id, failure_type)
    logger.error "Payment retry exhausted for subscription #{subscription_id}, suspending account"
    
    # Suspend the subscription
    suspension_params = {
      subscription_id: subscription_id,
      reason: 'payment_failure',
      suspend_type: 'dunning_failure',
      metadata: {
        final_attempt: true,
        processed_by: 'worker_service',
        suspended_at: Time.current.iso8601
      }
    }
    
    begin
      with_api_retry do
        api_client.post('/api/v1/billing/suspend_subscription', suspension_params)
      end
      
      logger.info "Successfully suspended subscription #{subscription_id}"
      
      # Send final notice notification
      send_final_notice_notification(subscription_id)
      
    rescue StandardError => e
      logger.error "Failed to suspend subscription #{subscription_id}: #{e.message}"
      raise # Re-raise to trigger job retry
    end
  end
  
  def send_recovery_notification(subscription_data, attempt_number)
    notification_params = {
      type: 'payment_recovered',
      account_id: subscription_data['account_id'],
      subscription_id: subscription_data['id'],
      message: "Payment successfully processed after #{attempt_number} attempts",
      severity: 'info',
      metadata: {
        recovery_attempt: attempt_number,
        recovery_date: Time.current.iso8601
      }
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent payment recovery notification for subscription #{subscription_data['id']}"
  rescue StandardError => e
    logger.error "Failed to send recovery notification: #{e.message}"
  end
  
  def send_dunning_notification(subscription_id, attempt_number)
    notification_params = {
      type: 'payment_retry_failed',
      subscription_id: subscription_id,
      message: "Payment attempt #{attempt_number} failed, will retry",
      severity: 'warning',
      metadata: {
        attempt_number: attempt_number,
        max_attempts: MAX_RETRY_ATTEMPTS,
        next_retry_date: (RETRY_INTERVALS[attempt_number - 1] || RETRY_INTERVALS.last).from_now.iso8601
      }
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent dunning notification #{attempt_number} for subscription #{subscription_id}"
  rescue StandardError => e
    logger.error "Failed to send dunning notification: #{e.message}"
  end
  
  def send_final_notice_notification(subscription_id)
    notification_params = {
      type: 'subscription_suspended',
      subscription_id: subscription_id,
      message: 'Subscription suspended due to payment failure',
      severity: 'critical',
      metadata: {
        suspension_reason: 'payment_failure',
        suspended_at: Time.current.iso8601
      }
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent final suspension notice for subscription #{subscription_id}"
  rescue StandardError => e
    logger.error "Failed to send final notice: #{e.message}"
  end
  
  def schedule_next_renewal(subscription_id, next_billing_date)
    renewal_date = Date.parse(next_billing_date)
    renewal_time = renewal_date.to_time + 9.hours
    
    Billing::SubscriptionRenewalJob.perform_at(renewal_time, subscription_id)
    
    logger.info "Scheduled next renewal for subscription #{subscription_id} at #{renewal_time}"
  rescue StandardError => e
    logger.error "Failed to schedule next renewal: #{e.message}"
  end
  
  def retryable_payment_error?(api_error)
    case api_error.status
    when 400, 401, 403, 404, 422
      false # Client errors are not retryable
    when 408, 429, 500, 502, 503, 504
      true # Timeout and server errors are retryable
    else
      true # Default to retryable for unknown errors
    end
  end
end