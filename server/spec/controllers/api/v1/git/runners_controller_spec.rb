# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::RunnersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:runner_read_user) { create(:user, account: account, permissions: ['git.runners.read']) }
  let(:runner_manage_user) do
    create(:user, account: account, permissions: %w[
      git.runners.read git.runners.manage git.runners.token
    ])
  end
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, git_provider: provider, account: account) }
  let(:repository) { create(:git_repository, git_provider_credential: credential, account: account) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # INDEX
  # =============================================================================

  describe 'GET #index' do
    let!(:runner1) { create(:git_runner, :online, git_provider_credential: credential, account: account) }
    let!(:runner2) { create(:git_runner, :offline, git_provider_credential: credential, account: account) }
    let!(:other_runner) { create(:git_runner) }

    context 'with valid permissions' do
      before { sign_in runner_read_user }

      it 'returns runners for the account' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['runners'].length).to eq(2)
      end

      it 'excludes runners from other accounts' do
        get :index

        json = JSON.parse(response.body)
        runner_ids = json['data']['runners'].map { |r| r['id'] }
        expect(runner_ids).not_to include(other_runner.id)
      end

      it 'includes stats' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['stats']).to be_present
        expect(json['data']['stats']['total']).to eq(2)
        expect(json['data']['stats']['online']).to eq(1)
        expect(json['data']['stats']['offline']).to eq(1)
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
      end

      it 'filters by status' do
        get :index, params: { status: 'online' }

        json = JSON.parse(response.body)
        expect(json['data']['runners'].length).to eq(1)
        expect(json['data']['runners'].first['status']).to eq('online')
      end

      it 'filters by scope' do
        org_runner = create(:git_runner, :organization_scope, git_provider_credential: credential, account: account)
        get :index, params: { scope: 'organization' }

        json = JSON.parse(response.body)
        runner_ids = json['data']['runners'].map { |r| r['id'] }
        expect(runner_ids).to include(org_runner.id)
        expect(runner_ids).not_to include(runner1.id)
      end

      it 'filters by credential_id' do
        other_credential = create(:git_provider_credential, git_provider: provider, account: account)
        other_cred_runner = create(:git_runner, git_provider_credential: other_credential, account: account)

        get :index, params: { credential_id: credential.id }

        json = JSON.parse(response.body)
        runner_ids = json['data']['runners'].map { |r| r['id'] }
        expect(runner_ids).to include(runner1.id, runner2.id)
        expect(runner_ids).not_to include(other_cred_runner.id)
      end

      it 'supports search by name' do
        runner1.update!(name: 'my-special-runner')

        get :index, params: { search: 'special' }

        json = JSON.parse(response.body)
        expect(json['data']['runners'].length).to eq(1)
        expect(json['data']['runners'].first['name']).to eq('my-special-runner')
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

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    let(:runner) { create(:git_runner, :with_repository, :with_jobs, git_provider_credential: credential, account: account, git_repository: repository) }

    context 'with valid permissions' do
      before { sign_in runner_read_user }

      it 'returns runner details' do
        get :show, params: { id: runner.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['runner']['id']).to eq(runner.id)
      end

      it 'includes job statistics' do
        get :show, params: { id: runner.id }

        json = JSON.parse(response.body)
        expect(json['data']['runner']).to include('successful_jobs', 'failed_jobs', 'success_rate')
      end

      it 'includes repository info when present' do
        get :show, params: { id: runner.id }

        json = JSON.parse(response.body)
        expect(json['data']['runner']['repository']).to be_present
        expect(json['data']['runner']['repository']['id']).to eq(repository.id)
      end
    end

    context 'when runner belongs to another account' do
      let(:other_runner) { create(:git_runner) }
      before { sign_in runner_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_runner.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # DESTROY
  # =============================================================================

  describe 'DELETE #destroy' do
    let!(:runner) { create(:git_runner, :with_repository, git_provider_credential: credential, account: account, git_repository: repository) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
    end

    context 'with valid permissions' do
      before { sign_in runner_manage_user }

      it 'deletes runner when provider returns success' do
        allow(mock_client).to receive(:delete_runner).and_return({ success: true })

        expect {
          delete :destroy, params: { id: runner.id }
        }.to change(GitRunner, :count).by(-1)

        expect(response).to have_http_status(:success)
      end

      it 'returns error when provider deletion fails' do
        allow(mock_client).to receive(:delete_runner).and_return({ success: false, error: 'Runner not found' })

        delete :destroy, params: { id: runner.id }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Runner not found')
      end
    end

    context 'without permissions' do
      before { sign_in runner_read_user }

      it 'returns forbidden error' do
        allow(mock_client).to receive(:delete_runner).and_return({ success: true })

        delete :destroy, params: { id: runner.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # SYNC
  # =============================================================================

  describe 'POST #sync' do
    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        post :sync

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with invalid credential_id' do
      before { sign_in runner_read_user }

      it 'returns not found error' do
        post :sync, params: { credential_id: 'non-existent-id' }

        expect(response).to have_http_status(:not_found)
      end
    end

    # Integration test for sync with active credentials requires more setup
    # Tested via request specs or integration tests
  end

  # =============================================================================
  # REGISTRATION TOKEN
  # =============================================================================

  describe 'POST #registration_token' do
    let(:runner) { create(:git_runner, :with_repository, git_provider_credential: credential, account: account, git_repository: repository) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:is_a?).with(::Git::GiteaApiClient).and_return(false)
    end

    context 'with valid permissions' do
      before { sign_in runner_manage_user }

      it 'returns registration token' do
        allow(mock_client).to receive(:runner_registration_token).and_return({
          token: 'ATOKEN123',
          expires_at: 1.hour.from_now.iso8601
        })

        post :registration_token, params: { id: runner.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['token']).to eq('ATOKEN123')
      end

      it 'returns error when token generation fails' do
        allow(mock_client).to receive(:runner_registration_token).and_return({
          token: nil,
          error: 'Failed to generate token'
        })

        post :registration_token, params: { id: runner.id }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without token permission' do
      before { sign_in runner_read_user }

      it 'returns forbidden error' do
        post :registration_token, params: { id: runner.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # REMOVAL TOKEN
  # =============================================================================

  describe 'POST #removal_token' do
    let(:runner) { create(:git_runner, :with_repository, git_provider_credential: credential, account: account, git_repository: repository) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:is_a?).with(::Git::GiteaApiClient).and_return(false)
      allow(mock_client).to receive(:respond_to?).with(:runner_removal_token).and_return(true)
    end

    context 'with valid permissions' do
      before { sign_in runner_manage_user }

      it 'returns removal token' do
        allow(mock_client).to receive(:runner_removal_token).and_return({
          token: 'RTOKEN456',
          expires_at: 1.hour.from_now.iso8601
        })

        post :removal_token, params: { id: runner.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['token']).to eq('RTOKEN456')
      end
    end
  end

  # =============================================================================
  # UPDATE LABELS
  # =============================================================================

  describe 'PUT #update_labels' do
    let(:runner) { create(:git_runner, :with_repository, labels: ['linux'], git_provider_credential: credential, account: account, git_repository: repository) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:respond_to?).with(:set_runner_labels).and_return(true)
      allow(mock_client).to receive(:respond_to?).with(:update_runner_labels).and_return(false)
    end

    context 'with valid permissions' do
      before { sign_in runner_manage_user }

      it 'updates runner labels' do
        allow(mock_client).to receive(:set_runner_labels).and_return({
          labels: ['linux', 'docker', 'self-hosted']
        })

        put :update_labels, params: { id: runner.id, labels: ['linux', 'docker', 'self-hosted'] }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['runner']['labels']).to include('docker')
      end

      it 'returns error when missing labels param' do
        put :update_labels, params: { id: runner.id }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permissions' do
      before { sign_in runner_read_user }

      it 'returns forbidden error' do
        put :update_labels, params: { id: runner.id, labels: ['new-label'] }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
