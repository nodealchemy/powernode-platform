# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Providers', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['ai.providers.read']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['ai.providers.read', 'ai.providers.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['ai.providers.read', 'ai.providers.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['ai.providers.read', 'ai.providers.delete']) }
  let(:user_with_credential_permissions) do
    create(:user, account: account, permissions: [
      'ai.providers.read', 'ai.credentials.read', 'ai.credentials.create',
      'ai.credentials.update', 'ai.credentials.delete'
    ])
  end
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/providers' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_provider, 3, account: account)
    end

    context 'with ai.providers.read permission' do
      it 'returns list of providers' do
        get '/api/v1/ai/providers', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes provider details' do
        get '/api/v1/ai/providers', headers: headers, as: :json

        data = json_response_data
        first_provider = data['items'].first

        expect(first_provider).to include('id', 'name', 'provider_type', 'is_active')
      end

      it 'includes capabilities' do
        get '/api/v1/ai/providers', headers: headers, as: :json

        data = json_response_data
        first_provider = data['items'].first

        expect(first_provider).to have_key('capabilities')
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/providers', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by provider_type' do
        create(:ai_provider, :openai, account: account)

        get '/api/v1/ai/providers?provider_type=openai',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        provider_types = data['items'].map { |p| p['provider_type'] }
        expect(provider_types.uniq).to eq(['openai'])
      end

      it 'filters by is_active' do
        # Create active providers
        create(:ai_provider, account: account, is_active: true)

        get '/api/v1/ai/providers?is_active=true',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        active_statuses = data['items'].map { |p| p['is_active'] }
        expect(active_statuses.uniq).to eq([true])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/providers', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/providers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/providers/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:ai_provider, :openai, account: account) }

    context 'with ai.providers.read permission' do
      it 'returns provider details' do
        get "/api/v1/ai/providers/#{provider.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['provider']).to include(
          'id' => provider.id,
          'name' => provider.name,
          'provider_type' => provider.provider_type
        )
      end

      it 'includes supported models' do
        get "/api/v1/ai/providers/#{provider.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['provider']).to have_key('supported_models')
      end

      it 'includes capabilities' do
        get "/api/v1/ai/providers/#{provider.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['provider']).to have_key('capabilities')
      end

      it 'includes api base url' do
        get "/api/v1/ai/providers/#{provider.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['provider']).to have_key('api_base_url')
      end
    end

    context 'when provider does not exist' do
      it 'returns not found error' do
        get '/api/v1/ai/providers/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing other account provider' do
      let(:other_account) { create(:account) }
      let(:other_provider) { create(:ai_provider, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/providers/#{other_provider.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/providers' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with ai.providers.create permission' do
      let(:valid_params) do
        {
          provider: {
            name: 'New Test Provider',
            provider_type: 'custom',
            api_base_url: 'https://api.test.com/v1',
            api_endpoint: 'https://api.test.com/v1/chat/completions',
            capabilities: ['text_generation'],
            supported_models: [{ id: 'test-model', name: 'Test Model' }],
            configuration_schema: { type: 'object', properties: {} }
          }
        }
      end

      it 'creates a new provider' do
        expect {
          post '/api/v1/ai/providers', params: valid_params, headers: headers, as: :json
        }.to change(Ai::Provider, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['provider']['name']).to eq('New Test Provider')
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/ai/providers',
             params: { provider: { name: '' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/providers',
             params: { provider: { name: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/ai/providers/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:provider) { create(:ai_provider, account: account) }

    context 'with ai.providers.update permission' do
      it 'updates provider successfully' do
        put "/api/v1/ai/providers/#{provider.id}",
            params: { provider: { description: 'Updated description' } },
            headers: headers,
            as: :json

        expect_success_response

        provider.reload
        expect(provider.description).to eq('Updated description')
      end

      it 'updates provider name' do
        put "/api/v1/ai/providers/#{provider.id}",
            params: { provider: { name: 'Updated Name' } },
            headers: headers,
            as: :json

        expect_success_response

        provider.reload
        expect(provider.name).to eq('Updated Name')
      end
    end
  end

  describe 'DELETE /api/v1/ai/providers/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:provider) { create(:ai_provider, account: account) }

    context 'with ai.providers.delete permission' do
      it 'deletes provider successfully' do
        provider_id = provider.id

        delete "/api/v1/ai/providers/#{provider_id}", headers: headers, as: :json

        expect_success_response
        expect(Ai::Provider.find_by(id: provider_id)).to be_nil
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        delete "/api/v1/ai/providers/#{provider.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/providers/:id/models' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:ai_provider, :openai, account: account) }

    context 'with ai.providers.read permission' do
      it 'returns supported models' do
        get "/api/v1/ai/providers/#{provider.id}/models", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['models']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/providers/:id/test_connection' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:ai_provider, account: account) }
    let!(:credential) { create(:ai_provider_credential, account: account, provider: provider, is_default: true) }

    context 'with ai.providers.read permission' do
      it 'tests provider connection' do
        post "/api/v1/ai/providers/#{provider.id}/test_connection", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('success')
      end
    end
  end

  describe 'GET /api/v1/ai/providers/:id/usage_summary' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:ai_provider, account: account) }

    context 'with ai.providers.read permission' do
      it 'returns usage summary' do
        get "/api/v1/ai/providers/#{provider.id}/usage_summary", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('usage_summary')
      end
    end
  end

  describe 'GET /api/v1/ai/providers/available' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_provider, 2, account: account, is_active: true)
      create(:ai_provider, :inactive, account: account)
    end

    context 'with ai.providers.read permission' do
      it 'returns only active providers' do
        get '/api/v1/ai/providers/available', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        active_statuses = data['providers'].map { |p| p['is_active'] }
        expect(active_statuses.uniq).to eq([true])
      end
    end
  end

  describe 'GET /api/v1/ai/providers/statistics' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_provider, 3, account: account)
    end

    context 'with ai.providers.read permission' do
      it 'returns provider statistics' do
        get '/api/v1/ai/providers/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['statistics']).to have_key('total_providers')
      end
    end
  end

  # Nested credential endpoints
  describe 'GET /api/v1/ai/providers/:provider_id/credentials' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }

    before do
      create_list(:ai_provider_credential, 2, account: account, provider: provider)
    end

    context 'with ai.credentials.read permission' do
      it 'returns list of credentials for provider' do
        get "/api/v1/ai/providers/#{provider.id}/credentials", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['credentials']).to be_an(Array)
        expect(data['credentials'].length).to eq(2)
      end

      it 'includes credential details' do
        get "/api/v1/ai/providers/#{provider.id}/credentials", headers: headers, as: :json

        data = json_response_data
        first_credential = data['credentials'].first

        expect(first_credential).to include('id', 'name', 'is_active', 'is_default')
      end
    end
  end

  describe 'POST /api/v1/ai/providers/:provider_id/credentials' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }

    context 'with ai.credentials.create permission' do
      let(:valid_params) do
        {
          credential: {
            name: 'New Test Credential',
            credentials: { api_key: 'test-key-123', model: 'test-model' }
          }
        }
      end

      it 'creates a new credential' do
        expect {
          post "/api/v1/ai/providers/#{provider.id}/credentials",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change(Ai::ProviderCredential, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['credential']['name']).to eq('New Test Credential')
      end
    end
  end

  describe 'GET /api/v1/ai/providers/:provider_id/credentials/:id' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, account: account, provider: provider) }

    context 'with ai.credentials.read permission' do
      it 'returns credential details' do
        get "/api/v1/ai/providers/#{provider.id}/credentials/#{credential.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['credential']).to include(
          'id' => credential.id,
          'name' => credential.name
        )
      end
    end
  end

  describe 'PUT /api/v1/ai/providers/:provider_id/credentials/:id' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, account: account, provider: provider) }

    context 'with ai.credentials.update permission' do
      it 'updates credential successfully' do
        put "/api/v1/ai/providers/#{provider.id}/credentials/#{credential.id}",
            params: { credential: { name: 'Updated Credential Name' } },
            headers: headers,
            as: :json

        expect_success_response

        credential.reload
        expect(credential.name).to eq('Updated Credential Name')
      end
    end
  end

  describe 'DELETE /api/v1/ai/providers/:provider_id/credentials/:id' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }
    # Create a default credential first
    let!(:default_credential) { create(:ai_provider_credential, account: account, provider: provider, is_default: true) }
    # Create a non-default credential to delete
    let!(:credential) { create(:ai_provider_credential, account: account, provider: provider, is_default: false) }

    context 'with ai.credentials.delete permission' do
      it 'deletes non-default credential successfully' do
        credential_id = credential.id

        delete "/api/v1/ai/providers/#{provider.id}/credentials/#{credential_id}",
               headers: headers,
               as: :json

        expect_success_response
        expect(Ai::ProviderCredential.find_by(id: credential_id)).to be_nil
      end
    end
  end

  describe 'POST /api/v1/ai/providers/:provider_id/credentials/:id/test' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, account: account, provider: provider) }

    context 'with ai.credentials.read permission' do
      it 'tests credential connection' do
        post "/api/v1/ai/providers/#{provider.id}/credentials/#{credential.id}/test",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('success')
      end
    end
  end

  describe 'POST /api/v1/ai/providers/:provider_id/credentials/:id/make_default' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:ai_provider, account: account) }
    let(:credential) { create(:ai_provider_credential, account: account, provider: provider, is_default: false) }

    context 'with ai.credentials.update permission' do
      it 'makes credential default' do
        post "/api/v1/ai/providers/#{provider.id}/credentials/#{credential.id}/make_default",
             headers: headers,
             as: :json

        expect_success_response

        credential.reload
        expect(credential.is_default).to be true
      end
    end
  end
end
