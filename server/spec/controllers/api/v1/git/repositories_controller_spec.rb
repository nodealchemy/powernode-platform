# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::RepositoriesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:repo_read_user) { create(:user, account: account, permissions: ['git.repositories.read']) }
  let(:repo_manage_user) do
    create(:user, account: account, permissions: %w[
      git.repositories.read git.repositories.sync git.repositories.webhooks.manage
      git.repositories.delete
    ])
  end
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # REPOSITORY CRUD OPERATIONS
  # =============================================================================

  describe 'GET #index' do
    let!(:repo1) { create(:git_repository, credential: credential, account: account) }
    let!(:repo2) { create(:git_repository, credential: credential, account: account) }
    let!(:other_repo) { create(:git_repository) }

    context 'with valid permissions' do
      before { sign_in repo_read_user }

      it 'returns repositories for the account' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['repositories'].length).to eq(2)
      end

      it 'excludes repositories from other accounts' do
        get :index

        json = JSON.parse(response.body)
        repo_ids = json['data']['repositories'].map { |r| r['id'] }
        expect(repo_ids).not_to include(other_repo.id)
      end

      it 'filters by credential_id' do
        other_credential = create(:git_provider_credential, provider: provider, account: account)
        other_cred_repo = create(:git_repository, credential: other_credential, account: account)

        get :index, params: { credential_id: credential.id }

        json = JSON.parse(response.body)
        repo_ids = json['data']['repositories'].map { |r| r['id'] }
        expect(repo_ids).to include(repo1.id, repo2.id)
        expect(repo_ids).not_to include(other_cred_repo.id)
      end

      it 'filters by visibility' do
        private_repo = create(:git_repository, :private, credential: credential, account: account)

        get :index, params: { visibility: 'private' }

        json = JSON.parse(response.body)
        repo_ids = json['data']['repositories'].map { |r| r['id'] }
        expect(repo_ids).to include(private_repo.id)
        expect(repo_ids).not_to include(repo1.id, repo2.id)
      end

      it 'supports search by name' do
        repo1.update!(name: 'my-awesome-project')

        get :index, params: { search: 'awesome' }

        json = JSON.parse(response.body)
        expect(json['data']['repositories'].length).to eq(1)
        expect(json['data']['repositories'].first['name']).to eq('my-awesome-project')
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show' do
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    context 'with valid permissions' do
      before { sign_in repo_read_user }

      it 'returns repository details' do
        get :show, params: { id: repo.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['repository']['id']).to eq(repo.id)
      end

      it 'includes repository statistics' do
        get :show, params: { id: repo.id }

        json = JSON.parse(response.body)
        expect(json['data']['repository']).to include('stars_count', 'forks_count')
      end
    end

    context 'when repository belongs to another account' do
      let(:other_repo) { create(:git_repository) }
      before { sign_in repo_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_repo.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # REPOSITORY SYNC
  # =============================================================================

  describe 'POST #sync' do
    let(:worker_api_client) { instance_double(WorkerApiClient) }

    before do
      allow(WorkerApiClient).to receive(:new).and_return(worker_api_client)
    end

    context 'with valid permissions' do
      before { sign_in repo_manage_user }

      it 'triggers repository sync' do
        expect(worker_api_client).to receive(:queue_git_repository_sync).with(credential.id)

        post :sync, params: { credential_id: credential.id }

        expect(response).to have_http_status(:accepted)
        json = JSON.parse(response.body)
        expect(json['data']['message']).to include('sync')
      end
    end

    context 'without permissions' do
      before { sign_in repo_read_user }

      it 'returns forbidden error' do
        allow(worker_api_client).to receive(:queue_git_repository_sync)

        post :sync, params: { credential_id: credential.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # WEBHOOK MANAGEMENT
  # =============================================================================

  describe 'POST #configure_webhook' do
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    before do
      allow_any_instance_of(Git::Repository).to receive(:configure_webhook!).and_return({
        success: true,
        webhook_id: 'webhook_123'
      })
    end

    context 'with valid permissions' do
      before { sign_in repo_manage_user }

      it 'configures webhook for repository' do
        post :configure_webhook, params: { id: repo.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in repo_read_user }

      it 'returns forbidden error' do
        post :configure_webhook, params: { id: repo.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #remove_webhook' do
    let(:repo) { create(:git_repository, :with_webhook, credential: credential, account: account) }

    before do
      allow_any_instance_of(Git::Repository).to receive(:remove_webhook!).and_return({
        success: true
      })
    end

    context 'with valid permissions' do
      before { sign_in repo_manage_user }

      it 'removes webhook from repository' do
        delete :remove_webhook, params: { id: repo.id }

        expect(response).to have_http_status(:success)
      end
    end
  end

  # =============================================================================
  # REPOSITORY DATA ENDPOINTS
  # =============================================================================

  describe 'GET #branches' do
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:list_branches).and_return([
        { name: 'main', protected: true },
        { name: 'develop', protected: false }
      ])
    end

    context 'with valid permissions' do
      before { sign_in repo_read_user }

      it 'returns repository branches' do
        get :branches, params: { id: repo.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['branches'].length).to eq(2)
      end
    end
  end

  describe 'GET #commits' do
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:list_commits).and_return([
        { sha: 'abc123', message: 'Initial commit' },
        { sha: 'def456', message: 'Add feature' }
      ])
    end

    context 'with valid permissions' do
      before { sign_in repo_read_user }

      it 'returns repository commits' do
        get :commits, params: { id: repo.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['commits'].length).to eq(2)
      end

      it 'filters by branch' do
        get :commits, params: { id: repo.id, branch: 'main' }

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET #pull_requests' do
    let(:repo) { create(:git_repository, credential: credential, account: account) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:list_pull_requests).and_return([
        { number: 1, title: 'Feature PR', state: 'open' }
      ])
    end

    context 'with valid permissions' do
      before { sign_in repo_read_user }

      it 'returns repository pull requests' do
        get :pull_requests, params: { id: repo.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['pull_requests'].length).to eq(1)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:repo) { create(:git_repository, credential: credential, account: account) }

    context 'with valid permissions' do
      before { sign_in repo_manage_user }

      it 'deletes the repository record' do
        expect {
          delete :destroy, params: { id: repo.id }
        }.to change(Git::Repository, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end
  end
end
