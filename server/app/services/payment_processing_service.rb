class PaymentProcessingService
  include ActiveModel::Model

  attr_accessor :account, :user

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Create payment intent for one-time payments
  def create_payment_intent(amount_cents:, currency: "USD", payment_method: nil, **options)
    case payment_method&.provider || options[:provider] || "stripe"
    when "stripe"
      create_stripe_payment_intent(amount_cents, currency, payment_method, options)
    when "paypal"
      create_paypal_payment_intent(amount_cents, currency, payment_method, options)
    else
      { success: false, error: "Unsupported payment provider" }
    end
  rescue => e
    Rails.logger.error "Payment intent creation failed: #{e.message}"
    { success: false, error: e.message }
  end

  # Process payment with retry logic
  def process_payment(payment:, retry_attempt: 0)
    return { success: false, error: "Too many retry attempts" } if retry_attempt > 3

    case payment.payment_method
    when "stripe_card", "stripe_bank"
      process_stripe_payment(payment, retry_attempt)
    when "paypal"
      process_paypal_payment(payment, retry_attempt)
    else
      { success: false, error: "Unsupported payment method" }
    end
  rescue => e
    Rails.logger.error "Payment processing failed: #{e.message}"
    { success: false, error: e.message, retry_attempt: retry_attempt }
  end

  # Retry failed payment
  def retry_payment(payment:)
    return { success: false, error: "Payment not in failed state" } unless payment.failed?

    retry_attempt = (payment.metadata_parsed["retry_attempt"] || 0) + 1
    result = process_payment(payment: payment, retry_attempt: retry_attempt)

    # Update payment with retry metadata
    payment.add_metadata("retry_attempt", retry_attempt)
    payment.add_metadata("last_retry_at", Time.current.iso8601)

    result
  end

  # Create refund
  def create_refund(payment:, amount_cents: nil, reason: nil)
    amount_cents ||= payment.amount_cents

    case payment.payment_method
    when "stripe_card", "stripe_bank"
      create_stripe_refund(payment, amount_cents, reason)
    when "paypal"
      create_paypal_refund(payment, amount_cents, reason)
    else
      { success: false, error: "Refunds not supported for this payment method" }
    end
  rescue => e
    Rails.logger.error "Refund creation failed: #{e.message}"
    { success: false, error: e.message }
  end

  # Attach payment method to customer
  def attach_payment_method(payment_method_id:, provider: "stripe")
    case provider
    when "stripe"
      attach_stripe_payment_method(payment_method_id)
    when "paypal"
      attach_paypal_payment_method(payment_method_id)
    else
      { success: false, error: "Unsupported provider" }
    end
  rescue => e
    Rails.logger.error "Payment method attachment failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # Stripe-specific methods
  def create_stripe_payment_intent(amount_cents, currency, payment_method, options)
    customer = ensure_stripe_customer

    intent_params = {
      amount: amount_cents,
      currency: currency.downcase,
      customer: customer.id,
      metadata: {
        account_id: account.id,
        user_id: user.id
      }
    }

    if payment_method
      intent_params[:payment_method] = payment_method.provider_payment_method_id
      intent_params[:confirmation_method] = "manual"
      intent_params[:confirm] = true
    end

    intent_params.merge!(options.slice(:description, :receipt_email, :statement_descriptor))

    stripe_intent = Stripe::PaymentIntent.create(intent_params)

    {
      success: true,
      payment_intent: stripe_intent,
      client_secret: stripe_intent.client_secret,
      status: stripe_intent.status
    }
  end

  def process_stripe_payment(payment, retry_attempt)
    if payment.stripe_payment_intent_id
      # Retrieve and confirm existing payment intent
      intent = Stripe::PaymentIntent.retrieve(payment.stripe_payment_intent_id)

      if intent.status == "requires_confirmation"
        intent = Stripe::PaymentIntent.confirm(intent.id)
      end
    else
      return { success: false, error: "No Stripe payment intent found" }
    end

    case intent.status
    when "succeeded"
      payment.update!(
        status: "succeeded",
        processed_at: Time.current,
        stripe_charge_id: intent.charges.data.first&.id
      )
      { success: true, payment_intent: intent }
    when "requires_action"
      { success: false, error: "Payment requires additional action", requires_action: true }
    when "processing"
      { success: false, error: "Payment is still processing", processing: true }
    else
      { success: false, error: "Payment failed with status: #{intent.status}" }
    end
  end

  def create_stripe_refund(payment, amount_cents, reason)
    refund_params = {
      charge: payment.stripe_charge_id,
      amount: amount_cents,
      reason: reason || "requested_by_customer",
      metadata: {
        account_id: account.id,
        original_payment_id: payment.id
      }
    }

    refund = Stripe::Refund.create(refund_params)

    # Update payment status
    if refund.amount == payment.amount_cents
      payment.update!(status: "refunded")
    else
      payment.update!(status: "partially_refunded")
    end

    {
      success: true,
      refund: refund,
      amount_refunded: refund.amount
    }
  end

  def attach_stripe_payment_method(payment_method_id)
    customer = ensure_stripe_customer

    payment_method = Stripe::PaymentMethod.retrieve(payment_method_id)
    payment_method.attach(customer: customer.id)

    # Create local payment method record
    local_payment_method = account.payment_methods.create!(
      user: user,
      provider: "stripe",
      provider_payment_method_id: payment_method.id,
      payment_method_type: map_stripe_payment_method_type(payment_method.type),
      card_brand: payment_method.card&.brand,
      card_last_four: payment_method.card&.last4,
      bank_account_last_four: payment_method.us_bank_account&.last4,
      metadata: {
        stripe_data: payment_method.to_hash
      }
    )

    {
      success: true,
      payment_method: local_payment_method,
      stripe_payment_method: payment_method
    }
  end

  # PayPal-specific methods
  def create_paypal_payment_intent(amount_cents, currency, payment_method, options)
    # PayPal payment intent creation
    # This would integrate with PayPal's Orders API
    {
      success: true,
      message: "PayPal integration not fully implemented yet"
    }
  end

  def process_paypal_payment(payment, retry_attempt)
    # PayPal payment processing
    {
      success: true,
      message: "PayPal processing not fully implemented yet"
    }
  end

  def create_paypal_refund(payment, amount_cents, reason)
    # PayPal refund creation
    {
      success: true,
      message: "PayPal refunds not fully implemented yet"
    }
  end

  def attach_paypal_payment_method(payment_method_id)
    # PayPal payment method attachment
    {
      success: true,
      message: "PayPal payment method attachment not fully implemented yet"
    }
  end

  # Helper methods
  def ensure_stripe_customer
    return @stripe_customer if @stripe_customer

    if account.stripe_customer_id.present?
      @stripe_customer = Stripe::Customer.retrieve(account.stripe_customer_id)
    else
      @stripe_customer = Stripe::Customer.create({
        email: user.email,
        name: user.full_name,
        metadata: {
          account_id: account.id,
          user_id: user.id
        }
      })

      account.update!(stripe_customer_id: @stripe_customer.id)
    end

    @stripe_customer
  end

  def map_stripe_payment_method_type(stripe_type)
    case stripe_type
    when "card"
      "card"
    when "us_bank_account", "sepa_debit"
      "bank_account"
    else
      stripe_type
    end
  end
end
