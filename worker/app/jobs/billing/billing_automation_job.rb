# frozen_string_literal: true

require_relative '../base_job'

# Converted from BillingAutomationJob to use API-only connectivity
# Handles subscription lifecycle management including trials, renewals, and billing automation
class Billing::BillingAutomationJob < BaseJob
  sidekiq_options queue: 'billing',
                  retry: 3

  def execute(subscription_id = nil)
    logger.info "Starting billing automation cycle at #{Time.current}"
    
    if subscription_id
      # Process specific subscription
      process_subscription(subscription_id)
    else
      # Process all subscriptions that need renewal
      process_subscriptions_needing_renewal
    end
    
    logger.info "Completed billing automation cycle at #{Time.current}"
  end

  private

  def process_subscriptions_needing_renewal
    # Get subscriptions needing renewal via API
    current_date = Date.current
    renewal_params = {
      status: ['active', 'trialing', 'past_due'],
      current_period_end_lte: current_date.end_of_day.iso8601,
      account_status: 'active',
      include: 'plan,account'
    }
    
    subscriptions = with_api_retry do
      api_client.get('/api/v1/subscriptions', renewal_params)
    end

    logger.info "Found #{subscriptions.size} subscriptions needing renewal"

    subscriptions.each do |subscription_data|
      process_subscription(subscription_data['id'])
    end
  end

  def process_subscription(subscription_id)
    subscription = with_api_retry do
      api_client.get("/api/v1/subscriptions/#{subscription_id}")
    end
    
    return unless subscription

    logger.info "Processing subscription #{subscription['id']} for account #{subscription.dig('account', 'name')}"

    begin
      case subscription['status']
      when 'trialing'
        handle_trial_ending(subscription)
      when 'active', 'past_due'
        handle_subscription_renewal(subscription)
      end
    rescue StandardError => e
      logger.error "Failed to process subscription #{subscription['id']}: #{e.message}"
      
      # Schedule retry for later
      Billing::BillingAutomationJob.perform_in(1.hour, subscription_id)
      
      # Send alert via API
      send_billing_failure_alert(subscription, e.message)
    end
  end

  def handle_trial_ending(subscription)
    trial_end = subscription['trial_end'] ? Time.parse(subscription['trial_end']) : nil
    return unless trial_end && trial_end <= Time.current

    logger.info "Trial ending for subscription #{subscription['id']}"

    # Get account payment methods via API
    payment_methods = with_api_retry do
      api_client.get("/api/v1/accounts/#{subscription['account_id']}/payment_methods", { default: true, active: true })
    end
    
    if payment_methods.empty?
      # No payment method - convert trial to grace period
      update_params = {
        status: 'past_due',
        current_period_start: Time.current.iso8601,
        current_period_end: 3.days.from_now.iso8601,
        metadata: subscription['metadata'].merge(
          'trial_ended_at' => Time.current.iso8601,
          'grace_period_ends' => 3.days.from_now.iso8601
        )
      }
      
      with_api_retry do
        api_client.patch("/api/v1/subscriptions/#{subscription['id']}", update_params)
      end
      
      send_payment_method_required_notification(subscription)
      return
    end

    # Generate first invoice and attempt payment via API
    begin
      invoice_params = {
        subscription_id: subscription['id'],
        invoice_type: 'trial_conversion',
        description: "Trial conversion for #{subscription.dig('plan', 'name')}"
      }
      
      invoice_result = with_api_retry do
        api_client.post('/api/v1/billing/generate_invoice', invoice_params)
      end
      
      payment_params = {
        invoice_id: invoice_result['id'],
        payment_method_id: payment_methods.first['id'],
        description: "Trial conversion payment"
      }
      
      payment_result = with_api_retry do
        api_client.post('/api/v1/billing/process_payment', payment_params)
      end
      
      if payment_result['success']
        # Successful payment - convert to active
        update_params = {
          status: 'active',
          current_period_start: Time.current.iso8601,
          current_period_end: calculate_new_period_end(subscription).iso8601
        }
        
        with_api_retry do
          api_client.patch("/api/v1/subscriptions/#{subscription['id']}", update_params)
        end
        
        send_trial_conversion_success_notification(subscription)
      else
        # Payment failed - handle according to retry policy
        with_api_retry do
          api_client.patch("/api/v1/subscriptions/#{subscription['id']}", { status: 'past_due' })
        end
        
        # Schedule payment retry
        Billing::PaymentRetryJob.perform_in(1.hour, subscription['id'], 'trial_conversion_failure')
      end
    rescue StandardError => e
      logger.error "Failed to process trial ending for subscription #{subscription['id']}: #{e.message}"
      
      with_api_retry do
        api_client.patch("/api/v1/subscriptions/#{subscription['id']}", { status: 'past_due' })
      end
      
      raise
    end
  end

  def handle_subscription_renewal(subscription)
    logger.info "Processing renewal for subscription #{subscription['id']}"

    # Get account payment methods via API
    payment_methods = with_api_retry do
      api_client.get("/api/v1/accounts/#{subscription['account_id']}/payment_methods", { default: true, active: true })
    end

    return if payment_methods.empty?

    begin
      # Generate renewal invoice via API
      invoice_params = {
        subscription_id: subscription['id'],
        invoice_type: 'subscription_renewal',
        description: "Subscription renewal for #{subscription.dig('plan', 'name')}"
      }
      
      invoice_result = with_api_retry do
        api_client.post('/api/v1/billing/generate_invoice', invoice_params)
      end
      
      # Attempt payment collection via API
      payment_params = {
        invoice_id: invoice_result['id'],
        payment_method_id: payment_methods.first['id'],
        description: "Subscription renewal payment"
      }
      
      payment_result = with_api_retry do
        api_client.post('/api/v1/billing/process_payment', payment_params)
      end
      
      if payment_result['success']
        # Successful payment - advance billing period
        new_period_end = calculate_new_period_end(subscription)
        update_params = {
          current_period_start: subscription['current_period_end'],
          current_period_end: new_period_end.iso8601,
          last_billing_date: Time.current.iso8601
        }
        
        # Reactivate if was past due
        if subscription['status'] == 'past_due'
          update_params[:status] = 'active'
        end
        
        with_api_retry do
          api_client.patch("/api/v1/subscriptions/#{subscription['id']}", update_params)
        end
        
        if subscription['status'] == 'past_due'
          send_reactivation_notification(subscription)
        end
        
        send_renewal_success_notification(subscription, invoice_result)
        
      else
        # Payment failed - schedule retry
        Billing::PaymentRetryJob.perform_in(1.hour, subscription['id'], 'renewal_failure')
        send_payment_failure_notification(subscription, payment_result)
      end
      
    rescue StandardError => e
      logger.error "Failed to process renewal for subscription #{subscription['id']}: #{e.message}"
      raise
    end
  end

  def calculate_new_period_end(subscription)
    current_end = Time.parse(subscription['current_period_end'])
    
    case subscription.dig('plan', 'billing_cycle')
    when 'monthly'
      current_end + 1.month
    when 'quarterly'
      current_end + 3.months
    when 'yearly'
      current_end + 1.year
    else
      current_end + 1.month
    end
  end

  # Notification methods (API-based)
  def send_payment_method_required_notification(subscription)
    notification_params = {
      type: 'payment_method_required',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: 'Payment method required for subscription renewal',
      severity: 'high'
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent payment method required notification for subscription #{subscription['id']}"
  rescue StandardError => e
    logger.error "Failed to send payment method notification: #{e.message}"
  end

  def send_trial_conversion_success_notification(subscription)
    notification_params = {
      type: 'trial_converted',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: 'Trial successfully converted to paid subscription',
      severity: 'info'
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent trial conversion success notification for subscription #{subscription['id']}"
  rescue StandardError => e
    logger.error "Failed to send trial conversion notification: #{e.message}"
  end

  def send_renewal_success_notification(subscription, invoice)
    notification_params = {
      type: 'renewal_success',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      invoice_id: invoice['id'],
      message: 'Subscription renewed successfully',
      severity: 'info'
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent renewal success notification for subscription #{subscription['id']}"
  rescue StandardError => e
    logger.error "Failed to send renewal notification: #{e.message}"
  end

  def send_payment_failure_notification(subscription, payment_result)
    notification_params = {
      type: 'payment_failed',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Payment failed: #{payment_result['error']}",
      severity: 'warning'
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent payment failure notification for subscription #{subscription['id']}"
  rescue StandardError => e
    logger.error "Failed to send payment failure notification: #{e.message}"
  end

  def send_reactivation_notification(subscription)
    notification_params = {
      type: 'subscription_reactivated',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: 'Subscription reactivated after successful payment',
      severity: 'info'
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', notification_params)
    end
    
    logger.info "Sent reactivation notification for subscription #{subscription['id']}"
  rescue StandardError => e
    logger.error "Failed to send reactivation notification: #{e.message}"
  end

  def send_billing_failure_alert(subscription, error_message)
    alert_params = {
      type: 'billing_automation_failure',
      account_id: subscription['account_id'],
      subscription_id: subscription['id'],
      message: "Billing automation failed: #{error_message}",
      severity: 'critical',
      admin_alert: true
    }
    
    with_api_retry do
      api_client.post('/api/v1/notifications', alert_params)
    end
    
    logger.error "ADMIN ALERT: Billing failure for subscription #{subscription['id']}: #{error_message}"
  rescue StandardError => e
    logger.error "Failed to send billing failure alert: #{e.message}"
  end
end