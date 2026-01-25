# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Integrations::Credentials', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['integrations.credentials.read', 'integrations.credentials.create', 'integrations.credentials.update', 'integrations.credentials.delete']) }
  let(:limited_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['integrations.credentials.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/integrations/credentials' do
    let!(:credential1) { create(:devops_integration_credential, account: account, name: "Credential 1") }
    let!(:credential2) { create(:devops_integration_credential, :github_app, account: account, name: "Credential 2") }
    let!(:other_credential) { create(:devops_integration_credential, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of credentials for current account' do
        get '/api/v1/integrations/credentials', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['credentials']).to be_an(Array)
        expect(data['credentials'].length).to eq(2)
        expect(data['credentials'].map { |c| c['id'] }).to include(credential1.id, credential2.id)
        expect(data['credentials'].none? { |c| c['id'] == other_credential.id }).to be true
        expect(data['pagination']).to have_key('current_page')
      end

      it 'returns credentials ordered by created_at desc' do
        get '/api/v1/integrations/credentials', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['credentials'].first['id']).to eq(credential2.id)
        expect(data['credentials'].last['id']).to eq(credential1.id)
      end

      it 'supports pagination' do
        create_list(:devops_integration_credential, 5, account: account)

        get '/api/v1/integrations/credentials', params: { page: 1, per_page: 3 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['credentials'].length).to eq(3)
        expect(data['pagination']['per_page']).to eq(3)
      end
    end

    context 'without integrations.credentials.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/credentials', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/integrations/credentials', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/integrations/credentials/:id' do
    let(:credential) { create(:devops_integration_credential, account: account) }
    let(:other_credential) { create(:devops_integration_credential, account: other_account) }

    context 'with proper permissions' do
      it 'returns credential details' do
        get "/api/v1/integrations/credentials/#{credential.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['credential']).to include(
          'id' => credential.id,
          'name' => credential.name,
          'credential_type' => credential.credential_type
        )
        expect(data['credential']).to have_key('metadata')
        expect(data['credential']).to have_key('validation_status')
      end

      it 'returns not found for non-existent credential' do
        get "/api/v1/integrations/credentials/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Credential not found', 404)
      end
    end

    context 'accessing credential from different account' do
      it 'returns not found error' do
        get "/api/v1/integrations/credentials/#{other_credential.id}", headers: headers, as: :json

        expect_error_response('Credential not found', 404)
      end
    end
  end

  describe 'POST /api/v1/integrations/credentials' do
    let(:valid_params) do
      {
        credential: {
          name: 'Test API Key',
          credential_type: 'api_key',
          credentials: {
            api_key: 'test_key_12345'
          },
          scopes: ['read', 'write'],
          metadata: { environment: 'production' }
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new credential' do
        expect {
          post '/api/v1/integrations/credentials', params: valid_params, headers: headers, as: :json
        }.to change { account.reload.devops_integration_credentials.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['credential']).to include(
          'name' => 'Test API Key',
          'credential_type' => 'api_key'
        )
      end

      it 'creates credential with github_app type' do
        github_params = {
          credential: {
            name: 'GitHub App',
            credential_type: 'github_app',
            credentials: {
              app_id: '123456',
              private_key: '-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----',
              installation_id: '789012'
            }
          }
        }

        post '/api/v1/integrations/credentials', params: github_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['credential']['credential_type']).to eq('github_app')
      end

      it 'returns validation error for invalid credential type' do
        invalid_params = valid_params.deep_merge(credential: { credential_type: 'invalid_type' })

        post '/api/v1/integrations/credentials', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns validation error for missing required credential fields' do
        invalid_params = valid_params.deep_merge(credential: { credentials: {} })

        post '/api/v1/integrations/credentials', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without integrations.credentials.create permission' do
      it 'returns forbidden error' do
        post '/api/v1/integrations/credentials', params: valid_params, headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/integrations/credentials/:id' do
    let(:credential) { create(:devops_integration_credential, account: account) }
    let(:update_params) do
      {
        credential: {
          name: 'Updated Credential Name',
          metadata: { updated: true }
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the credential' do
        patch "/api/v1/integrations/credentials/#{credential.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['credential']['name']).to eq('Updated Credential Name')
      end

      it 'returns validation error for invalid update' do
        invalid_params = { credential: { credential_type: 'invalid_type' } }

        patch "/api/v1/integrations/credentials/#{credential.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without integrations.credentials.update permission' do
      it 'returns forbidden error' do
        patch "/api/v1/integrations/credentials/#{credential.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'DELETE /api/v1/integrations/credentials/:id' do
    let!(:credential) { create(:devops_integration_credential, account: account) }

    context 'with proper permissions' do
      it 'deletes the credential' do
        expect {
          delete "/api/v1/integrations/credentials/#{credential.id}", headers: headers, as: :json
        }.to change { account.reload.devops_integration_credentials.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Credential deleted')
      end
    end

    context 'without integrations.credentials.delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/integrations/credentials/#{credential.id}", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/credentials/:id/rotate' do
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with proper permissions' do
      it 'rotates the credential encryption key' do
        post "/api/v1/integrations/credentials/#{credential.id}/rotate", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['credential']).to have_key('id')
        expect(json_response['message']).to eq('Credential rotated successfully')
      end
    end

    context 'without integrations.credentials.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/credentials/#{credential.id}/rotate", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/credentials/:id/verify' do
    let(:credential) { create(:devops_integration_credential, account: account) }

    context 'with proper permissions' do
      it 'verifies the credential encryption' do
        post "/api/v1/integrations/credentials/#{credential.id}/verify", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('valid')
        expect([true, false]).to include(data['valid'])
      end
    end

    context 'without integrations.credentials.read permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/credentials/#{credential.id}/verify", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end
end
