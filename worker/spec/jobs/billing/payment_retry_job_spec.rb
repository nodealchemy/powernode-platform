# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::PaymentRetryJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:subscription_id) { SecureRandom.uuid }
  let(:account_id) { SecureRandom.uuid }
  let(:failure_type) { 'payment_failure' }
  let(:attempt_number) { 1 }

  let(:subscription_data) do
    {
      'id' => subscription_id,
      'account_id' => account_id,
      'status' => 'past_due',
      'price_cents' => 2999,
      'currency' => 'USD',
      'plan_name' => 'Pro Plan'
    }
  end

  let(:account_data) do
    {
      'id' => account_id,
      'name' => 'Test Account'
    }
  end

  describe '#execute' do
    context 'when payment retry succeeds' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        stub_backend_api_success(:post, '/api/v1/billing/retry_payment', {
          'success' => true,
          'next_billing_date' => Date.current.next_month.to_s
        })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'retries payment via backend API' do
        result = described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect(result['success']).to be true
        expect_api_request(:post, '/api/v1/billing/retry_payment')
      end

      it 'sends recovery notification' do
        described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'schedules next renewal' do
        expect(Billing::SubscriptionRenewalJob).to receive(:perform_at)

        described_class.new.execute(subscription_id, failure_type, attempt_number)
      end

      it 'logs success message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id, failure_type, attempt_number)

        expect_logged(:info, /successful/)
      end
    end

    context 'when payment retry fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        stub_backend_api_success(:post, '/api/v1/billing/retry_payment', {
          'success' => false,
          'error' => 'Card declined',
          'retryable' => true
        })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'schedules next retry attempt' do
        expect(Billing::PaymentRetryJob).to receive(:perform_at)

        described_class.new.execute(subscription_id, failure_type, attempt_number)
      end

      it 'sends dunning notification' do
        described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'logs warning message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id, failure_type, attempt_number)

        expect_logged(:warn, /failed/)
      end
    end

    context 'when maximum retries reached' do
      let(:attempt_number) { 6 }

      before do
        stub_backend_api_success(:post, '/api/v1/billing/suspend_subscription', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'suspends subscription' do
        described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect_api_request(:post, '/api/v1/billing/suspend_subscription')
      end

      it 'sends final notice notification' do
        described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id, failure_type, attempt_number)

        expect_logged(:error, /Maximum retry/)
      end

      it 'does not schedule further retries' do
        expect(Billing::PaymentRetryJob).not_to receive(:perform_at)

        described_class.new.execute(subscription_id, failure_type, attempt_number)
      end
    end

    context 'when subscription not found' do
      before do
        stub_backend_api_error(:get, "/api/v1/subscriptions/#{subscription_id}", status: 404, error_message: 'Not found')
      end

      it 'logs error and returns' do
        job = described_class.new
        capture_logs_for(job)

        result = job.execute(subscription_id, failure_type, attempt_number)

        expect(result).to be_nil
        expect_logged(:error, /not found/)
      end
    end

    context 'when error is non-retryable' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        stub_backend_api_success(:post, '/api/v1/billing/retry_payment', {
          'success' => false,
          'error' => 'Invalid payment method',
          'retryable' => false
        })
        stub_backend_api_success(:post, '/api/v1/billing/suspend_subscription', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'stops retries and suspends subscription' do
        expect(Billing::PaymentRetryJob).not_to receive(:perform_at)

        described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect_api_request(:post, '/api/v1/billing/suspend_subscription')
      end
    end

    context 'with retry intervals' do
      it 'uses exponential backoff' do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        stub_backend_api_success(:post, '/api/v1/billing/retry_payment', {
          'success' => false,
          'error' => 'Failed',
          'retryable' => true
        })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })

        expect(Billing::PaymentRetryJob).to receive(:perform_at) do |time, *_args|
          expect(time).to be_between(Time.now + 1.day - 1.minute, Time.now + 1.day + 1.minute)
        end

        described_class.new.execute(subscription_id, failure_type, 1)
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        stub_backend_api_error(:post, '/api/v1/billing/retry_payment', status: 500, error_message: 'Server error')
      end

      it 'returns failure result' do
        result = described_class.new.execute(subscription_id, failure_type, attempt_number)

        expect(result['success']).to be false
      end

      it 'schedules retry for retryable errors' do
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
        expect(Billing::PaymentRetryJob).to receive(:perform_at)

        described_class.new.execute(subscription_id, failure_type, attempt_number)
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses billing queue' do
      expect(described_class.sidekiq_options['queue']).to eq('billing')
    end

    it 'has manual retry handling' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end
  end

  describe 'retry constants' do
    it 'has maximum retry attempts defined' do
      expect(Billing::PaymentRetryJob::MAX_RETRY_ATTEMPTS).to eq(5)
    end

    it 'has retry intervals defined' do
      expect(Billing::PaymentRetryJob::RETRY_INTERVALS).to eq([1.day, 3.days, 7.days, 14.days, 30.days])
    end
  end
end
