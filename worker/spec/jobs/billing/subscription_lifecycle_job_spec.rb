# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::SubscriptionLifecycleJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:subscription_id) { SecureRandom.uuid }
  let(:account_id) { SecureRandom.uuid }

  let(:subscription_data) do
    {
      'id' => subscription_id,
      'account_id' => account_id,
      'status' => 'trialing',
      'trial_end' => 7.days.from_now.iso8601,
      'current_period_end' => 1.month.from_now.iso8601,
      'plan' => {
        'id' => SecureRandom.uuid,
        'name' => 'Pro Plan',
        'billing_cycle' => 'monthly'
      },
      'metadata' => {}
    }
  end

  let(:payment_methods) do
    [{
      'id' => SecureRandom.uuid,
      'account_id' => account_id,
      'type' => 'card',
      'default' => true,
      'active' => true
    }]
  end

  describe '#execute' do
    context 'with trial_ending_reminder action' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", payment_methods)
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'sends trial ending notification' do
        described_class.new.execute('trial_ending_reminder', subscription_id, days_until_end: 7)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'schedules billing automation for final day' do
        expect(Billing::BillingAutomationJob).to receive(:perform_in).with(1.day, subscription_id)

        described_class.new.execute('trial_ending_reminder', subscription_id, days_until_end: 1)
      end

      it 'includes payment method status in notification' do
        described_class.new.execute('trial_ending_reminder', subscription_id, days_until_end: 3)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'logs notification sent' do
        job = described_class.new
        capture_logs_for(job)

        job.execute('trial_ending_reminder', subscription_id, days_until_end: 7)

        expect_logged(:info, /Sent trial ending notification/)
      end
    end

    context 'with trial_ended action' do
      let(:trial_ended_subscription) do
        subscription_data.merge(
          'status' => 'trialing',
          'trial_end' => 1.day.ago.iso8601
        )
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", trial_ended_subscription)
      end

      it 'delegates to billing automation' do
        expect(Billing::BillingAutomationJob).to receive(:perform_async).with(subscription_id)

        described_class.new.execute('trial_ended', subscription_id)
      end

      it 'logs processing message' do
        allow(Billing::BillingAutomationJob).to receive(:perform_async)
        job = described_class.new
        capture_logs_for(job)

        job.execute('trial_ended', subscription_id)

        expect_logged(:info, /Processing trial end/)
      end
    end

    context 'with renewal_reminder action' do
      let(:active_subscription) do
        subscription_data.merge(
          'status' => 'active',
          'current_period_end' => 7.days.from_now.iso8601
        )
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", active_subscription)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", payment_methods)
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'sends renewal reminder notification' do
        described_class.new.execute('renewal_reminder', subscription_id, days_until_renewal: 7)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'includes payment method validity in notification' do
        described_class.new.execute('renewal_reminder', subscription_id, days_until_renewal: 3)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'schedules billing automation for final day' do
        expect(Billing::BillingAutomationJob).to receive(:perform_in).with(1.day, subscription_id)

        described_class.new.execute('renewal_reminder', subscription_id, days_until_renewal: 1)
      end

      it 'logs reminder sent' do
        job = described_class.new
        capture_logs_for(job)

        job.execute('renewal_reminder', subscription_id, days_until_renewal: 7)

        expect_logged(:info, /Sent renewal reminder/)
      end
    end

    context 'with payment_method_update_required action' do
      let(:past_due_subscription) do
        subscription_data.merge('status' => 'past_due')
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", past_due_subscription)
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'sends payment method update notification' do
        described_class.new.execute('payment_method_update_required', subscription_id, reason: 'expired')

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'sets grace period for past due subscriptions' do
        described_class.new.execute('payment_method_update_required', subscription_id, reason: 'expired')

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'schedules grace period ending job' do
        expect(Billing::SubscriptionLifecycleJob).to receive(:perform_in).with(
          7.days,
          'grace_period_ending',
          subscription_id
        )

        described_class.new.execute('payment_method_update_required', subscription_id, reason: 'expired')
      end

      it 'logs processing message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute('payment_method_update_required', subscription_id, reason: 'expired')

        expect_logged(:info, /Processing payment method update requirement/)
      end
    end

    context 'with subscription_expired action' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/billing/cancel_subscription', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'cancels subscription via API' do
        described_class.new.execute('subscription_expired', subscription_id, reason: 'payment_failure')

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'cancels in payment gateway' do
        described_class.new.execute('subscription_expired', subscription_id, reason: 'payment_failure')

        expect_api_request(:post, '/api/v1/billing/cancel_subscription')
      end

      it 'sends expiration notification' do
        described_class.new.execute('subscription_expired', subscription_id, reason: 'payment_failure')

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'logs processing message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute('subscription_expired', subscription_id, reason: 'payment_failure')

        expect_logged(:info, /Processing subscription expiration/)
      end
    end

    context 'with reactivation_attempt action' do
      let(:cancelled_subscription) do
        subscription_data.merge('status' => 'cancelled')
      end

      let(:outstanding_invoice) do
        {
          'id' => SecureRandom.uuid,
          'subscription_id' => subscription_id,
          'status' => 'unpaid',
          'amount_cents' => 2999
        }
      end

      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", cancelled_subscription)
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", payment_methods)
        stub_backend_api_success(:get, '/api/v1/invoices', [outstanding_invoice])
        stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => true })
        stub_backend_api_success(:patch, "/api/v1/subscriptions/#{subscription_id}", { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'attempts payment for outstanding invoice' do
        described_class.new.execute('reactivation_attempt', subscription_id)

        expect_api_request(:post, '/api/v1/billing/process_payment')
      end

      it 'reactivates subscription on successful payment' do
        described_class.new.execute('reactivation_attempt', subscription_id)

        expect_api_request(:patch, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'sends reactivation success notification' do
        described_class.new.execute('reactivation_attempt', subscription_id)

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'schedules renewal reminders' do
        expect(Billing::SubscriptionLifecycleJob).to receive(:perform_at).at_least(:once)

        described_class.new.execute('reactivation_attempt', subscription_id)
      end

      it 'logs reactivation attempt' do
        job = described_class.new
        capture_logs_for(job)

        job.execute('reactivation_attempt', subscription_id)

        expect_logged(:info, /Attempting subscription reactivation/)
      end

      context 'when payment fails' do
        before do
          stub_backend_api_success(:post, '/api/v1/billing/process_payment', { 'success' => false, 'error' => 'Card declined' })
        end

        it 'sends reactivation failure notification' do
          described_class.new.execute('reactivation_attempt', subscription_id)

          expect_api_request(:post, '/api/v1/notifications')
        end

        it 'does not reactivate subscription' do
          expect(WebMock).not_to have_requested(:patch, %r{/subscriptions/#{subscription_id}})

          described_class.new.execute('reactivation_attempt', subscription_id)
        end
      end

      context 'when no payment methods available' do
        before do
          stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [])
        end

        it 'skips reactivation attempt' do
          result = described_class.new.execute('reactivation_attempt', subscription_id)

          expect(result).to be_nil
          expect(WebMock).not_to have_requested(:post, %r{/billing/process_payment})
        end
      end
    end

    context 'with grace_period_ending action' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      context 'when payment method was added' do
        before do
          stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", payment_methods)
        end

        it 'attempts reactivation' do
          expect(Billing::SubscriptionLifecycleJob).to receive(:perform_async).with(
            'reactivation_attempt',
            subscription_id
          )

          described_class.new.execute('grace_period_ending', subscription_id)
        end
      end

      context 'when no payment method available' do
        before do
          stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", [])
        end

        it 'expires subscription' do
          expect(Billing::SubscriptionLifecycleJob).to receive(:perform_async).with(
            'subscription_expired',
            subscription_id,
            reason: 'no_payment_method'
          )

          described_class.new.execute('grace_period_ending', subscription_id)
        end
      end

      it 'logs processing message' do
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/payment_methods", payment_methods)
        allow(Billing::SubscriptionLifecycleJob).to receive(:perform_async)
        job = described_class.new
        capture_logs_for(job)

        job.execute('grace_period_ending', subscription_id)

        expect_logged(:info, /Processing grace period end/)
      end
    end

    context 'with unknown action' do
      before do
        stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute('invalid_action', subscription_id)

        expect_logged(:error, /Unknown subscription lifecycle action/)
      end
    end

    context 'when subscription not found' do
      before do
        stub_backend_api_error(:get, "/api/v1/subscriptions/#{subscription_id}", status: 404, error_message: 'Not found')
      end

      it 'logs warning and returns' do
        job = described_class.new
        capture_logs_for(job)

        result = job.execute('trial_ending_reminder', subscription_id, days_until_end: 7)

        expect(result).to be_nil
        expect_logged(:warn, /not found/)
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_connection_failure(:get, "/api/v1/subscriptions/#{subscription_id}")
      end

      it 'raises error for retry' do
        expect { described_class.new.execute('trial_ending_reminder', subscription_id) }.to raise_error
      end
    end
  end

  describe 'helper methods' do
    before do
      stub_backend_api_success(:get, "/api/v1/subscriptions/#{subscription_id}", subscription_data)
    end

    it 'calculates days until trial end' do
      job = described_class.new
      days = job.send(:calculate_days_until_trial_end, subscription_data)

      expect(days).to be >= 6
      expect(days).to be <= 8
    end

    it 'calculates days until renewal' do
      job = described_class.new
      days = job.send(:calculate_days_until_renewal, subscription_data)

      expect(days).to be >= 28
      expect(days).to be <= 31
    end

    it 'calculates new period end for monthly cycle' do
      job = described_class.new
      new_end = job.send(:calculate_new_period_end, subscription_data)

      expect(new_end).to be_within(1.hour).of(Time.current + 1.month)
    end
  end

  describe 'sidekiq options' do
    it 'uses subscription_lifecycle queue' do
      expect(described_class.sidekiq_options['queue']).to eq('subscription_lifecycle')
    end

    it 'has retry count of 2' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
    end
  end
end
