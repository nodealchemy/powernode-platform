# frozen_string_literal: true

# Webhook Test Helpers
#
# Provides methods for mocking webhook payloads and signatures from
# external payment providers (Stripe, PayPal) during testing.
#
# Usage:
#   let(:payload) { mock_stripe_webhook(:checkout_session_completed) }
#   post '/api/v1/webhooks/stripe', params: payload[:body], headers: payload[:headers]
#
module WebhookTestHelpers
  # =============================================================================
  # STRIPE WEBHOOK HELPERS
  # =============================================================================

  # Generate a mock Stripe webhook payload with valid signature
  # @param event_type [Symbol, String] The Stripe event type
  # @param data [Hash] Custom data to merge into the event
  # @return [Hash] Hash with :body and :headers keys
  def mock_stripe_webhook(event_type, data: {})
    event = build_stripe_event(event_type, data)
    signature = generate_stripe_signature(event.to_json)

    {
      body: event.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'Stripe-Signature' => signature
      },
      event: event
    }
  end

  # Generate a valid Stripe webhook signature
  # @param payload [String] The JSON payload
  # @param timestamp [Integer] Unix timestamp (defaults to current time)
  # @return [String] The Stripe-Signature header value
  def generate_stripe_signature(payload, timestamp: Time.current.to_i)
    secret = stripe_webhook_secret
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, signed_payload)

    "t=#{timestamp},v1=#{signature}"
  end

  # Build a Stripe event structure
  # @param event_type [Symbol, String] The event type
  # @param data [Hash] Custom data
  # @return [Hash] Stripe event structure
  def build_stripe_event(event_type, data = {})
    event_type = event_type.to_s.tr('_', '.')

    base_event = {
      id: "evt_#{SecureRandom.hex(12)}",
      object: 'event',
      api_version: '2023-10-16',
      created: Time.current.to_i,
      type: event_type,
      livemode: false,
      pending_webhooks: 1,
      request: {
        id: "req_#{SecureRandom.hex(12)}",
        idempotency_key: SecureRandom.uuid
      },
      data: {
        object: stripe_event_object(event_type, data)
      }
    }

    deep_merge_hash(base_event, data.slice(:id, :type, :data))
  end

  # Get the Stripe webhook secret for testing
  def stripe_webhook_secret
    ENV.fetch('STRIPE_WEBHOOK_SECRET', 'whsec_test_secret_key_for_testing')
  end

  # =============================================================================
  # STRIPE EVENT OBJECTS
  # =============================================================================

  # Build the appropriate object for a Stripe event type
  def stripe_event_object(event_type, data = {})
    case event_type
    when 'checkout.session.completed'
      stripe_checkout_session(data)
    when 'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted'
      stripe_subscription(data)
    when 'invoice.paid', 'invoice.payment_failed', 'invoice.payment_succeeded'
      stripe_invoice(data)
    when 'payment_intent.succeeded', 'payment_intent.payment_failed'
      stripe_payment_intent(data)
    when 'customer.created', 'customer.updated', 'customer.deleted'
      stripe_customer(data)
    when 'charge.succeeded', 'charge.failed', 'charge.refunded'
      stripe_charge(data)
    else
      { id: "obj_#{SecureRandom.hex(12)}" }.merge(data[:object] || {})
    end
  end

  def stripe_checkout_session(data = {})
    {
      id: data[:session_id] || "cs_test_#{SecureRandom.hex(12)}",
      object: 'checkout.session',
      mode: data[:mode] || 'subscription',
      status: 'complete',
      payment_status: 'paid',
      customer: data[:customer_id] || "cus_#{SecureRandom.hex(12)}",
      subscription: data[:subscription_id] || "sub_#{SecureRandom.hex(12)}",
      client_reference_id: data[:client_reference_id],
      metadata: data[:metadata] || {},
      amount_total: data[:amount_total] || 2999,
      currency: data[:currency] || 'usd'
    }
  end

  def stripe_subscription(data = {})
    {
      id: data[:subscription_id] || "sub_#{SecureRandom.hex(12)}",
      object: 'subscription',
      status: data[:status] || 'active',
      customer: data[:customer_id] || "cus_#{SecureRandom.hex(12)}",
      current_period_start: (data[:period_start] || Time.current).to_i,
      current_period_end: (data[:period_end] || 1.month.from_now).to_i,
      cancel_at_period_end: data[:cancel_at_period_end] || false,
      canceled_at: data[:canceled_at]&.to_i,
      metadata: data[:metadata] || {},
      items: {
        data: [{
          id: "si_#{SecureRandom.hex(12)}",
          price: {
            id: data[:price_id] || "price_#{SecureRandom.hex(12)}",
            unit_amount: data[:amount] || 2999,
            currency: data[:currency] || 'usd'
          }
        }]
      }
    }
  end

  def stripe_invoice(data = {})
    {
      id: data[:invoice_id] || "in_#{SecureRandom.hex(12)}",
      object: 'invoice',
      status: data[:status] || 'paid',
      customer: data[:customer_id] || "cus_#{SecureRandom.hex(12)}",
      subscription: data[:subscription_id] || "sub_#{SecureRandom.hex(12)}",
      amount_paid: data[:amount_paid] || 2999,
      amount_due: data[:amount_due] || 2999,
      currency: data[:currency] || 'usd',
      hosted_invoice_url: "https://invoice.stripe.com/i/#{SecureRandom.hex(12)}",
      invoice_pdf: "https://pay.stripe.com/invoice/#{SecureRandom.hex(12)}/pdf",
      metadata: data[:metadata] || {}
    }
  end

  def stripe_payment_intent(data = {})
    {
      id: data[:payment_intent_id] || "pi_#{SecureRandom.hex(12)}",
      object: 'payment_intent',
      status: data[:status] || 'succeeded',
      amount: data[:amount] || 2999,
      currency: data[:currency] || 'usd',
      customer: data[:customer_id] || "cus_#{SecureRandom.hex(12)}",
      payment_method: data[:payment_method_id] || "pm_#{SecureRandom.hex(12)}",
      metadata: data[:metadata] || {}
    }
  end

  def stripe_customer(data = {})
    {
      id: data[:customer_id] || "cus_#{SecureRandom.hex(12)}",
      object: 'customer',
      email: data[:email] || "customer@example.com",
      name: data[:name] || "Test Customer",
      metadata: data[:metadata] || {}
    }
  end

  def stripe_charge(data = {})
    {
      id: data[:charge_id] || "ch_#{SecureRandom.hex(12)}",
      object: 'charge',
      status: data[:status] || 'succeeded',
      amount: data[:amount] || 2999,
      currency: data[:currency] || 'usd',
      customer: data[:customer_id] || "cus_#{SecureRandom.hex(12)}",
      payment_intent: data[:payment_intent_id] || "pi_#{SecureRandom.hex(12)}",
      refunded: data[:refunded] || false,
      metadata: data[:metadata] || {}
    }
  end

  # =============================================================================
  # PAYPAL WEBHOOK HELPERS
  # =============================================================================

  # Generate a mock PayPal webhook payload
  # @param event_type [Symbol, String] The PayPal event type
  # @param data [Hash] Custom data to merge into the event
  # @return [Hash] Hash with :body and :headers keys
  def mock_paypal_webhook(event_type, data: {})
    event = build_paypal_event(event_type, data)

    {
      body: event.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'PayPal-Transmission-Id' => SecureRandom.uuid,
        'PayPal-Transmission-Time' => Time.current.iso8601,
        'PayPal-Transmission-Sig' => generate_paypal_signature(event.to_json),
        'PayPal-Cert-Url' => 'https://api.sandbox.paypal.com/v1/notifications/certs/CERT-123',
        'PayPal-Auth-Algo' => 'SHA256withRSA'
      },
      event: event
    }
  end

  # Generate a mock PayPal signature (for testing only)
  def generate_paypal_signature(payload)
    # In tests, we typically mock the verification
    Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(payload))
  end

  # Build a PayPal event structure
  def build_paypal_event(event_type, data = {})
    event_type = event_type.to_s.upcase.tr('_', '.')

    {
      id: "WH-#{SecureRandom.hex(8).upcase}-#{SecureRandom.hex(8).upcase}",
      event_version: '1.0',
      create_time: Time.current.iso8601,
      resource_type: paypal_resource_type(event_type),
      event_type: event_type,
      summary: "A #{event_type.downcase.tr('.', ' ')} event occurred",
      resource: paypal_event_resource(event_type, data)
    }
  end

  def paypal_resource_type(event_type)
    case event_type
    when /^BILLING\.SUBSCRIPTION/
      'subscription'
    when /^PAYMENT\.CAPTURE/, /^PAYMENT\.SALE/
      'capture'
    when /^CHECKOUT\.ORDER/
      'checkout-order'
    when /^INVOICING\.INVOICE/
      'invoice'
    else
      'resource'
    end
  end

  def paypal_event_resource(event_type, data = {})
    case event_type
    when 'BILLING.SUBSCRIPTION.CREATED', 'BILLING.SUBSCRIPTION.ACTIVATED',
         'BILLING.SUBSCRIPTION.CANCELLED', 'BILLING.SUBSCRIPTION.SUSPENDED'
      paypal_subscription(data)
    when 'PAYMENT.CAPTURE.COMPLETED', 'PAYMENT.CAPTURE.DENIED'
      paypal_capture(data)
    when 'CHECKOUT.ORDER.APPROVED', 'CHECKOUT.ORDER.COMPLETED'
      paypal_order(data)
    else
      { id: data[:resource_id] || SecureRandom.uuid }
    end
  end

  def paypal_subscription(data = {})
    {
      id: data[:subscription_id] || "I-#{SecureRandom.hex(8).upcase}",
      plan_id: data[:plan_id] || "P-#{SecureRandom.hex(8).upcase}",
      status: data[:status] || 'ACTIVE',
      status_update_time: Time.current.iso8601,
      start_time: (data[:start_time] || Time.current).iso8601,
      subscriber: {
        email_address: data[:email] || 'subscriber@example.com',
        name: {
          given_name: data[:first_name] || 'Test',
          surname: data[:last_name] || 'User'
        },
        payer_id: data[:payer_id] || SecureRandom.hex(8).upcase
      },
      billing_info: {
        cycle_executions: [{
          tenure_type: 'REGULAR',
          sequence: 1,
          cycles_completed: data[:cycles_completed] || 1,
          cycles_remaining: data[:cycles_remaining] || 0
        }],
        last_payment: {
          amount: {
            currency_code: data[:currency] || 'USD',
            value: data[:amount] || '29.99'
          },
          time: Time.current.iso8601
        },
        next_billing_time: (data[:next_billing] || 1.month.from_now).iso8601
      },
      custom_id: data[:custom_id]
    }
  end

  def paypal_capture(data = {})
    {
      id: data[:capture_id] || SecureRandom.hex(8).upcase,
      status: data[:status] || 'COMPLETED',
      amount: {
        currency_code: data[:currency] || 'USD',
        value: data[:amount] || '29.99'
      },
      final_capture: true,
      seller_protection: {
        status: 'ELIGIBLE'
      },
      create_time: Time.current.iso8601,
      update_time: Time.current.iso8601,
      custom_id: data[:custom_id]
    }
  end

  def paypal_order(data = {})
    {
      id: data[:order_id] || SecureRandom.hex(8).upcase,
      status: data[:status] || 'APPROVED',
      intent: 'CAPTURE',
      purchase_units: [{
        reference_id: data[:reference_id] || 'default',
        amount: {
          currency_code: data[:currency] || 'USD',
          value: data[:amount] || '29.99'
        },
        custom_id: data[:custom_id]
      }],
      payer: {
        email_address: data[:email] || 'payer@example.com',
        payer_id: data[:payer_id] || SecureRandom.hex(8).upcase
      },
      create_time: Time.current.iso8601,
      update_time: Time.current.iso8601
    }
  end

  # =============================================================================
  # WEBHOOK VERIFICATION HELPERS
  # =============================================================================

  # Stub Stripe webhook signature verification to always pass
  def stub_stripe_webhook_verification
    allow(Stripe::Webhook).to receive(:construct_event).and_call_original
  end

  # Stub Stripe webhook signature verification to fail
  def stub_stripe_webhook_verification_failure
    allow(Stripe::Webhook).to receive(:construct_event)
      .and_raise(Stripe::SignatureVerificationError.new('Invalid signature', 'sig_header'))
  end

  # Stub PayPal webhook verification to always pass
  def stub_paypal_webhook_verification
    # PayPal verification is typically done via API call
    # Stub the verification service
    allow_any_instance_of(Payments::PaypalWebhookService)
      .to receive(:verify_webhook_signature)
      .and_return(true)
  end

  # Stub PayPal webhook verification to fail
  def stub_paypal_webhook_verification_failure
    allow_any_instance_of(Payments::PaypalWebhookService)
      .to receive(:verify_webhook_signature)
      .and_return(false)
  end

  private

  def deep_merge_hash(hash1, hash2)
    hash1.merge(hash2) do |_key, old_val, new_val|
      if old_val.is_a?(Hash) && new_val.is_a?(Hash)
        deep_merge_hash(old_val, new_val)
      else
        new_val
      end
    end
  end
end

RSpec.configure do |config|
  config.include WebhookTestHelpers, type: :request
  config.include WebhookTestHelpers, type: :controller
end
