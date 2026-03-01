# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::MemoryPoolsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/memory_pools" }

  # Users
  let(:read_user) { user_with_permissions('ai.memory_pools.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.memory_pools.read', 'ai.memory_pools.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data - override invalid factory defaults with valid values
  let(:memory_pool) do
    create(:ai_memory_pool, account: account, pool_type: "shared", scope: "execution")
  end

  # =========================================================================
  # INDEX (ai.memory_pools.read)
  # =========================================================================
  describe "GET /api/v1/ai/memory_pools" do
    let(:path) { base_path }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory_pools.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with list of pools' do
      memory_pool # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']).to be_an(Array)
    end

    it 'filters by scope' do
      memory_pool # create
      get path, params: { scope: 'execution' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end

    it 'filters by pool_type' do
      memory_pool # create
      get path, params: { pool_type: 'shared' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.memory_pools.read)
  # =========================================================================
  describe "GET /api/v1/ai/memory_pools/:id" do
    let(:path) { "#{base_path}/#{memory_pool.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with pool details' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['id']).to eq(memory_pool.id)
    end

    it 'returns not found for nonexistent pool' do
      get "#{base_path}/#{SecureRandom.uuid}", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # CREATE (ai.memory_pools.manage)
  # =========================================================================
  describe "POST /api/v1/ai/memory_pools" do
    let(:path) { base_path }
    let(:valid_params) do
      {
        name: "Test Pool",
        pool_type: "shared",
        scope: "execution"
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory_pools.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a memory pool when user has manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['name']).to eq('Test Pool')
    end
  end

  # =========================================================================
  # UPDATE (ai.memory_pools.manage)
  # =========================================================================
  describe "PATCH /api/v1/ai/memory_pools/:id" do
    let(:path) { "#{base_path}/#{memory_pool.id}" }
    let(:update_params) { { name: "Updated Pool" } }

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory_pools.manage permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'updates the pool when user has manage permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DESTROY (ai.memory_pools.manage)
  # =========================================================================
  describe "DELETE /api/v1/ai/memory_pools/:id" do
    let(:path) { "#{base_path}/#{memory_pool.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory_pools.manage permission' do
      delete path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'deletes the pool when user has manage permission' do
      delete path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['message']).to include('deleted')
    end
  end

  # =========================================================================
  # READ DATA (ai.memory_pools.read)
  # =========================================================================
  describe "GET /api/v1/ai/memory_pools/:id/data/:key" do
    let(:path) { "#{base_path}/#{memory_pool.id}/data/test_key" }

    before do
      allow_any_instance_of(Ai::MemoryPool).to receive(:read_data).and_return("test_value")
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns data for the given key' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['key']).to eq('test_key')
      expect(json_response['data']['value']).to eq('test_value')
    end
  end

  # =========================================================================
  # WRITE DATA (ai.memory_pools.manage)
  # =========================================================================
  describe "POST /api/v1/ai/memory_pools/:id/write_data" do
    let(:path) { "#{base_path}/#{memory_pool.id}/write_data" }
    let(:write_params) { { key: "test_key", value: "test_value" } }

    before do
      allow_any_instance_of(Ai::MemoryPool).to receive(:write_data).and_return(true)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: write_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.memory_pools.manage permission' do
      post path, params: write_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'writes data when user has manage permission' do
      post path, params: write_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # QUERY (ai.memory_pools.read)
  # =========================================================================
  describe "POST /api/v1/ai/memory_pools/:id/query" do
    let(:path) { "#{base_path}/#{memory_pool.id}/query" }
    let(:query_params) { { scope: 'execution' } }

    it 'returns 401 when unauthenticated' do
      post path, params: query_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, params: query_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns query results' do
      post path, params: query_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to be_an(Array)
    end
  end
end
