# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::BillingAutomationJob, type: :job do
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
      'current_period_end' => Date.current.end_of_day.iso8601,
      'plan' => { 'name' => 'Pro Plan', 'billing_cycle' => 'monthly' },
      'account' => { 'name' => 'Test Account' },
      'price_cents' => 2999,
      'currency' => 'USD'
    }
  end

  describe '#execute' do
    context 'with no subscription_id (batch processing)' do
      before do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [subscription_data])
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [{ 'id' => SecureRandom.uuid, 'default' => true }])
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => true })
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      it 'fetches subscriptions needing renewal' do
        expect { described_class.new.execute }.not_to raise_error
      end

      it 'processes each subscription' do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => true })
        stub_backend_api_success(:get, '/api/v1/accounts/#{account_id}/payment_methods', [{ 'id' => SecureRandom.uuid }])
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)

        result = described_class.new.execute

        expect(result).not_to be_nil
      end
    end

    context 'with specific subscription_id' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      it 'processes only that subscription' do
        expect_any_instance_of(described_class).to receive(:process_subscription).with(subscription_id)

        described_class.new.execute(subscription_id)
      end
    end

    context 'when subscription not found' do
      before do
        stub_backend_api_error(:get, "/api/v1/subscriptions/#{subscription_id}", status: 404, error_message: 'Not found')
      end

      it 'handles error gracefully' do
        expect { described_class.new.execute(subscription_id) }.not_to raise_error
      end
    end
  end

  describe 'trial ending handling' do
    let(:trialing_subscription) do
      subscription_data.merge(
        'status' => 'trialing',
        'trial_end' => Time.current.iso8601
      )
    end

    context 'with valid payment method' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", trialing_subscription)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [{ 'id' => SecureRandom.uuid }])
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => true })
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      it 'converts trial to active subscription' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/billing/process_payment')
        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'generates trial conversion invoice' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/billing/generate_invoice')
      end
    end

    context 'without payment method' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", trialing_subscription)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [])
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'converts to past_due status' do
        described_class.new.execute(subscription_id)

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'sends payment method required notification' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/notifications')
      end
    end

    context 'when payment fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", trialing_subscription)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [{ 'id' => SecureRandom.uuid }])
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => false, 'error' => 'Card declined' })
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      it 'sets subscription to past_due' do
        described_class.new.execute(subscription_id)

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'schedules payment retry' do
        expect(Billing::PaymentRetryJob).to receive(:perform_in).with(1.hour, subscription_id, 'trial_conversion_failure')

        described_class.new.execute(subscription_id)
      end
    end
  end

  describe 'subscription renewal handling' do
    context 'with active subscription' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [{ 'id' => SecureRandom.uuid }])
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => true })
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      it 'generates renewal invoice' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/billing/generate_invoice')
      end

      it 'processes payment' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/billing/process_payment')
      end

      it 'advances billing period' do
        described_class.new.execute(subscription_id)

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end
    end

    context 'with past_due subscription' do
      let(:past_due_subscription) { subscription_data.merge('status' => 'past_due') }

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", past_due_subscription)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [{ 'id' => SecureRandom.uuid }])
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => true })
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'reactivates subscription on successful payment' do
        described_class.new.execute(subscription_id)

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'sends reactivation notification' do
        described_class.new.execute(subscription_id)

        # Job sends both reactivation and renewal success notifications
        expect(
          a_request(:post, 'http://localhost:3000/api/v1/notifications')
        ).to have_been_made.at_least_once
      end
    end

    context 'when payment fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [{ 'id' => SecureRandom.uuid }])
        stub_backend_api_success(:post, '/api/v1/billing/generate_invoice', { 'id' => SecureRandom.uuid })
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => false, 'error' => 'Insufficient funds' })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'schedules payment retry' do
        expect(Billing::PaymentRetryJob).to receive(:perform_in).with(1.hour, subscription_id, 'renewal_failure')

        described_class.new.execute(subscription_id)
      end

      it 'sends payment failure notification' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/notifications')
      end
    end

    context 'when no payment methods available' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [])
      end

      it 'skips payment processing' do
        described_class.new.execute(subscription_id)

        expect(WebMock).not_to have_requested(:post, %r{/billing/process_payment})
      end
    end
  end

  describe 'error handling' do
    context 'when API call fails' do
      before do
        stub_backend_api_error(:get, "/api/v1/subscriptions/#{subscription_id}", status: 500, error_message: 'Server error')
      end

      it 'logs error message' do
        expect_any_instance_of(described_class).to receive(:log_error)

        expect { described_class.new.execute(subscription_id) }.not_to raise_error
      end
    end

    context 'when subscription processing fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_error(:get, "/api/v1/accounts/#{account_id}/payment_methods", status: 500, error_message: 'Error')
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'schedules retry' do
        expect(Billing::BillingAutomationJob).to receive(:perform_in).with(1.hour, subscription_id)

        described_class.new.execute(subscription_id)
      end

      it 'sends billing failure alert' do
        described_class.new.execute(subscription_id)

        expect_api_request(:post, '/api/v1/notifications')
      end
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
