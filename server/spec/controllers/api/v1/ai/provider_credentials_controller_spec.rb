# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ProviderCredentialsController", type: :request do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.providers.read', account: account) }
  let(:create_user) { user_with_permissions('ai.credentials.create', account: account) }
  let(:update_user) { user_with_permissions('ai.credentials.update', account: account) }
  let(:delete_user) { user_with_permissions('ai.credentials.delete', account: account) }
  let(:test_user) { user_with_permissions('ai.credentials.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:credential) { create(:ai_provider_credential, account: account, provider: provider) }

  let(:base_path) { "/api/v1/ai/providers/#{provider.id}/credentials" }

  # =========================================================================
  # INDEX (ai.providers.read)
  # =========================================================================
  describe "GET /api/v1/ai/providers/:provider_id/credentials" do
    let(:path) { base_path }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.providers.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['credentials']).to be_an(Array)
    end
  end

  # =========================================================================
  # SHOW (ai.providers.read)
  # =========================================================================
  describe "GET /api/v1/ai/providers/:provider_id/credentials/:id" do
    let(:path) { "#{base_path}/#{credential.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.providers.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response_data['credential']).to be_a(Hash)
    end
  end

  # =========================================================================
  # CREATE (ai.credentials.create)
  # =========================================================================
  describe "POST /api/v1/ai/providers/:provider_id/credentials" do
    let(:path) { base_path }
    let(:valid_params) do
      {
        credential: {
          name: "New Test Credential",
          credentials: { api_key: "test-key-123", model: "test-model" },
          is_active: true,
          is_default: false
        }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.credentials.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.credentials.create permission' do
      allow(::Ai::ProviderManagementService).to receive(:create_provider_credential).and_return(credential)

      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE (ai.credentials.update)
  # =========================================================================
  describe "PATCH /api/v1/ai/providers/:provider_id/credentials/:id" do
    let(:path) { "#{base_path}/#{credential.id}" }
    let(:update_params) do
      { credential: { name: "Updated Credential Name" } }
    end

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.credentials.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.credentials.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DESTROY (ai.credentials.delete)
  # =========================================================================
  describe "DELETE /api/v1/ai/providers/:provider_id/credentials/:id" do
    let(:path) { "#{base_path}/#{credential.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.credentials.delete permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.credentials.delete permission' do
      delete path, headers: auth_headers_for(delete_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # TEST (ai.credentials.read)
  # =========================================================================
  describe "POST /api/v1/ai/providers/:provider_id/credentials/:id/test" do
    let(:path) { "#{base_path}/#{credential.id}/test" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.credentials.read permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.credentials.read permission' do
      mock_service = instance_double(::Ai::ProviderManagementService)
      allow(::Ai::ProviderManagementService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:test_with_details_simple).and_return(
        success: true, response_time_ms: 150, message: "Connection successful"
      )
      allow(credential).to receive(:record_success!)
      allow(provider).to receive(:update_health_metrics)

      post path, headers: auth_headers_for(test_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # MAKE_DEFAULT (ai.credentials.update)
  # =========================================================================
  describe "POST /api/v1/ai/providers/:provider_id/credentials/:id/make_default" do
    let(:path) { "#{base_path}/#{credential.id}/make_default" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.credentials.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.credentials.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # ROTATE (ai.credentials.update)
  # =========================================================================
  describe "POST /api/v1/ai/providers/:provider_id/credentials/:id/rotate" do
    let(:path) { "#{base_path}/#{credential.id}/rotate" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.credentials.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.credentials.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
    end
  end
end
