# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::CommunityAgentsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/community/agents" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.community_agents.read', account: account) }
  let(:create_user) { user_with_permissions('ai.community_agents.create', account: account) }
  let(:manage_user) { user_with_permissions('ai.community_agents.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:community_agent) { create(:community_agent, owner_account: account) }

  # =========================================================================
  # INDEX (ai.community_agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/community/agents" do
    let(:path) { base_path }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.community_agents.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.community_agents.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.community_agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/community/agents/:id" do
    let(:path) { "#{base_path}/#{community_agent.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.community_agents.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.community_agents.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE (ai.community_agents.create)
  # =========================================================================
  describe "POST /api/v1/ai/community/agents" do
    let(:path) { base_path }
    let(:valid_params) do
      {
        agent: {
          name: "Test Community Agent",
          description: "A test agent",
          endpoint_url: "https://agent.example.com/agent.json",
          category: "automation"
        }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.community_agents.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.community_agents.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # PUBLISH (ai.community_agents.manage)
  # =========================================================================
  describe "POST /api/v1/ai/community/agents/:id/publish" do
    let(:path) { "#{base_path}/#{community_agent.id}/publish" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.community_agents.manage permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.community_agents.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UNPUBLISH (ai.community_agents.manage)
  # =========================================================================
  describe "POST /api/v1/ai/community/agents/:id/unpublish" do
    let(:path) { "#{base_path}/#{community_agent.id}/unpublish" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.community_agents.manage permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.community_agents.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
