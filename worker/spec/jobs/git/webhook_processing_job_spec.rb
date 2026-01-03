# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::WebhookProcessingJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:event_id) { 'event-123-uuid' }
  let(:api_client_double) { instance_double(BackendApiClient) }

  let(:sample_event) do
    {
      'id' => event_id,
      'event_type' => 'push',
      'action' => nil,
      'payload' => {
        'ref' => 'refs/heads/main',
        'commits' => [
          { 'id' => 'abc123', 'message' => 'Test commit' }
        ]
      },
      'repository' => {
        'id' => 'repo-123',
        'full_name' => 'owner/repo',
        'credential_id' => 'cred-123'
      }
    }
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    allow(api_client_double).to receive(:get).and_return({ 'data' => sample_event })
    allow(api_client_double).to receive(:patch).and_return({ 'success' => true })
    allow(api_client_double).to receive(:post).and_return({ 'success' => true })
    # Mock idempotency methods
    allow(job_instance).to receive(:already_processed?).and_return(false)
    allow(job_instance).to receive(:mark_processed)
  end

  describe 'class configuration' do
    it_behaves_like 'a base job', described_class

    it 'uses webhooks queue' do
      expect(described_class.sidekiq_options['queue']).to eq('webhooks')
    end

    it 'has 3 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    context 'when event already processed' do
      before do
        allow(job_instance).to receive(:already_processed?).and_return(true)
      end

      it 'skips processing' do
        result = job_instance.execute(event_id)

        expect(result).to eq({ skipped: true, reason: 'already_processed' })
      end

      it 'does not fetch event from API' do
        job_instance.execute(event_id)

        expect(api_client_double).not_to have_received(:get)
      end
    end

    context 'when event not found' do
      before do
        allow(api_client_double).to receive(:get).and_return({ 'data' => nil })
      end

      it 'returns error' do
        result = job_instance.execute(event_id)

        expect(result).to eq({ error: 'Event not found' })
      end
    end

    context 'with push event' do
      it 'processes push event successfully' do
        allow(Git::RepositorySyncJob).to receive(:perform_async)

        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'push_processed',
          commits_count: 1,
          ref: 'refs/heads/main'
        )
      end

      it 'queues repository sync job' do
        allow(Git::RepositorySyncJob).to receive(:perform_async)

        job_instance.execute(event_id)

        expect(Git::RepositorySyncJob).to have_received(:perform_async).with(
          'cred-123',
          'repo-123',
          'commits'
        )
      end

      it 'marks event as processing then processed' do
        allow(Git::RepositorySyncJob).to receive(:perform_async)

        job_instance.execute(event_id)

        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/git/webhook_events/#{event_id}/processing"
        )
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/git/webhook_events/#{event_id}/processed",
          hash_including(:processing_result)
        )
      end

      it 'marks as processed in idempotency store' do
        allow(Git::RepositorySyncJob).to receive(:perform_async)

        job_instance.execute(event_id)

        expect(job_instance).to have_received(:mark_processed).with("git_webhook:#{event_id}")
      end
    end

    context 'with pull_request event' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'pull_request',
          'payload' => {
            'action' => 'opened',
            'pull_request' => { 'number' => 42 }
          },
          'repository' => { 'id' => 'repo-123', 'full_name' => 'owner/repo' }
        }
      end

      it 'processes pull request event' do
        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'pull_request_opened',
          pr_number: 42
        )
      end
    end

    context 'with workflow_run event' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'workflow_run',
          'payload' => {
            'workflow_run' => {
              'id' => 'run-456',
              'status' => 'completed',
              'conclusion' => 'success'
            }
          },
          'repository' => { 'id' => 'repo-123', 'full_name' => 'owner/repo' }
        }
      end

      it 'processes workflow run event' do
        allow(Git::PipelineSyncJob).to receive(:perform_async)

        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'workflow_run_synced',
          run_id: 'run-456',
          status: 'completed',
          conclusion: 'success'
        )
      end

      it 'queues pipeline sync job' do
        allow(Git::PipelineSyncJob).to receive(:perform_async)

        job_instance.execute(event_id)

        expect(Git::PipelineSyncJob).to have_received(:perform_async).with(
          'repo-123',
          'run-456'
        )
      end
    end

    context 'with workflow_job event' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'workflow_job',
          'payload' => {
            'workflow_job' => {
              'id' => 'job-789',
              'status' => 'completed',
              'conclusion' => 'success'
            }
          }
        }
      end

      it 'processes workflow job event' do
        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'workflow_job_processed',
          job_id: 'job-789',
          status: 'completed',
          conclusion: 'success'
        )
      end
    end

    context 'with create/delete ref event' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'create',
          'payload' => {
            'ref_type' => 'branch',
            'ref' => 'feature/new-branch'
          },
          'repository' => { 'id' => 'repo-123', 'credential_id' => 'cred-123' }
        }
      end

      it 'processes ref create event' do
        allow(Git::RepositorySyncJob).to receive(:perform_async)

        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'ref_create',
          ref_type: 'branch',
          ref: 'feature/new-branch'
        )
      end

      it 'queues branch sync for branch events' do
        allow(Git::RepositorySyncJob).to receive(:perform_async)

        job_instance.execute(event_id)

        expect(Git::RepositorySyncJob).to have_received(:perform_async).with(
          'cred-123',
          'repo-123',
          'branches'
        )
      end
    end

    context 'with release event' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'release',
          'payload' => {
            'action' => 'published',
            'release' => {
              'tag_name' => 'v1.0.0',
              'name' => 'Version 1.0.0'
            }
          }
        }
      end

      it 'processes release event' do
        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'release_published',
          tag_name: 'v1.0.0',
          name: 'Version 1.0.0'
        )
      end
    end

    context 'with ping event' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'ping',
          'payload' => { 'zen' => 'Keep it logically awesome.' }
        }
      end

      it 'acknowledges ping event' do
        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'ping_acknowledged',
          zen: 'Keep it logically awesome.'
        )
      end
    end

    context 'with unknown event type' do
      let(:sample_event) do
        {
          'id' => event_id,
          'event_type' => 'unknown_event',
          'action' => 'triggered',
          'payload' => {}
        }
      end

      it 'handles generic event' do
        result = job_instance.execute(event_id)

        expect(result).to include(
          success: true,
          action: 'generic_processed',
          event_type: 'unknown_event'
        )
      end
    end

    context 'when processing fails' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/webhook_events/#{event_id}")
          .and_raise(BackendApiClient::ApiError.new('API Error', 500))
      end

      it 'raises the error' do
        expect { job_instance.execute(event_id) }
          .to raise_error(BackendApiClient::ApiError)
      end
    end

    context 'when event processing raises error' do
      before do
        allow(job_instance).to receive(:process_event).and_raise(StandardError.new('Processing failed'))
      end

      it 'marks event as failed' do
        expect { job_instance.execute(event_id) }.to raise_error(StandardError)

        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/git/webhook_events/#{event_id}/failed",
          hash_including(:error_message)
        )
      end
    end
  end

  describe 'logging' do
    let(:job_args) { event_id }

    before do
      allow(Git::RepositorySyncJob).to receive(:perform_async)
    end

    it_behaves_like 'a job with logging'
  end
end
