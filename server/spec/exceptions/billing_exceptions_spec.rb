# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillingExceptions do
  describe BillingExceptions::BillingError do
    it 'creates error with default attributes' do
      error = described_class.new('Test error')

      expect(error.message).to eq('Test error')
      expect(error.code).to eq('BILLING_ERROR')
      expect(error.details).to eq({})
      expect(error.recoverable).to be true
      expect(error.retry_after).to be_nil
    end

    it 'creates error with custom attributes' do
      error = described_class.new(
        'Custom error',
        code: 'CUSTOM_ERROR',
        details: { subscription_id: 'sub_123' },
        recoverable: false,
        retry_after: 60
      )

      expect(error.message).to eq('Custom error')
      expect(error.code).to eq('CUSTOM_ERROR')
      expect(error.details).to eq({ subscription_id: 'sub_123' })
      expect(error.recoverable).to be false
      expect(error.retry_after).to eq(60)
    end

    it 'converts to hash correctly' do
      error = described_class.new(
        'Test error',
        code: 'TEST_CODE',
        details: { foo: 'bar' },
        recoverable: true,
        retry_after: 30
      )

      hash = error.to_h

      expect(hash[:code]).to eq('TEST_CODE')
      expect(hash[:message]).to eq('Test error')
      expect(hash[:details]).to eq({ foo: 'bar' })
      expect(hash[:recoverable]).to be true
      expect(hash[:retry_after]).to eq(30)
    end

    it 'omits nil values from hash' do
      error = described_class.new('Test error')
      hash = error.to_h

      expect(hash).not_to have_key(:retry_after)
    end
  end

  describe BillingExceptions::PaymentError do
    it 'creates payment error with provider context' do
      error = described_class.new('Payment failed', provider: 'stripe')

      expect(error.code).to eq('PAYMENT_ERROR')
      expect(error.details[:provider]).to eq('stripe')
      expect(error.recoverable).to be true
    end

    it 'creates payment error with payment_id context' do
      error = described_class.new(
        'Payment failed',
        provider: 'paypal',
        payment_id: 'pay_123',
        details: { amount: 1000 }
      )

      expect(error.details[:provider]).to eq('paypal')
      expect(error.details[:payment_id]).to eq('pay_123')
      expect(error.details[:amount]).to eq(1000)
    end
  end

  describe BillingExceptions::RefundError do
    it 'creates non-recoverable refund error' do
      error = described_class.new('Refund failed', payment_id: 'pay_123')

      expect(error.code).to eq('REFUND_ERROR')
      expect(error.details[:payment_id]).to eq('pay_123')
      expect(error.recoverable).to be false
    end

    it 'includes refund amount in details' do
      error = described_class.new(
        'Partial refund failed',
        payment_id: 'pay_123',
        refund_amount: 5000
      )

      expect(error.details[:refund_amount]).to eq(5000)
    end
  end

  describe BillingExceptions::SubscriptionError do
    it 'creates subscription error with subscription_id context' do
      error = described_class.new(
        'Subscription operation failed',
        subscription_id: 'sub_456'
      )

      expect(error.code).to eq('SUBSCRIPTION_ERROR')
      expect(error.details[:subscription_id]).to eq('sub_456')
      expect(error.recoverable).to be true
    end

    it 'includes action in details' do
      error = described_class.new(
        'Cancel failed',
        subscription_id: 'sub_456',
        action: 'cancel'
      )

      expect(error.details[:action]).to eq('cancel')
    end
  end

  describe BillingExceptions::GatewayError do
    it 'creates gateway error with gateway context' do
      error = described_class.new(
        'Gateway timeout',
        gateway: 'stripe',
        operation: 'charge'
      )

      expect(error.code).to eq('GATEWAY_ERROR')
      expect(error.details[:gateway]).to eq('stripe')
      expect(error.details[:operation]).to eq('charge')
      expect(error.recoverable).to be true
    end
  end

  describe BillingExceptions::ValidationError do
    it 'creates non-recoverable validation error' do
      error = described_class.new(
        'Invalid card number',
        field: 'card_number',
        value: '****1234'
      )

      expect(error.code).to eq('VALIDATION_ERROR')
      expect(error.details[:field]).to eq('card_number')
      expect(error.details[:value]).to eq('****1234')
      expect(error.recoverable).to be false
    end
  end

  describe BillingExceptions::InvoiceError do
    it 'creates invoice error with invoice_id context' do
      error = described_class.new(
        'Invoice generation failed',
        invoice_id: 'inv_789',
        action: 'generate'
      )

      expect(error.code).to eq('INVOICE_ERROR')
      expect(error.details[:invoice_id]).to eq('inv_789')
      expect(error.details[:action]).to eq('generate')
      expect(error.recoverable).to be true
    end
  end

  describe BillingExceptions::RateLimitError do
    it 'creates rate limit error with retry_after' do
      error = described_class.new(
        'Rate limit exceeded',
        provider: 'stripe',
        retry_after: 120
      )

      expect(error.code).to eq('RATE_LIMIT_ERROR')
      expect(error.details[:provider]).to eq('stripe')
      expect(error.recoverable).to be true
      expect(error.retry_after).to eq(120)
    end

    it 'defaults retry_after to 60 seconds' do
      error = described_class.new('Rate limit exceeded', provider: 'stripe')

      expect(error.retry_after).to eq(60)
    end
  end

  describe BillingExceptions::AccountBillingError do
    it 'creates account billing error' do
      error = described_class.new(
        'Account billing setup failed',
        account_id: 'acc_123',
        action: 'setup'
      )

      expect(error.code).to eq('ACCOUNT_BILLING_ERROR')
      expect(error.details[:account_id]).to eq('acc_123')
      expect(error.details[:action]).to eq('setup')
    end
  end

  describe BillingExceptions::DunningError do
    it 'creates dunning error with attempt context' do
      error = described_class.new(
        'Dunning process failed',
        subscription_id: 'sub_456',
        attempt: 3
      )

      expect(error.code).to eq('DUNNING_ERROR')
      expect(error.details[:subscription_id]).to eq('sub_456')
      expect(error.details[:attempt]).to eq(3)
      expect(error.recoverable).to be true
    end
  end

  describe BillingExceptions::ReconciliationError do
    it 'creates non-recoverable reconciliation error' do
      error = described_class.new(
        'Data mismatch',
        provider: 'stripe',
        discrepancy_type: 'amount_mismatch'
      )

      expect(error.code).to eq('RECONCILIATION_ERROR')
      expect(error.details[:provider]).to eq('stripe')
      expect(error.details[:discrepancy_type]).to eq('amount_mismatch')
      expect(error.recoverable).to be false
    end
  end

  describe BillingExceptions::WebhookError do
    it 'creates webhook error with event context' do
      error = described_class.new(
        'Webhook processing failed',
        provider: 'stripe',
        event_type: 'invoice.payment_failed'
      )

      expect(error.code).to eq('WEBHOOK_ERROR')
      expect(error.details[:provider]).to eq('stripe')
      expect(error.details[:event_type]).to eq('invoice.payment_failed')
      expect(error.recoverable).to be true
    end
  end

  describe BillingExceptions::IdempotencyError do
    it 'creates non-recoverable idempotency error' do
      error = described_class.new(
        'Duplicate operation detected',
        idempotency_key: 'renewal:sub_123:2024-01-15'
      )

      expect(error.code).to eq('IDEMPOTENCY_ERROR')
      expect(error.details[:idempotency_key]).to eq('renewal:sub_123:2024-01-15')
      expect(error.recoverable).to be false
    end
  end

  describe 'exception hierarchy' do
    it 'all billing exceptions inherit from BillingError' do
      exception_classes = [
        BillingExceptions::PaymentError,
        BillingExceptions::RefundError,
        BillingExceptions::SubscriptionError,
        BillingExceptions::GatewayError,
        BillingExceptions::ValidationError,
        BillingExceptions::InvoiceError,
        BillingExceptions::RateLimitError,
        BillingExceptions::AccountBillingError,
        BillingExceptions::DunningError,
        BillingExceptions::ReconciliationError,
        BillingExceptions::WebhookError,
        BillingExceptions::IdempotencyError
      ]

      exception_classes.each do |klass|
        error = klass.new('Test')
        expect(error).to be_a(BillingExceptions::BillingError)
        expect(error).to be_a(StandardError)
      end
    end

    it 'all billing exceptions can be rescued with BillingError' do
      expect {
        raise BillingExceptions::PaymentError.new('Test')
      }.to raise_error(BillingExceptions::BillingError)

      expect {
        raise BillingExceptions::RefundError.new('Test')
      }.to raise_error(BillingExceptions::BillingError)

      expect {
        raise BillingExceptions::SubscriptionError.new('Test')
      }.to raise_error(BillingExceptions::BillingError)
    end
  end
end
