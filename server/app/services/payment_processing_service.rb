# frozen_string_literal: true

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

  # Attach payment method to customer with security validation
  def attach_payment_method(payment_method_id:, provider: "stripe", request_metadata: {})
    # First perform security validation
    if provider == "stripe"
      stripe_payment_method = Stripe::PaymentMethod.retrieve(payment_method_id)
      
      security_validator = PaymentMethodSecurityValidator.new(
        account: account,
        user: user,
        payment_method_data: stripe_payment_method.to_hash.merge('provider' => provider),
        request_metadata: request_metadata
      )
      
      validation_result = security_validator.validate
      
      # Block high-risk payment methods
      if validation_result[:recommendation] == 'reject'
        return {
          success: false,
          error: "Payment method rejected due to security concerns",
          security_validation: validation_result
        }
      end
      
      # Require additional verification for risky payment methods
      if validation_result[:requires_additional_verification]
        return {
          success: false,
          error: "Additional verification required",
          requires_verification: true,
          security_validation: validation_result
        }
      end
    end
    
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
    paypal_service = PaypalService.new(account: account, user: user)
    
    result = paypal_service.create_payment_order(
      amount_cents: amount_cents,
      currency: currency,
      return_url: options[:return_url],
      cancel_url: options[:cancel_url],
      description: options[:description],
      invoice_number: options[:invoice_number],
      items: options[:items]
    )
    
    if result[:success]
      {
        success: true,
        payment_id: result[:payment_id],
        approval_url: result[:approval_url],
        status: result[:status]
      }
    else
      result
    end
  end

  def process_paypal_payment(payment, retry_attempt)
    return { success: false, error: "No PayPal payment ID found" } unless payment.paypal_payment_id

    paypal_service = PaypalService.new(account: account, user: user)
    
    # For existing PayPal payments, we need the payer_id from the return flow
    # This method would typically be called after the user returns from PayPal
    payer_id = payment.metadata_parsed["payer_id"]
    
    return { success: false, error: "PayPal payer ID required" } unless payer_id
    
    result = paypal_service.execute_payment(
      payment_id: payment.paypal_payment_id,
      payer_id: payer_id
    )
    
    if result[:success]
      payment.update!(
        status: result[:status] == "approved" ? "succeeded" : result[:status],
        processed_at: Time.current,
        paypal_transaction_id: result[:transaction_id]
      )
      
      { success: true, payment: result[:payment] }
    else
      payment.update!(status: "failed", error_message: result[:error])
      result
    end
  end

  def create_paypal_refund(payment, amount_cents, reason)
    return { success: false, error: "No PayPal transaction ID found" } unless payment.paypal_transaction_id

    paypal_service = PaypalService.new(account: account, user: user)
    
    result = paypal_service.create_refund(
      transaction_id: payment.paypal_transaction_id,
      amount_cents: amount_cents,
      reason: reason
    )
    
    if result[:success]
      # Update payment status
      if result[:amount_refunded].try(:[], :total).to_f == payment.amount.to_f
        payment.update!(status: "refunded")
      else
        payment.update!(status: "partially_refunded")
      end
      
      {
        success: true,
        refund: result[:refund],
        refund_id: result[:refund_id],
        amount_refunded: result[:amount_refunded]
      }
    else
      result
    end
  end

  def attach_paypal_payment_method(payment_method_id)
    # PayPal doesn't use the same "attach" model as Stripe
    # PayPal payment methods are typically handled through agreements for subscriptions
    # For one-time payments, the payment method is handled in the payment flow
    
    # Create a local record for tracking
    local_payment_method = account.payment_methods.create!(
      user: user,
      provider: "paypal",
      provider_payment_method_id: payment_method_id,
      payment_method_type: "paypal_account",
      metadata: {
        paypal_payer_id: payment_method_id
      }
    )

    {
      success: true,
      payment_method: local_payment_method,
      message: "PayPal payment method recorded"
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
