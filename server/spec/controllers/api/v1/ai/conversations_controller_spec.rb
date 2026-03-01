# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ConversationsController", type: :request do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.conversations.read', account: account) }
  let(:create_user) { user_with_permissions('ai.conversations.create', 'ai.conversations.read', account: account) }
  let(:update_user) { user_with_permissions('ai.conversations.update', 'ai.conversations.read', account: account) }
  let(:delete_user) { user_with_permissions('ai.conversations.delete', 'ai.conversations.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:conversation) do
    create(:ai_conversation, account: account, user: read_user, agent: agent, provider: provider)
  end

  # =========================================================================
  # INDEX (global conversations)
  # =========================================================================
  describe "GET /api/v1/ai/conversations" do
    let(:path) { "/api/v1/ai/conversations" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.conversations.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['conversations']).to be_an(Array)
    end
  end

  # =========================================================================
  # SHOW
  # =========================================================================
  describe "GET /api/v1/ai/conversations/:id" do
    let(:path) { "/api/v1/ai/conversations/#{conversation.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.conversations.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response_data['conversation']).to be_a(Hash)
    end
  end

  # =========================================================================
  # CREATE (nested under agent)
  # =========================================================================
  describe "POST /api/v1/ai/agents/:agent_id/conversations" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/conversations" }
    let(:valid_params) do
      { conversation: { title: "Test Conversation" } }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.conversations.create permission' do
      # Stub provider availability check
      allow(ProviderAvailabilityService).to receive(:validate_agent_provider!).and_return(true)

      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE
  # =========================================================================
  describe "PATCH /api/v1/ai/conversations/:id" do
    let(:path) { "/api/v1/ai/conversations/#{conversation.id}" }
    let(:update_params) do
      { conversation: { title: "Updated Title" } }
    end

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.conversations.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DESTROY
  # =========================================================================
  describe "DELETE /api/v1/ai/conversations/:id" do
    let(:path) { "/api/v1/ai/conversations/#{conversation.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.delete permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.conversations.delete permission' do
      delete path, headers: auth_headers_for(delete_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # ARCHIVE
  # =========================================================================
  describe "POST /api/v1/ai/conversations/:id/archive" do
    let(:path) { "/api/v1/ai/conversations/#{conversation.id}/archive" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.conversations.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # STATS
  # =========================================================================
  describe "GET /api/v1/ai/conversations/:id/stats" do
    let(:path) { "/api/v1/ai/conversations/#{conversation.id}/stats" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.conversations.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.conversations.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response_data['stats']).to be_a(Hash)
    end
  end
end
