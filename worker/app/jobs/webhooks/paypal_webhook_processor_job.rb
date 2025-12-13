# frozen_string_literal: true

require_relative 'base_webhook_job'

class Webhooks::PaypalWebhookProcessorJob < Webhooks::BaseWebhookJob
  sidekiq_options queue: 'webhooks', retry: 3, backtrace: true

  SUPPORTED_EVENTS = [
    'BILLING.SUBSCRIPTION.CREATED',
    'BILLING.SUBSCRIPTION.ACTIVATED',
    'BILLING.SUBSCRIPTION.SUSPENDED',
    'BILLING.SUBSCRIPTION.CANCELLED',
    'BILLING.SUBSCRIPTION.EXPIRED',
    'BILLING.SUBSCRIPTION.PAYMENT.COMPLETED',
    'BILLING.SUBSCRIPTION.PAYMENT.FAILED',
    'PAYMENT.SALE.COMPLETED',
    'PAYMENT.SALE.DENIED',
    'PAYMENT.SALE.REFUNDED',
    'PAYMENT.CAPTURE.COMPLETED',
    'PAYMENT.CAPTURE.DENIED'
  ].freeze

  def process_webhook(webhook_data)
    event_type = webhook_data['event_type']
    payload = webhook_data['payload']
    
    log_info("Processing PayPal webhook", event_type: event_type, resource_id: payload.dig('resource', 'id'))

    unless SUPPORTED_EVENTS.include?(event_type)
      log_info("Unsupported PayPal event type, skipping", event_type: event_type)
      return { success: true, message: "Event type not supported" }
    end

    case event_type
    when /^BILLING\.SUBSCRIPTION\./
      process_subscription_event(payload, event_type)
    when /^PAYMENT\.(SALE|CAPTURE)\./
      process_payment_event(payload, event_type)
    else
      log_info("Unknown PayPal event type", event_type: event_type)
      { success: true, message: "Unknown event type" }
    end
  rescue => e
    log_error("PayPal webhook processing failed", e, event_type: event_type)
    raise
  end

  private

  def process_subscription_event(payload, event_type)
    resource = payload['resource']
    agreement_id = resource['id']

    log_info("Processing subscription event", event_type: event_type, agreement_id: agreement_id)

    # Find subscription by PayPal agreement ID with retry logic
    subscription_response = with_api_retry(max_attempts: 3) do
      api_client.get("/api/v1/subscriptions", params: { paypal_agreement_id: agreement_id })
    end

    unless subscription_response[:success]
      log_error("Failed to find subscription", nil, agreement_id: agreement_id)
      return { success: false, error: "Subscription not found" }
    end

    subscription_data = subscription_response[:data]
    subscription_data = subscription_data.first if subscription_data.is_a?(Array)
    return { success: true, message: "No matching subscription found" } unless subscription_data

    case event_type
    when 'BILLING.SUBSCRIPTION.CREATED'
      update_subscription_status(subscription_data['id'], 'pending', {
        paypal_agreement_id: agreement_id,
        next_billing_time: resource['billing_info']&.dig('next_billing_time')
      })

    when 'BILLING.SUBSCRIPTION.ACTIVATED'
      update_subscription_status(subscription_data['id'], 'active', {
        activated_at: Time.current.utc.iso8601,
        next_billing_time: resource['billing_info']&.dig('next_billing_time'),
        agreement_details: resource['agreement_details']
      })

    when 'BILLING.SUBSCRIPTION.SUSPENDED'
      update_subscription_status(subscription_data['id'], 'past_due', {
        suspended_at: Time.current.utc.iso8601,
        suspension_reason: resource['status_change_note']
      })

    when 'BILLING.SUBSCRIPTION.CANCELLED', 'BILLING.SUBSCRIPTION.EXPIRED'
      update_subscription_status(subscription_data['id'], 'cancelled', {
        cancelled_at: Time.current.utc.iso8601,
        cancellation_reason: event_type == 'BILLING.SUBSCRIPTION.EXPIRED' ? 'expired' : 'cancelled'
      })

    when 'BILLING.SUBSCRIPTION.PAYMENT.COMPLETED'
      process_successful_subscription_payment(subscription_data, resource)

    when 'BILLING.SUBSCRIPTION.PAYMENT.FAILED'
      process_failed_subscription_payment(subscription_data, resource)
    end

    { success: true, message: "Subscription event processed" }
  end

  def process_payment_event(payload, event_type)
    resource = payload['resource']
    payment_id = resource['parent_payment'] || resource['id']

    log_info("Processing payment event", event_type: event_type, payment_id: payment_id)

    # Find payment by PayPal payment ID with retry logic
    payment_response = with_api_retry(max_attempts: 3) do
      api_client.get("/api/v1/payments", params: { paypal_payment_id: payment_id })
    end

    unless payment_response[:success]
      log_error("Failed to find payment", nil, payment_id: payment_id)
      return { success: false, error: "Payment not found" }
    end

    payment_data = payment_response[:data]
    payment_data = payment_data.first if payment_data.is_a?(Array)
    return { success: true, message: "No matching payment found" } unless payment_data

    case event_type
    when 'PAYMENT.SALE.COMPLETED', 'PAYMENT.CAPTURE.COMPLETED'
      update_payment_status(payment_data['id'], 'succeeded', {
        paypal_transaction_id: resource['id'],
        processed_at: Time.current.utc.iso8601,
        transaction_fee: resource['transaction_fee']
      })

    when 'PAYMENT.SALE.DENIED', 'PAYMENT.CAPTURE.DENIED'
      update_payment_status(payment_data['id'], 'failed', {
        error_message: resource['reason_code'] || 'Payment denied',
        failed_at: Time.current.utc.iso8601
      })

    when 'PAYMENT.SALE.REFUNDED'
      process_refund_event(payment_data, resource)
    end

    { success: true, message: "Payment event processed" }
  end

  def process_successful_subscription_payment(subscription_data, resource)
    log_info("Processing successful subscription payment", subscription_id: subscription_data['id'])

    # Create payment record
    payment_data = {
      account_id: subscription_data['account_id'],
      user_id: subscription_data['user_id'],
      subscription_id: subscription_data['id'],
      amount_cents: (resource['amount']['total'].to_f * 100).to_i,
      currency: resource['amount']['currency'],
      payment_method: 'paypal',
      status: 'succeeded',
      paypal_transaction_id: resource['id'],
      processed_at: Time.current.utc.iso8601,
      metadata: {
        paypal_fee: resource['transaction_fee'],
        billing_period: resource['billing_period']
      }
    }

    payment_response = with_api_retry(max_attempts: 3) do
      api_client.post("/api/v1/payments", payment_data)
    end

    if payment_response[:success]
      # Update subscription billing period
      next_billing_time = resource.dig('billing_info', 'next_billing_time')
      
      update_subscription_status(subscription_data['id'], 'active', {
        current_period_start: Date.current.iso8601,
        current_period_end: next_billing_time ? Date.parse(next_billing_time).iso8601 : nil,
        next_billing_date: next_billing_time
      })

      # Create invoice if needed
      create_subscription_invoice(subscription_data, payment_response[:data])

      log_info("Subscription payment processed successfully", 
        subscription_id: subscription_data['id'],
        payment_id: payment_response[:data]['id']
      )
    else
      log_error("Failed to create payment record", nil, 
        subscription_id: subscription_data['id'],
        error: payment_response[:error]
      )
    end
  end

  def process_failed_subscription_payment(subscription_data, resource)
    log_info("Processing failed subscription payment", subscription_id: subscription_data['id'])

    # Update subscription status to past_due
    update_subscription_status(subscription_data['id'], 'past_due', {
      last_payment_attempt: Time.current.utc.iso8601,
      payment_failure_reason: resource['reason_code'] || 'Payment failed'
    })

    # Create failed payment record
    payment_data = {
      account_id: subscription_data['account_id'],
      user_id: subscription_data['user_id'],
      subscription_id: subscription_data['id'],
      amount_cents: (resource['amount']['total'].to_f * 100).to_i,
      currency: resource['amount']['currency'],
      payment_method: 'paypal',
      status: 'failed',
      error_message: resource['reason_code'] || 'PayPal payment failed',
      failed_at: Time.current.utc.iso8601,
      metadata: {
        failure_reason: resource['reason_code'],
        billing_period: resource['billing_period']
      }
    }

    with_api_retry(max_attempts: 3) do
      api_client.post("/api/v1/payments", payment_data)
    end

    # Trigger dunning process
    trigger_dunning_process(subscription_data['id'], resource['reason_code'])
  end

  def process_refund_event(payment_data, resource)
    log_info("Processing refund event", payment_id: payment_data['id'])

    refund_amount_cents = (resource['amount']['total'].to_f * 100).to_i
    
    # Determine refund status
    if refund_amount_cents >= payment_data['amount_cents']
      new_status = 'refunded'
    else
      new_status = 'partially_refunded'
    end

    update_payment_status(payment_data['id'], new_status, {
      refund_amount_cents: refund_amount_cents,
      refund_id: resource['id'],
      refunded_at: Time.current.utc.iso8601,
      refund_reason: resource['reason']
    })

    log_info("Refund processed successfully", 
      payment_id: payment_data['id'],
      refund_amount: refund_amount_cents,
      status: new_status
    )
  end

  def update_subscription_status(subscription_id, status, metadata = {})
    update_data = { status: status }.merge(metadata)

    response = with_api_retry(max_attempts: 3) do
      api_client.patch("/api/v1/subscriptions/#{subscription_id}", update_data)
    end

    unless response[:success]
      log_error("Failed to update subscription status", nil,
        subscription_id: subscription_id,
        status: status,
        error: response[:error]
      )
    end

    create_audit_log(
      resource_type: 'Subscription',
      resource_id: subscription_id,
      action: 'status_change',
      metadata: { 
        old_status: metadata[:old_status],
        new_status: status,
        source: 'paypal_webhook'
      }
    )
  end

  def update_payment_status(payment_id, status, metadata = {})
    update_data = { status: status }.merge(metadata)

    response = with_api_retry(max_attempts: 3) do
      api_client.patch("/api/v1/payments/#{payment_id}", update_data)
    end

    unless response[:success]
      log_error("Failed to update payment status", nil,
        payment_id: payment_id,
        status: status,
        error: response[:error]
      )
    end

    create_audit_log(
      resource_type: 'Payment',
      resource_id: payment_id,
      action: 'status_change',
      metadata: { 
        old_status: metadata[:old_status],
        new_status: status,
        source: 'paypal_webhook'
      }
    )
  end

  def create_subscription_invoice(subscription_data, payment_data)
    invoice_data = {
      account_id: subscription_data['account_id'],
      subscription_id: subscription_data['id'],
      payment_id: payment_data['id'],
      invoice_number: generate_invoice_number,
      subtotal_cents: payment_data['amount_cents'],
      total_amount_cents: payment_data['amount_cents'],
      currency: payment_data['currency'],
      status: 'paid',
      paid_at: payment_data['processed_at'],
      due_date: Date.current.iso8601
    }

    response = with_api_retry(max_attempts: 3) do
      api_client.post("/api/v1/invoices", invoice_data)
    end

    unless response[:success]
      log_error("Failed to create subscription invoice", nil,
        subscription_id: subscription_data['id'],
        payment_id: payment_data['id'],
        error: response[:error]
      )
    end
  end

  def trigger_dunning_process(subscription_id, failure_reason)
    dunning_data = {
      subscription_id: subscription_id,
      failure_reason: failure_reason,
      webhook_source: 'paypal'
    }

    # Enqueue dunning process job
    WorkerJobService.enqueue_job('DunningProcessJob', dunning_data)
  rescue => e
    log_error("Failed to trigger dunning process", e, subscription_id: subscription_id)
  end

  def generate_invoice_number
    "INV-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
  end
end