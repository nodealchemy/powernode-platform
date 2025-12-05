# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiMonitoringHealthCheckJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:account_id) { SecureRandom.uuid }

  describe '#execute' do
    let(:job) { described_class.new }

    context 'when broadcast succeeds' do
      before do
        stub_backend_api_success(:post, '/api/v1/ai/monitoring/broadcast_metrics', {
          'success' => true
        })
      end

      it 'broadcasts monitoring metrics via backend API' do
        job.execute(account_id)

        expect_api_request(:post, '/api/v1/ai/monitoring/broadcast_metrics')
      end

      it 'schedules next health check' do
        expect(AiMonitoringHealthCheckJob).to receive(:perform_in).with(30.seconds, account_id)

        job.execute(account_id)
      end

      it 'logs success message' do
        capture_logs_for(job)

        job.execute(account_id)

        expect_logged(:info, /Successfully broadcasted/)
      end
    end

    context 'when broadcast fails' do
      before do
        stub_backend_api_success(:post, '/api/v1/ai/monitoring/broadcast_metrics', {
          'success' => false,
          'error' => 'Broadcast failed'
        })
      end

      it 'logs error message' do
        capture_logs_for(job)

        job.execute(account_id)

        expect_logged(:error, /Failed to broadcast/)
      end

      it 'still schedules next health check' do
        expect(AiMonitoringHealthCheckJob).to receive(:perform_in).with(30.seconds, account_id)

        job.execute(account_id)
      end
    end

    context 'when API call raises error' do
      before do
        stub_backend_api_error(:post, '/api/v1/ai/monitoring/broadcast_metrics',
                               status: 500, error_message: 'Server error')
      end

      it 'raises error for retry' do
        expect { job.execute(account_id) }.to raise_error(StandardError)
      end

      it 'logs error message' do
        capture_logs_for(job)

        expect { job.execute(account_id) }.to raise_error(StandardError)

        expect_logged(:error, /health check failed/)
      end
    end
  end

  describe 'sidekiq options' do
    it 'has retry count of 3' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
