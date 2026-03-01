---
Last Updated: 2026-02-28
Platform Version: 0.3.0
---

# Payment Integration Specialist Guide

## Role & Responsibilities

The Payment Integration Specialist handles all payment gateway integrations, webhook processing, and payment security for Powernode's subscription platform.

### Core Responsibilities
- Integrating payment gateways (Stripe, PayPal)
- Handling webhook events and processing
- Implementing payment retry logic
- Managing payment method storage
- Handling refunds and chargebacks

### Key Focus Areas
- PCI DSS compliance and security best practices
- Robust webhook handling and validation
- Payment method tokenization and storage
- Retry mechanisms and failure handling
- Comprehensive payment audit trails

## Payment Gateway Integration Standards

### 1. Stripe Integration (MANDATORY)

#### Stripe Configuration
```ruby
# config/initializers/stripe.rb
Rails.configuration.stripe = {
  publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'],
  secret_key: ENV['STRIPE_SECRET_KEY'],
  webhook_secret: ENV['STRIPE_WEBHOOK_SECRET']
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]
Stripe.api_version = '2023-10-16'

# Enable request logging in development
if Rails.env.development?
  Stripe.log_level = Stripe::LEVEL_DEBUG
end
```

#### Stripe Service Implementation
```ruby
# app/services/stripe_service.rb
class StripeService
  class StripeServiceError < StandardError; end
  
  def initialize
    @stripe_key = Rails.configuration.stripe[:secret_key]
    validate_configuration!
  end
  
  # Create customer in Stripe
  def create_customer(account)
    customer = Stripe::Customer.create({
      email: account.primary_email,
      name: account.name,
      metadata: {
        account_id: account.id,
        environment: Rails.env
      }
    })
    
    account.update!(stripe_customer_id: customer.id)
    customer
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe customer creation failed: #{e.message}"
    raise StripeServiceError, "Failed to create customer: #{e.message}"
  end
  
  # Create subscription
  def create_subscription(account, plan, payment_method_token)
    customer = ensure_customer(account)
    
    # Attach payment method to customer
    payment_method = Stripe::PaymentMethod.attach(
      payment_method_token,
      { customer: customer.id }
    )
    
    # Create subscription
    subscription = Stripe::Subscription.create({
      customer: customer.id,
      items: [{ price: plan.stripe_price_id }],
      default_payment_method: payment_method.id,
      expand: ['latest_invoice.payment_intent'],
      metadata: {
        account_id: account.id,
        plan_id: plan.id
      }
    })
    
    # Store payment method locally
    store_payment_method(account, payment_method)
    
    subscription
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe subscription creation failed: #{e.message}"
    raise StripeServiceError, "Failed to create subscription: #{e.message}"
  end
  
  # Process payment
  def process_payment(subscription, amount_cents)
    payment_intent = Stripe::PaymentIntent.create({
      amount: amount_cents,
      currency: 'usd',
      customer: subscription.account.stripe_customer_id,
      payment_method: subscription.default_payment_method&.stripe_payment_method_id,
      confirmation_method: 'manual',
      confirm: true,
      metadata: {
        subscription_id: subscription.id,
        account_id: subscription.account_id
      }
    })
    
    # Create local payment record
    create_local_payment(subscription, payment_intent, amount_cents)
    
    payment_intent
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe payment processing failed: #{e.message}"
    raise StripeServiceError, "Payment processing failed: #{e.message}"
  end
  
  # Handle subscription updates
  def update_subscription(subscription, new_plan)
    stripe_subscription = Stripe::Subscription.retrieve(subscription.stripe_subscription_id)
    
    Stripe::Subscription.modify(stripe_subscription.id, {
      items: [{ 
        id: stripe_subscription.items.data[0].id,
        price: new_plan.stripe_price_id 
      }],
      proration_behavior: 'create_prorations',
      metadata: {
        plan_id: new_plan.id,
        updated_at: Time.current.iso8601
      }
    })
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe subscription update failed: #{e.message}"
    raise StripeServiceError, "Failed to update subscription: #{e.message}"
  end
  
  private
  
  def validate_configuration!
    required_keys = [:secret_key, :publishable_key, :webhook_secret]
    missing_keys = required_keys.reject { |key| Rails.configuration.stripe[key].present? }
    
    if missing_keys.any?
      raise StripeServiceError, "Missing Stripe configuration: #{missing_keys.join(', ')}"
    end
  end
  
  def ensure_customer(account)
    return Stripe::Customer.retrieve(account.stripe_customer_id) if account.stripe_customer_id
    
    create_customer(account)
  end
  
  def store_payment_method(account, stripe_pm)
    PaymentMethod.create!(
      account: account,
      provider: 'stripe',
      stripe_payment_method_id: stripe_pm.id,
      method_type: stripe_pm.type,
      last_four: stripe_pm.card&.last4,
      exp_month: stripe_pm.card&.exp_month,
      exp_year: stripe_pm.card&.exp_year,
      brand: stripe_pm.card&.brand,
      active: true
    )
  end
  
  def create_local_payment(subscription, payment_intent, amount_cents)
    Payment.create!(
      subscription: subscription,
      stripe_payment_intent_id: payment_intent.id,
      amount_cents: amount_cents,
      currency: payment_intent.currency,
      status: payment_intent.status,
      payment_method: subscription.default_payment_method,
      metadata: payment_intent.metadata.to_h
    )
  end
end
```

### 2. PayPal Integration (MANDATORY)

#### PayPal Configuration
```ruby
# config/initializers/paypal.rb
PayPal::SDK.configure(
  mode: Rails.env.production? ? 'live' : 'sandbox',
  client_id: ENV['PAYPAL_CLIENT_ID'],
  client_secret: ENV['PAYPAL_CLIENT_SECRET'],
  ssl_options: {
    ca_file: nil,
    verify_mode: OpenSSL::SSL::VERIFY_PEER
  }
)
```

#### PayPal Service Implementation
```ruby
# app/services/paypal_service.rb
class PaypalService
  include PayPal::SDK::REST
  
  class PaypalServiceError < StandardError; end
  
  def initialize
    validate_configuration!
  end
  
  # Create billing plan
  def create_billing_plan(plan)
    billing_plan = BillingPlan.new({
      name: plan.name,
      description: plan.description,
      type: 'INFINITE',
      payment_definitions: [{
        name: "#{plan.name} Payment",
        type: 'REGULAR',
        frequency: plan.billing_interval.upcase,
        frequency_interval: '1',
        amount: {
          currency: 'USD',
          value: plan.price.to_f.to_s
        },
        cycles: '0'
      }],
      merchant_preferences: {
        setup_fee: {
          currency: 'USD',
          value: '0'
        },
        return_url: "#{ENV['FRONTEND_URL']}/billing/success",
        cancel_url: "#{ENV['FRONTEND_URL']}/billing/cancel",
        auto_bill_amount: 'YES',
        initial_fail_amount_action: 'CONTINUE'
      }
    })
    
    if billing_plan.create
      # Activate the plan
      billing_plan.activate
      
      # Store PayPal plan ID
      plan.update!(paypal_plan_id: billing_plan.id)
      billing_plan
    else
      raise PaypalServiceError, "Failed to create billing plan: #{billing_plan.error.inspect}"
    end
  end
  
  # Create billing agreement
  def create_billing_agreement(account, plan)
    billing_agreement = BillingAgreement.new({
      name: "#{plan.name} Subscription for #{account.name}",
      description: "Subscription to #{plan.name}",
      start_date: 1.minute.from_now.iso8601,
      plan: {
        id: plan.paypal_plan_id
      },
      payer: {
        payment_method: 'paypal'
      }
    })
    
    if billing_agreement.create
      billing_agreement
    else
      raise PaypalServiceError, "Failed to create billing agreement: #{billing_agreement.error.inspect}"
    end
  end
  
  # Execute billing agreement after user approval
  def execute_billing_agreement(token, account, plan)
    billing_agreement = BillingAgreement.new({ token: token })
    
    if billing_agreement.execute
      # Create local subscription record
      subscription = account.subscriptions.create!(
        plan: plan,
        status: 'active',
        paypal_agreement_id: billing_agreement.id,
        current_period_start: Time.current,
        current_period_end: 1.month.from_now
      )
      
      billing_agreement
    else
      raise PaypalServiceError, "Failed to execute billing agreement: #{billing_agreement.error.inspect}"
    end
  end
  
  # Cancel billing agreement
  def cancel_billing_agreement(subscription)
    billing_agreement = BillingAgreement.find(subscription.paypal_agreement_id)
    
    cancel_note = {
      cancel_note: "Subscription cancelled by user"
    }
    
    if billing_agreement.cancel(cancel_note)
      subscription.update!(status: 'cancelled', cancelled_at: Time.current)
      true
    else
      raise PaypalServiceError, "Failed to cancel billing agreement: #{billing_agreement.error.inspect}"
    end
  end
  
  private
  
  def validate_configuration!
    required_env_vars = %w[PAYPAL_CLIENT_ID PAYPAL_CLIENT_SECRET]
    missing_vars = required_env_vars.reject { |var| ENV[var].present? }
    
    if missing_vars.any?
      raise PaypalServiceError, "Missing PayPal configuration: #{missing_vars.join(', ')}"
    end
  end
end
```

### 3. Webhook Processing (MANDATORY)

#### Stripe Webhook Handler
```ruby
# app/controllers/webhooks/stripe_controller.rb
class Webhooks::StripeController < ApplicationController
  skip_before_action :authenticate_request
  before_action :verify_webhook_signature
  
  def handle
    case @event.type
    when 'payment_intent.succeeded'
      handle_payment_succeeded
    when 'payment_intent.payment_failed'
      handle_payment_failed
    when 'invoice.payment_succeeded'
      handle_invoice_payment_succeeded
    when 'invoice.payment_failed'
      handle_invoice_payment_failed
    when 'customer.subscription.updated'
      handle_subscription_updated
    when 'customer.subscription.deleted'
      handle_subscription_cancelled
    else
      Rails.logger.info "Unhandled Stripe webhook event: #{@event.type}"
    end
    
    render json: { received: true }, status: :ok
  end
  
  private
  
  def verify_webhook_signature
    payload = request.raw_post
    sig_header = request.headers['Stripe-Signature']
    
    begin
      @event = Stripe::Webhook.construct_event(
        payload, sig_header, Rails.configuration.stripe[:webhook_secret]
      )
    rescue JSON::ParserError => e
      Rails.logger.error "Stripe webhook JSON parsing error: #{e.message}"
      render json: { error: 'Invalid payload' }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error "Stripe webhook signature verification failed: #{e.message}"
      render json: { error: 'Invalid signature' }, status: :bad_request
      return
    end
    
    # Log webhook for audit trail
    AuditLog.create!(
      action: 'webhook_received',
      resource_type: 'Stripe',
      resource_id: @event.id,
      details: {
        event_type: @event.type,
        created: @event.created,
        livemode: @event.livemode
      },
      ip_address: request.remote_ip,
      metadata: { user_agent: request.user_agent }
    )
  end
  
  def handle_payment_succeeded
    payment_intent = @event.data.object
    
    payment = Payment.find_by(stripe_payment_intent_id: payment_intent.id)
    if payment
      payment.update!(
        status: 'succeeded',
        processed_at: Time.current,
        metadata: payment_intent.metadata.to_h
      )
      
      # Delegate to worker for post-processing
      WorkerJobService.enqueue_billing_job('payment_succeeded', {
        payment_id: payment.id,
        payment_intent_id: payment_intent.id
      })
    end
  end
  
  def handle_payment_failed
    payment_intent = @event.data.object
    
    payment = Payment.find_by(stripe_payment_intent_id: payment_intent.id)
    if payment
      payment.update!(
        status: 'failed',
        failure_reason: payment_intent.last_payment_error&.message,
        processed_at: Time.current
      )
      
      # Delegate to worker for retry logic
      WorkerJobService.enqueue_billing_job('payment_failed', {
        payment_id: payment.id,
        subscription_id: payment.subscription_id,
        failure_reason: payment_intent.last_payment_error&.message
      })
    end
  end
  
  def handle_subscription_updated
    stripe_subscription = @event.data.object
    
    subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription.id)
    if subscription
      subscription.update!(
        status: stripe_subscription.status,
        current_period_start: Time.at(stripe_subscription.current_period_start),
        current_period_end: Time.at(stripe_subscription.current_period_end),
        metadata: stripe_subscription.metadata.to_h
      )
      
      # Broadcast update to frontend
      SubscriptionBroadcastService.broadcast_update(subscription)
    end
  end
end
```

#### PayPal Webhook Handler
```ruby
# app/controllers/webhooks/paypal_controller.rb
class Webhooks::PaypalController < ApplicationController
  skip_before_action :authenticate_request
  before_action :verify_webhook_signature
  
  def handle
    case @event_type
    when 'BILLING.SUBSCRIPTION.ACTIVATED'
      handle_subscription_activated
    when 'BILLING.SUBSCRIPTION.CANCELLED'
      handle_subscription_cancelled
    when 'PAYMENT.SALE.COMPLETED'
      handle_payment_completed
    when 'PAYMENT.SALE.DENIED'
      handle_payment_denied
    else
      Rails.logger.info "Unhandled PayPal webhook event: #{@event_type}"
    end
    
    render json: { received: true }, status: :ok
  end
  
  private
  
  def verify_webhook_signature
    @webhook_data = JSON.parse(request.raw_post)
    @event_type = @webhook_data['event_type']
    
    # PayPal webhook signature verification
    verifier = PaypalWebhookVerifier.new
    unless verifier.verify(request.headers, request.raw_post)
      Rails.logger.error "PayPal webhook signature verification failed"
      render json: { error: 'Invalid signature' }, status: :bad_request
      return
    end
    
    # Log webhook for audit trail
    AuditLog.create!(
      action: 'webhook_received',
      resource_type: 'PayPal',
      resource_id: @webhook_data['id'],
      details: {
        event_type: @event_type,
        create_time: @webhook_data['create_time'],
        summary: @webhook_data['summary']
      },
      ip_address: request.remote_ip
    )
  end
  
  def handle_subscription_activated
    agreement_id = @webhook_data.dig('resource', 'id')
    
    subscription = Subscription.find_by(paypal_agreement_id: agreement_id)
    if subscription
      subscription.update!(
        status: 'active',
        activated_at: Time.current
      )
      
      # Broadcast update
      SubscriptionBroadcastService.broadcast_update(subscription)
    end
  end
  
  def handle_payment_completed
    sale_id = @webhook_data.dig('resource', 'id')
    agreement_id = @webhook_data.dig('resource', 'billing_agreement_id')
    
    subscription = Subscription.find_by(paypal_agreement_id: agreement_id)
    if subscription
      # Create payment record
      Payment.create!(
        subscription: subscription,
        paypal_sale_id: sale_id,
        amount_cents: (@webhook_data.dig('resource', 'amount', 'total').to_f * 100).to_i,
        currency: @webhook_data.dig('resource', 'amount', 'currency'),
        status: 'succeeded',
        processed_at: Time.current,
        metadata: @webhook_data['resource']
      )
      
      # Delegate to worker
      WorkerJobService.enqueue_billing_job('paypal_payment_completed', {
        subscription_id: subscription.id,
        sale_id: sale_id
      })
    end
  end
end
```

### 4. Payment Method Security (MANDATORY)

#### Payment Method Model
```ruby
# app/models/payment_method.rb
class PaymentMethod < ApplicationRecord
  belongs_to :account
  has_many :payments, dependent: :destroy
  
  validates :provider, inclusion: { in: %w[stripe paypal] }
  validates :method_type, inclusion: { in: %w[card bank_account paypal] }
  validates :last_four, presence: true, length: { is: 4 }
  
  scope :active, -> { where(active: true) }
  scope :cards, -> { where(method_type: 'card') }
  
  # Never store full payment details
  def display_name
    case method_type
    when 'card'
      "#{brand&.capitalize} ending in #{last_four}"
    when 'paypal'
      "PayPal (#{email})"
    when 'bank_account'
      "Bank ending in #{last_four}"
    else
      "Payment method ending in #{last_four}"
    end
  end
  
  def expired?
    return false unless exp_month && exp_year
    Date.new(exp_year, exp_month, -1) < Date.current
  end
end
```

#### PCI Compliance Validation
```ruby
# app/services/payment_method_security_validator.rb
class PaymentMethodSecurityValidator
  PCI_VIOLATION_PATTERNS = [
    /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,  # Full credit card numbers
    /\b\d{3,4}\b.*\b\d{2}\/\d{2,4}\b/,             # CVV with expiration
    /pan|primary.account.number/i,                   # PAN references
    /cvv|cvc|security.code/i                         # Security codes
  ].freeze
  
  def self.validate_data(data)
    violations = []
    
    data_string = data.to_json.downcase
    
    PCI_VIOLATION_PATTERNS.each do |pattern|
      if data_string.match?(pattern)
        violations << "Potential PCI violation: #{pattern.source}"
      end
    end
    
    violations
  end
  
  def self.sanitize_payment_data(params)
    # Remove sensitive fields that should never be stored
    sensitive_fields = %w[
      card_number cvv cvc security_code pan
      full_name billing_address
    ]
    
    params.deep_dup.tap do |sanitized|
      sensitive_fields.each do |field|
        sanitized.delete(field)
        sanitized.delete(field.to_sym)
      end
    end
  end
end
```

### 5. Payment Retry Logic (MANDATORY)

#### Retry Service Implementation
```ruby
# app/services/payment_retry_service.rb
class PaymentRetryService < BaseService
  attribute :payment, Payment
  
  RETRY_SCHEDULE = [1.day, 3.days, 5.days, 7.days].freeze
  MAX_RETRIES = RETRY_SCHEDULE.length
  
  def call
    return failure("Payment not found") unless payment
    return failure("Payment already succeeded") if payment.succeeded?
    return failure("Maximum retries exceeded") if max_retries_exceeded?
    
    begin
      result = process_retry
      
      if result.success?
        success({ payment: payment_data(payment) })
      else
        schedule_next_retry
        failure("Retry failed", result.details)
      end
    rescue StandardError => e
      Rails.logger.error "Payment retry failed: #{e.message}"
      failure("Retry processing error", { error: e.message })
    end
  end
  
  private
  
  def process_retry
    case payment.provider
    when 'stripe'
      StripeService.new.retry_payment(payment)
    when 'paypal'
      PaypalService.new.retry_payment(payment)
    else
      ServiceResult.new(success: false, error: "Unknown payment provider")
    end
  end
  
  def max_retries_exceeded?
    payment.retry_count >= MAX_RETRIES
  end
  
  def schedule_next_retry
    next_retry_delay = RETRY_SCHEDULE[payment.retry_count]
    
    if next_retry_delay
      # Delegate to worker service
      WorkerJobService.enqueue_billing_job('payment_retry', {
        payment_id: payment.id,
        retry_attempt: payment.retry_count + 1,
        scheduled_at: next_retry_delay.from_now.iso8601
      })
      
      payment.update!(
        retry_count: payment.retry_count + 1,
        next_retry_at: next_retry_delay.from_now
      )
    else
      # Mark as permanently failed
      payment.update!(
        status: 'permanently_failed',
        retry_count: payment.retry_count + 1
      )
      
      # Notify customer
      WorkerJobService.enqueue_billing_job('payment_permanently_failed', {
        subscription_id: payment.subscription_id,
        payment_id: payment.id
      })
    end
  end
end
```

### 6. Refund and Chargeback Handling (MANDATORY)

#### Refund Service
```ruby
# app/services/refund_service.rb
class RefundService < BaseService
  attribute :payment, Payment
  attribute :amount_cents, Integer
  attribute :reason, String
  
  validates :payment, :reason, presence: true
  
  def call
    return failure("Invalid parameters", errors.full_messages) unless valid?
    return failure("Payment not refundable") unless payment.refundable?
    
    begin
      case payment.provider
      when 'stripe'
        process_stripe_refund
      when 'paypal'
        process_paypal_refund
      else
        failure("Unsupported payment provider")
      end
    rescue StandardError => e
      Rails.logger.error "Refund processing failed: #{e.message}"
      failure("Refund failed", { error: e.message })
    end
  end
  
  private
  
  def process_stripe_refund
    refund_amount = amount_cents || payment.amount_cents
    
    stripe_refund = Stripe::Refund.create({
      payment_intent: payment.stripe_payment_intent_id,
      amount: refund_amount,
      reason: map_refund_reason(reason),
      metadata: {
        payment_id: payment.id,
        refund_reason: reason
      }
    })
    
    # Create local refund record
    create_refund_record(stripe_refund, refund_amount)
    
    success({ refund_id: stripe_refund.id, amount_cents: refund_amount })
  end
  
  def process_paypal_refund
    # PayPal refund implementation
    refund_amount = amount_cents || payment.amount_cents
    
    sale = Sale.find(payment.paypal_sale_id)
    refund_request = RefundRequest.new({
      amount: {
        total: (refund_amount / 100.0).to_s,
        currency: payment.currency.upcase
      },
      reason: reason
    })
    
    refund = sale.refund(refund_request)
    
    if refund.success?
      create_refund_record(refund, refund_amount)
      success({ refund_id: refund.id, amount_cents: refund_amount })
    else
      failure("PayPal refund failed", { error: refund.error })
    end
  end
  
  def create_refund_record(gateway_refund, amount_cents)
    Refund.create!(
      payment: payment,
      amount_cents: amount_cents,
      reason: reason,
      provider_refund_id: gateway_refund.id,
      status: 'processed',
      processed_at: Time.current,
      metadata: gateway_refund.to_h
    )
    
    # Update payment status
    payment.update!(refunded_amount_cents: payment.refunded_amount_cents + amount_cents)
  end
  
  def map_refund_reason(reason)
    case reason.downcase
    when /duplicate/
      'duplicate'
    when /fraud/
      'fraudulent'
    when /customer/
      'requested_by_customer'
    else
      'requested_by_customer'
    end
  end
end
```

### 7. Security and Compliance (MANDATORY)

#### PCI DSS Compliance Headers
```ruby
# app/middleware/pci_security_headers.rb
class PciSecurityHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    
    # PCI DSS required headers
    headers['X-Frame-Options'] = 'DENY'
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-XSS-Protection'] = '1; mode=block'
    headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload'
    headers['Content-Security-Policy'] = build_csp_header
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # Remove server information
    headers.delete('Server')
    headers.delete('X-Powered-By')
    
    [status, headers, response]
  end
  
  private
  
  def build_csp_header
    [
      "default-src 'self'",
      "script-src 'self' js.stripe.com",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https:",
      "connect-src 'self' api.stripe.com",
      "frame-src js.stripe.com hooks.stripe.com",
      "object-src 'none'",
      "base-uri 'none'"
    ].join('; ')
  end
end
```

#### Sensitive Data Sanitizer
```ruby
# app/services/sensitive_data_sanitizer.rb
class SensitiveDataSanitizer
  SENSITIVE_PATTERNS = {
    credit_card: /\b(?:\d[ -]*?){13,19}\b/,
    ssn: /\b\d{3}-?\d{2}-?\d{4}\b/,
    email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
    phone: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/
  }.freeze
  
  def self.sanitize(text)
    return text unless text.is_a?(String)
    
    sanitized = text.dup
    
    SENSITIVE_PATTERNS.each do |type, pattern|
      sanitized.gsub!(pattern, "[#{type.to_s.upcase}_REDACTED]")
    end
    
    sanitized
  end
  
  def self.sanitize_hash(hash)
    hash.deep_transform_values do |value|
      value.is_a?(String) ? sanitize(value) : value
    end
  end
  
  def self.log_safe(data)
    case data
    when Hash
      sanitize_hash(data)
    when String
      sanitize(data)
    else
      data
    end
  end
end
```

## Development Commands

### Payment Gateway Setup
```bash
# Install payment gems
bundle add stripe paypal-sdk-rest

# Generate payment controllers and models
rails generate controller Webhooks::Stripe
rails generate controller Webhooks::Paypal
rails generate model PaymentMethod account:references provider:string
rails generate model Payment subscription:references amount_cents:integer
rails generate model Refund payment:references amount_cents:integer

# Run payment-related migrations
rails db:migrate

# Test webhook endpoints
curl -X POST localhost:3000/webhooks/stripe \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
```

### Security Testing
```bash
# Test PCI compliance
curl -I localhost:3000/api/v1/subscriptions

# Validate webhook signatures
rails runner "puts StripeWebhookVerifier.verify(headers, payload)"

# Test payment processing in console
rails console
> StripeService.new.create_customer(Account.first)
> PaypalService.new.create_billing_plan(Plan.first)
```

## Integration Points

### Payment Integration Specialist Coordinates With:
- **Billing Engine Developer**: Subscription lifecycle, payment processing
- **Backend Job Engineer**: Webhook processing, retry mechanisms
- **Security Specialist**: PCI compliance, data protection
- **API Developer**: Payment endpoint security, error handling
- **Notification Engineer**: Payment failure notifications, receipts

## Quick Reference

### Payment Processing Flow
1. **Customer Setup**: Create customer in payment gateway
2. **Payment Method**: Tokenize and store payment method securely
3. **Subscription Creation**: Create recurring billing setup
4. **Payment Processing**: Process individual payments
5. **Webhook Handling**: Process gateway notifications
6. **Retry Logic**: Handle failed payments automatically
7. **Refund Processing**: Handle refund requests
8. **Audit Logging**: Track all payment operations

### Security Checklist
- ✅ Never store full payment card data
- ✅ Use tokenization for payment methods
- ✅ Validate webhook signatures
- ✅ Implement PCI DSS security headers
- ✅ Sanitize all logged data
- ✅ Use HTTPS for all payment communications
- ✅ Implement proper error handling without exposing sensitive data
- ✅ Regular security audits and penetration testing

**ALWAYS REFERENCE ../TODO.md FOR CURRENT TASKS AND PRIORITIES**