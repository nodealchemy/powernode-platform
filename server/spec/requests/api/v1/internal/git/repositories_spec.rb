# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::Repositories', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, provider: git_provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/git/repositories' do
    context 'with valid parameters' do
      let(:repo_params) do
        {
          credential_id: credential.id,
          repository: {
            external_id: 'repo-123',
            name: 'test-repo',
            full_name: 'owner/test-repo',
            owner: 'owner',
            description: 'Test repository',
            default_branch: 'main',
            clone_url: 'https://github.com/owner/test-repo.git',
            ssh_url: 'git@github.com:owner/test-repo.git',
            web_url: 'https://github.com/owner/test-repo',
            is_private: true,
            is_fork: false,
            is_archived: false,
            stars_count: 10,
            forks_count: 2,
            open_issues_count: 5,
            primary_language: 'Ruby',
            topics: ['rails', 'api']
          }
        }
      end

      it 'creates a new repository' do
        expect {
          post api_v1_internal_git_repositories_path,
               params: repo_params,
               headers: internal_headers
        }.to change(Devops::GitRepository, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['name']).to eq('test-repo')
        expect(json['data']['created']).to be true
      end

      it 'updates existing repository' do
        existing_repo = create(:git_repository,
                               credential: credential,
                               account: account,
                               external_id: 'repo-123',
                               stars_count: 5)

        post api_v1_internal_git_repositories_path,
             params: repo_params,
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['created']).to be false

        existing_repo.reload
        expect(existing_repo.stars_count).to eq(10)
      end

      it 'builds languages hash from primary_language' do
        post api_v1_internal_git_repositories_path,
             params: repo_params,
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        repo = Devops::GitRepository.last
        expect(repo.languages).to eq({ 'Ruby' => 100 })
      end

      it 'uses provided languages if primary_language not present' do
        params = repo_params.deep_dup
        params[:repository].delete(:primary_language)
        params[:repository][:languages] = { 'Ruby' => 80, 'JavaScript' => 20 }

        post api_v1_internal_git_repositories_path,
             params: params,
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        repo = Devops::GitRepository.last
        # Language values come back as strings from params processing
        expect(repo.languages).to eq({ 'Ruby' => '80', 'JavaScript' => '20' })
      end
    end

    context 'with non-existent credential' do
      it 'returns not found' do
        post api_v1_internal_git_repositories_path,
             params: {
               credential_id: SecureRandom.uuid,
               repository: { external_id: 'repo-1', name: 'test' }
             },
             headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Credential not found')
      end
    end

    context 'with validation errors' do
      it 'returns validation error' do
        post api_v1_internal_git_repositories_path,
             params: {
               credential_id: credential.id,
               repository: { external_id: '' }
             },
             headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post api_v1_internal_git_repositories_path,
             params: { credential_id: credential.id, repository: {} }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/git/repositories/:id' do
    context 'with valid internal authentication' do
      it 'returns the repository' do
        get api_v1_internal_git_repository_path(repository), headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['id']).to eq(repository.id)
        expect(json['data']['name']).to eq(repository.name)
      end

      it 'includes credential information' do
        get api_v1_internal_git_repository_path(repository), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['credential']).to be_present
        expect(json['data']['credential']['id']).to eq(credential.id)
        expect(json['data']['credential']['provider_type']).to eq(credential.provider_type)
      end
    end

    context 'with non-existent repository' do
      it 'returns not found' do
        get api_v1_internal_git_repository_path(SecureRandom.uuid), headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Repository not found')
      end
    end
  end

  describe 'PATCH /api/v1/internal/git/repositories/:id' do
    context 'with valid parameters' do
      it 'updates the repository' do
        patch api_v1_internal_git_repository_path(repository),
              params: {
                last_synced_at: Time.current.iso8601,
                stars_count: 100,
                forks_count: 20
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true

        repository.reload
        expect(repository.stars_count).to eq(100)
        expect(repository.forks_count).to eq(20)
      end

      it 'updates languages and topics' do
        patch api_v1_internal_git_repository_path(repository),
              params: {
                languages: { 'Ruby' => 70, 'JavaScript' => 30 },
                topics: ['api', 'rails', 'backend']
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        repository.reload
        # Language values come back as strings from params processing
        expect(repository.languages).to eq({ 'Ruby' => '70', 'JavaScript' => '30' })
        expect(repository.topics).to eq(['api', 'rails', 'backend'])
      end
    end

    context 'with validation errors' do
      it 'returns validation error' do
        # Eagerly create repository before stubbing
        repo_record = repository

        allow_any_instance_of(Devops::GitRepository).to receive(:update).and_return(false)
        allow_any_instance_of(Devops::GitRepository).to receive_message_chain(:errors, :full_messages).and_return(['Validation failed'])

        patch api_v1_internal_git_repository_path(repo_record),
              params: { stars_count: -1 },
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/internal/git/repositories/:id/sync_branches' do
    it 'syncs branches successfully' do
      branches_data = [
        { name: 'main', sha: 'abc123' },
        { name: 'develop', sha: 'def456' }
      ]

      post sync_branches_api_v1_internal_git_repository_path(repository),
           params: { branches: branches_data },
           headers: internal_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['repository_id']).to eq(repository.id)
      expect(json['data']['synced_count']).to eq(2)
    end
  end

  describe 'POST /api/v1/internal/git/repositories/:id/sync_commits' do
    it 'syncs commits successfully' do
      commits_data = [
        { sha: 'abc123', message: 'Initial commit' },
        { sha: 'def456', message: 'Add feature' }
      ]

      post sync_commits_api_v1_internal_git_repository_path(repository),
           params: { commits: commits_data },
           headers: internal_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['synced_count']).to eq(2)
    end
  end

  describe 'POST /api/v1/internal/git/repositories/:id/sync_pipelines' do
    context 'with valid pipeline data' do
      let(:pipelines_data) do
        [
          {
            external_id: 'pipeline-1',
            name: 'CI Pipeline',
            status: 'completed',
            conclusion: 'success',
            trigger_event: 'push',
            ref: 'refs/heads/main',
            sha: 'abc123',
            actor_username: 'developer',
            web_url: 'https://example.com/pipeline/1',
            run_number: 1,
            total_jobs: 3,
            completed_jobs: 3,
            duration_seconds: 120
          }
        ]
      end

      it 'syncs pipelines successfully' do
        post sync_pipelines_api_v1_internal_git_repository_path(repository),
             params: { pipelines: pipelines_data },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['synced_count']).to eq(1)
        expect(json['data']['pipeline_ids'].length).to eq(1)
      end

      it 'creates new pipelines' do
        expect {
          post sync_pipelines_api_v1_internal_git_repository_path(repository),
               params: { pipelines: pipelines_data },
               headers: internal_headers
        }.to change(Devops::GitPipeline, :count).by(1)
      end

      it 'updates existing pipelines' do
        existing = create(:git_pipeline,
                          repository: repository,
                          account: account,
                          external_id: 'pipeline-1',
                          status: 'in_progress')

        post sync_pipelines_api_v1_internal_git_repository_path(repository),
             params: { pipelines: pipelines_data },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        existing.reload
        expect(existing.status).to eq('completed')
        expect(existing.conclusion).to eq('success')
      end
    end
  end
end
