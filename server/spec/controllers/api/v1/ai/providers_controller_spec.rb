# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::ProvidersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:worker) { create(:worker) }

  # Provider permissions
  let(:provider_read_user) { create(:user, account: account, permissions: [ 'ai.providers.read' ]) }
  let(:provider_manage_user) { create(:user, account: account, permissions: [ 'ai.providers.read', 'ai.providers.create', 'ai.providers.update', 'ai.providers.delete' ]) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'ai.providers.read', 'ai.providers.create', 'ai.providers.update', 'ai.providers.delete', 'ai.credentials.create', 'ai.credentials.update', 'ai.credentials.delete', 'ai.credentials.read', 'ai.credentials.decrypt', 'admin.ai.providers.read' ]) }
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  # Credential permissions
  let(:credential_read_user) { create(:user, account: account, permissions: [ 'ai.providers.read', 'ai.credentials.read' ]) }
  let(:credential_manage_user) { create(:user, account: account, permissions: [ 'ai.providers.read', 'ai.credentials.read', 'ai.credentials.create', 'ai.credentials.update', 'ai.credentials.delete' ]) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # PROVIDER CRUD OPERATIONS
  # =============================================================================

  describe 'GET #index' do
    let!(:provider1) { create(:ai_provider, account: account, name: 'OpenAI Provider', provider_type: 'openai', is_active: true, priority_order: 1) }
    let!(:provider2) { create(:ai_provider, account: account, name: 'Anthropic Provider', provider_type: 'anthropic', is_active: true, priority_order: 2) }
    let!(:inactive_provider) { create(:ai_provider, account: account, name: 'Inactive Provider', is_active: false) }
    let!(:other_account_provider) { create(:ai_provider, name: 'Other Account Provider') }

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns list of active providers for the account' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['items'].length).to eq(2)
        expect(json['data']['items'].map { |p| p['id'] }).to contain_exactly(provider1.id, provider2.id)
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to include(
          'current_page' => 1,
          'per_page' => 20,
          'total_pages' => 1,
          'total_count' => 2
        )
      end

      it 'filters by provider_type' do
        get :index, params: { provider_type: 'openai' }

        json = JSON.parse(response.body)
        expect(json['data']['items'].length).to eq(1)
        expect(json['data']['items'].first['name']).to eq('OpenAI Provider')
      end

      it 'filters by capability' do
        provider1.update!(capabilities: [ 'text_generation', 'chat' ])
        provider2.update!(capabilities: [ 'text_generation' ])

        get :index, params: { capability: 'chat' }

        json = JSON.parse(response.body)
        expect(json['data']['items'].length).to eq(1)
        expect(json['data']['items'].first['id']).to eq(provider1.id)
      end

      it 'searches by name' do
        get :index, params: { search: 'OpenAI' }

        json = JSON.parse(response.body)
        expect(json['data']['items'].length).to eq(1)
        expect(json['data']['items'].first['name']).to eq('OpenAI Provider')
      end

      it 'sorts by name' do
        get :index, params: { sort: 'name' }

        json = JSON.parse(response.body)
        names = json['data']['items'].map { |p| p['name'] }
        expect(names).to eq([ 'Anthropic Provider', 'OpenAI Provider' ])
      end

      it 'sorts by priority order' do
        get :index, params: { sort: 'priority' }

        json = JSON.parse(response.body)
        priorities = json['data']['items'].map { |p| p['priority_order'] }
        expect(priorities).to eq([ 1, 2 ])
      end

      it 'supports pagination' do
        get :index, params: { page: 1, per_page: 1 }

        json = JSON.parse(response.body)
        expect(json['data']['items'].length).to eq(1)
        expect(json['data']['pagination']['total_pages']).to eq(2)
      end
    end

    context 'with admin permissions' do
      before { sign_in admin_user }

      it 'includes inactive providers for admin users' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['items'].length).to eq(3)
        expect(json['data']['items'].map { |p| p['id'] }).to include(inactive_provider.id)
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns unauthorized error' do
        get :index

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error'].downcase).to include('permission')
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
    let(:provider) { create(:ai_provider, :openai, account: account) }
    let!(:credential1) { create(:ai_provider_credential, provider: provider, account: account, name: 'Credential 1') }
    let!(:credential2) { create(:ai_provider_credential, provider: provider, account: account, name: 'Credential 2') }

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns provider details' do
        get :show, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['provider']['id']).to eq(provider.id)
        expect(json['data']['provider']['name']).to eq(provider.name)
      end

      it 'includes detailed provider information' do
        get :show, params: { id: provider.id }

        json = JSON.parse(response.body)
        provider_data = json['data']['provider']
        expect(provider_data).to include(
          'id' => provider.id,
          'name' => provider.name,
          'slug' => provider.slug,
          'provider_type' => provider.provider_type,
          'description' => provider.description,
          'supported_models' => provider.supported_models,
          'capabilities' => provider.capabilities
        )
      end

      it 'includes associated credentials' do
        get :show, params: { id: provider.id }

        json = JSON.parse(response.body)
        credentials = json['data']['provider']['credentials']
        expect(credentials.length).to eq(2)
        expect(credentials.map { |c| c['id'] }).to contain_exactly(credential1.id, credential2.id)
      end
    end

    context 'when provider does not exist' do
      before { sign_in provider_read_user }

      it 'returns not found error' do
        get :show, params: { id: 'nonexistent-id' }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('not found')
      end
    end

    context 'when accessing another account\'s provider' do
      let(:other_provider) { create(:ai_provider) }
      before { sign_in provider_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_provider.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        provider: {
          name: 'New Provider',
          provider_type: 'custom',
          api_endpoint: 'https://api.example.com/v1',
          capabilities: [ 'text_generation', 'chat' ],
          supported_models: [
            { name: 'model-1', id: 'model-1', context_length: 4096 }
          ],
          configuration_schema: { type: 'object', properties: {} },
          is_active: true,
          priority_order: 1
        }
      }
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'creates a new provider' do
        expect {
          post :create, params: valid_params
        }.to change(Ai::Provider, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['provider']['name']).to eq('New Provider')
      end

      it 'assigns provider to current account' do
        post :create, params: valid_params

        provider = Ai::Provider.last
        expect(provider.account_id).to eq(account.id)
      end

      it 'returns created provider details' do
        post :create, params: valid_params

        json = JSON.parse(response.body)
        provider_data = json['data']['provider']
        expect(provider_data).to include(
          'name' => 'New Provider',
          'provider_type' => 'custom',
          'capabilities' => [ 'text_generation', 'chat' ]
        )
      end
    end

    context 'with invalid parameters' do
      before { sign_in provider_manage_user }

      it 'returns validation errors for missing name' do
        invalid_params = valid_params.deep_dup
        invalid_params[:provider].delete(:name)

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['details']['errors']).to be_present
      end

      it 'returns validation errors for invalid provider_type' do
        invalid_params = valid_params.deep_dup
        invalid_params[:provider][:provider_type] = 'invalid_type'

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
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
    let(:provider) { create(:ai_provider, account: account, name: 'Original Name') }
    let(:update_params) do
      {
        id: provider.id,
        provider: {
          name: 'Updated Name',
          description: 'Updated description'
        }
      }
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'updates the provider' do
        patch :update, params: update_params

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['provider']['name']).to eq('Updated Name')
        expect(provider.reload.name).to eq('Updated Name')
      end

      it 'returns updated provider details' do
        patch :update, params: update_params

        json = JSON.parse(response.body)
        expect(json['data']['provider']['description']).to eq('Updated description')
      end
    end

    context 'with invalid parameters' do
      before { sign_in provider_manage_user }

      it 'returns validation errors' do
        invalid_params = {
          id: provider.id,
          provider: { name: '' }
        }

        patch :update, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
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
    let!(:provider) { create(:ai_provider, account: account, name: 'Provider to Delete') }

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'deletes the provider' do
        expect {
          delete :destroy, params: { id: provider.id }
        }.to change(Ai::Provider, :count).by(-1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('deleted successfully')
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


  describe 'GET #models' do
    let(:provider) { create(:ai_provider, :openai, account: account) }

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns provider models' do
        get :models, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['models']).to be_an(Array)
        expect(json['data']['count']).to eq(provider.supported_models.length)
      end

      it 'includes provider information' do
        get :models, params: { id: provider.id }

        json = JSON.parse(response.body)
        expect(json['data']['provider']).to include(
          'id' => provider.id,
          'name' => provider.name,
          'provider_type' => provider.provider_type
        )
      end
    end
  end

  describe 'GET #usage_summary' do
    let(:provider) { create(:ai_provider, account: account) }

    before do
      allow(Ai::ProviderManagementService).to receive(:provider_usage_summary).and_return({
        total_executions: 150,
        total_tokens: 50000,
        total_cost: 12.50,
        average_response_time: 250.5
      })
    end

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns usage summary' do
        get :usage_summary, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['usage_summary']).to include(
          'total_executions' => 150,
          'total_tokens' => 50000,
          'total_cost' => 12.50
        )
      end

      it 'includes period information' do
        get :usage_summary, params: { id: provider.id, period: 7 }

        json = JSON.parse(response.body)
        expect(json['data']['period']).to include(
          'days' => 7
        )
      end

      it 'defaults to 30 day period' do
        get :usage_summary, params: { id: provider.id }

        json = JSON.parse(response.body)
        expect(json['data']['period']['days']).to eq(30)
      end
    end
  end

  describe 'GET #available' do
    before do
      allow(Ai::ProviderManagementService).to receive(:get_available_providers_for_account).and_return(
        Ai::Provider.where(account: account)
      )
    end

    context 'with valid permissions' do
      let!(:provider1) { create(:ai_provider, account: account, is_active: true) }
      let!(:provider2) { create(:ai_provider, account: account, is_active: true) }

      before { sign_in provider_read_user }

      it 'returns available providers' do
        get :available

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['providers'].length).to eq(2)
        expect(json['data']['count']).to eq(2)
      end
    end
  end

  describe 'GET #statistics' do
    let!(:provider1) { create(:ai_provider, account: account, provider_type: 'openai', is_active: true) }
    let!(:provider2) { create(:ai_provider, account: account, provider_type: 'anthropic', is_active: true) }
    let!(:inactive_provider) { create(:ai_provider, account: account, is_active: false) }

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'returns provider statistics' do
        get :statistics

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['statistics']).to include(
          'total_providers' => 3,
          'active_providers' => 2
        )
      end

      it 'includes providers by type breakdown' do
        get :statistics

        json = JSON.parse(response.body)
        expect(json['data']['statistics']['providers_by_type']).to be_a(Hash)
      end
    end
  end


  # =============================================================================
  # CROSS-ACCOUNT ISOLATION
  # =============================================================================

  describe 'cross-account isolation' do
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account, permissions: [ 'ai.providers.read', 'ai.credentials.read' ]) }
    let!(:other_provider) { create(:ai_provider, account: other_account) }

    before { sign_in other_user }

    it 'does not show providers from other accounts in index' do
      create(:ai_provider, account: account)

      get :index

      json = JSON.parse(response.body)
      expect(json['data']['items'].map { |p| p['account_id'] }.uniq).to eq([ other_account.id ])
    end

    it 'does not allow accessing other account providers' do
      provider = create(:ai_provider, account: account)

      get :show, params: { id: provider.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'does not allow accessing other account credentials' do
      provider = create(:ai_provider, account: account)
      credential = create(:ai_provider_credential, provider: provider, account: account)

      get :show, params: { provider_id: provider.id, id: credential.id }

      expect(response).to have_http_status(:not_found)
    end
  end
end
