# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::SubscriptionRenewalJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with retry logic'

  before { mock_powernode_worker_config }

  let(:subscription_id) { SecureRandom.uuid }
  let(:account_id) { SecureRandom.uuid }

  let(:subscription_data) do
    {
      'id' => subscription_id,
      'account_id' => account_id,
      'status' => 'active',
      'next_billing_date' => Date.current.to_s,
      'price_cents' => 2999,
      'currency' => 'USD',
      'billing_cycle' => 'monthly',
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
    context 'when renewal succeeds' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        stub_backend_api_success(:post, '/api/v1/billing/process_renewal', {
          'success' => true,
          'next_billing_date' => Date.current.next_month.to_s
        })
      end

      it 'processes renewal via backend API' do
        result = described_class.new.execute(subscription_id)

        expect(result['success']).to be true
        expect_api_request(:post, '/api/v1/billing/process_renewal')
      end

      it 'schedules next renewal' do
        expect(Billing::SubscriptionRenewalJob).to receive(:perform_at)

        described_class.new.execute(subscription_id)
      end

      it 'logs success message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id)

        expect_logged(:info, /Successfully renewed/)
      end
    end

    context 'when renewal fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
      end

      context 'with payment failure (402)' do
        before do
          stub_backend_api_error(:post, '/api/v1/billing/process_renewal', status: 402, error_message: 'Payment required')
        end

        it 'schedules payment retry' do
          expect(Billing::PaymentRetryJob).to receive(:perform_at).with(
            kind_of(Time),
            subscription_id,
            'renewal_failure'
          )

          described_class.new.execute(subscription_id)
        end

        it 'logs error message' do
          job = described_class.new
          capture_logs_for(job)

          job.execute(subscription_id)

          expect_logged(:error, /Failed to renew/)
        end
      end

      context 'with missing payment method (404)' do
        before do
          stub_backend_api_error(:post, '/api/v1/billing/process_renewal', status: 404, error_message: 'Payment method not found')
          stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
        end

        it 'sends payment method required notification' do
          described_class.new.execute(subscription_id)

          expect_api_request(:post, '/api/v1/notifications')
        end

        it 'does not schedule retry' do
          expect(Billing::SubscriptionRenewalJob).not_to receive(:perform_at)

          described_class.new.execute(subscription_id)
        end
      end

      context 'with validation error (422)' do
        before do
          stub_backend_api_error(:post, '/api/v1/billing/process_renewal', status: 422, error_message: 'Validation failed')
        end

        it 'logs error without retry' do
          job = described_class.new
          capture_logs_for(job)
          expect(Billing::SubscriptionRenewalJob).not_to receive(:perform_at)

          job.execute(subscription_id)

          expect_logged(:error, /validation failed/)
        end
      end

      context 'with generic failure' do
        before do
          stub_backend_api_error(:post, '/api/v1/billing/process_renewal', status: 500, error_message: 'Server error')
        end

        it 'schedules renewal retry' do
          expect(Billing::SubscriptionRenewalJob).to receive(:perform_at).with(
            kind_of(Time),
            subscription_id
          )

          described_class.new.execute(subscription_id)
        end
      end
    end

    context 'when subscription not found' do
      before do
        stub_backend_api_error(:get, "/api/v1/subscriptions/#{subscription_id}", status: 404, error_message: 'Not found')
      end

      it 'raises ArgumentError' do
        expect { described_class.new.execute(subscription_id) }.to raise_error(ArgumentError, /not found/)
      end
    end

    context 'when subscription not eligible for renewal' do
      let(:ineligible_subscription) do
        subscription_data.merge(
          'status' => 'canceled',
          'next_billing_date' => nil
        )
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", ineligible_subscription)
      end

      it 'skips processing' do
        result = described_class.new.execute(subscription_id)

        expect(result).to be_nil
        expect(WebMock).not_to have_requested(:post, %r{/billing/process_renewal})
      end

      it 'logs skip message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id)

        expect_logged(:info, /not eligible/)
      end
    end

    context 'with future billing date' do
      let(:future_subscription) do
        subscription_data.merge('next_billing_date' => (Date.current + 2.days).to_s)
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", future_subscription)
      end

      it 'skips processing' do
        result = described_class.new.execute(subscription_id)

        expect(result).to be_nil
      end
    end

    context 'with inactive subscription' do
      let(:inactive_subscription) do
        subscription_data.merge('status' => 'paused')
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", inactive_subscription)
      end

      it 'skips processing' do
        result = described_class.new.execute(subscription_id)

        expect(result).to be_nil
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_connection_failure(:get, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'raises error for retry' do
        expect { described_class.new.execute(subscription_id) }.to raise_error
      end
    end
  end

  describe 'next renewal scheduling' do
    before do
      stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
      stub_backend_api_success(:post, '/api/v1/billing/process_renewal', {
        'success' => true,
        'next_billing_date' => Date.current.next_month.to_s
      })
    end

    it 'schedules at 9 AM on billing date' do
      expected_time = Date.current.next_month.to_time + 9.hours

      expect(Billing::SubscriptionRenewalJob).to receive(:perform_at) do |time, _id|
        expect(time).to be_within(1.minute).of(expected_time)
      end

      described_class.new.execute(subscription_id)
    end
  end

  describe 'sidekiq options' do
    it 'uses billing queue' do
      expect(described_class.sidekiq_options['queue']).to eq('billing')
    end

    it 'has retry enabled' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
