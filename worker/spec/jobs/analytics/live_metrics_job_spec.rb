# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::LiveMetricsJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:account_id) { SecureRandom.uuid }

  let(:live_metrics_response) do
    {
      'current_metrics' => {
        'mrr' => 15_000,
        'arr' => 180_000,
        'active_customers' => 150,
        'churn_rate' => 2.5,
        'arpu' => 100,
        'growth_rate' => 8.5
      },
      'today_activity' => {
        'new_subscriptions' => 5,
        'cancelled_subscriptions' => 1,
        'payments_processed' => 25,
        'failed_payments' => 2,
        'revenue_today' => 2500
      },
      'weekly_trend' => [
        { 'date' => (Date.today - 6).to_s, 'revenue' => 2100 },
        { 'date' => (Date.today - 5).to_s, 'revenue' => 2200 },
        { 'date' => (Date.today - 4).to_s, 'revenue' => 2150 },
        { 'date' => (Date.today - 3).to_s, 'revenue' => 2400 },
        { 'date' => (Date.today - 2).to_s, 'revenue' => 2350 },
        { 'date' => (Date.today - 1).to_s, 'revenue' => 2500 },
        { 'date' => Date.today.to_s, 'revenue' => 2500 }
      ],
      'last_updated' => Time.current.iso8601
    }
  end

  describe '#execute' do
    context 'when processing live metrics for specific account' do
      before do
        stub_backend_api_success(:get, '/api/v1/analytics/live', live_metrics_response)
        stub_backend_api_success(:post, '/api/v1/analytics/cache', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/analytics/broadcast', { 'success' => true })
      end

      it 'fetches live metrics from API' do
        described_class.new.execute(account_id: account_id)

        expect_api_request(:get, '/api/v1/analytics/live')
      end

      it 'returns metrics data' do
        result = described_class.new.execute(account_id: account_id)

        expect(result['current_metrics']['mrr']).to eq(15_000)
        expect(result['current_metrics']['active_customers']).to eq(150)
      end

      it 'logs success message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(account_id: account_id)

        expect_logged(:info, /processed successfully/)
      end
    end

    context 'when processing global metrics' do
      before do
        stub_backend_api_success(:get, '/api/v1/analytics/live', live_metrics_response)
        stub_backend_api_success(:post, '/api/v1/analytics/cache', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/analytics/broadcast', { 'success' => true })
      end

      it 'processes metrics without account filter' do
        described_class.new.execute(account_id: nil)

        expect_api_request(:get, '/api/v1/analytics/live')
      end

      it 'logs global metrics processing' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(account_id: nil)

        expect_logged(:info, /global/)
      end
    end

    context 'when broadcast is disabled' do
      before do
        stub_backend_api_success(:get, '/api/v1/analytics/live', live_metrics_response)
        stub_backend_api_success(:post, '/api/v1/analytics/cache', { 'success' => true })
      end

      it 'skips broadcasting' do
        described_class.new.execute(account_id: account_id, broadcast: false)

        expect_no_api_request(:post, '/api/v1/analytics/broadcast')
      end
    end

    context 'when API returns error' do
      before do
        stub_backend_api_error(:get, '/api/v1/analytics/live', status: 500, error_message: 'Server error')
        stub_backend_api_success(:post, '/api/v1/analytics/cache', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/analytics/broadcast', { 'success' => true })
      end

      it 'uses fallback metrics' do
        # Allow the response to indicate failure but not throw
        allow_any_instance_of(BackendApiClient).to receive(:get).and_return(
          double('Response', success?: false, data: nil)
        )

        result = described_class.new.execute(account_id: account_id)

        expect(result[:current_metrics][:mrr]).to eq(0)
        expect(result[:current_metrics][:active_customers]).to eq(0)
      end
    end

    context 'when an error occurs during processing' do
      before do
        stub_backend_api_success(:get, '/api/v1/analytics/live', live_metrics_response)
        allow_any_instance_of(described_class).to receive(:cache_live_metrics).and_raise(StandardError, 'Cache error')
        allow(ErrorNotificationService).to receive(:notify)
      end

      it 'logs error' do
        job = described_class.new
        capture_logs_for(job)

        expect {
          job.execute(account_id: account_id)
        }.to raise_error(StandardError, 'Cache error')

        expect_logged(:error, /Live metrics job failed/)
      end

      it 'sends error notification' do
        expect(ErrorNotificationService).to receive(:notify).with(
          hash_including(error: kind_of(StandardError), context: hash_including(job: 'LiveMetricsJob'))
        )

        expect {
          described_class.new.execute(account_id: account_id)
        }.to raise_error(StandardError)
      end

      it 're-raises the error' do
        expect {
          described_class.new.execute(account_id: account_id)
        }.to raise_error(StandardError, 'Cache error')
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses analytics queue' do
      expect(described_class.sidekiq_options['queue']).to eq('analytics')
    end
  end

  describe '#calculate_fallback_metrics' do
    let(:job) { described_class.new }

    it 'returns default metrics structure' do
      result = job.send(:calculate_fallback_metrics, account_id)

      expect(result).to have_key(:current_metrics)
      expect(result).to have_key(:today_activity)
      expect(result).to have_key(:weekly_trend)
      expect(result).to have_key(:last_updated)
      expect(result).to have_key(:account_id)
    end

    it 'returns zero values for current metrics' do
      result = job.send(:calculate_fallback_metrics, account_id)

      expect(result[:current_metrics][:mrr]).to eq(0)
      expect(result[:current_metrics][:arr]).to eq(0)
      expect(result[:current_metrics][:active_customers]).to eq(0)
      expect(result[:current_metrics][:churn_rate]).to eq(0)
      expect(result[:current_metrics][:arpu]).to eq(0)
      expect(result[:current_metrics][:growth_rate]).to eq(0)
    end

    it 'returns zero values for today activity' do
      result = job.send(:calculate_fallback_metrics, account_id)

      expect(result[:today_activity][:new_subscriptions]).to eq(0)
      expect(result[:today_activity][:cancelled_subscriptions]).to eq(0)
      expect(result[:today_activity][:payments_processed]).to eq(0)
      expect(result[:today_activity][:failed_payments]).to eq(0)
      expect(result[:today_activity][:revenue_today]).to eq(0)
    end

    it 'includes account_id' do
      result = job.send(:calculate_fallback_metrics, account_id)

      expect(result[:account_id]).to eq(account_id)
    end

    it 'includes timestamp' do
      result = job.send(:calculate_fallback_metrics, account_id)

      expect(result[:last_updated]).to be_present
    end
  end
end
