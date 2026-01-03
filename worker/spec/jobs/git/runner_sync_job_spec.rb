# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::RunnerSyncJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:api_client_double) { instance_double(BackendApiClient) }
  let(:credential_id) { 'cred-123-uuid' }
  let(:repository_id) { 'repo-456-uuid' }
  let(:account_id) { 'account-789-uuid' }

  let(:sample_credential) do
    {
      'id' => credential_id,
      'provider_type' => 'github',
      'api_base_url' => nil,
      'access_token' => 'ghp_test_token',
      'status' => 'active'
    }
  end

  let(:sample_repository) do
    {
      'id' => repository_id,
      'owner' => 'test-owner',
      'name' => 'test-repo',
      'full_name' => 'test-owner/test-repo',
      'credential_id' => credential_id
    }
  end

  let(:github_runners_response) do
    {
      'runners' => [
        {
          'id' => 1,
          'name' => 'runner-1',
          'status' => 'online',
          'busy' => false,
          'labels' => [{ 'name' => 'self-hosted' }, { 'name' => 'linux' }],
          'os' => 'Linux',
          'arch' => 'X64'
        }
      ]
    }
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    allow(api_client_double).to receive(:get).and_return({ 'data' => {} })
    allow(api_client_double).to receive(:post).and_return({ 'success' => true })
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
    context 'with no parameters' do
      it 'returns error when no credential or account provided' do
        result = job_instance.execute({})

        expect(result).to eq({ error: 'credential_id or account_id required' })
      end
    end

    context 'with credential_id' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/repositories")
          .and_return({ 'data' => [sample_repository] })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/repositories/#{repository_id}")
          .and_return({ 'data' => sample_repository })

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runners})
          .to_return(status: 200, body: github_runners_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'syncs runners for the credential' do
        result = job_instance.execute(credential_id: credential_id)

        expect(result).to include(success: true)
        expect(result[:synced_count]).to be >= 0
      end

      it 'fetches decrypted credentials' do
        job_instance.execute(credential_id: credential_id)

        expect(api_client_double).to have_received(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      end

      it 'syncs runners to backend' do
        job_instance.execute(credential_id: credential_id)

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/git/runners/sync', hash_including(:runners))
      end
    end

    context 'with credential_id and repository_id' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/repositories/#{repository_id}")
          .and_return({ 'data' => sample_repository })

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runners})
          .to_return(status: 200, body: github_runners_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'syncs runners for specific repository' do
        result = job_instance.execute(
          credential_id: credential_id,
          repository_id: repository_id
        )

        expect(result).to include(success: true)
      end
    end

    context 'with account_id' do
      let(:credentials_list) do
        [
          { 'id' => credential_id, 'status' => 'active' }
        ]
      end

      before do
        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/credentials', { account_id: account_id })
          .and_return({ 'data' => credentials_list })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/repositories")
          .and_return({ 'data' => [sample_repository] })

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runners})
          .to_return(status: 200, body: github_runners_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'syncs runners for all credentials in account' do
        result = job_instance.execute(account_id: account_id)

        expect(result).to include(success: true)
      end

      it 'fetches credentials for account' do
        job_instance.execute(account_id: account_id)

        expect(api_client_double).to have_received(:get)
          .with('/api/v1/internal/git/credentials', { account_id: account_id })
      end
    end

    context 'when credential not found' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => nil })
      end

      it 'returns error' do
        result = job_instance.execute(credential_id: credential_id)

        expect(result).to eq({ error: 'Credential not found' })
      end
    end

    context 'with GitLab provider' do
      let(:gitlab_credential) do
        sample_credential.merge('provider_type' => 'gitlab', 'api_base_url' => 'https://gitlab.com/api/v4')
      end

      let(:gitlab_runners_response) do
        [
          {
            'id' => 1,
            'description' => 'runner-1',
            'status' => 'online',
            'active' => true,
            'tag_list' => ['docker', 'linux'],
            'platform' => 'linux',
            'architecture' => 'amd64'
          }
        ]
      end

      before do
        # Disable real HTTP connections for this context
        WebMock.disable_net_connect!

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => gitlab_credential })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/repositories")
          .and_return({ 'data' => [sample_repository] })

        # Stub ANY request to gitlab.com
        stub_request(:any, %r{gitlab\.com})
          .to_return(status: 200, body: gitlab_runners_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'normalizes GitLab runners' do
        job_instance.execute(credential_id: credential_id)

        expect(api_client_double).to have_received(:post) do |_path, data|
          runner = data[:runners].first
          expect(runner[:external_id]).to eq('1')
          expect(runner[:name]).to eq('runner-1')
          expect(runner[:labels]).to include('docker', 'linux')
        end
      end
    end

    context 'when provider API fails' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/repositories")
          .and_return({ 'data' => [sample_repository] })

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runners})
          .to_return(status: 401, body: { message: 'Unauthorized' }.to_json)
      end

      it 'continues without raising error' do
        result = job_instance.execute(credential_id: credential_id)

        expect(result).to include(success: true, synced_count: 0)
      end
    end
  end

  describe 'logging' do
    let(:job_args) { { credential_id: credential_id } }

    before do
      allow(api_client_double).to receive(:get).and_return({ 'data' => nil })
    end

    it_behaves_like 'a job with logging'
  end
end
