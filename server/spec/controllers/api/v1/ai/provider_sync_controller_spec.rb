# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ProviderSyncController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/providers" }

  # Users
  let(:read_user) { user_with_permissions('ai.providers.read', account: account) }
  let(:update_user) { user_with_permissions('ai.providers.update', account: account) }
  let(:create_user) { user_with_permissions('ai.providers.create', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:provider) { create(:ai_provider, account: account) }
  let(:credential) do
    create(:ai_provider_credential, account: account, provider: provider, is_default: true, is_active: true)
  end

  before do
    # Stub AuditLogging to prevent re-raise in test env
    allow(Audit::LoggingService).to receive_message_chain(:instance, :log)
  end

  # =========================================================================
  # TEST CONNECTION (ai.providers.read)
  # =========================================================================
  describe "POST /api/v1/ai/providers/:id/test_connection" do
    let(:path) { "#{base_path}/#{provider.id}/test_connection" }
    let(:test_result) do
      { success: true, response_time_ms: 150, message: "Connection successful" }
    end
    let(:management_service) { instance_double(Ai::ProviderManagementService) }

    before do
      credential # ensure exists
      allow(Ai::ProviderManagementService).to receive(:new).and_return(management_service)
      allow(management_service).to receive(:test_with_details_simple).and_return(test_result)
      allow_any_instance_of(Ai::ProviderCredential).to receive(:record_success!)
      allow_any_instance_of(Ai::Provider).to receive(:update_health_metrics)
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.read permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'tests connection and returns result' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['success']).to be true
      expect(json_response['data']['response_time_ms']).to eq(150)
    end

    it 'returns not found for nonexistent provider' do
      post "#{base_path}/#{SecureRandom.uuid}/test_connection", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end

    it 'tests with specific credential_id' do
      post path, params: { credential_id: credential.id }.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SYNC MODELS (ai.providers.update)
  # =========================================================================
  describe "POST /api/v1/ai/providers/:id/sync_models" do
    let(:path) { "#{base_path}/#{provider.id}/sync_models" }

    before do
      allow(Ai::ProviderManagementService).to receive(:sync_provider_models).and_return(true)
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'syncs models and returns success' do
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['message']).to include('synced')
    end

    it 'returns error when provider is inactive' do
      provider.update!(is_active: false)
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('not active')
    end

    it 'returns error when sync fails' do
      allow(Ai::ProviderManagementService).to receive(:sync_provider_models).and_return(false)
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # =========================================================================
  # SYNC ALL (ai.providers.update)
  # =========================================================================
  describe "POST /api/v1/ai/providers/sync_all" do
    let(:path) { "#{base_path}/sync_all" }

    before do
      allow(Ai::ProviderManagementService).to receive(:sync_all_providers).and_return({
        synced: 2, failed: 0
      })
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'syncs all providers and returns results' do
      post path, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['results']['synced']).to eq(2)
      expect(json_response['data']['message']).to include('Synced')
    end
  end

  # =========================================================================
  # TEST ALL (ai.providers.read)
  # =========================================================================
  describe "POST /api/v1/ai/providers/test_all" do
    let(:path) { "#{base_path}/test_all" }

    before do
      management_service = instance_double(Ai::ProviderManagementService)
      allow(Ai::ProviderManagementService).to receive(:new).and_return(management_service)
      allow(management_service).to receive(:test_provider_connection).and_return({
        success: true, message: "OK", response_time_ms: 100
      })
      # health_status and last_health_check_at columns may not exist yet
      allow_any_instance_of(Ai::Provider).to receive(:update).and_return(true)
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.read permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'tests all providers and returns summary' do
      provider # ensure at least one
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['results']).to be_an(Array)
      expect(json_response['data']['summary']).to include('total', 'successful', 'failed')
    end
  end

  # =========================================================================
  # SETUP DEFAULTS (ai.providers.create)
  # =========================================================================
  describe "POST /api/v1/ai/providers/setup_defaults" do
    let(:path) { "#{base_path}/setup_defaults" }

    before do
      allow(Ai::Providers::DefaultConfig).to receive(:types).and_return([])
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.providers.create permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with created providers list' do
      post path, headers: auth_headers_for(create_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['created_providers']).to be_an(Array)
      expect(json_response['data']['message']).to be_present
    end
  end
end
