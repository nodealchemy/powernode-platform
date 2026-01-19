# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Internal::Git::RepositoriesController, type: :controller do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
  let(:repository) do
    create(:git_repository,
           credential: credential,
           account: account,
           name: 'my-repo',
           full_name: 'owner/my-repo',
           owner: 'owner')
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    set_service_auth_headers
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    it 'returns repository details' do
      get :show, params: { id: repository.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(repository.id)
      expect(json['data']['name']).to eq('my-repo')
      expect(json['data']['full_name']).to eq('owner/my-repo')
    end

    it 'includes credential information' do
      get :show, params: { id: repository.id }

      json = JSON.parse(response.body)
      expect(json['data']['credential']['id']).to eq(credential.id)
      expect(json['data']['credential']['provider_type']).to eq('github')
    end

    it 'includes sync timestamps' do
      repository.update!(last_synced_at: 1.hour.ago, last_commit_at: 30.minutes.ago)

      get :show, params: { id: repository.id }

      json = JSON.parse(response.body)
      expect(json['data']['last_synced_at']).to be_present
      expect(json['data']['last_commit_at']).to be_present
    end

    it 'returns not found for non-existent repository' do
      get :show, params: { id: SecureRandom.uuid }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end
  end

  # =============================================================================
  # UPDATE
  # =============================================================================

  describe 'PATCH #update' do
    it 'updates repository attributes' do
      patch :update, params: {
        id: repository.id,
        stars_count: 100,
        forks_count: 25,
        open_issues_count: 10
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      repository.reload
      expect(repository.stars_count).to eq(100)
      expect(repository.forks_count).to eq(25)
      expect(repository.open_issues_count).to eq(10)
    end

    it 'can update sync timestamps' do
      sync_time = Time.current

      patch :update, params: {
        id: repository.id,
        last_synced_at: sync_time.iso8601
      }

      expect(response).to have_http_status(:success)
      repository.reload
      expect(repository.last_synced_at).to be_within(1.second).of(sync_time)
    end

    it 'can update languages' do
      patch :update, params: {
        id: repository.id,
        languages: { 'Ruby' => 80, 'JavaScript' => 15, 'HTML' => 5 }
      }

      expect(response).to have_http_status(:success)
      repository.reload
      expect(repository.languages['Ruby']).to eq(80)
    end

    it 'can update topics' do
      patch :update, params: {
        id: repository.id,
        topics: %w[rails api backend]
      }

      expect(response).to have_http_status(:success)
      repository.reload
      expect(repository.topics).to include('rails', 'api')
    end
  end

  # =============================================================================
  # SYNC BRANCHES
  # =============================================================================

  describe 'POST #sync_branches' do
    let(:branches_data) do
      [
        { name: 'main', protected: true },
        { name: 'develop', protected: false },
        { name: 'feature/new-feature', protected: false }
      ]
    end

    it 'accepts branches data for sync' do
      post :sync_branches, params: { id: repository.id, branches: branches_data }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['repository_id']).to eq(repository.id)
      expect(json['data']['synced_count']).to eq(3)
    end

    it 'handles empty branches list' do
      post :sync_branches, params: { id: repository.id, branches: [] }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['synced_count']).to eq(0)
    end
  end

  # =============================================================================
  # SYNC COMMITS
  # =============================================================================

  describe 'POST #sync_commits' do
    let(:commits_data) do
      [
        { sha: 'abc123', message: 'Initial commit', author: 'developer' },
        { sha: 'def456', message: 'Add feature', author: 'developer' }
      ]
    end

    it 'accepts commits data for sync' do
      post :sync_commits, params: { id: repository.id, commits: commits_data }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['synced_count']).to eq(2)
    end
  end

  # =============================================================================
  # SYNC PIPELINES
  # =============================================================================

  describe 'POST #sync_pipelines' do
    let(:pipelines_data) do
      [
        {
          external_id: 'run_123',
          name: 'CI Build',
          status: 'completed',
          conclusion: 'success',
          trigger_event: 'push',
          ref: 'refs/heads/main',
          sha: 'abc123',
          actor_username: 'developer',
          run_number: 42,
          total_jobs: 3,
          completed_jobs: 3
        },
        {
          external_id: 'run_124',
          name: 'Deploy',
          status: 'in_progress',
          trigger_event: 'workflow_dispatch',
          ref: 'refs/heads/release',
          sha: 'def456',
          actor_username: 'deployer',
          run_number: 43
        }
      ]
    end

    it 'creates pipeline records' do
      expect {
        post :sync_pipelines, params: { id: repository.id, pipelines: pipelines_data }
      }.to change(Devops::GitPipeline, :count).by(2)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['synced_count']).to eq(2)
      expect(json['data']['pipeline_ids'].length).to eq(2)
    end

    it 'updates existing pipelines' do
      existing_pipeline = create(:git_pipeline,
                                  repository: repository,
                                  account: account,
                                  external_id: 'run_123',
                                  status: 'in_progress')

      expect {
        post :sync_pipelines, params: { id: repository.id, pipelines: pipelines_data }
      }.to change(Devops::GitPipeline, :count).by(1) # Only 1 new

      existing_pipeline.reload
      expect(existing_pipeline.status).to eq('completed')
      expect(existing_pipeline.conclusion).to eq('success')
    end

    it 'associates pipelines with account' do
      post :sync_pipelines, params: { id: repository.id, pipelines: pipelines_data }

      json = JSON.parse(response.body)
      pipeline_id = json['data']['pipeline_ids'].first
      pipeline = Devops::GitPipeline.find(pipeline_id)
      expect(pipeline.account_id).to eq(account.id)
    end
  end

  # =============================================================================
  # AUTHENTICATION
  # =============================================================================

  describe 'authentication' do
    it 'requires service token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :show, params: { id: repository.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
