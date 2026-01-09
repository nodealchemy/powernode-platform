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

  # =============================================================================
  # PROVIDER CUSTOM ACTIONS
  # =============================================================================

  describe 'POST #test_connection' do
    let(:provider) { create(:ai_provider, :openai, account: account) }
    let!(:credential) { create(:ai_provider_credential, :default, provider: provider, account: account) }

    before do
      # Controller now uses test_with_details_simple for flat response format
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details_simple).and_return({
        success: true,
        response_time_ms: 150.5,
        message: 'Connection successful'
      })
    end

    context 'with valid permissions' do
      before { sign_in provider_read_user }

      it 'tests the connection with default credential' do
        post :test_connection, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['success']).to be true
        expect(json['data']['response_time_ms']).to eq(150.5)
      end

      it 'tests with specific credential' do
        other_credential = create(:ai_provider_credential, provider: provider, account: account)

        post :test_connection, params: { id: provider.id, credential_id: other_credential.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'updates credential status on success' do
        expect_any_instance_of(Ai::ProviderCredential).to receive(:record_success!)

        post :test_connection, params: { id: provider.id }
      end

      it 'updates credential status on failure' do
        # Controller now uses test_with_details_simple for flat response format
        allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details_simple).and_return({
          success: false,
          error: 'Connection failed'
        })

        expect_any_instance_of(Ai::ProviderCredential).to receive(:record_failure!).with('Connection failed')

        post :test_connection, params: { id: provider.id }
      end

      it 'returns error when no active credentials found' do
        credential.update!(is_active: false, is_default: false)

        post :test_connection, params: { id: provider.id }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to include('No active credentials')
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        post :test_connection, params: { id: provider.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #sync_models' do
    let(:provider) { create(:ai_provider, account: account) }

    before do
      allow(Ai::ProviderManagementService).to receive(:sync_provider_models).and_return(true)
    end

    context 'with valid permissions' do
      before { sign_in provider_manage_user }

      it 'syncs provider models' do
        expect(Ai::ProviderManagementService).to receive(:sync_provider_models).with(provider)

        post :sync_models, params: { id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('synced successfully')
      end

      it 'returns updated provider with models' do
        provider.update!(supported_models: [ { 'name' => 'model-1' }, { 'name' => 'model-2' } ])

        post :sync_models, params: { id: provider.id }

        json = JSON.parse(response.body)
        expect(json['data']['provider']['supported_models'].length).to eq(2)
      end
    end

    context 'when sync fails' do
      before do
        sign_in provider_manage_user
        allow(Ai::ProviderManagementService).to receive(:sync_provider_models).and_return(false)
      end

      it 'returns error response' do
        post :sync_models, params: { id: provider.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Failed to sync')
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
  # CREDENTIALS - NESTED RESOURCE
  # =============================================================================

  describe 'GET #credentials_index' do
    let(:provider) { create(:ai_provider, account: account) }
    let!(:credential1) { create(:ai_provider_credential, provider: provider, account: account, name: 'Credential 1') }
    let!(:credential2) { create(:ai_provider_credential, provider: provider, account: account, name: 'Credential 2', is_active: false) }
    let!(:other_provider_credential) { create(:ai_provider_credential, account: account) }

    context 'with valid permissions' do
      before { sign_in credential_read_user }

      it 'returns credentials for provider' do
        get :index, params: { provider_id: provider.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['credentials'].length).to eq(2)
        expect(json['data']['credentials'].map { |c| c['id'] }).to contain_exactly(credential1.id, credential2.id)
      end

      it 'includes pagination metadata' do
        get :index, params: { provider_id: provider.id }

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
        expect(json['data']['total_count']).to eq(2)
      end

      it 'filters by active status' do
        get :index, params: { provider_id: provider.id, active: true }

        json = JSON.parse(response.body)
        expect(json['data']['credentials'].length).to eq(1)
        expect(json['data']['credentials'].first['id']).to eq(credential1.id)
      end

      it 'filters by default_only' do
        credential1.update!(is_default: true)

        get :index, params: { provider_id: provider.id, default_only: 'true' }

        json = JSON.parse(response.body)
        expect(json['data']['credentials'].length).to eq(1)
        expect(json['data']['credentials'].first['is_default']).to be true
      end

      it 'searches by name' do
        get :index, params: { provider_id: provider.id, search: 'Credential 1' }

        json = JSON.parse(response.body)
        expect(json['data']['credentials'].length).to eq(1)
        expect(json['data']['credentials'].first['name']).to eq('Credential 1')
      end

      it 'sorts by name' do
        get :index, params: { provider_id: provider.id, sort: 'name' }

        json = JSON.parse(response.body)
        names = json['data']['credentials'].map { |c| c['name'] }
        expect(names).to eq([ 'Credential 1', 'Credential 2' ])
      end
    end

    context 'as worker' do
      before do
        # Set WORKER_TOKEN environment variable for worker authentication
        ENV['WORKER_TOKEN'] = worker.auth_token
        @request.headers['X-Worker-Token'] = worker.auth_token
      end

      after do
        # Clean up environment variable
        ENV.delete('WORKER_TOKEN')
      end

      it 'allows worker to access all credentials' do
        get :index

        expect(response).to have_http_status(:success)
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index, params: { provider_id: provider.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #credential_show' do
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, provider: provider, account: account) }

    context 'with valid permissions' do
      before { sign_in credential_read_user }

      it 'returns credential details' do
        get :show, params: { provider_id: provider.id, id: credential.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['credential']['id']).to eq(credential.id)
      end

      it 'includes provider information' do
        get :show, params: { provider_id: provider.id, id: credential.id }

        json = JSON.parse(response.body)
        expect(json['data']['credential']['provider']).to include(
          'id' => provider.id,
          'name' => provider.name
        )
      end

      it 'includes credential keys but not decrypted values' do
        get :show, params: { provider_id: provider.id, id: credential.id }

        json = JSON.parse(response.body)
        expect(json['data']['credential']['credential_keys']).to be_an(Array)
        expect(json['data']['credential']['credentials']).to be_nil
      end
    end

    context 'with decrypt permission' do
      before { sign_in admin_user }

      it 'includes decrypted credentials' do
        get :show, params: { provider_id: provider.id, id: credential.id }

        json = JSON.parse(response.body)
        expect(response).to have_http_status(:success)
        expect(json['data']['credential']).to be_present
        expect(json['data']['credential']['credentials']).to be_a(Hash)
      end
    end
  end

  describe 'POST #credential_create' do
    let(:provider) { create(:ai_provider, :openai, account: account) }
    let(:valid_params) do
      {
        provider_id: provider.id,
        credential: {
          name: 'New Credential',
          credentials: {
            api_key: 'sk-test-key',
            model: 'gpt-3.5-turbo'
          },
          is_active: true
        }
      }
    end

    before do
      allow(Ai::ProviderManagementService).to receive(:create_provider_credential).and_return(
        create(:ai_provider_credential, provider: provider, account: account, name: 'New Credential')
      )
    end

    context 'with valid permissions' do
      before { sign_in credential_manage_user }

      it 'creates a new credential' do
        expect(Ai::ProviderManagementService).to receive(:create_provider_credential)

        post :create, params: valid_params

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['credential']['name']).to eq('New Credential')
      end
    end

    context 'with validation errors' do
      before do
        sign_in credential_manage_user
        allow(Ai::ProviderManagementService).to receive(:create_provider_credential).and_raise(
          Ai::ProviderManagementService::ValidationError, 'Invalid credentials format'
        )
      end

      it 'returns validation error' do
        post :create, params: valid_params

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Validation failed')
      end
    end

    context 'without permissions' do
      before { sign_in credential_read_user }

      it 'returns forbidden error' do
        post :create, params: valid_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH #credential_update' do
    let(:provider) { create(:ai_provider, account: account) }
    let!(:credential) { create(:ai_provider_credential, provider: provider, account: account, name: 'Original Name') }
    let(:update_params) do
      {
        provider_id: provider.id,
        id: credential.id,
        credential: {
          name: 'Updated Name'
        }
      }
    end

    context 'with valid permissions' do
      before { sign_in credential_manage_user }

      it 'updates the credential' do
        patch :update, params: update_params

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['credential']['name']).to eq('Updated Name')
        expect(credential.reload.name).to eq('Updated Name')
      end

      it 'allows updating credentials' do
        update_with_creds = update_params.deep_dup
        update_with_creds[:credential][:credentials] = { api_key: 'new-api-key-1234567890' }

        # Stub the validation method to not raise errors
        allow(Ai::ProviderManagementService).to receive(:validate_provider_credentials)

        patch :update, params: update_with_creds

        expect(response).to have_http_status(:success)
      end

      it 'validates new credentials before updating' do
        update_with_creds = update_params.deep_dup
        update_with_creds[:credential][:credentials] = { api_key: 'new-api-key-1234567890' }

        expect(Ai::ProviderManagementService).to receive(:validate_provider_credentials)

        patch :update, params: update_with_creds
      end
    end

    context 'without permissions' do
      before { sign_in credential_read_user }

      it 'returns forbidden error' do
        patch :update, params: update_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #credential_destroy' do
    let(:provider) { create(:ai_provider, account: account) }
    let!(:credential) { create(:ai_provider_credential, provider: provider, account: account) }

    context 'with valid permissions' do
      before do
        sign_in credential_manage_user
        # Create second credential so first can be deleted (model prevents deleting last credential)
        create(:ai_provider_credential, provider: provider, account: account, is_default: false)
      end

      it 'deletes the credential' do
        expect {
          delete :destroy, params: { provider_id: provider.id, id: credential.id }
        }.to change(Ai::ProviderCredential, :count).by(-1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('deleted successfully')
      end
    end

    context 'when credential cannot be deleted' do
      before do
        sign_in credential_manage_user
        allow_any_instance_of(Ai::ProviderCredential).to receive(:destroy).and_return(false)
        allow_any_instance_of(Ai::ProviderCredential).to receive(:errors).and_return(
          double(any?: true, full_messages: [ 'Cannot delete the only credential' ])
        )
      end

      it 'returns validation errors' do
        delete :destroy, params: { provider_id: provider.id, id: credential.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without permissions' do
      before { sign_in credential_read_user }

      it 'returns forbidden error' do
        delete :destroy, params: { provider_id: provider.id, id: credential.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # CREDENTIAL CUSTOM ACTIONS
  # =============================================================================

  describe 'POST #credential_test' do
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, provider: provider, account: account) }

    before do
      # Controller now uses test_with_details_simple for flat response format
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details_simple).and_return({
        success: true,
        response_time_ms: 120.3,
        message: 'Test successful'
      })
    end

    context 'with valid permissions' do
      before { sign_in credential_read_user }

      it 'tests the credential connection' do
        post :credential_test, params: { provider_id: provider.id, id: credential.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['success']).to be true
      end

      it 'updates credential status on success' do
        expect_any_instance_of(Ai::ProviderCredential).to receive(:record_success!)

        post :credential_test, params: { provider_id: provider.id, id: credential.id }
      end

      it 'updates credential status on failure' do
        # Controller now uses test_with_details_simple for flat response format
        allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details_simple).and_return({
          success: false,
          error: 'Authentication failed'
        })

        expect_any_instance_of(Ai::ProviderCredential).to receive(:record_failure!).with('Authentication failed')

        post :credential_test, params: { provider_id: provider.id, id: credential.id }
      end
    end
  end

  describe 'POST #credential_make_default' do
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential1) { create(:ai_provider_credential, :default, provider: provider, account: account) }
    let(:credential2) { create(:ai_provider_credential, provider: provider, account: account) }

    context 'with valid permissions' do
      before { sign_in credential_manage_user }

      it 'sets credential as default' do
        post :credential_make_default, params: { provider_id: provider.id, id: credential2.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('set as default')
        expect(credential2.reload.is_default).to be true
      end

      it 'unsets previous default credential' do
        # Force lazy-loaded credential1 to be created before making credential2 default
        credential1
        credential2

        post :credential_make_default, params: { provider_id: provider.id, id: credential2.id }

        expect(credential1.reload.is_default).to be false
      end
    end

    context 'without permissions' do
      before { sign_in credential_read_user }

      it 'returns forbidden error' do
        post :credential_make_default, params: { provider_id: provider.id, id: credential2.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #credential_rotate' do
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, provider: provider, account: account) }

    context 'with valid permissions' do
      before { sign_in credential_manage_user }

      it 'initiates credential rotation' do
        post :credential_rotate, params: { provider_id: provider.id, id: credential.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('rotation initiated')
      end
    end

    context 'without permissions' do
      before { sign_in credential_read_user }

      it 'returns forbidden error' do
        post :credential_rotate, params: { provider_id: provider.id, id: credential.id }

        expect(response).to have_http_status(:forbidden)
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
