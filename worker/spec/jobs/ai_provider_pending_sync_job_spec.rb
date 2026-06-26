# frozen_string_literal: true

require 'rails_helper'

# C1 (operator decision 2026-06-11): provider model sync is pull-based.
# Providers flag themselves sync-pending on create/update (the after_commit
# no longer fetches inline); this short-interval sweep picks the flags up
# within minutes via the internal API. AiProviderModelSyncJob remains the
# daily full-sweep backstop.
RSpec.describe AiProviderPendingSyncJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'

  let(:job_instance) { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'runs on the ai_orchestration queue' do
      expect(described_class.get_sidekiq_options['queue'].to_s).to eq('ai_orchestration')
    end
  end

  describe '#execute' do
    it 'POSTs the internal sync_pending endpoint and returns the results' do
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/ai/providers/sync_pending', {})
        .and_return({ 'results' => { 'synced' => 1, 'failed' => 0, 'errors' => [] } })

      result = job_instance.execute

      expect(result['synced']).to eq(1)
      expect(result['failed']).to eq(0)
    end

    it 'returns an empty hash when the response has no results key' do
      allow(api_client_double).to receive(:post).and_return({})

      expect(job_instance.execute).to eq({})
    end

    it 'raises on API failure so Sidekiq retries' do
      allow(api_client_double).to receive(:post).and_raise(StandardError, 'connection refused')

      expect { job_instance.execute }.to raise_error(StandardError, 'connection refused')
    end
  end
end
