# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::PipelineSyncJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:repository_id) { 'repo-123-uuid' }
  let(:credential_id) { 'cred-456-uuid' }
  let(:external_pipeline_id) { '789' }
  let(:api_client_double) { instance_double(BackendApiClient) }

  let(:sample_repository) do
    {
      'id' => repository_id,
      'name' => 'test-repo',
      'full_name' => 'owner/test-repo',
      'owner' => 'owner',
      'default_branch' => 'main',
      'credential_id' => credential_id,
      'provider' => {
        'provider_type' => 'github',
        'api_base_url' => nil
      }
    }
  end

  let(:sample_decrypted) do
    {
      'access_token' => 'ghp_test_token_123'
    }
  end

  let(:sample_pipeline) do
    {
      'id' => external_pipeline_id.to_i,
      'name' => 'CI',
      'display_title' => 'CI Build',
      'status' => 'completed',
      'conclusion' => 'success',
      'event' => 'push',
      'head_branch' => 'main',
      'head_sha' => 'abc123def456',
      'actor' => { 'login' => 'developer' },
      'html_url' => 'https://github.com/owner/test-repo/actions/runs/789',
      'run_number' => 42,
      'run_attempt' => 1,
      'run_started_at' => '2024-01-15T10:00:00Z',
      'completed_at' => '2024-01-15T10:05:00Z'
    }
  end

  let(:sample_jobs) do
    [
      {
        'id' => 1001,
        'name' => 'build',
        'status' => 'completed',
        'conclusion' => 'success',
        'runner_name' => 'ubuntu-latest',
        'runner_id' => 'runner-1',
        'started_at' => '2024-01-15T10:00:30Z',
        'completed_at' => '2024-01-15T10:03:00Z',
        'steps' => [
          { 'name' => 'Checkout', 'status' => 'completed', 'conclusion' => 'success' },
          { 'name' => 'Build', 'status' => 'completed', 'conclusion' => 'success' }
        ]
      },
      {
        'id' => 1002,
        'name' => 'test',
        'status' => 'completed',
        'conclusion' => 'success',
        'runner_name' => 'ubuntu-latest',
        'runner_id' => 'runner-2',
        'started_at' => '2024-01-15T10:03:00Z',
        'completed_at' => '2024-01-15T10:05:00Z',
        'steps' => []
      }
    ]
  end

  let(:pipelines_list_response) do
    {
      'workflow_runs' => [
        sample_pipeline,
        sample_pipeline.merge('id' => 788, 'run_number' => 41)
      ]
    }
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)

    # Default API stubs
    allow(api_client_double).to receive(:get)
      .with("/api/v1/internal/git/repositories/#{repository_id}")
      .and_return({ 'data' => sample_repository })
    allow(api_client_double).to receive(:get)
      .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      .and_return({ 'data' => sample_decrypted })
    allow(api_client_double).to receive(:post).and_return({ 'success' => true })

    # Stub external GitHub API calls
    stub_request(:get, "https://api.github.com/repos/owner/test-repo/actions/runs/#{external_pipeline_id}")
      .to_return(status: 200, body: sample_pipeline.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/actions/runs/#{external_pipeline_id}/jobs})
      .to_return(status: 200, body: { 'jobs' => sample_jobs }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/actions/runs\?})
      .to_return(status: 200, body: pipelines_list_response.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/actions/runs/\d+/jobs})
      .to_return(status: 200, body: { 'jobs' => sample_jobs }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'class configuration' do
    it_behaves_like 'a base job', described_class

    it 'uses services queue' do
      expect(described_class.sidekiq_options['queue']).to eq('services')
    end

    it 'has 3 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    context 'when repository not found' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/repositories/#{repository_id}")
          .and_return({ 'data' => nil })
      end

      it 'returns error' do
        result = job_instance.execute(repository_id)

        expect(result).to eq({ error: 'Repository not found' })
      end
    end

    context 'syncing single pipeline' do
      it 'fetches pipeline details from provider' do
        result = job_instance.execute(repository_id, external_pipeline_id)

        expect(result).to include(
          success: true,
          pipeline_id: external_pipeline_id,
          status: 'completed',
          conclusion: 'success',
          jobs_count: 2
        )
      end

      it 'posts normalized pipeline to backend' do
        job_instance.execute(repository_id, external_pipeline_id)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines",
          hash_including(
            pipelines: [
              hash_including(
                external_id: external_pipeline_id,
                name: 'CI',
                status: 'completed',
                conclusion: 'success',
                trigger_event: 'push',
                ref: 'main',
                sha: 'abc123def456',
                actor_username: 'developer',
                run_number: 42,
                total_jobs: 2
              )
            ]
          )
        )
      end

      it 'syncs pipeline jobs' do
        job_instance.execute(repository_id, external_pipeline_id)

        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/git/pipelines/sync_jobs',
          hash_including(
            repository_id: repository_id,
            pipeline_external_id: external_pipeline_id,
            jobs: array_including(
              hash_including(
                external_id: '1001',
                name: 'build',
                status: 'completed',
                conclusion: 'success'
              ),
              hash_including(
                external_id: '1002',
                name: 'test'
              )
            )
          )
        )
      end

      context 'when pipeline not found on provider' do
        before do
          stub_request(:get, "https://api.github.com/repos/owner/test-repo/actions/runs/#{external_pipeline_id}")
            .to_return(status: 404, body: { message: 'Not Found' }.to_json)
        end

        it 'returns error' do
          result = job_instance.execute(repository_id, external_pipeline_id)

          expect(result).to eq({ error: 'Pipeline not found' })
        end
      end
    end

    context 'syncing recent pipelines' do
      it 'fetches list of recent pipelines' do
        result = job_instance.execute(repository_id)

        expect(result).to include(
          success: true,
          synced_count: 2
        )
      end

      it 'posts all pipelines to backend' do
        job_instance.execute(repository_id)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines",
          hash_including(
            pipelines: array_including(
              hash_including(external_id: external_pipeline_id),
              hash_including(external_id: '788')
            )
          )
        )
      end
    end

    context 'with GitLab provider' do
      let(:sample_repository) do
        {
          'id' => repository_id,
          'name' => 'gitlab-repo',
          'full_name' => 'group/gitlab-repo',
          'owner' => 'group',
          'credential_id' => credential_id,
          'provider' => {
            'provider_type' => 'gitlab',
            'api_base_url' => nil
          }
        }
      end

      let(:gitlab_pipeline) do
        {
          'id' => 999,
          'status' => 'success',
          'ref' => 'main',
          'sha' => 'gitlab123',
          'user' => { 'username' => 'gitlab_user' },
          'web_url' => 'https://gitlab.com/group/gitlab-repo/-/pipelines/999',
          'source' => 'push',
          'started_at' => '2024-01-15T10:00:00Z',
          'finished_at' => '2024-01-15T10:05:00Z'
        }
      end

      let(:gitlab_jobs) do
        [
          { 'id' => 2001, 'name' => 'build', 'status' => 'success' }
        ]
      end

      before do
        # Stub GitLab pipelines - catch with or without /api/v4
        stub_request(:get, %r{https://gitlab.com.*/pipelines(\?.*)?$})
          .to_return(status: 200, body: [gitlab_pipeline].to_json, headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, %r{https://gitlab.com.*/pipelines/\d+$})
          .to_return(status: 200, body: gitlab_pipeline.to_json, headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, %r{https://gitlab.com.*/pipelines/\d+/jobs})
          .to_return(status: 200, body: gitlab_jobs.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'uses correct GitLab API headers' do
        job_instance.execute(repository_id)

        expect(WebMock).to have_requested(:get, %r{https://gitlab.com.*/pipelines})
          .with(headers: { 'PRIVATE-TOKEN' => 'ghp_test_token_123' }).at_least_once
      end

      it 'normalizes GitLab pipeline status' do
        job_instance.execute(repository_id)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines",
          hash_including(
            pipelines: array_including(
              hash_including(
                status: 'completed',
                conclusion: 'success'
              )
            )
          )
        )
      end
    end

    context 'with Gitea provider' do
      let(:sample_repository) do
        {
          'id' => repository_id,
          'name' => 'gitea-repo',
          'full_name' => 'owner/gitea-repo',
          'owner' => 'owner',
          'credential_id' => credential_id,
          'provider' => {
            'provider_type' => 'gitea',
            'api_base_url' => 'https://git.example.com/api/v1'
          }
        }
      end

      before do
        # Stub Gitea pipelines - catch with or without /api/v1
        stub_request(:get, %r{https://git.example.com.*/actions/runs(\?.*)?$})
          .to_return(status: 200, body: pipelines_list_response.to_json, headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, %r{https://git.example.com.*/actions/runs/\d+$})
          .to_return(status: 200, body: sample_pipeline.to_json, headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, %r{https://git.example.com.*/actions/runs/\d+/jobs})
          .to_return(status: 200, body: { 'jobs' => sample_jobs }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'uses custom API base URL' do
        job_instance.execute(repository_id)

        expect(WebMock).to have_requested(:get, %r{https://git.example.com.*/actions/runs}).at_least_once
      end
    end

    context 'when provider API fails' do
      before do
        stub_request(:get, %r{https://api.github.com/.*})
          .to_return(status: 500, body: { message: 'Internal Server Error' }.to_json)
      end

      it 'raises error' do
        expect { job_instance.execute(repository_id) }
          .to raise_error(StandardError, /Provider API error: 500/)
      end
    end

    context 'when job sync fails' do
      before do
        # First allow sync_pipelines to succeed
        allow(api_client_double).to receive(:post)
          .with("/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines", anything)
          .and_return({ 'success' => true })
        # Then make sync_jobs fail
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/pipelines/sync_jobs', anything)
          .and_raise(BackendApiClient::ApiError.new('Failed', 500))
      end

      it 'continues without raising' do
        # Should not raise, just log warning
        expect { job_instance.execute(repository_id, external_pipeline_id) }
          .not_to raise_error
      end
    end
  end

  describe 'status normalization' do
    let(:status_test_cases) do
      {
        'queued' => 'queued',
        'waiting' => 'queued',
        'pending' => 'queued',
        'in_progress' => 'in_progress',
        'running' => 'in_progress',
        'completed' => 'completed',
        'success' => 'completed',
        'failed' => 'completed',
        'failure' => 'completed',
        'cancelled' => 'completed',
        'canceled' => 'completed',
        'skipped' => 'completed'
      }
    end

    it 'normalizes various status values correctly' do
      status_test_cases.each do |input, expected|
        normalized = job_instance.send(:normalize_status, input)
        expect(normalized).to eq(expected), "Expected #{input} to normalize to #{expected}, got #{normalized}"
      end
    end
  end

  describe 'conclusion normalization' do
    let(:conclusion_test_cases) do
      {
        'success' => 'success',
        'failed' => 'failure',
        'failure' => 'failure',
        'cancelled' => 'cancelled',
        'canceled' => 'cancelled',
        'skipped' => 'skipped'
      }
    end

    it 'normalizes various conclusion values correctly' do
      conclusion_test_cases.each do |input, expected|
        normalized = job_instance.send(:normalize_conclusion, input)
        expect(normalized).to eq(expected), "Expected #{input} to normalize to #{expected}, got #{normalized}"
      end
    end
  end

  describe 'logging' do
    let(:job_args) { [repository_id] }

    it_behaves_like 'a job with logging'
  end
end
