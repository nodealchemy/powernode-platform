# frozen_string_literal: true

# Unified exception hierarchy for billing/payment/subscription operations.
# All billing-related code should use these exceptions for consistent
# error handling and Sidekiq retry behavior.
module BillingExceptions
  # Base class for all billing-related exceptions
  class BillingError < StandardError
    attr_reader :code, :details, :recoverable, :retry_after

    def initialize(message, code: nil, details: {}, recoverable: true, retry_after: nil)
      super(message)
      @code = code || "BILLING_ERROR"
      @details = details
      @recoverable = recoverable
      @retry_after = retry_after
    end

    def to_h
      {
        code: code,
        message: message,
        details: details,
        recoverable: recoverable,
        retry_after: retry_after
      }.compact
    end
  end

  # Payment processing errors (Stripe, PayPal API failures)
  class PaymentError < BillingError
    def initialize(message, provider: nil, payment_id: nil, details: {})
      super(
        message,
        code: "PAYMENT_ERROR",
        details: details.merge(provider: provider, payment_id: payment_id).compact,
        recoverable: true
      )
    end
  end

  # Refund processing errors
  class RefundError < BillingError
    def initialize(message, payment_id: nil, refund_amount: nil, details: {})
      super(
        message,
        code: "REFUND_ERROR",
        details: details.merge(payment_id: payment_id, refund_amount: refund_amount).compact,
        recoverable: false
      )
    end
  end

  # Subscription lifecycle errors
  class SubscriptionError < BillingError
    def initialize(message, subscription_id: nil, action: nil, details: {})
      super(
        message,
        code: "SUBSCRIPTION_ERROR",
        details: details.merge(subscription_id: subscription_id, action: action).compact,
        recoverable: true
      )
    end
  end

  # Payment gateway configuration/connectivity errors
  class GatewayError < BillingError
    def initialize(message, gateway: nil, operation: nil, details: {})
      super(
        message,
        code: "GATEWAY_ERROR",
        details: details.merge(gateway: gateway, operation: operation).compact,
        recoverable: true
      )
    end
  end

  # Input validation errors (non-recoverable - user must fix input)
  class ValidationError < BillingError
    def initialize(message, field: nil, value: nil, details: {})
      super(
        message,
        code: "VALIDATION_ERROR",
        details: details.merge(field: field, value: value).compact,
        recoverable: false
      )
    end
  end

  # Invoice generation/processing errors
  class InvoiceError < BillingError
    def initialize(message, invoice_id: nil, action: nil, details: {})
      super(
        message,
        code: "INVOICE_ERROR",
        details: details.merge(invoice_id: invoice_id, action: action).compact,
        recoverable: true
      )
    end
  end

  # Rate limiting errors (recoverable with retry_after)
  class RateLimitError < BillingError
    def initialize(message, provider: nil, retry_after: 60, details: {})
      super(
        message,
        code: "RATE_LIMIT_ERROR",
        details: details.merge(provider: provider).compact,
        recoverable: true,
        retry_after: retry_after
      )
    end
  end

  # Account-level billing errors
  class AccountBillingError < BillingError
    def initialize(message, account_id: nil, action: nil, details: {})
      super(
        message,
        code: "ACCOUNT_BILLING_ERROR",
        details: details.merge(account_id: account_id, action: action).compact,
        recoverable: true
      )
    end
  end

  # Dunning/payment recovery errors
  class DunningError < BillingError
    def initialize(message, subscription_id: nil, attempt: nil, details: {})
      super(
        message,
        code: "DUNNING_ERROR",
        details: details.merge(subscription_id: subscription_id, attempt: attempt).compact,
        recoverable: true
      )
    end
  end

  # Reconciliation errors (data mismatch between systems)
  class ReconciliationError < BillingError
    def initialize(message, provider: nil, discrepancy_type: nil, details: {})
      super(
        message,
        code: "RECONCILIATION_ERROR",
        details: details.merge(provider: provider, discrepancy_type: discrepancy_type).compact,
        recoverable: false
      )
    end
  end

  # Webhook processing errors
  class WebhookError < BillingError
    def initialize(message, provider: nil, event_type: nil, details: {})
      super(
        message,
        code: "WEBHOOK_ERROR",
        details: details.merge(provider: provider, event_type: event_type).compact,
        recoverable: true
      )
    end
  end

  # Idempotency violation (duplicate operation attempted)
  class IdempotencyError < BillingError
    def initialize(message, idempotency_key: nil, details: {})
      super(
        message,
        code: "IDEMPOTENCY_ERROR",
        details: details.merge(idempotency_key: idempotency_key).compact,
        recoverable: false
      )
    end
  end

  # Configuration errors (missing credentials, invalid settings)
  class ConfigurationError < BillingError
    def initialize(message, provider: nil, missing_config: nil, details: {})
      super(
        message,
        code: "CONFIGURATION_ERROR",
        details: details.merge(provider: provider, missing_config: missing_config).compact,
        recoverable: false
      )
    end
  end
end
