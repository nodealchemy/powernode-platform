# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::BillingCleanupJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  describe '#execute' do
    context 'when cleanup succeeds' do
      before do
        stub_backend_api_success(:post, '/api/v1/billing/cleanup', { 'count' => 10 })
        stub_backend_api_success(:post, '/api/v1/analytics/update_metrics', { 'active_by_plan' => { 'pro' => 50 } })
        stub_backend_api_success(:post, '/api/v1/billing/reactivate_suspended_accounts', { 'reactivated_count' => 2, 'reactivated_accounts' => [] })
        stub_backend_api_success(:post, '/api/v1/billing/health_report', {
          'report' => {
            'payment_success_rate' => 0.98,
            'subscription_health' => { 'churn_rate' => 0.05 }
          }
        })
      end

      it 'cleans up old failed payments' do
        described_class.new.execute

        expect(WebMock).to have_requested(:post, %r{/billing/cleanup}).at_least_once
      end

      it 'cleans up expired invoices' do
        described_class.new.execute

        expect(WebMock).to have_requested(:post, %r{/billing/cleanup}).at_least_once
      end

      it 'updates subscription metrics' do
        described_class.new.execute

        expect_api_request(:post, '/api/v1/analytics/update_metrics')
      end

      it 'cleans up orphaned payment methods' do
        described_class.new.execute

        expect(WebMock).to have_requested(:post, %r{/billing/cleanup}).at_least_once
      end

      it 'updates account suspension status' do
        described_class.new.execute

        expect_api_request(:post, '/api/v1/billing/reactivate_suspended_accounts')
      end

      it 'generates billing health report' do
        described_class.new.execute

        expect_api_request(:post, '/api/v1/billing/health_report')
      end

      it 'logs completion message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute

        expect_logged(:info, /completed successfully/)
      end
    end

    context 'when accounts are reactivated' do
      let(:reactivated_accounts) do
        [
          { 'id' => SecureRandom.uuid, 'name' => 'Account 1' },
          { 'id' => SecureRandom.uuid, 'name' => 'Account 2' }
        ]
      end

      before do
        stub_backend_api_success(:post, '/api/v1/billing/cleanup', { 'count' => 0 })
        stub_backend_api_success(:post, '/api/v1/analytics/update_metrics', { 'active_by_plan' => {} })
        stub_backend_api_success(:post, '/api/v1/billing/reactivate_suspended_accounts', {
          'reactivated_count' => 2,
          'reactivated_accounts' => reactivated_accounts
        })
        stub_backend_api_success(:post, '/api/v1/billing/health_report', {
          'report' => {
            'payment_success_rate' => 0.98,
            'subscription_health' => { 'churn_rate' => 0.05 }
          }
        })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'sends reactivation notifications' do
        described_class.new.execute

        expect(WebMock).to have_requested(:post, %r{/notifications}).twice
      end
    end

    context 'when billing health is poor' do
      before do
        stub_backend_api_success(:post, '/api/v1/billing/cleanup', { 'count' => 0 })
        stub_backend_api_success(:post, '/api/v1/analytics/update_metrics', { 'active_by_plan' => {} })
        stub_backend_api_success(:post, '/api/v1/billing/reactivate_suspended_accounts', { 'reactivated_count' => 0, 'reactivated_accounts' => [] })
        stub_backend_api_success(:post, '/api/v1/billing/health_report', {
          'report' => {
            'payment_success_rate' => 0.92, # Below 0.95 threshold
            'subscription_health' => { 'churn_rate' => 0.12 } # Above 0.10 threshold
          }
        })
        stub_backend_api_success(:post, '/api/v1/notifications', { 'success' => true })
      end

      it 'sends billing health alert' do
        described_class.new.execute

        expect_api_request(:post, '/api/v1/notifications')
      end

      it 'logs warning message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute

        expect_logged(:warn, /health issues detected/)
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_error(:post, '/api/v1/billing/cleanup', status: 500, error_message: 'Server error')
      end

      it 'raises error' do
        expect { described_class.new.execute }.to raise_error
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        expect { job.execute }.to raise_error

        expect_logged(:error, /cleanup failed/)
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses maintenance queue' do
      expect(described_class.sidekiq_options['queue']).to eq('maintenance')
    end

    it 'has retry count of 1' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end
  end
end
