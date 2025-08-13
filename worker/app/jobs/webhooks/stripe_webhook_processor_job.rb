require_relative '../base_job'

# Comprehensive Stripe webhook event processor
class Webhooks::StripeWebhookProcessorJob < BaseJob
  sidekiq_options queue: 'webhooks', retry: 3

  CRITICAL_EVENTS = %w[
    invoice.payment_failed
    invoice.payment_succeeded
    customer.subscription.deleted
    customer.subscription.updated
    payment_intent.succeeded
    payment_intent.payment_failed
    setup_intent.succeeded
    setup_intent.setup_failed
  ].freeze

  def execute(webhook_data)
    event_type = webhook_data['event_type']
    payload = webhook_data['payload']
    account_id = webhook_data['account_id']
    
    logger.info "Processing Stripe webhook: #{event_type} for account: #{account_id}"
    
    # Mark webhook as processing
    mark_webhook_processing(webhook_data['webhook_event_id'])
    
    result = case event_type
             when 'invoice.payment_succeeded'
               process_invoice_payment_succeeded(payload, account_id)
             when 'invoice.payment_failed'
               process_invoice_payment_failed(payload, account_id)
             when 'customer.subscription.updated'
               process_subscription_updated(payload, account_id)
             when 'customer.subscription.deleted'
               process_subscription_deleted(payload, account_id)
             when 'payment_intent.succeeded'
               process_payment_intent_succeeded(payload, account_id)
             when 'payment_intent.payment_failed'
               process_payment_intent_failed(payload, account_id)
             when 'setup_intent.succeeded'
               process_setup_intent_succeeded(payload, account_id)
             when 'setup_intent.setup_failed'
               process_setup_intent_failed(payload, account_id)
             when 'payment_method.attached'
               process_payment_method_attached(payload, account_id)
             when 'payment_method.detached'
               process_payment_method_detached(payload, account_id)
             when 'customer.created'
               process_customer_created(payload, account_id)
             when 'customer.updated'
               process_customer_updated(payload, account_id)
             else
               process_unhandled_event(event_type, payload, account_id)
             end
    
    if result[:success]
      mark_webhook_processed(webhook_data['webhook_event_id'])
      logger.info "Successfully processed Stripe webhook: #{event_type}"
    else
      mark_webhook_failed(webhook_data['webhook_event_id'], result[:error])
      logger.error "Failed to process Stripe webhook: #{event_type} - #{result[:error]}"
    end
    
    result
  rescue => e
    logger.error "Stripe webhook processing error: #{e.message}"
    mark_webhook_failed(webhook_data['webhook_event_id'], e.message)
    { success: false, error: e.message }
  end

  private

  def process_invoice_payment_succeeded(payload, account_id)
    invoice_data = payload['object']
    stripe_invoice_id = invoice_data['id']
    
    # Find local invoice and update
    invoice_update = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/invoice_paid', {
        stripe_invoice_id: stripe_invoice_id,
        account_id: account_id,
        amount_paid: invoice_data['amount_paid'],
        payment_intent_id: invoice_data['payment_intent'],
        metadata: invoice_data
      })
    end
    
    if invoice_update['success']
      # Trigger subscription activation if needed
      if invoice_data['subscription']
        activate_subscription_if_needed(invoice_data['subscription'], account_id)
      end
      
      { success: true, message: 'Invoice payment processed' }
    else
      { success: false, error: invoice_update['error'] || 'Failed to update invoice' }
    end
  end

  def process_invoice_payment_failed(payload, account_id)
    invoice_data = payload['object']
    stripe_invoice_id = invoice_data['id']
    
    # Update invoice status and trigger retry logic
    failure_update = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/invoice_failed', {
        stripe_invoice_id: stripe_invoice_id,
        account_id: account_id,
        failure_code: invoice_data['last_finalization_error']&.dig('code'),
        failure_message: invoice_data['last_finalization_error']&.dig('message'),
        subscription_id: invoice_data['subscription'],
        metadata: invoice_data
      })
    end
    
    if failure_update['success'] && invoice_data['subscription']
      # Trigger payment retry process
      subscription_id = get_local_subscription_id(invoice_data['subscription'], account_id)
      
      if subscription_id
        Billing::PaymentRetryJob.perform_async(subscription_id, 'invoice_payment_failure', 1)
        logger.info "Queued payment retry for subscription: #{subscription_id}"
      end
    end
    
    { success: true, message: 'Invoice payment failure processed' }
  end

  def process_subscription_updated(payload, account_id)
    subscription_data = payload['object']
    stripe_subscription_id = subscription_data['id']
    
    sync_result = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/subscription_updated', {
        stripe_subscription_id: stripe_subscription_id,
        account_id: account_id,
        status: subscription_data['status'],
        current_period_start: Time.at(subscription_data['current_period_start']),
        current_period_end: Time.at(subscription_data['current_period_end']),
        cancel_at_period_end: subscription_data['cancel_at_period_end'],
        canceled_at: subscription_data['canceled_at'] ? Time.at(subscription_data['canceled_at']) : nil,
        trial_end: subscription_data['trial_end'] ? Time.at(subscription_data['trial_end']) : nil,
        metadata: subscription_data
      })
    end
    
    if sync_result['success']
      { success: true, message: 'Subscription synchronized' }
    else
      { success: false, error: sync_result['error'] || 'Failed to sync subscription' }
    end
  end

  def process_subscription_deleted(payload, account_id)
    subscription_data = payload['object']
    stripe_subscription_id = subscription_data['id']
    
    cancellation_result = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/subscription_canceled', {
        stripe_subscription_id: stripe_subscription_id,
        account_id: account_id,
        canceled_at: Time.at(subscription_data['canceled_at'] || Time.current.to_i),
        cancellation_reason: 'stripe_webhook_deletion',
        metadata: subscription_data
      })
    end
    
    { success: true, message: 'Subscription cancellation processed' }
  end

  def process_payment_intent_succeeded(payload, account_id)
    payment_intent = payload['object']
    payment_intent_id = payment_intent['id']
    
    payment_update = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/payment_succeeded', {
        payment_intent_id: payment_intent_id,
        account_id: account_id,
        amount: payment_intent['amount'],
        currency: payment_intent['currency'],
        charges: payment_intent['charges']['data'],
        metadata: payment_intent
      })
    end
    
    { success: true, message: 'Payment intent success processed' }
  end

  def process_payment_intent_failed(payload, account_id)
    payment_intent = payload['object']
    payment_intent_id = payment_intent['id']
    
    failure_update = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/payment_failed', {
        payment_intent_id: payment_intent_id,
        account_id: account_id,
        failure_code: payment_intent['last_payment_error']&.dig('code'),
        failure_message: payment_intent['last_payment_error']&.dig('message'),
        amount: payment_intent['amount'],
        currency: payment_intent['currency'],
        metadata: payment_intent
      })
    end
    
    { success: true, message: 'Payment intent failure processed' }
  end

  def process_setup_intent_succeeded(payload, account_id)
    setup_intent = payload['object']
    
    setup_result = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/setup_intent_succeeded', {
        setup_intent_id: setup_intent['id'],
        account_id: account_id,
        payment_method: setup_intent['payment_method'],
        usage: setup_intent['usage'],
        metadata: setup_intent
      })
    end
    
    { success: true, message: 'Setup intent success processed' }
  end

  def process_setup_intent_failed(payload, account_id)
    setup_intent = payload['object']
    
    { success: true, message: 'Setup intent failure logged' }
  end

  def process_payment_method_attached(payload, account_id)
    payment_method = payload['object']
    
    attachment_result = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/payment_method_attached', {
        payment_method_id: payment_method['id'],
        account_id: account_id,
        customer: payment_method['customer'],
        type: payment_method['type'],
        card: payment_method['card'],
        metadata: payment_method
      })
    end
    
    { success: true, message: 'Payment method attachment processed' }
  end

  def process_payment_method_detached(payload, account_id)
    payment_method = payload['object']
    
    detachment_result = with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/payment_method_detached', {
        payment_method_id: payment_method['id'],
        account_id: account_id,
        metadata: payment_method
      })
    end
    
    { success: true, message: 'Payment method detachment processed' }
  end

  def process_customer_created(payload, account_id)
    customer = payload['object']
    
    { success: true, message: 'Customer creation logged' }
  end

  def process_customer_updated(payload, account_id)
    customer = payload['object']
    
    { success: true, message: 'Customer update logged' }
  end

  def process_unhandled_event(event_type, payload, account_id)
    logger.info "Unhandled Stripe webhook event: #{event_type}"
    
    # Log unhandled events for future implementation
    with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/unhandled_event', {
        event_type: event_type,
        account_id: account_id,
        payload_summary: {
          object_type: payload['object']['object'],
          id: payload['object']['id']
        }
      })
    end
    
    { success: true, message: 'Unhandled event logged' }
  end

  def activate_subscription_if_needed(stripe_subscription_id, account_id)
    with_api_retry do
      api_client.post('/api/v1/webhooks/stripe/activate_subscription', {
        stripe_subscription_id: stripe_subscription_id,
        account_id: account_id
      })
    end
  rescue => e
    logger.error "Failed to activate subscription: #{e.message}"
  end

  def get_local_subscription_id(stripe_subscription_id, account_id)
    subscription_data = with_api_retry do
      api_client.get("/api/v1/subscriptions/by_stripe_id/#{stripe_subscription_id}")
    end
    
    subscription_data&.dig('subscription', 'id')
  rescue => e
    logger.error "Failed to get local subscription ID: #{e.message}"
    nil
  end

  def mark_webhook_processing(webhook_event_id)
    return unless webhook_event_id
    
    with_api_retry do
      api_client.patch("/api/v1/webhook_events/#{webhook_event_id}/processing")
    end
  end

  def mark_webhook_processed(webhook_event_id)
    return unless webhook_event_id
    
    with_api_retry do
      api_client.patch("/api/v1/webhook_events/#{webhook_event_id}/processed")
    end
  end

  def mark_webhook_failed(webhook_event_id, error_message)
    return unless webhook_event_id
    
    with_api_retry do
      api_client.patch("/api/v1/webhook_events/#{webhook_event_id}/failed", {
        error_message: error_message
      })
    end
  end
end