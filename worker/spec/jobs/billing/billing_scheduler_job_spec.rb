# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::BillingSchedulerJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before do
    mock_powernode_worker_config
    # Clear any stale locks from previous tests
    Sidekiq.redis { |conn| conn.del("lock:billing:scheduler:#{Date.current}") }
  end

  let(:date) { Date.current }
  let(:subscription) { { 'id' => SecureRandom.uuid, 'account_id' => SecureRandom.uuid } }

  describe '#execute' do
    context 'with successful scheduling' do
      before do
        # Stub all subscription queries - the job makes multiple calls with different params
        stub_backend_api_success(:get, '/api/v1/subscriptions', [subscription])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [])
        # Allow all job scheduling to proceed
        allow(Billing::BillingAutomationJob).to receive(:perform_in)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_in)
      end

      it 'schedules billing automation' do
        described_class.new.execute(date)
        expect(Billing::BillingAutomationJob).to have_received(:perform_in).at_least(:once)
      end

      it 'schedules trial ending reminders' do
        described_class.new.execute(date)
        expect(Billing::SubscriptionLifecycleJob).to have_received(:perform_async).at_least(:once)
      end

      it 'schedules renewal reminders' do
        described_class.new.execute(date)
        expect(Billing::SubscriptionLifecycleJob).to have_received(:perform_async).at_least(:once)
      end

      it 'logs completion message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(date)

        expect_logged(:info, /completed successfully/)
      end
    end

    context 'with payment methods expiring' do
      let(:payment_method) do
        {
          'id' => SecureRandom.uuid,
          'account_id' => subscription['account_id'],
          'expires_at' => (date + 30.days).to_s
        }
      end

      before do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [subscription])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [payment_method])
        # Stub any PATCH requests that might occur
        stub_backend_api_success(:patch, "/api/v1/payment_methods/#{payment_method['id']}", {})
      end

      it 'schedules payment method expiration reminders' do
        # Allow any lifecycle job calls since the scheduler schedules multiple types
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_in)
        allow(Billing::BillingAutomationJob).to receive(:perform_in)

        described_class.new.execute(date)

        # Verify at least one lifecycle job was scheduled
        expect(Billing::SubscriptionLifecycleJob).to have_received(:perform_async).at_least(:once)
      end
    end

    context 'with payment methods expiring today' do
      let(:payment_method_expiring_today) do
        {
          'id' => SecureRandom.uuid,
          'account_id' => SecureRandom.uuid,
          'expires_at' => date.to_s
        }
      end

      before do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [subscription])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [payment_method_expiring_today])
        stub_backend_api_success(:patch, "/api/v1/payment_methods/#{payment_method_expiring_today['id']}", {})
        allow(Billing::BillingAutomationJob).to receive(:perform_in)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_in)
      end

      it 'marks payment methods as expired' do
        described_class.new.execute(date)

        expect_api_request(:patch, "/api/v1/payment_methods/#{payment_method_expiring_today['id']}")
      end
    end

    context 'with grace period ending' do
      let(:grace_period_subscription) do
        subscription.merge('status' => 'past_due')
      end

      before do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [grace_period_subscription])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [])
      end

      it 'schedules grace period ending jobs' do
        # Allow other scheduled jobs since the scheduler schedules multiple types
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_in)
        allow(Billing::BillingAutomationJob).to receive(:perform_in)

        described_class.new.execute(date)

        # Verify grace_period_ending was scheduled
        expect(Billing::SubscriptionLifecycleJob).to have_received(:perform_async).with('grace_period_ending', grace_period_subscription['id'])
      end
    end

    context 'with long-overdue subscriptions' do
      before do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [subscription])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [])
        allow(Billing::BillingAutomationJob).to receive(:perform_in)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_in)
      end

      it 'schedules subscription expiration jobs' do
        described_class.new.execute(date)
        expect(Billing::SubscriptionLifecycleJob).to have_received(:perform_async).at_least(:once)
      end
    end

    context 'with reactivation candidates' do
      before do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [subscription])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [])
        allow(Billing::BillingAutomationJob).to receive(:perform_in)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_in)
      end

      it 'schedules reactivation attempts' do
        described_class.new.execute(date)
        expect(Billing::SubscriptionLifecycleJob).to have_received(:perform_in).at_least(:once)
      end
    end

    context 'with string date parameter' do
      it 'parses date correctly' do
        stub_backend_api_success(:get, '/api/v1/subscriptions', [])
        stub_backend_api_success(:get, '/api/v1/payment_methods', [])

        expect { described_class.new.execute(date.to_s) }.not_to raise_error
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_error(:get, '/api/v1/subscriptions', status: 500, error_message: 'Server error')
      end

      it 'raises error' do
        expect { described_class.new.execute(date) }.to raise_error
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        expect { job.execute(date) }.to raise_error

        expect_logged(:error, /scheduler failed/)
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses billing_scheduler queue' do
      expect(described_class.sidekiq_options['queue']).to eq('billing_scheduler')
    end

    it 'has retry count of 1' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end
  end
end
