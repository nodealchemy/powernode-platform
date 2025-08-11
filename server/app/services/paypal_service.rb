# frozen_string_literal: true

require 'paypal-sdk-rest'

class PaypalService
  include PayPal::SDK::REST
  include PayPal::SDK::Core::Logging

  attr_reader :account, :user

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Create PayPal payment order
  def create_payment_order(amount_cents:, currency: "USD", return_url: nil, cancel_url: nil, **options)
    amount = Money.new(amount_cents, currency)
    
    payment = Payment.new({
      intent: "sale",
      payer: {
        payment_method: "paypal"
      },
      redirect_urls: {
        return_url: return_url || "#{ENV['FRONTEND_URL']}/payments/paypal/return",
        cancel_url: cancel_url || "#{ENV['FRONTEND_URL']}/payments/paypal/cancel"
      },
      transactions: [{
        item_list: {
          items: options[:items] || [{
            name: options[:description] || "Payment",
            sku: "payment",
            price: amount.to_f.to_s,
            currency: currency,
            quantity: 1
          }]
        },
        amount: {
          currency: currency,
          total: amount.to_f.to_s
        },
        description: options[:description] || "Payment for account #{account.name}",
        custom: account.id, # Store account ID for webhook processing
        invoice_number: options[:invoice_number]
      }]
    })

    if payment.create
      Rails.logger.info "PayPal payment created successfully: #{payment.id}"
      
      approval_url = payment.links.find { |link| link.rel == "approval_url" }&.href
      
      {
        success: true,
        payment_id: payment.id,
        payment: payment,
        approval_url: approval_url,
        status: payment.state
      }
    else
      Rails.logger.error "PayPal payment creation failed: #{payment.error}"
      {
        success: false,
        error: payment.error,
        details: payment.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal payment creation error: #{e.message}"
    { success: false, error: e.message }
  end

  # Execute approved PayPal payment
  def execute_payment(payment_id:, payer_id:)
    payment = Payment.find(payment_id)
    
    if payment.execute(payer_id: payer_id)
      Rails.logger.info "PayPal payment executed successfully: #{payment.id}"
      
      {
        success: true,
        payment: payment,
        status: payment.state,
        transaction_id: payment.transactions.first&.related_resources&.first&.sale&.id
      }
    else
      Rails.logger.error "PayPal payment execution failed: #{payment.error}"
      {
        success: false,
        error: payment.error,
        details: payment.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal payment execution error: #{e.message}"
    { success: false, error: e.message }
  end

  # Create PayPal subscription plan
  def create_subscription_plan(plan:)
    billing_plan = Plan.new({
      name: plan.name,
      description: plan.description || "Subscription plan for #{plan.name}",
      type: "INFINITE", # Ongoing subscription
      payment_definitions: [{
        name: "Regular payment definition",
        type: "REGULAR",
        frequency: map_frequency_to_paypal(plan.billing_interval),
        frequency_interval: plan.interval_count || 1,
        amount: {
          value: plan.price.to_f.to_s,
          currency: plan.currency
        },
        cycles: "0", # Infinite cycles
        charge_models: []
      }],
      merchant_preferences: {
        auto_bill_amount: "YES",
        cancel_url: "#{ENV['FRONTEND_URL']}/subscriptions/cancel",
        return_url: "#{ENV['FRONTEND_URL']}/subscriptions/success",
        initial_fail_amount_action: "CONTINUE",
        max_fail_attempts: "3",
        setup_fee: {
          value: "0.00",
          currency: plan.currency
        }
      }
    })

    if billing_plan.create
      Rails.logger.info "PayPal billing plan created: #{billing_plan.id}"
      
      # Activate the plan
      patch = Patch.new([{
        op: "replace",
        path: "/",
        value: { state: "ACTIVE" }
      }])
      
      if billing_plan.update(patch)
        Rails.logger.info "PayPal billing plan activated: #{billing_plan.id}"
        
        {
          success: true,
          plan_id: billing_plan.id,
          billing_plan: billing_plan,
          status: "ACTIVE"
        }
      else
        Rails.logger.error "Failed to activate PayPal billing plan: #{billing_plan.error}"
        {
          success: false,
          error: "Failed to activate billing plan",
          details: billing_plan.error
        }
      end
    else
      Rails.logger.error "PayPal billing plan creation failed: #{billing_plan.error}"
      {
        success: false,
        error: billing_plan.error,
        details: billing_plan.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal subscription plan creation error: #{e.message}"
    { success: false, error: e.message }
  end

  # Create PayPal subscription agreement
  def create_subscription_agreement(plan_id:, start_date: nil, **options)
    start_date ||= (Time.current + 1.minute).iso8601
    
    agreement = Agreement.new({
      name: options[:name] || "Subscription Agreement for #{account.name}",
      description: options[:description] || "Subscription agreement",
      start_date: start_date,
      plan: {
        id: plan_id
      },
      payer: {
        payment_method: "paypal"
      }
    })

    if agreement.create
      Rails.logger.info "PayPal agreement created: #{agreement.id}"
      
      approval_url = agreement.links.find { |link| link.rel == "approval_url" }&.href
      
      {
        success: true,
        agreement_id: agreement.id,
        agreement: agreement,
        approval_url: approval_url,
        status: agreement.state
      }
    else
      Rails.logger.error "PayPal agreement creation failed: #{agreement.error}"
      {
        success: false,
        error: agreement.error,
        details: agreement.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal subscription agreement creation error: #{e.message}"
    { success: false, error: e.message }
  end

  # Execute approved subscription agreement
  def execute_subscription_agreement(agreement_id:)
    agreement = Agreement.new(id: agreement_id)
    
    if agreement.execute
      Rails.logger.info "PayPal agreement executed: #{agreement_id}"
      
      {
        success: true,
        agreement: agreement,
        status: agreement.state
      }
    else
      Rails.logger.error "PayPal agreement execution failed: #{agreement.error}"
      {
        success: false,
        error: agreement.error,
        details: agreement.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal agreement execution error: #{e.message}"
    { success: false, error: e.message }
  end

  # Cancel PayPal subscription
  def cancel_subscription(agreement_id:, reason: nil)
    agreement = Agreement.find(agreement_id)
    
    cancel_note = AgreementStateDescriptor.new({
      note: reason || "Subscription cancelled by user"
    })
    
    if agreement.cancel(cancel_note)
      Rails.logger.info "PayPal subscription cancelled: #{agreement_id}"
      
      {
        success: true,
        agreement: agreement,
        status: "Cancelled"
      }
    else
      Rails.logger.error "PayPal subscription cancellation failed: #{agreement.error}"
      {
        success: false,
        error: agreement.error,
        details: agreement.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal subscription cancellation error: #{e.message}"
    { success: false, error: e.message }
  end

  # Create refund for PayPal payment
  def create_refund(transaction_id:, amount_cents: nil, currency: "USD", reason: nil)
    sale = Sale.find(transaction_id)
    
    refund_request = if amount_cents
      amount = Money.new(amount_cents, currency)
      {
        amount: {
          total: amount.to_f.to_s,
          currency: currency
        },
        reason: reason || "Refund requested"
      }
    else
      { reason: reason || "Full refund requested" }
    end
    
    refund = sale.refund(refund_request)
    
    if refund.success?
      Rails.logger.info "PayPal refund created: #{refund.id}"
      
      {
        success: true,
        refund: refund,
        refund_id: refund.id,
        status: refund.state,
        amount_refunded: refund.amount
      }
    else
      Rails.logger.error "PayPal refund creation failed: #{refund.error}"
      {
        success: false,
        error: refund.error,
        details: refund.error_details
      }
    end
  rescue => e
    Rails.logger.error "PayPal refund creation error: #{e.message}"
    { success: false, error: e.message }
  end

  # Get payment details
  def get_payment_details(payment_id:)
    payment = Payment.find(payment_id)
    
    {
      success: true,
      payment: payment,
      status: payment.state,
      amount: payment.transactions.first&.amount,
      payer_info: payment.payer&.payer_info
    }
  rescue => e
    Rails.logger.error "PayPal payment details error: #{e.message}"
    { success: false, error: e.message }
  end

  # Get subscription details
  def get_subscription_details(agreement_id:)
    agreement = Agreement.find(agreement_id)
    
    {
      success: true,
      agreement: agreement,
      status: agreement.state,
      next_billing_date: agreement.agreement_details&.next_billing_date,
      last_payment_date: agreement.agreement_details&.last_payment_date
    }
  rescue => e
    Rails.logger.error "PayPal subscription details error: #{e.message}"
    { success: false, error: e.message }
  end

  # Verify webhook signature
  def verify_webhook_signature(webhook_id:, headers:, payload:)
    # PayPal webhook signature verification
    # This is a simplified implementation - in production you'd use PayPal's verification
    begin
      webhook_event = WebhookEvent.new({
        id: webhook_id,
        event_body: payload,
        headers: headers
      })
      
      # In a real implementation, you'd verify against PayPal's API
      # For now, we'll do basic validation
      event_data = JSON.parse(payload)
      
      {
        success: true,
        valid: event_data.key?('id') && event_data.key?('event_type'),
        event_data: event_data
      }
    rescue JSON::ParserError => e
      Rails.logger.error "PayPal webhook signature verification error: #{e.message}"
      { success: false, error: "Invalid JSON payload" }
    rescue => e
      Rails.logger.error "PayPal webhook verification error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def map_frequency_to_paypal(billing_interval)
    case billing_interval
    when 'day'
      'DAY'
    when 'week'
      'WEEK'
    when 'month'
      'MONTH'
    when 'year'
      'YEAR'
    else
      'MONTH' # Default to monthly
    end
  end
end