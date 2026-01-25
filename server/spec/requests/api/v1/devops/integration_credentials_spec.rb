# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::IntegrationCredentials', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['devops.integrations.credentials.read']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['devops.integrations.credentials.read', 'devops.integrations.credentials.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['devops.integrations.credentials.read', 'devops.integrations.credentials.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['devops.integrations.credentials.read', 'devops.integrations.credentials.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/integration_credentials' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:devops_integration_credential, 3, account: account)
    end

    context 'with devops.integrations.credentials.read permission' do
      it 'returns list of credentials' do
        get '/api/v1/devops/integration_credentials', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['credentials']).to be_an(Array)
        expect(response_data['data']['credentials'].length).to eq(3)
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/integration_credentials', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_pages', 'total_count')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/integration_credentials', headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/integration_credentials', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_credentials/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with devops.integrations.credentials.read permission' do
      it 'returns credential details' do
        get "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['credential']).to be_present
      end
    end

    context 'when credential does not exist' do
      it 'returns not found error' do
        get '/api/v1/devops/integration_credentials/nonexistent-id', headers: headers, as: :json

        expect_error_response('Credential', 404)
      end
    end

    context 'when accessing other account credential' do
      let(:other_account) { create(:account) }
      let(:other_credential) { create(:devops_integration_credential, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/devops/integration_credentials/#{other_credential.id}", headers: headers, as: :json

        expect_error_response('Credential', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_credentials' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with devops.integrations.credentials.create permission' do
      let(:valid_params) do
        {
          credential: {
            name: 'Test Credential',
            credential_type: 'oauth',
            scopes: ['read', 'write'],
            credentials: { token: 'test_token' },
            metadata: { provider: 'github' }
          }
        }
      end

      it 'creates a new credential' do
        allow(Devops::RegistryService).to receive(:create_credential).and_return(
          double(credential_summary: { id: 'test-id', name: 'Test Credential' })
        )

        post '/api/v1/devops/integration_credentials', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end

      it 'handles validation errors' do
        allow(Devops::RegistryService).to receive(:create_credential).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid credentials')
        )

        post '/api/v1/devops/integration_credentials', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/devops/integration_credentials',
             params: { credential: { name: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/integration_credentials/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with devops.integrations.credentials.update permission' do
      it 'updates credential successfully' do
        allow(Devops::RegistryService).to receive(:update_credential).and_return(
          double(credential_summary: { id: credential.id, name: 'Updated Credential' })
        )

        patch "/api/v1/devops/integration_credentials/#{credential.id}",
              params: { credential: { name: 'Updated Credential' } },
              headers: headers,
              as: :json

        expect_success_response
      end

      it 'handles validation errors' do
        allow(Devops::RegistryService).to receive(:update_credential).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid update')
        )

        patch "/api/v1/devops/integration_credentials/#{credential.id}",
              params: { credential: { name: '' } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/devops/integration_credentials/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with devops.integrations.credentials.delete permission' do
      it 'deletes credential successfully' do
        allow(Devops::RegistryService).to receive(:delete_credential).and_return(true)

        delete "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json

        expect_success_response
      end

      it 'handles deletion errors' do
        allow(Devops::RegistryService).to receive(:delete_credential).and_raise(
          Devops::RegistryService::ValidationError.new('Cannot delete in-use credential')
        )

        delete "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_credentials/:id/rotate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with devops.integrations.credentials.update permission' do
      it 'rotates credential successfully' do
        allow(Devops::CredentialEncryptionService).to receive(:rotate_key).and_return(true)

        post "/api/v1/devops/integration_credentials/#{credential.id}/rotate", headers: headers, as: :json

        expect_success_response
      end

      it 'handles rotation errors' do
        allow(Devops::CredentialEncryptionService).to receive(:rotate_key).and_raise(
          Devops::CredentialEncryptionService::EncryptionError.new('Rotation failed')
        )

        post "/api/v1/devops/integration_credentials/#{credential.id}/rotate", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_credentials/:id/verify' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with devops.integrations.credentials.read permission' do
      it 'verifies credential successfully' do
        allow(Devops::CredentialEncryptionService).to receive(:valid?).and_return(true)

        post "/api/v1/devops/integration_credentials/#{credential.id}/verify", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['valid']).to be true
      end
    end
  end
end
