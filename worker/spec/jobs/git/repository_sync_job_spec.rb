# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::RepositorySyncJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:credential_id) { 'cred-123-uuid' }
  let(:repository_id) { 'repo-456-uuid' }
  let(:api_client_double) { instance_double(BackendApiClient) }

  let(:sample_credential) do
    {
      'id' => credential_id,
      'name' => 'GitHub Token',
      'auth_type' => 'personal_access_token',
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

  let(:sample_repository) do
    {
      'id' => repository_id,
      'name' => 'test-repo',
      'full_name' => 'owner/test-repo',
      'owner' => 'owner',
      'default_branch' => 'main',
      'credential_id' => credential_id
    }
  end

  let(:github_repos_response) do
    [
      {
        'id' => 12345,
        'name' => 'repo-1',
        'full_name' => 'owner/repo-1',
        'owner' => { 'login' => 'owner' },
        'description' => 'Test repository',
        'default_branch' => 'main',
        'clone_url' => 'https://github.com/owner/repo-1.git',
        'ssh_url' => 'git@github.com:owner/repo-1.git',
        'html_url' => 'https://github.com/owner/repo-1',
        'private' => false,
        'fork' => false,
        'archived' => false,
        'stargazers_count' => 10,
        'forks_count' => 2,
        'open_issues_count' => 5,
        'language' => 'Ruby',
        'topics' => ['rails', 'api']
      }
    ]
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)

    # Default API stubs
    allow(api_client_double).to receive(:get)
      .with("/api/v1/internal/git/credentials/#{credential_id}")
      .and_return({ 'data' => sample_credential })
    allow(api_client_double).to receive(:get)
      .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      .and_return({ 'data' => sample_decrypted })
    allow(api_client_double).to receive(:get)
      .with("/api/v1/internal/git/repositories/#{repository_id}")
      .and_return({ 'data' => sample_repository })
    allow(api_client_double).to receive(:post).and_return({ 'success' => true })
    allow(api_client_double).to receive(:patch).and_return({ 'success' => true })

    # Stub external GitHub API calls
    stub_request(:get, %r{https://api.github.com/.*})
      .to_return(status: 200, body: github_repos_response.to_json, headers: { 'Content-Type' => 'application/json' })
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
    context 'when credential not found' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}")
          .and_return({ 'data' => nil })
      end

      it 'returns error' do
        result = job_instance.execute(credential_id)

        expect(result).to eq({ error: 'Credential not found' })
      end
    end

    context 'syncing all repositories for credential' do
      it 'fetches repositories from provider' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: true,
          synced_count: 1,
          error_count: 0,
          total_count: 1
        )
      end

      it 'posts each repository to backend' do
        job_instance.execute(credential_id)

        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/git/repositories',
          hash_including(
            credential_id: credential_id,
            repository: hash_including(
              external_id: '12345',
              name: 'repo-1',
              full_name: 'owner/repo-1'
            )
          )
        )
      end

      it 'handles errors for individual repositories' do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/repositories', anything)
          .and_raise(BackendApiClient::ApiError.new('Failed', 500))

        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: true,
          synced_count: 0,
          error_count: 1
        )
      end
    end

    context 'syncing specific repository' do
      context 'when repository not found' do
        before do
          allow(api_client_double).to receive(:get)
            .with("/api/v1/internal/git/repositories/#{repository_id}")
            .and_return({ 'data' => nil })
        end

        it 'returns error' do
          result = job_instance.execute(credential_id, repository_id, 'branches')

          expect(result).to eq({ error: 'Repository not found' })
        end
      end

      context 'syncing branches' do
        let(:branches_response) do
          [
            { 'name' => 'main', 'commit' => { 'sha' => 'abc123' } },
            { 'name' => 'develop', 'commit' => { 'sha' => 'def456' } }
          ]
        end

        before do
          stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/branches(\?.*)?$})
            .to_return(status: 200, body: branches_response.to_json, headers: { 'Content-Type' => 'application/json' })
        end

        it 'syncs branches to backend' do
          result = job_instance.execute(credential_id, repository_id, 'branches')

          expect(result).to include(success: true, sync_type: 'branches', count: 2)
          expect(api_client_double).to have_received(:post).with(
            "/api/v1/internal/git/repositories/#{repository_id}/sync_branches",
            hash_including(branches: branches_response)
          )
        end
      end

      context 'syncing commits' do
        let(:commits_response) do
          [
            { 'sha' => 'abc123', 'commit' => { 'message' => 'Initial commit' } },
            { 'sha' => 'def456', 'commit' => { 'message' => 'Add feature' } }
          ]
        end

        before do
          stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/commits.*})
            .to_return(status: 200, body: commits_response.to_json, headers: { 'Content-Type' => 'application/json' })
        end

        it 'syncs commits to backend' do
          result = job_instance.execute(credential_id, repository_id, 'commits')

          expect(result).to include(success: true, sync_type: 'commits', count: 2)
          expect(api_client_double).to have_received(:post).with(
            "/api/v1/internal/git/repositories/#{repository_id}/sync_commits",
            hash_including(commits: commits_response, branch: 'main')
          )
        end
      end

      context 'syncing pipelines' do
        let(:pipelines_response) do
          {
            'workflow_runs' => [
              { 'id' => 1, 'status' => 'completed', 'conclusion' => 'success' },
              { 'id' => 2, 'status' => 'in_progress', 'conclusion' => nil }
            ]
          }
        end

        before do
          stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/actions/runs.*})
            .to_return(status: 200, body: pipelines_response.to_json, headers: { 'Content-Type' => 'application/json' })
        end

        it 'syncs pipelines to backend' do
          result = job_instance.execute(credential_id, repository_id, 'pipelines')

          expect(result).to include(success: true, sync_type: 'pipelines', count: 2)
          expect(api_client_double).to have_received(:post).with(
            "/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines",
            hash_including(pipelines: pipelines_response['workflow_runs'])
          )
        end
      end

      context 'syncing metadata' do
        let(:repo_response) do
          {
            'id' => 12345,
            'name' => 'test-repo',
            'full_name' => 'owner/test-repo',
            'owner' => { 'login' => 'owner' },
            'description' => 'Updated description',
            'default_branch' => 'main',
            'clone_url' => 'https://github.com/owner/test-repo.git',
            'ssh_url' => 'git@github.com:owner/test-repo.git',
            'html_url' => 'https://github.com/owner/test-repo',
            'private' => true,
            'fork' => false,
            'archived' => false,
            'stargazers_count' => 50,
            'forks_count' => 10,
            'open_issues_count' => 3,
            'language' => 'Ruby',
            'topics' => ['rails']
          }
        end

        before do
          stub_request(:get, 'https://api.github.com/repos/owner/test-repo')
            .to_return(status: 200, body: repo_response.to_json, headers: { 'Content-Type' => 'application/json' })
        end

        it 'syncs repository metadata to backend' do
          result = job_instance.execute(credential_id, repository_id, 'metadata')

          expect(result).to include(success: true, sync_type: 'metadata')
          expect(api_client_double).to have_received(:patch).with(
            "/api/v1/internal/git/repositories/#{repository_id}",
            hash_including(
              repository: hash_including(
                external_id: '12345',
                is_private: true,
                stars_count: 50
              )
            )
          )
        end
      end

      context 'full sync (no sync_type)' do
        let(:repo_response) do
          {
            'id' => 12345,
            'name' => 'test-repo',
            'full_name' => 'owner/test-repo',
            'owner' => { 'login' => 'owner' },
            'default_branch' => 'main',
            'clone_url' => 'https://github.com/owner/test-repo.git',
            'ssh_url' => 'git@github.com:owner/test-repo.git',
            'html_url' => 'https://github.com/owner/test-repo'
          }
        end

        let(:branches_response) do
          [{ 'name' => 'main', 'commit' => { 'sha' => 'abc123' } }]
        end

        before do
          stub_request(:get, 'https://api.github.com/repos/owner/test-repo')
            .to_return(status: 200, body: repo_response.to_json, headers: { 'Content-Type' => 'application/json' })
          stub_request(:get, %r{https://api.github.com/repos/owner/test-repo/branches.*})
            .to_return(status: 200, body: branches_response.to_json, headers: { 'Content-Type' => 'application/json' })
        end

        it 'syncs metadata and branches' do
          result = job_instance.execute(credential_id, repository_id, nil)

          expect(result).to include(success: true, sync_type: 'full')
          expect(api_client_double).to have_received(:patch)
          expect(api_client_double).to have_received(:post).with(
            "/api/v1/internal/git/repositories/#{repository_id}/sync_branches",
            anything
          )
        end
      end
    end

    context 'with GitLab provider' do
      let(:sample_credential) do
        {
          'id' => credential_id,
          'provider' => {
            'provider_type' => 'gitlab',
            'api_base_url' => nil
          }
        }
      end

      let(:gitlab_repos_response) do
        [
          {
            'id' => 99999,
            'name' => 'gitlab-repo',
            'path_with_namespace' => 'group/gitlab-repo',
            'namespace' => { 'path' => 'group' },
            'description' => 'GitLab repo',
            'default_branch' => 'main',
            'http_url_to_repo' => 'https://gitlab.com/group/gitlab-repo.git',
            'ssh_url_to_repo' => 'git@gitlab.com:group/gitlab-repo.git',
            'web_url' => 'https://gitlab.com/group/gitlab-repo',
            'visibility' => 'private',
            'forked_from_project' => nil,
            'archived' => false,
            'star_count' => 5
          }
        ]
      end

      before do
        # Stub GitLab API - catch with or without /api/v4
        stub_request(:get, %r{https://gitlab.com.*/repos(\?.*)?$})
          .to_return(status: 200, body: gitlab_repos_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'uses correct GitLab API headers' do
        job_instance.execute(credential_id)

        expect(WebMock).to have_requested(:get, %r{https://gitlab.com.*/repos})
          .with(headers: { 'PRIVATE-TOKEN' => 'ghp_test_token_123' })
      end

      it 'normalizes GitLab repository format' do
        job_instance.execute(credential_id)

        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/git/repositories',
          hash_including(
            repository: hash_including(
              full_name: 'group/gitlab-repo',
              owner: 'group',
              is_private: true
            )
          )
        )
      end
    end

    context 'when provider API fails' do
      before do
        stub_request(:get, %r{https://api.github.com/.*})
          .to_return(status: 401, body: { message: 'Bad credentials' }.to_json)
      end

      it 'raises error' do
        expect { job_instance.execute(credential_id) }
          .to raise_error(StandardError, /Provider API error: 401/)
      end
    end
  end

  describe 'repository normalization' do
    it 'extracts all required fields from GitHub response' do
      job_instance.execute(credential_id)

      expect(api_client_double).to have_received(:post).with(
        '/api/v1/internal/git/repositories',
        hash_including(
          repository: hash_including(
            external_id: '12345',
            name: 'repo-1',
            full_name: 'owner/repo-1',
            owner: 'owner',
            description: 'Test repository',
            default_branch: 'main',
            clone_url: 'https://github.com/owner/repo-1.git',
            ssh_url: 'git@github.com:owner/repo-1.git',
            web_url: 'https://github.com/owner/repo-1',
            is_private: false,
            is_fork: false,
            is_archived: false,
            stars_count: 10,
            forks_count: 2,
            open_issues_count: 5,
            primary_language: 'Ruby',
            topics: ['rails', 'api']
          )
        )
      )
    end
  end

  describe 'logging' do
    let(:job_args) { [credential_id] }

    it_behaves_like 'a job with logging'
  end
end
