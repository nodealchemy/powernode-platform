class ProcessWebhookEventJob < ApplicationJob
  queue_as :webhooks

  def perform(webhook_event_id)
    webhook_event = WebhookEvent.find(webhook_event_id)

    # Skip if already processed
    return if webhook_event.processed?

    webhook_event.start_processing!

    begin
      case webhook_event.provider
      when "stripe"
        process_stripe_event(webhook_event)
      when "paypal"
        process_paypal_event(webhook_event)
      else
        webhook_event.add_error("Unsupported provider: #{webhook_event.provider}")
        webhook_event.mark_failed!
        return
      end

      webhook_event.mark_processed!
      Rails.logger.info "Successfully processed webhook event #{webhook_event.id}"

    rescue => e
      error_message = "Webhook processing failed: #{e.message}"
      Rails.logger.error "#{error_message}\n#{e.backtrace.join("\n")}"

      webhook_event.add_error(error_message)
      webhook_event.mark_failed!

      # Schedule retry if applicable
      if webhook_event.should_retry?
        ProcessWebhookEventJob.set(wait: webhook_event.next_retry_at).perform_later(webhook_event_id)
      end
    end
  end

  private

  def process_stripe_event(webhook_event)
    event_data = webhook_event.event_data_parsed

    case webhook_event.event_type
    when "payment_intent.succeeded"
      handle_stripe_payment_succeeded(event_data, webhook_event)
    when "payment_intent.payment_failed"
      handle_stripe_payment_failed(event_data, webhook_event)
    when "invoice.payment_succeeded"
      handle_stripe_invoice_payment_succeeded(event_data, webhook_event)
    when "invoice.payment_failed"
      handle_stripe_invoice_payment_failed(event_data, webhook_event)
    when "customer.subscription.created"
      handle_stripe_subscription_created(event_data, webhook_event)
    when "customer.subscription.updated"
      handle_stripe_subscription_updated(event_data, webhook_event)
    when "customer.subscription.deleted"
      handle_stripe_subscription_deleted(event_data, webhook_event)
    else
      Rails.logger.info "Unhandled Stripe event type: #{webhook_event.event_type}"
      webhook_event.skip!
    end
  end

  def process_paypal_event(webhook_event)
    event_data = webhook_event.event_data_parsed

    case webhook_event.event_type
    when "PAYMENT.SALE.COMPLETED"
      handle_paypal_payment_completed(event_data, webhook_event)
    when "PAYMENT.SALE.DENIED"
      handle_paypal_payment_denied(event_data, webhook_event)
    when "BILLING.SUBSCRIPTION.CREATED"
      handle_paypal_subscription_created(event_data, webhook_event)
    when "BILLING.SUBSCRIPTION.CANCELLED"
      handle_paypal_subscription_cancelled(event_data, webhook_event)
    else
      Rails.logger.info "Unhandled PayPal event type: #{webhook_event.event_type}"
      webhook_event.skip!
    end
  end

  # Stripe event handlers
  def handle_stripe_payment_succeeded(event_data, webhook_event)
    payment_intent = event_data["data"]["object"]

    payment = Payment.find_by(stripe_payment_intent_id: payment_intent["id"])
    if payment
      payment.update!(
        status: "succeeded",
        processed_at: Time.current,
        stripe_charge_id: payment_intent["charges"]["data"].first["id"]
      )

      # Mark invoice as paid if this was the last payment
      invoice = payment.invoice
      if invoice.total_cents <= invoice.payments.succeeded.sum(:amount_cents)
        invoice.update!(status: "paid", paid_at: Time.current)
      end
    end
  end

  def handle_stripe_payment_failed(event_data, webhook_event)
    payment_intent = event_data["data"]["object"]

    payment = Payment.find_by(stripe_payment_intent_id: payment_intent["id"])
    if payment
      payment.update!(
        status: "failed",
        failed_at: Time.current,
        failure_reason: payment_intent["last_payment_error"]["message"]
      )

      # Handle subscription payment failure
      if payment.invoice.subscription
        billing_service = BillingService.new(payment.invoice.subscription)
        billing_service.handle_failed_payment(payment)
      end
    end
  end

  def handle_stripe_invoice_payment_succeeded(event_data, webhook_event)
    stripe_invoice = event_data["data"]["object"]
    subscription = Subscription.find_by(stripe_subscription_id: stripe_invoice["subscription"])

    if subscription
      # Create or update local invoice record
      billing_service = BillingService.new(subscription)
      billing_service.create_invoice_from_stripe(stripe_invoice)
    end
  end

  def handle_stripe_invoice_payment_failed(event_data, webhook_event)
    stripe_invoice = event_data["data"]["object"]
    subscription = Subscription.find_by(stripe_subscription_id: stripe_invoice["subscription"])

    if subscription
      billing_service = BillingService.new(subscription)

      # Find the related payment and handle failure
      payment = Payment.find_by(
        invoice: subscription.invoices.where(stripe_invoice_id: stripe_invoice["id"])
      )

      if payment
        billing_service.handle_failed_payment(payment)
      end
    end
  end

  def handle_stripe_subscription_created(event_data, webhook_event)
    stripe_subscription = event_data["data"]["object"]
    account_id = stripe_subscription["metadata"]["account_id"]

    if account_id
      account = Account.find(account_id)
      subscription = account.subscriptions.find_by(stripe_subscription_id: stripe_subscription["id"])

      if subscription
        subscription.update!(
          status: stripe_subscription["status"],
          current_period_start: Time.at(stripe_subscription["current_period_start"]),
          current_period_end: Time.at(stripe_subscription["current_period_end"])
        )
      end
    end
  end

  def handle_stripe_subscription_updated(event_data, webhook_event)
    stripe_subscription = event_data["data"]["object"]
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription["id"])

    if subscription
      subscription.update!(
        status: stripe_subscription["status"],
        current_period_start: Time.at(stripe_subscription["current_period_start"]),
        current_period_end: Time.at(stripe_subscription["current_period_end"]),
        canceled_at: stripe_subscription["canceled_at"] ? Time.at(stripe_subscription["canceled_at"]) : nil
      )
    end
  end

  def handle_stripe_subscription_deleted(event_data, webhook_event)
    stripe_subscription = event_data["data"]["object"]
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription["id"])

    if subscription
      subscription.update!(
        status: "canceled",
        canceled_at: Time.current,
        ended_at: Time.current
      )
    end
  end

  # PayPal event handlers (placeholder implementations)
  def handle_paypal_payment_completed(event_data, webhook_event)
    Rails.logger.info "PayPal payment completed event processing not fully implemented"
  end

  def handle_paypal_payment_denied(event_data, webhook_event)
    Rails.logger.info "PayPal payment denied event processing not fully implemented"
  end

  def handle_paypal_subscription_created(event_data, webhook_event)
    Rails.logger.info "PayPal subscription created event processing not fully implemented"
  end

  def handle_paypal_subscription_cancelled(event_data, webhook_event)
    Rails.logger.info "PayPal subscription cancelled event processing not fully implemented"
  end
end
