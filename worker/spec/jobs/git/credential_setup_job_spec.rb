# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::CredentialSetupJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:credential_id) { 'cred-123-uuid' }
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

  let(:github_user_response) do
    {
      'login' => 'testuser',
      'id' => 12345,
      'avatar_url' => 'https://avatars.githubusercontent.com/u/12345',
      'email' => 'test@example.com'
    }
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
    allow(api_client_double).to receive(:patch).and_return({ 'success' => true })

    # Stub external GitHub API calls - allow any query params
    stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
      .to_return(
        status: 200,
        body: github_user_response.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'X-OAuth-Scopes' => 'repo, user, workflow'
        }
      )

    # Mock RepositorySyncJob
    allow(Git::RepositorySyncJob).to receive(:perform_async)
  end

  describe 'class configuration' do
    it_behaves_like 'a base job', described_class

    it 'uses services queue' do
      expect(described_class.sidekiq_options['queue']).to eq('services')
    end

    it 'has 2 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
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

    context 'with successful connection test' do
      it 'returns success with user info' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: true,
          username: 'testuser',
          user_id: '12345',
          avatar_url: 'https://avatars.githubusercontent.com/u/12345',
          scopes: ['repo', 'user', 'workflow'],
          repo_sync_queued: true
        )
      end

      it 'updates credential with user info' do
        job_instance.execute(credential_id)

        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/git/credentials/#{credential_id}",
          hash_including(
            credential: hash_including(
              external_username: 'testuser',
              external_user_id: '12345',
              external_avatar_url: 'https://avatars.githubusercontent.com/u/12345',
              scopes: ['repo', 'user', 'workflow'],
              last_test_status: 'success',
              last_error: nil
            )
          )
        )
      end

      it 'queues repository sync job' do
        job_instance.execute(credential_id)

        expect(Git::RepositorySyncJob).to have_received(:perform_async).with(credential_id)
      end
    end

    context 'with skip_repo_sync option' do
      it 'does not queue repository sync when skip_repo_sync is true' do
        result = job_instance.execute(credential_id, { 'skip_repo_sync' => true })

        expect(result[:repo_sync_queued]).to be false
        expect(Git::RepositorySyncJob).not_to have_received(:perform_async)
      end

      it 'accepts symbol keys' do
        result = job_instance.execute(credential_id, { skip_repo_sync: true })

        expect(result[:repo_sync_queued]).to be false
        expect(Git::RepositorySyncJob).not_to have_received(:perform_async)
      end
    end

    context 'with failed connection test' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_return(
            status: 401,
            body: { message: 'Bad credentials' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns failure' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: false,
          error: 'Bad credentials'
        )
      end

      it 'updates credential with failure status' do
        job_instance.execute(credential_id)

        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/internal/git/credentials/#{credential_id}",
          hash_including(
            credential: hash_including(
              last_test_status: 'failed',
              last_error: 'Bad credentials'
            )
          )
        )
      end

      it 'does not queue repository sync' do
        job_instance.execute(credential_id)

        expect(Git::RepositorySyncJob).not_to have_received(:perform_async)
      end
    end

    context 'with connection timeout' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_raise(Faraday::TimeoutError.new('Connection timed out'))
      end

      it 'returns failure with timeout message' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: false,
          error: match(/timeout/i)
        )
      end
    end

    context 'with connection failure' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_raise(Faraday::ConnectionFailed.new('Failed to connect'))
      end

      it 'returns failure with connection message' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: false,
          error: match(/Connection failed/i)
        )
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

      let(:gitlab_user_response) do
        {
          'username' => 'gitlab_user',
          'id' => 99999,
          'avatar_url' => 'https://gitlab.com/uploads/avatar.png',
          'email' => 'gitlab@example.com'
        }
      end

      before do
        # Stub all GitLab API endpoints - catch both /user and /api/v4/user patterns
        stub_request(:get, %r{https://gitlab.com.*/user(\?.*)?$})
          .to_return(status: 200, body: gitlab_user_response.to_json, headers: { 'Content-Type' => 'application/json' })
        stub_request(:get, %r{https://gitlab.com.*/projects(\?.*)?$})
          .to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'uses correct GitLab API headers' do
        job_instance.execute(credential_id)

        expect(WebMock).to have_requested(:get, %r{https://gitlab.com.*/user})
          .with(headers: { 'PRIVATE-TOKEN' => 'ghp_test_token_123' }).at_least_once
      end

      it 'extracts GitLab user info correctly' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: true,
          username: 'gitlab_user',
          user_id: '99999'
        )
      end

      it 'attempts to infer GitLab scopes' do
        job_instance.execute(credential_id)

        # Should have tried to access projects to check read_api scope
        expect(WebMock).to have_requested(:get, %r{https://gitlab.com.*/projects})
      end
    end

    context 'with Gitea provider' do
      let(:sample_credential) do
        {
          'id' => credential_id,
          'provider' => {
            'provider_type' => 'gitea',
            'api_base_url' => 'https://git.example.com/api/v1'
          }
        }
      end

      let(:gitea_user_response) do
        {
          'login' => 'gitea_user',
          'id' => 55555,
          'avatar_url' => 'https://git.example.com/avatar/55555',
          'email' => 'gitea@example.com'
        }
      end

      before do
        # Stub Gitea API endpoints - catch with or without /api/v1
        stub_request(:get, %r{https://git.example.com.*/user(\?.*)?$})
          .to_return(status: 200, body: gitea_user_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'uses custom API base URL' do
        job_instance.execute(credential_id)

        expect(WebMock).to have_requested(:get, %r{https://git.example.com.*/user})
      end

      it 'extracts Gitea user info correctly' do
        result = job_instance.execute(credential_id)

        expect(result).to include(
          success: true,
          username: 'gitea_user',
          user_id: '55555',
          scopes: [] # Gitea doesn't expose scopes
        )
      end
    end

    context 'when backend API fails' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}")
          .and_raise(BackendApiClient::ApiError.new('Backend unavailable', 503))
      end

      it 'raises error' do
        expect { job_instance.execute(credential_id) }
          .to raise_error(BackendApiClient::ApiError)
      end
    end
  end

  describe 'error message parsing' do
    context 'with hash error response' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_return(
            status: 403,
            body: { 'message' => 'API rate limit exceeded' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'extracts message from hash' do
        result = job_instance.execute(credential_id)

        expect(result[:error]).to eq('API rate limit exceeded')
      end
    end

    context 'with error_description in response' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_return(
            status: 401,
            body: { 'error_description' => 'Token expired' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'extracts error_description' do
        result = job_instance.execute(credential_id)

        expect(result[:error]).to eq('Token expired')
      end
    end

    context 'with string error response' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_return(
            status: 500,
            body: 'Internal Server Error',
            headers: { 'Content-Type' => 'text/plain' }
          )
      end

      it 'truncates long string responses' do
        result = job_instance.execute(credential_id)

        expect(result[:error].length).to be <= 200
      end
    end
  end

  describe 'scope extraction' do
    context 'with GitHub scopes header' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_return(
            status: 200,
            body: github_user_response.to_json,
            headers: {
              'Content-Type' => 'application/json',
              'X-OAuth-Scopes' => 'repo, workflow, read:user'
            }
          )
      end

      it 'parses comma-separated scopes' do
        result = job_instance.execute(credential_id)

        expect(result[:scopes]).to eq(['repo', 'workflow', 'read:user'])
      end
    end

    context 'without scopes header' do
      before do
        stub_request(:get, %r{https://api.github.com/user(\?.*)?$})
          .to_return(
            status: 200,
            body: github_user_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns empty scopes array' do
        result = job_instance.execute(credential_id)

        expect(result[:scopes]).to eq([])
      end
    end
  end

  describe 'logging' do
    let(:job_args) { [credential_id] }

    it_behaves_like 'a job with logging'
  end
end
