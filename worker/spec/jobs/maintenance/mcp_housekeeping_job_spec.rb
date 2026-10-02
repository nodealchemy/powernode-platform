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
    let(:summary) do
      {
        'sessions_deleted' => 2, 'access_tokens_deleted' => 5,
        'access_grants_deleted' => 3, 'dcr_apps_deleted' => 7
      }
    end
    let(:policy) { { 'data' => { 'account_ids' => ['acct-1'], 'max_idle_seconds' => 2_592_000 } } }

    before do
      allow(api_client).to receive(:post).with('/api/v1/internal/mcp/housekeeping').and_return('data' => summary)
      allow(api_client).to receive(:get).with('/api/v1/internal/mcp/sandbox_cache_policy').and_return(policy)
      allow(McpSandboxCachePruner).to receive(:call).and_return(pruned: 0)
    end

    it 'triggers backend housekeeping and returns the prune summary' do
      expect(job.execute).to include(summary)
    end

    it 're-raises on backend failure so Sidekiq retries' do
      allow(api_client).to receive(:post).and_raise(StandardError, 'boom')

      expect { job.execute }.to raise_error(StandardError, 'boom')
    end

    # IMP-f074ef554781 — the per-account stdio sandbox caches on this host.
    describe 'sandbox cache pruning' do
      it "prunes with the backend's account list and idle age, and reports the count" do
        expect(McpSandboxCachePruner).to receive(:call)
          .with(account_ids: ['acct-1'], max_idle_seconds: 2_592_000).and_return(pruned: 3, kept_running: 1)

        expect(job.execute).to include('sandbox_caches_pruned' => 3)
      end

      it 'does not fail the OAuth housekeeping, or retry it, when the policy cannot be fetched' do
        allow(api_client).to receive(:get).and_raise(StandardError, 'backend down')

        result = job.execute

        expect(result).to include(summary)
        expect(result).not_to have_key('sandbox_caches_pruned')
        expect(job).to have_received(:log_error).with(/sandbox cache/i, instance_of(StandardError))
      end

      it 'prunes nothing when the backend sends no account list' do
        allow(api_client).to receive(:get).and_return('data' => { 'max_idle_seconds' => 2_592_000 })

        job.execute

        expect(McpSandboxCachePruner).to have_received(:call).with(hash_including(account_ids: []))
      end
    end
  end
end
