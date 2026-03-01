# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ApiReferenceController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.agents.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # =========================================================================
  # INDEX (ai.agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/api_reference" do
    let(:path) { "/api/v1/ai/api_reference" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.agents.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns list of API sections' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['sections']).to be_an(Array)
      expect(json_response['data']['total_sections']).to be > 0
    end

    it 'includes section metadata' do
      get path, headers: auth_headers_for(read_user)
      section = json_response['data']['sections'].first
      expect(section).to include('section', 'description', 'endpoint_count', 'base_path')
    end
  end

  # =========================================================================
  # SEARCH (ai.agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/api_reference/search" do
    let(:path) { "/api/v1/ai/api_reference/search" }

    it 'returns 401 when unauthenticated' do
      get path, params: { q: 'agents' }, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, params: { q: 'agents' }, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns search results for a query' do
      get path, params: { q: 'agents' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['query']).to eq('agents')
      expect(json_response['data']['results']).to be_an(Array)
      expect(json_response['data']['count']).to be_a(Integer)
    end

    it 'returns error when query parameter is missing' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:bad_request)
    end
  end

  # =========================================================================
  # SHOW (ai.agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/api_reference/:section" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/api_reference/agents", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/api_reference/agents", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns section details with endpoints' do
      get "/api/v1/ai/api_reference/agents", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['section']).to eq('agents')
      expect(json_response['data']['endpoints']).to be_an(Array)
      expect(json_response['data']['endpoint_count']).to be_a(Integer)
    end

    it 'returns 404 for nonexistent section' do
      get "/api/v1/ai/api_reference/nonexistent_section", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
