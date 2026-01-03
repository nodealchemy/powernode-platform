# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::ProvidersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:provider_read_user) { create(:user, account: account, permissions: ['git.providers.read']) }
  let(:provider_manage_user) do
    create(:user, account: account, permissions: %w[
      git.providers.read git.providers.create git.providers.update git.providers.delete
      git.credentials.read git.credentials.create git.credentials.update git.credentials.delete
      git.credentials.test
    ])
  end
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # PROVIDER CRUD OPERATIONS
  # =============================================================================

  describe 'GET #index' do
    let!(:github_provider) { create(:git_provider, :github) }
    let!(:gitlab_provider) { create(:git_provider, :gitlab) }
    let!(:gitea_provider) { create(:git_provider, :gitea) }
    let!(:inactive_provider) { create(:git_provider, :inactive) }

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns list of active providers' do
        get :index
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['providers'].length).to eq(3)
      end

      it 'filters by provider_type' do
        get :index, params: { provider_type: 'github' }

        json = JSON.parse(response.body)
        expect(json['data']['providers'].length).to eq(1)
        expect(json['data']['providers'].first['provider_type']).to eq('github')
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to include(
          'current_page' => 1,
          'per_page' => 20
        )
      end

      it 'supports search by name' do
        get :index, params: { search: 'GitHub' }

        json = JSON.parse(response.body)
        expect(json['data']['providers'].length).to eq(1)
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET #show' do
    let(:provider) { create(:git_provider, :github) }

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns provider details' do
        get :show, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['provider']['id']).to eq(provider.id)
      end

      it 'includes provider capabilities' do
        get :show, params: { id: provider.id }

        json = JSON.parse(response.body)
        expect(json['data']['provider']['capabilities']).to be_present
      end
    end

    context 'when provider does not exist' do
      before { sign_in provider_read_user }

      it 'returns not found error' do
        get :show, params: { id: 'nonexistent-id' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        provider: {
          name: 'My Git Provider',
          slug: 'my-git-provider',
          provider_type: 'github',
          capabilities: %w[repos branches commits],
          is_active: true
        }
      }
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'creates a new provider' do
        expect {
          post :create, params: valid_params
        }.to change(GitProvider, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['provider']['name']).to eq('My Git Provider')
      end
    end

    context 'with invalid parameters' do
      before { sign_in provider_manage_user }

      it 'returns validation errors' do
        invalid_params = { provider: { name: '' } }

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in provider_read_user }

      it 'returns forbidden error' do
        post :create, params: valid_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH #update' do
    let(:provider) { create(:git_provider, name: 'Original Name') }
    let(:update_params) do
      {
        id: provider.id,
        provider: { name: 'Updated Name' }
      }
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'updates the provider' do
        patch :update, params: update_params

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['provider']['name']).to eq('Updated Name')
        expect(provider.reload.name).to eq('Updated Name')
      end
    end

    context 'without permissions' do
      before { sign_in provider_read_user }

      it 'returns forbidden error' do
        patch :update, params: update_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:provider) { create(:git_provider) }

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'deletes the provider' do
        expect {
          delete :destroy, params: { id: provider.id }
        }.to change(GitProvider, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end

    context 'without permissions' do
      before { sign_in provider_read_user }

      it 'returns forbidden error' do
        delete :destroy, params: { id: provider.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # CREDENTIALS - NESTED RESOURCE
  # =============================================================================

  describe 'GET #credentials' do
    let(:provider) { create(:git_provider) }
    let!(:credential1) { create(:git_provider_credential, git_provider: provider, account: account) }
    let!(:credential2) { create(:git_provider_credential, git_provider: provider, account: account) }
    let!(:other_account_cred) { create(:git_provider_credential, git_provider: provider) }

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'returns credentials for the provider' do
        get :credentials, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['credentials'].length).to eq(2)
      end

      it 'excludes credentials from other accounts' do
        get :credentials, params: { id: provider.id }

        json = JSON.parse(response.body)
        credential_ids = json['data']['credentials'].map { |c| c['id'] }
        expect(credential_ids).not_to include(other_account_cred.id)
      end
    end
  end

  describe 'POST #create_credential' do
    let(:provider) { create(:git_provider, :github) }
    let(:valid_params) do
      {
        id: provider.id,
        credential: {
          name: 'My GitHub Token',
          auth_type: 'personal_access_token',
          credentials: { access_token: 'ghp_test_token_123' }
        }
      }
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'creates a new credential' do
        expect {
          post :create_credential, params: valid_params
        }.to change(GitProviderCredential, :count).by(1)

        expect(response).to have_http_status(:created)
      end

      it 'associates credential with current account' do
        post :create_credential, params: valid_params

        credential = GitProviderCredential.last
        expect(credential.account).to eq(account)
      end
    end

    context 'without permissions' do
      before { sign_in provider_read_user }

      it 'returns forbidden error' do
        post :create_credential, params: valid_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #destroy_credential' do
    let(:provider) { create(:git_provider) }
    # Create two credentials so we can delete one (model prevents deleting last credential)
    let!(:credential) { create(:git_provider_credential, git_provider: provider, account: account) }
    let!(:other_credential) { create(:git_provider_credential, git_provider: provider, account: account) }

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'deletes the credential' do
        expect {
          delete :destroy_credential, params: { id: provider.id, credential_id: credential.id }
        }.to change(GitProviderCredential, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end

    context 'when credential belongs to another account' do
      let!(:other_credential) { create(:git_provider_credential, git_provider: provider) }
      before { sign_in provider_manage_user }

      it 'returns not found error' do
        delete :destroy_credential, params: { id: provider.id, credential_id: other_credential.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # CREDENTIAL ACTIONS
  # =============================================================================

  describe 'POST #test_credential' do
    let(:provider) { create(:git_provider, :github) }
    let(:credential) { create(:git_provider_credential, git_provider: provider, account: account) }

    before do
      allow_any_instance_of(GitProviderTestService).to receive(:test_with_rate_limit).and_return({
        success: true,
        response_time_ms: 150.0,
        user: { login: 'testuser' }
      })
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'tests the credential' do
        post :test_credential, params: { id: provider.id, credential_id: credential.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['success']).to be true
      end

      it 'updates credential on successful test' do
        expect_any_instance_of(GitProviderCredential).to receive(:record_success!)

        post :test_credential, params: { id: provider.id, credential_id: credential.id }
      end
    end
  end

  describe 'POST #make_default' do
    let(:provider) { create(:git_provider) }
    let!(:credential1) { create(:git_provider_credential, :default, git_provider: provider, account: account) }
    let!(:credential2) { create(:git_provider_credential, git_provider: provider, account: account) }

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'sets credential as default' do
        post :make_default, params: { id: provider.id, credential_id: credential2.id }

        expect(response).to have_http_status(:success)
        expect(credential2.reload.is_default).to be true
      end

      it 'unsets previous default' do
        post :make_default, params: { id: provider.id, credential_id: credential2.id }

        expect(credential1.reload.is_default).to be false
      end
    end
  end

  # =============================================================================
  # OAUTH FLOW
  # =============================================================================

  describe 'POST #oauth_authorize' do
    let(:provider) { create(:git_provider, :github, supports_oauth: true) }

    before do
      allow_any_instance_of(GitOAuthService).to receive(:authorization_url)
        .and_return('https://github.com/login/oauth/authorize?client_id=test')
      allow_any_instance_of(GitOAuthService).to receive(:generate_state)
        .and_return('test_state_token')
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'returns OAuth authorization URL' do
        post :oauth_authorize, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['authorization_url']).to be_present
      end
    end

    context 'when provider does not support OAuth' do
      let(:no_oauth_provider) { create(:git_provider, supports_oauth: false) }
      before { sign_in provider_manage_user }

      it 'returns error' do
        post :oauth_authorize, params: { id: no_oauth_provider.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
