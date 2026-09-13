# frozen_string_literal: true

require 'rails_helper'

# IMP-01a04d08-9288. The write paths here used to stub Devops::RegistryService
# wholesale, so they asserted only the status the controller renders around a
# double. That is how RegistryService#create_credential could fail on EVERY
# call — it saved before assigning the credentials, tripping the
# encrypted_credentials presence validation — while "creates a new credential"
# stayed green (it also posted credential_type 'oauth', which is not a valid
# type: the real API would 422 it).
#
# The examples now drive the REAL service and assert the ROW. Stubs remain
# only on Security::CredentialEncryptionService for rotate/verify, the crypto
# boundary those two endpoints exist to exercise.
RSpec.describe 'Api::V1::Devops::IntegrationCredentials', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'devops.integrations.credentials.read' ]) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'devops.integrations.credentials.read', 'devops.integrations.credentials.create' ]) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: [ 'devops.integrations.credentials.read', 'devops.integrations.credentials.update' ]) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: [ 'devops.integrations.credentials.read', 'devops.integrations.credentials.delete' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  def account_credentials = Devops::IntegrationCredential.where(account: account)

  describe 'GET /api/v1/devops/integration_credentials' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:devops_integration_credential, 3, account: account)
      create(:devops_integration_credential, account: other_account)
    end

    context 'with devops.integrations.credentials.read permission' do
      it "returns this account's credentials only" do
        get '/api/v1/devops/integration_credentials', headers: headers, as: :json

        expect_success_response
        expect(json_response['data']['credentials'].length).to eq(3)
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/integration_credentials', headers: headers, as: :json

        expect(json_response['data']['pagination']).to include('current_page', 'total_pages', 'total_count')
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

    it 'returns credential details' do
      get "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json

      expect_success_response
      expect(json_response['data']['credential']['id']).to eq(credential.id)
    end

    it 'returns not found for an unknown id' do
      get '/api/v1/devops/integration_credentials/nonexistent-id', headers: headers, as: :json

      expect_error_response('Credential', 404)
    end

    it "returns not found for another account's credential" do
      other_credential = create(:devops_integration_credential, account: other_account)

      get "/api/v1/devops/integration_credentials/#{other_credential.id}", headers: headers, as: :json

      expect_error_response('Credential', 404)
    end
  end

  describe 'POST /api/v1/devops/integration_credentials' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:secret) { "sk_probe_#{SecureRandom.hex(12)}" }
    let(:valid_params) do
      {
        credential: {
          name: 'Test Credential',
          credential_type: 'api_key',
          scopes: [ 'read', 'write' ],
          credentials: { api_key: secret },
          metadata: { provider: 'github' }
        }
      }
    end

    context 'with devops.integrations.credentials.create permission' do
      it 'creates the credential in this account, encrypted, and never echoes the secret' do
        expect {
          post '/api/v1/devops/integration_credentials', params: valid_params, headers: headers, as: :json
        }.to change { account_credentials.count }.by(1)

        expect(response).to have_http_status(:created)
        row = account_credentials.find_by!(name: 'Test Credential')
        expect(row).to have_attributes(credential_type: 'api_key', scopes: [ 'read', 'write' ])
        expect(row.encrypted_credentials).to be_present
        expect(row.encrypted_credentials).not_to include(secret)
        expect(row.reload.decrypt).to include('api_key' => secret)
        expect(response.body).not_to include(secret)
      end

      it 'answers 422 and creates nothing for an unknown credential type' do
        expect {
          post '/api/v1/devops/integration_credentials',
               params: { credential: valid_params[:credential].merge(credential_type: 'oauth') },
               headers: headers, as: :json
        }.not_to change(Devops::IntegrationCredential, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'answers 422 and creates nothing when no secret material is supplied' do
        expect {
          post '/api/v1/devops/integration_credentials',
               params: { credential: valid_params[:credential].except(:credentials) },
               headers: headers, as: :json
        }.not_to change(Devops::IntegrationCredential, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden and creates nothing' do
        expect {
          post '/api/v1/devops/integration_credentials', params: valid_params, headers: headers, as: :json
        }.not_to change(Devops::IntegrationCredential, :count)

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/integration_credentials/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:credential) { create(:devops_integration_credential, account: account, name: 'Before') }

    it 'persists the new name' do
      patch "/api/v1/devops/integration_credentials/#{credential.id}",
            params: { credential: { name: 'Updated Credential' } }, headers: headers, as: :json

      expect_success_response
      expect(credential.reload.name).to eq('Updated Credential')
    end

    it 'answers 422 and leaves the row alone when the update is invalid' do
      patch "/api/v1/devops/integration_credentials/#{credential.id}",
            params: { credential: { name: '' } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(credential.reload.name).to eq('Before')
    end

    # IMP-01a08cd2: rotating the secret through update used to fail on every
    # call — the controller hands over permitted ActionController::Parameters,
    # which is not a Hash, and the model's credentials_format rejected it.
    it 'rotates the secret material, encrypted, and never echoes it' do
      new_secret = "sk_rotated_#{SecureRandom.hex(12)}"

      patch "/api/v1/devops/integration_credentials/#{credential.id}",
            params: { credential: { credentials: { api_key: new_secret } } }, headers: headers, as: :json

      expect_success_response
      expect(credential.reload.decrypt).to include('api_key' => new_secret)
      expect(credential.encrypted_credentials).not_to include(new_secret)
      expect(response.body).not_to include(new_secret)
    end

    it 'rejects secret material missing its required key and rolls the whole update back' do
      patch "/api/v1/devops/integration_credentials/#{credential.id}",
            params: { credential: { name: 'Renamed', credentials: { token: 'wrong-shape' } } },
            headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(credential.reload.name).to eq('Before')
      expect(credential.decrypt).not_to include('token')
    end
  end

  describe 'DELETE /api/v1/devops/integration_credentials/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let!(:credential) { create(:devops_integration_credential, account: account) }

    it 'removes the row' do
      expect {
        delete "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json
      }.to change { account_credentials.count }.by(-1)

      expect_success_response
      expect(Devops::IntegrationCredential.exists?(credential.id)).to be(false)
    end

    it 'refuses to delete a credential an integration is using, and keeps it' do
      create(:devops_integration_instance, account: account,
                                           template: create(:devops_integration_template),
                                           credential: credential)

      delete "/api/v1/devops/integration_credentials/#{credential.id}", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Devops::IntegrationCredential.exists?(credential.id)).to be(true)
    end
  end

  describe 'POST /api/v1/devops/integration_credentials/:id/rotate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    it 'rotates credential successfully' do
      allow(Security::CredentialEncryptionService).to receive(:rotate_encryption).and_return('rotated_encrypted_data')

      post "/api/v1/devops/integration_credentials/#{credential.id}/rotate", headers: headers, as: :json

      expect_success_response
    end

    it 'handles rotation errors' do
      allow(Security::CredentialEncryptionService).to receive(:rotate_encryption).and_raise(
        Security::CredentialEncryptionService::DecryptionError.new('Rotation failed')
      )

      post "/api/v1/devops/integration_credentials/#{credential.id}/rotate", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /api/v1/devops/integration_credentials/:id/verify' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:credential) { create(:devops_integration_credential, account: account) }

    it 'verifies credential successfully' do
      allow(Security::CredentialEncryptionService).to receive(:valid_encrypted_credentials?).and_return(true)

      post "/api/v1/devops/integration_credentials/#{credential.id}/verify", headers: headers, as: :json

      expect_success_response
      expect(json_response['data']['valid']).to be true
    end
  end
end
