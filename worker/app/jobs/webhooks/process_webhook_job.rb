# frozen_string_literal: true

require_relative '../base_job'

# Job for processing webhook events from payment gateways
# Handles Stripe, PayPal, and other webhook notifications
class Webhooks::ProcessWebhookJob < BaseJob
  sidekiq_options queue: 'webhooks',
                  retry: 2

  def execute(webhook_data)
    validate_required_params(webhook_data, 'provider', 'event_type', 'payload')
    
    provider = webhook_data['provider']
    event_type = webhook_data['event_type']
    
    logger.info "Processing #{provider} webhook: #{event_type}"
    
    # Process webhook based on provider
    result = case provider.downcase
             when 'stripe'
               process_stripe_webhook(webhook_data)
             when 'paypal'
               process_paypal_webhook(webhook_data)
             else
               logger.warn "Unknown webhook provider: #{provider}"
               { 'success' => false, 'error' => "Unsupported provider: #{provider}" }
             end
    
    if result['success']
      logger.info "Successfully processed #{provider} webhook: #{event_type}"
    else
      logger.error "Failed to process #{provider} webhook: #{result['error']}"
    end
    
    result
  end
  
  private
  
  def process_stripe_webhook(webhook_data)
    event_type = webhook_data['event_type']
    payload = webhook_data['payload']
    
    case event_type
    when 'invoice.payment_succeeded'
      handle_payment_succeeded(payload, 'stripe')
    when 'invoice.payment_failed'
      handle_payment_failed(payload, 'stripe')
    when 'customer.subscription.updated'
      handle_subscription_updated(payload, 'stripe')
    when 'customer.subscription.deleted'
      handle_subscription_cancelled(payload, 'stripe')
    when 'payment_method.attached'
      handle_payment_method_attached(payload, 'stripe')
    when 'payment_intent.succeeded'
      handle_payment_intent_succeeded(payload, 'stripe')
    when 'payment_intent.payment_failed'
      handle_payment_intent_failed(payload, 'stripe')
    else
      logger.info "Unhandled Stripe event type: #{event_type}"
      { 'success' => true, 'message' => 'Event type not handled' }
    end
  end
  
  def process_paypal_webhook(webhook_data)
    # Delegate to specialized PayPal webhook processor
    processor = Webhooks::PaypalWebhookProcessorJob.new
    result = processor.process_webhook(webhook_data)
    
    if result[:success]
      { 'success' => true, 'message' => result[:message] || 'PayPal webhook processed successfully' }
    else
      { 'success' => false, 'error' => result[:error] || 'PayPal webhook processing failed' }
    end
  rescue => e
    logger.error "PayPal webhook processing failed: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_payment_succeeded(payload, provider)
    payment_data = extract_payment_data(payload, provider)
    
    webhook_params = {
      event_type: 'payment_succeeded',
      provider: provider,
      payment_data: payment_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/payment_succeeded', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process payment succeeded webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_payment_failed(payload, provider)
    payment_data = extract_payment_data(payload, provider)
    
    webhook_params = {
      event_type: 'payment_failed',
      provider: provider,
      payment_data: payment_data,
      raw_payload: payload
    }
    
    result = with_api_retry do
      api_client.post('/api/v1/webhooks/payment_failed', webhook_params)
    end
    
    # Schedule payment retry if subscription is identified
    if result['subscription_id']
      Billing::PaymentRetryJob.perform_in(1.hour, result['subscription_id'], 'webhook_failure')
      logger.info "Scheduled payment retry for subscription #{result['subscription_id']}"
    end
    
    result
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process payment failed webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_subscription_updated(payload, provider)
    subscription_data = extract_subscription_data(payload, provider)
    
    webhook_params = {
      event_type: 'subscription_updated',
      provider: provider,
      subscription_data: subscription_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/subscription_updated', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process subscription updated webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_subscription_cancelled(payload, provider)
    subscription_data = extract_subscription_data(payload, provider)
    
    webhook_params = {
      event_type: 'subscription_cancelled',
      provider: provider,
      subscription_data: subscription_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/subscription_cancelled', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process subscription cancelled webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_subscription_activated(payload, provider)
    subscription_data = extract_subscription_data(payload, provider)
    
    webhook_params = {
      event_type: 'subscription_activated',
      provider: provider,
      subscription_data: subscription_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/subscription_activated', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process subscription activated webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_payment_method_attached(payload, provider)
    payment_method_data = extract_payment_method_data(payload, provider)
    
    webhook_params = {
      event_type: 'payment_method_attached',
      provider: provider,
      payment_method_data: payment_method_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/payment_method_attached', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process payment method attached webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_payment_intent_succeeded(payload, provider)
    payment_data = extract_payment_intent_data(payload, provider)
    
    webhook_params = {
      event_type: 'payment_intent_succeeded',
      provider: provider,
      payment_data: payment_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/payment_intent_succeeded', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process payment intent succeeded webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  def handle_payment_intent_failed(payload, provider)
    payment_data = extract_payment_intent_data(payload, provider)
    
    webhook_params = {
      event_type: 'payment_intent_failed',
      provider: provider,
      payment_data: payment_data,
      raw_payload: payload
    }
    
    with_api_retry do
      api_client.post('/api/v1/webhooks/payment_intent_failed', webhook_params)
    end
  rescue BackendApiClient::ApiError => e
    logger.error "Failed to process payment intent failed webhook: #{e.message}"
    { 'success' => false, 'error' => e.message }
  end
  
  # Provider-specific data extraction methods
  def extract_payment_data(payload, provider)
    case provider
    when 'stripe'
      extract_stripe_payment_data(payload)
    when 'paypal'
      extract_paypal_payment_data(payload)
    else
      {}
    end
  end
  
  def extract_subscription_data(payload, provider)
    case provider
    when 'stripe'
      extract_stripe_subscription_data(payload)
    when 'paypal'
      extract_paypal_subscription_data(payload)
    else
      {}
    end
  end
  
  def extract_payment_method_data(payload, provider)
    case provider
    when 'stripe'
      extract_stripe_payment_method_data(payload)
    else
      {}
    end
  end
  
  def extract_payment_intent_data(payload, provider)
    case provider
    when 'stripe'
      extract_stripe_payment_intent_data(payload)
    else
      {}
    end
  end
  
  # Stripe-specific extraction methods
  def extract_stripe_payment_data(payload)
    invoice = payload.dig('data', 'object') || {}
    
    {
      external_id: invoice['id'],
      amount_cents: invoice['amount_paid'],
      currency: invoice['currency'],
      status: invoice['status'],
      customer_id: invoice['customer'],
      subscription_id: invoice['subscription'],
      payment_intent_id: invoice['payment_intent']
    }
  end
  
  def extract_stripe_subscription_data(payload)
    subscription = payload.dig('data', 'object') || {}
    
    {
      external_id: subscription['id'],
      customer_id: subscription['customer'],
      status: subscription['status'],
      current_period_start: Time.at(subscription['current_period_start']).iso8601,
      current_period_end: Time.at(subscription['current_period_end']).iso8601,
      plan_id: subscription.dig('items', 'data', 0, 'price', 'id'),
      quantity: subscription.dig('items', 'data', 0, 'quantity')
    }
  end
  
  def extract_stripe_payment_method_data(payload)
    payment_method = payload.dig('data', 'object') || {}
    
    {
      external_id: payment_method['id'],
      customer_id: payment_method['customer'],
      type: payment_method['type'],
      card: payment_method['card']
    }
  end
  
  def extract_stripe_payment_intent_data(payload)
    payment_intent = payload.dig('data', 'object') || {}
    
    {
      external_id: payment_intent['id'],
      amount_cents: payment_intent['amount'],
      currency: payment_intent['currency'],
      status: payment_intent['status'],
      customer_id: payment_intent['customer'],
      payment_method_id: payment_intent['payment_method']
    }
  end
  
  # PayPal-specific extraction methods
  def extract_paypal_payment_data(payload)
    resource = payload['resource'] || {}
    
    {
      external_id: resource['id'],
      amount_cents: (resource.dig('amount', 'total').to_f * 100).to_i,
      currency: resource.dig('amount', 'currency'),
      status: resource['state'],
      parent_payment: resource['parent_payment']
    }
  end
  
  def extract_paypal_subscription_data(payload)
    resource = payload['resource'] || {}
    
    {
      external_id: resource['id'],
      status: resource['status'],
      plan_id: resource['plan_id'],
      start_time: resource['start_time']
    }
  end
end