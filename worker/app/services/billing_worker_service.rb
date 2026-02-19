# frozen_string_literal: true

require_relative 'base_worker_service'

class BillingWorkerService < BaseWorkerService
  # Create subscription with payment method via API
  def create_subscription_with_payment(plan_id:, payment_method_id:, account_id:, user_id:, trial_end: nil, quantity: 1, **options)
    log_info("Creating subscription with payment", plan_id: plan_id, account_id: account_id)

    begin
      # Get plan details
      plan_response = api_client.get("/api/v1/plans/#{plan_id}")
      unless plan_response[:success]
        return { success: false, error: "Plan not found" }
      end
      plan = plan_response[:data]

      # Get payment method details
      payment_method_response = api_client.get("/api/v1/payment_methods/#{payment_method_id}")
      unless payment_method_response[:success]
        return { success: false, error: "Payment method not found" }
      end
      payment_method = payment_method_response[:data]

      # Calculate subscription details
      current_period_end = calculate_period_end(plan, trial_end)
      is_trial = trial_end.present? || (plan['trial_days'] && plan['trial_days'] > 0)

      subscription_data = {
        plan_id: plan_id,
        account_id: account_id,
        user_id: user_id,
        quantity: quantity,
        trial_end: trial_end || (plan['trial_days'] ? plan['trial_days'].days.from_now.iso8601 : nil),
        current_period_start: Time.current.iso8601,
        current_period_end: current_period_end,
        status: is_trial ? "trialing" : "active",
        metadata: options
      }

      # Create subscription in gateway
      case payment_method['provider']
      when "stripe"
        result = create_stripe_subscription(subscription_data, payment_method, options)
      when "paypal"
        result = create_paypal_subscription(subscription_data, payment_method, options)
      else
        return { success: false, error: "Unsupported payment provider" }
      end

      if result[:success]
        # Create subscription record via API
        subscription_response = api_client.post("/api/v1/subscriptions", subscription_data.merge(
          stripe_subscription_id: result[:stripe_subscription_id],
          paypal_agreement_id: result[:paypal_agreement_id]
        ))

        if subscription_response[:success]
          log_info("Subscription created successfully", subscription_id: subscription_response[:data]['id'])
          { success: true, subscription: subscription_response[:data] }
        else
          log_error("Failed to create subscription record", nil, error: subscription_response[:error])
          { success: false, error: subscription_response[:error] }
        end
      else
        log_error("Failed to create gateway subscription", nil, error: result[:error])
        result
      end

    rescue => e
      log_error("Subscription creation failed", e, plan_id: plan_id, account_id: account_id)
      { success: false, error: e.message }
    end
  end

  # Process subscription renewal via API
  def process_renewal(subscription_id:, payment_retry_attempt: 0)
    log_info("Processing subscription renewal", subscription_id: subscription_id, retry_attempt: payment_retry_attempt)

    begin
      # Get subscription details
      subscription_response = api_client.get("/api/v1/subscriptions/#{subscription_id}")
      unless subscription_response[:success]
        return { success: false, error: "Subscription not found" }
      end
      subscription = subscription_response[:data]

      # Check if renewal is due
      unless renewal_due?(subscription)
        log_info("Renewal not due yet", subscription_id: subscription_id, next_billing: subscription['current_period_end'])
        return { success: true, message: "Renewal not due" }
      end

      # Get account and plan details
      account_response = api_client.get("/api/v1/accounts/#{subscription['account_id']}")
      plan_response = api_client.get("/api/v1/plans/#{subscription['plan_id']}")

      unless account_response[:success] && plan_response[:success]
        return { success: false, error: "Failed to load account or plan details" }
      end

      account = account_response[:data]
      plan = plan_response[:data]

      # Calculate renewal amount with proration
      renewal_amount = calculate_renewal_amount(subscription, plan)

      # Process payment based on provider
      if subscription['stripe_subscription_id']
        result = process_stripe_renewal(subscription, renewal_amount, payment_retry_attempt)
      elsif subscription['paypal_agreement_id']
        result = process_paypal_renewal(subscription, renewal_amount, payment_retry_attempt)
      else
        return { success: false, error: "No payment method configured" }
      end

      if result[:success]
        # Update subscription period
        next_period_end = calculate_next_period_end(subscription, plan)
        
        update_data = {
          current_period_start: subscription['current_period_end'],
          current_period_end: next_period_end,
          status: 'active',
          last_renewal_at: Time.current.iso8601
        }

        api_client.patch("/api/v1/subscriptions/#{subscription_id}", update_data)

        # Create audit log
        create_audit_log(
          account_id: subscription['account_id'],
          action: 'renew',
          resource_type: 'Subscription',
          resource_id: subscription_id,
          metadata: { 
            amount: renewal_amount,
            period_end: next_period_end,
            retry_attempt: payment_retry_attempt
          }
        )

        log_info("Subscription renewed successfully", subscription_id: subscription_id, amount: renewal_amount)
        { success: true, subscription: subscription, amount: renewal_amount }
      else
        # Handle failed renewal
        handle_renewal_failure(subscription_id, result[:error], payment_retry_attempt)
      end

    rescue => e
      log_error("Renewal processing failed", e, subscription_id: subscription_id)
      { success: false, error: e.message }
    end
  end

  # Cancel subscription
  def cancel_subscription(subscription_id:, cancellation_reason: nil, immediate: false)
    log_info("Canceling subscription", subscription_id: subscription_id, immediate: immediate)

    begin
      # Get subscription details
      subscription_response = api_client.get("/api/v1/subscriptions/#{subscription_id}")
      unless subscription_response[:success]
        return { success: false, error: "Subscription not found" }
      end
      subscription = subscription_response[:data]

      # Cancel in gateway
      if subscription['stripe_subscription_id']
        gateway_result = cancel_stripe_subscription(subscription['stripe_subscription_id'], immediate)
      elsif subscription['paypal_agreement_id']
        gateway_result = cancel_paypal_subscription(subscription['paypal_agreement_id'], cancellation_reason)
      else
        gateway_result = { success: true } # No gateway cancellation needed
      end

      if gateway_result[:success]
        # Update subscription status
        cancelled_at = Time.current.iso8601
        ends_at = immediate ? cancelled_at : subscription['current_period_end']

        update_data = {
          status: immediate ? 'cancelled' : 'canceling',
          cancelled_at: cancelled_at,
          cancellation_reason: cancellation_reason,
          ended_at: immediate ? cancelled_at : nil,
          ends_at: ends_at
        }

        api_client.patch("/api/v1/subscriptions/#{subscription_id}", update_data)

        # Create audit log
        create_audit_log(
          account_id: subscription['account_id'],
          action: 'cancel',
          resource_type: 'Subscription',
          resource_id: subscription_id,
          metadata: { 
            reason: cancellation_reason,
            immediate: immediate,
            ends_at: ends_at
          }
        )

        log_info("Subscription cancelled successfully", subscription_id: subscription_id)
        { success: true, subscription: subscription, ends_at: ends_at }
      else
        log_error("Failed to cancel subscription in gateway", nil, error: gateway_result[:error])
        { success: false, error: gateway_result[:error] }
      end

    rescue => e
      log_error("Subscription cancellation failed", e, subscription_id: subscription_id)
      { success: false, error: e.message }
    end
  end

  # Suspend subscription for failed payments
  def suspend_subscription(subscription_id:, suspension_reason: nil)
    log_info("Suspending subscription", subscription_id: subscription_id)

    begin
      update_data = {
        status: 'past_due',
        suspended_at: Time.current.iso8601,
        suspension_reason: suspension_reason
      }

      response = api_client.patch("/api/v1/subscriptions/#{subscription_id}", update_data)
      
      if response[:success]
        # Create audit log
        create_audit_log(
          resource_type: 'Subscription',
          resource_id: subscription_id,
          action: 'suspend',
          metadata: { reason: suspension_reason }
        )

        log_info("Subscription suspended successfully", subscription_id: subscription_id)
        { success: true, message: "Subscription suspended" }
      else
        { success: false, error: response[:error] }
      end

    rescue => e
      log_error("Subscription suspension failed", e, subscription_id: subscription_id)
      { success: false, error: e.message }
    end
  end

  private

  def calculate_period_end(plan, trial_end)
    if trial_end
      trial_end
    elsif plan['trial_days'] && plan['trial_days'] > 0
      plan['trial_days'].days.from_now.iso8601
    else
      case plan['billing_interval']
      when 'month'
        plan['interval_count'].months.from_now.iso8601
      when 'year'
        plan['interval_count'].years.from_now.iso8601
      when 'week'
        plan['interval_count'].weeks.from_now.iso8601
      else
        1.month.from_now.iso8601
      end
    end
  end

  def calculate_next_period_end(subscription, plan)
    current_end = Time.parse(subscription['current_period_end'])
    
    case plan['billing_interval']
    when 'month'
      current_end + plan['interval_count'].months
    when 'year'  
      current_end + plan['interval_count'].years
    when 'week'
      current_end + plan['interval_count'].weeks
    else
      current_end + 1.month
    end.iso8601
  end

  def renewal_due?(subscription)
    return false unless subscription['status'] == 'active'
    
    current_period_end = Time.parse(subscription['current_period_end'])
    current_period_end <= Time.current
  end

  def calculate_renewal_amount(subscription, plan)
    response = api_client.post('/api/v1/internal/billing/calculate_renewal', {
      subscription_id: subscription['id'], plan_id: plan['id']
    })
    response.dig(:data, 'amount') || (plan['price_cents'] * subscription['quantity'])
  rescue StandardError
    plan['price_cents'] * subscription['quantity']
  end

  def handle_renewal_failure(subscription_id, error, retry_attempt)
    log_error("Renewal failed", nil, subscription_id: subscription_id, error: error, retry_attempt: retry_attempt)

    if retry_attempt < 3
      # Schedule retry
      retry_delay = case retry_attempt
      when 0 then 1.hour
      when 1 then 1.day
      when 2 then 3.days
      else 1.week
      end

      WorkerJobService.schedule_job(
        'Billing::SubscriptionRenewalJob',
        { subscription_id: subscription_id, retry_attempt: retry_attempt + 1 },
        retry_delay.from_now
      )

      log_info("Scheduled renewal retry", subscription_id: subscription_id, retry_in: retry_delay)
    else
      # Suspend subscription after max retries
      suspend_subscription(subscription_id: subscription_id, suspension_reason: "Payment failed after #{retry_attempt} attempts")
      
      # Trigger dunning process
      WorkerJobService.enqueue_job('DunningProcessJob', { subscription_id: subscription_id, reason: error })
    end

    { success: false, error: error, retry_scheduled: retry_attempt < 3 }
  end

  def create_stripe_subscription(subscription_data, payment_method, options)
    response = api_client.post('/api/v1/internal/billing/create_subscription', {
      gateway: 'stripe', subscription: subscription_data,
      payment_method: payment_method, options: options
    })
    response[:success] ? response[:data] : { success: false, error: response[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def create_paypal_subscription(subscription_data, payment_method, options)
    response = api_client.post('/api/v1/internal/billing/create_subscription', {
      gateway: 'paypal', subscription: subscription_data,
      payment_method: payment_method, options: options
    })
    response[:success] ? response[:data] : { success: false, error: response[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def process_stripe_renewal(subscription, amount, retry_attempt)
    response = api_client.post('/api/v1/internal/billing/process_renewal', {
      gateway: 'stripe', subscription_id: subscription['id'],
      amount: amount, retry_attempt: retry_attempt
    })
    response[:success] ? response[:data] : { success: false, error: response[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def process_paypal_renewal(subscription, amount, retry_attempt)
    response = api_client.post('/api/v1/internal/billing/process_renewal', {
      gateway: 'paypal', subscription_id: subscription['id'],
      amount: amount, retry_attempt: retry_attempt
    })
    response[:success] ? response[:data] : { success: false, error: response[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def cancel_stripe_subscription(stripe_subscription_id, immediate)
    response = api_client.post('/api/v1/internal/billing/cancel_subscription', {
      gateway: 'stripe', gateway_subscription_id: stripe_subscription_id,
      immediate: immediate
    })
    response[:success] ? { success: true } : { success: false, error: response[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def cancel_paypal_subscription(paypal_agreement_id, reason)
    response = api_client.post('/api/v1/internal/billing/cancel_subscription', {
      gateway: 'paypal', gateway_agreement_id: paypal_agreement_id,
      reason: reason
    })
    response[:success] ? { success: true } : { success: false, error: response[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end