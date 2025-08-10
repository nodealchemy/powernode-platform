require_relative 'base_worker'

# Worker for processing webhook events from payment gateways
class WebhookProcessorWorker < BaseWorker
  sidekiq_options queue: 'webhooks', retry: 5, backtrace: true

  def perform(webhook_event_id)
    log_info("Processing webhook event", event_id: webhook_event_id)
    
    begin
      # Get webhook event from API
      response = api_client.get("/api/v1/webhooks/events/#{webhook_event_id}")
      
      unless response[:success]
        log_error("Failed to fetch webhook event", nil, event_id: webhook_event_id)
        return
      end

      webhook_event = response[:data]
      
      # Process based on provider and event type
      case webhook_event[:provider]
      when 'stripe'
        process_stripe_webhook(webhook_event)
      when 'paypal'
        process_paypal_webhook(webhook_event)
      else
        log_error("Unknown webhook provider", nil, 
          event_id: webhook_event_id,
          provider: webhook_event[:provider]
        )
        return
      end

      # Mark webhook as processed
      api_client.update_webhook_event(webhook_event_id, 'processed')
      
      log_info("Webhook event processed successfully",
        event_id: webhook_event_id,
        provider: webhook_event[:provider],
        event_type: webhook_event[:event_type]
      )
      
    rescue ApiClient::ApiError => e
      # Mark webhook as failed
      api_client.update_webhook_event(webhook_event_id, 'failed', e.message) rescue nil
      handle_api_error(e, event_id: webhook_event_id)
    rescue => e
      # Mark webhook as failed
      api_client.update_webhook_event(webhook_event_id, 'failed', e.message) rescue nil
      log_error("Unexpected error processing webhook", e, event_id: webhook_event_id)
      raise
    end
  end

  private

  def process_stripe_webhook(webhook_event)
    payload = webhook_event[:payload]
    
    case webhook_event[:event_type]
    when 'invoice.payment_succeeded'
      handle_payment_succeeded(payload, 'stripe')
    when 'invoice.payment_failed'
      handle_payment_failed(payload, 'stripe')
    when 'customer.subscription.updated'
      handle_subscription_updated(payload, 'stripe')
    when 'customer.subscription.deleted'
      handle_subscription_canceled(payload, 'stripe')
    when 'invoice.created'
      handle_invoice_created(payload, 'stripe')
    else
      log_warn("Unhandled Stripe webhook event type", event_type: webhook_event[:event_type])
    end
  end

  def process_paypal_webhook(webhook_event)
    payload = webhook_event[:payload]
    
    case webhook_event[:event_type]
    when 'BILLING.SUBSCRIPTION.ACTIVATED'
      handle_subscription_activated(payload, 'paypal')
    when 'BILLING.SUBSCRIPTION.CANCELLED'
      handle_subscription_canceled(payload, 'paypal')
    when 'PAYMENT.SALE.COMPLETED'
      handle_payment_succeeded(payload, 'paypal')
    when 'PAYMENT.SALE.DENIED'
      handle_payment_failed(payload, 'paypal')
    else
      log_warn("Unhandled PayPal webhook event type", event_type: webhook_event[:event_type])
    end
  end

  def handle_payment_succeeded(payload, provider)
    log_info("Processing payment success", provider: provider)
    
    # Extract relevant data based on provider
    case provider
    when 'stripe'
      invoice_id = payload['data']['object']['id']
      amount_cents = payload['data']['object']['amount_paid']
      subscription_id = payload['data']['object']['subscription']
    when 'paypal'
      # PayPal structure would be different
      payment_id = payload['resource']['id']
      amount_cents = (payload['resource']['amount']['total'].to_f * 100).to_i
    end
    
    # Update payment status via API
    # This would need to be implemented based on your payment tracking system
    log_info("Payment succeeded", 
      provider: provider,
      amount_cents: amount_cents,
      external_id: invoice_id || payment_id
    )
  end

  def handle_payment_failed(payload, provider)
    log_info("Processing payment failure", provider: provider)
    
    case provider
    when 'stripe'
      invoice_id = payload['data']['object']['id']
      subscription_id = payload['data']['object']['subscription']
      failure_code = payload['data']['object']['last_payment_error']&.dig('code')
    when 'paypal'
      payment_id = payload['resource']['id']
      failure_reason = payload['resource']['reason_code']
    end
    
    # Handle payment failure
    log_info("Payment failed",
      provider: provider,
      external_id: invoice_id || payment_id,
      failure_reason: failure_code || failure_reason
    )
    
    # Could trigger dunning management
    BillingAutomationWorker.perform_async('process_dunning', subscription_id) if subscription_id
  end

  def handle_subscription_updated(payload, provider)
    log_info("Processing subscription update", provider: provider)
    
    case provider
    when 'stripe'
      subscription = payload['data']['object']
      subscription_id = subscription['id']
      status = subscription['status']
      
      # Update subscription status
      api_client.update_subscription_status(subscription_id, map_stripe_status(status))
    end
  end

  def handle_subscription_activated(payload, provider)
    log_info("Processing subscription activation", provider: provider)
    
    case provider
    when 'paypal'
      subscription = payload['resource']
      subscription_id = subscription['id']
      
      api_client.update_subscription_status(subscription_id, 'active')
    end
  end

  def handle_subscription_canceled(payload, provider)
    log_info("Processing subscription cancellation", provider: provider)
    
    case provider
    when 'stripe'
      subscription_id = payload['data']['object']['id']
    when 'paypal'
      subscription_id = payload['resource']['id']
    end
    
    api_client.update_subscription_status(subscription_id, 'canceled')
  end

  def handle_invoice_created(payload, provider)
    log_info("Processing invoice creation", provider: provider)
    
    case provider
    when 'stripe'
      invoice = payload['data']['object']
      # Handle invoice creation logic
    end
  end

  def map_stripe_status(stripe_status)
    case stripe_status
    when 'active'
      'active'
    when 'past_due'
      'past_due'
    when 'canceled'
      'canceled'
    when 'unpaid'
      'past_due'
    when 'trialing'
      'trialing'
    else
      'unknown'
    end
  end
end