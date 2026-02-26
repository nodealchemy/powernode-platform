# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::Credentials', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) do
    create(:git_provider_credential,
           account: account,
           provider: git_provider,
           is_active: true)
  end
  let(:repository) { create(:git_repository, credential: credential, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/git/credentials' do
    context 'with valid internal authentication' do
      it 'returns all credentials' do
        credential # eagerly create the first credential
        credential2 = create(:git_provider_credential, account: account, provider: git_provider)

        get api_v1_internal_git_credentials_path, headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data'].length).to eq(2)
      end

      it 'filters by account_id when provided' do
        credential # eagerly create
        other_account = create(:account)
        create(:git_provider_credential, account: other_account, provider: git_provider)

        get api_v1_internal_git_credentials_path,
            params: { account_id: account.id },
            headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data'].length).to eq(1)
        expect(json['data'][0]['account_id']).to eq(account.id)
      end

      it 'filters by active status when provided' do
        inactive_cred = create(:git_provider_credential,
                               account: account,
                               provider: git_provider,
                               is_active: false)

        get api_v1_internal_git_credentials_path,
            params: { active: 'true' },
            headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data'].all? { |c| c['is_active'] }).to be true
      end

      it 'includes provider information' do
        credential # eagerly create
        get api_v1_internal_git_credentials_path, headers: internal_headers

        json = JSON.parse(response.body)
        cred_data = json['data'].first
        expect(cred_data['provider']).to be_present
        expect(cred_data['provider']['provider_type']).to eq(git_provider.provider_type)
        expect(cred_data['provider']['api_base_url']).to eq(git_provider.api_base_url)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_internal_git_credentials_path

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/git/credentials/:id' do
    context 'with valid internal authentication' do
      it 'returns the credential' do
        get api_v1_internal_git_credential_path(credential), headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['id']).to eq(credential.id)
        expect(json['data']['name']).to eq(credential.name)
        expect(json['data']['auth_type']).to eq(credential.auth_type)
      end

      it 'includes health status indicators' do
        get api_v1_internal_git_credential_path(credential), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']).to have_key('healthy')
        expect(json['data']).to have_key('can_be_used')
        expect(json['data']).to have_key('last_test_status')
      end

      it 'includes usage statistics' do
        credential.update!(
          success_count: 10,
          failure_count: 2,
          consecutive_failures: 0,
          last_used_at: 1.hour.ago
        )

        get api_v1_internal_git_credential_path(credential), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['success_count']).to eq(10)
        expect(json['data']['failure_count']).to eq(2)
        expect(json['data']['consecutive_failures']).to eq(0)
        expect(json['data']['last_used_at']).to be_present
      end
    end

    context 'with non-existent credential' do
      it 'returns not found' do
        get api_v1_internal_git_credential_path(SecureRandom.uuid), headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Credential not found')
      end
    end
  end

  describe 'GET /api/v1/internal/git/credentials/:id/repositories' do
    context 'with valid internal authentication' do
      it 'returns repositories for the credential' do
        repo1 = create(:git_repository, credential: credential, account: account)
        repo2 = create(:git_repository, credential: credential, account: account)

        get repositories_api_v1_internal_git_credential_path(credential),
            headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data'].length).to eq(2)
        expect(json['data'].map { |r| r['id'] }).to contain_exactly(repo1.id, repo2.id)
      end

      it 'includes repository details' do
        repository # eagerly create
        get repositories_api_v1_internal_git_credential_path(credential),
            headers: internal_headers

        json = JSON.parse(response.body)
        repo_data = json['data'].first
        expect(repo_data).to have_key('name')
        expect(repo_data).to have_key('full_name')
        expect(repo_data).to have_key('owner')
        expect(repo_data).to have_key('default_branch')
        expect(repo_data).to have_key('provider_type')
      end
    end
  end

  describe 'GET /api/v1/internal/git/credentials/:id/decrypted' do
    context 'with valid internal authentication' do
      it 'returns decrypted credentials' do
        get decrypted_api_v1_internal_git_credential_path(credential),
            headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['id']).to eq(credential.id)
        expect(json['data']['auth_type']).to eq(credential.auth_type)
        expect(json['data']['credentials']).to be_present
      end

      it 'includes provider information for API calls' do
        get decrypted_api_v1_internal_git_credential_path(credential),
            headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['provider']).to be_present
        expect(json['data']['provider']['provider_type']).to eq(git_provider.provider_type)
        expect(json['data']['provider']['api_base_url']).to eq(git_provider.api_base_url)
        expect(json['data']['provider']['web_base_url']).to eq(git_provider.web_base_url)
      end

      it 'handles decryption errors gracefully' do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:credentials).and_raise(StandardError.new('Decryption failed'))

        get decrypted_api_v1_internal_git_credential_path(credential),
            headers: internal_headers

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Failed to decrypt credentials')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get decrypted_api_v1_internal_git_credential_path(credential)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
