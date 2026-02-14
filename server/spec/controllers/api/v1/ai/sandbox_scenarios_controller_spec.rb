# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::SandboxScenariosController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.sandboxes.read', account: account) }
  let(:create_user) { user_with_permissions('ai.sandboxes.create', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:sandbox) { create(:ai_sandbox, account: account) }
  let(:base_path) { "/api/v1/ai/sandboxes/#{sandbox.id}" }

  # =========================================================================
  # SCENARIOS (ai.sandboxes.read)
  # =========================================================================
  describe "GET /api/v1/ai/sandboxes/:sandbox_id/scenarios" do
    let(:path) { "#{base_path}/scenarios" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.sandboxes.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # MOCKS (ai.sandboxes.read)
  # =========================================================================
  describe "GET /api/v1/ai/sandboxes/:sandbox_id/mocks" do
    let(:path) { "#{base_path}/mocks" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.sandboxes.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE_SCENARIO (ai.sandboxes.create)
  # =========================================================================
  describe "POST /api/v1/ai/sandboxes/:sandbox_id/scenarios" do
    let(:path) { "#{base_path}/scenarios" }
    let(:valid_params) do
      {
        name: "Test Scenario",
        scenario_type: "functional",
        description: "A test scenario"
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.sandboxes.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
