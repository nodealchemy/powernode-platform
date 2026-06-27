# frozen_string_literal: true

require 'rails_helper'

# The worker has no DB access, so this job's only job is to trigger the backend
# internal housekeeping endpoint on a schedule and surface its summary. All real
# pruning happens server-side (Mcp::HousekeepingService); here the backend client
# is mocked.
RSpec.describe Maintenance::McpHousekeepingJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
  end

  describe 'job configuration' do
    it 'runs on the maintenance queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('maintenance')
    end
  end

  describe '#execute' do
    it 'triggers backend housekeeping and returns the prune summary' do
      summary = {
        'sessions_deleted' => 2, 'access_tokens_deleted' => 5,
        'access_grants_deleted' => 3, 'dcr_apps_deleted' => 7
      }
      expect(api_client).to receive(:post)
        .with('/api/v1/internal/mcp/housekeeping')
        .and_return('data' => summary)

      expect(job.execute).to eq(summary)
    end

    it 're-raises on backend failure so Sidekiq retries' do
      allow(api_client).to receive(:post).and_raise(StandardError, 'boom')

      expect { job.execute }.to raise_error(StandardError, 'boom')
    end
  end
end
