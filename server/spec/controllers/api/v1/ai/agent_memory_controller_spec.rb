# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::AgentMemoryController", type: :request do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.memory.read', account: account) }
  let(:write_user) { user_with_permissions('ai.memory.read', 'ai.memory.write', account: account) }
  let(:manage_user) { user_with_permissions('ai.memory.read', 'ai.memory.write', 'ai.memory.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Stub services
  before do
    # Stub ContextPersistenceService methods
    allow(Ai::ContextPersistenceService).to receive(:get_agent_memory).and_return(nil)
    allow(Ai::ContextPersistenceService).to receive(:recall_memory).and_return(nil)
    allow(Ai::ContextPersistenceService).to receive(:get_relevant_memories).and_return([])

    entry_double = double('Entry', entry_summary: { key: "test", value: "data" })
    allow(Ai::ContextPersistenceService).to receive(:store_memory).and_return(entry_double)
  end

  # =========================================================================
  # INDEX (GET /api/v1/ai/agents/:agent_id/memory)
  # =========================================================================
  describe "GET /api/v1/ai/agents/:agent_id/memory" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.memory.read permission (no memory)' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['memory']).to be_nil
      expect(json_response_data['entries']).to eq([])
    end

    it 'returns 404 when agent does not exist' do
      get "/api/v1/ai/agents/nonexistent-id/memory", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # SHOW (GET /api/v1/ai/agents/:agent_id/memory/:key)
  # =========================================================================
  describe "GET /api/v1/ai/agents/:agent_id/memory/:key" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/test_key" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 when key not found' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end

    it 'returns success when key exists' do
      allow(Ai::ContextPersistenceService).to receive(:recall_memory).and_return({ data: "test" })
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
    end
  end

  # =========================================================================
  # CREATE (POST /api/v1/ai/agents/:agent_id/memory)
  # =========================================================================
  describe "POST /api/v1/ai/agents/:agent_id/memory" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory" }
    let(:valid_params) { { memory: { key: "test_key", value: { data: "test" } } } }

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.write permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.memory.write permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(write_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE (PATCH /api/v1/ai/agents/:agent_id/memory/:key)
  # =========================================================================
  describe "PATCH /api/v1/ai/agents/:agent_id/memory/:key" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/test_key" }
    let(:update_params) { { memory: { value: { data: "updated" } } } }

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.write permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.memory.write permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(write_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # DESTROY (DELETE /api/v1/ai/agents/:agent_id/memory/:key)
  # =========================================================================
  describe "DELETE /api/v1/ai/agents/:agent_id/memory/:key" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/test_key" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.write permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.memory.write permission' do
      delete path, headers: auth_headers_for(write_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # SEARCH (POST /api/v1/ai/agents/:agent_id/memory/search)
  # =========================================================================
  describe "POST /api/v1/ai/agents/:agent_id/memory/search" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/search" }

    it 'returns 401 when unauthenticated' do
      post path, params: { q: "test" }.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.read permission' do
      post path, params: { q: "test" }.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.memory.read permission' do
      post path, params: { q: "test" }.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['memories']).to be_an(Array)
    end
  end

  # =========================================================================
  # CLEAR (POST /api/v1/ai/agents/:agent_id/memory/clear)
  # =========================================================================
  describe "POST /api/v1/ai/agents/:agent_id/memory/clear" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/clear" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.manage permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.memory.manage permission (no memory to clear)' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['cleared']).to eq(0)
    end
  end

  # =========================================================================
  # STATS (GET /api/v1/ai/agents/:agent_id/memory/stats)
  # =========================================================================
  describe "GET /api/v1/ai/agents/:agent_id/memory/stats" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/stats" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.memory.read permission (no memory)' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['stats']['has_memory']).to eq(false)
    end
  end

  # =========================================================================
  # SYNC (POST /api/v1/ai/agents/:agent_id/memory/sync)
  # =========================================================================
  describe "POST /api/v1/ai/agents/:agent_id/memory/sync" do
    let(:path) { "/api/v1/ai/agents/#{agent.id}/memory/sync" }

    it 'returns 401 when unauthenticated' do
      post path, params: { source_context_id: SecureRandom.uuid }.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory.manage permission' do
      post path, params: { source_context_id: SecureRandom.uuid }.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.memory.manage permission' do
      post path, params: { source_context_id: SecureRandom.uuid }.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
