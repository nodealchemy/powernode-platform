# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::DiscoveryController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.discovery.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.discovery.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:discovery_result) { create(:ai_discovery_result, account: account, scan_type: 'full_scan') }

  # =========================================================================
  # INDEX (ai.discovery.read)
  # =========================================================================
  describe "GET /api/v1/ai/discovery" do
    let(:path) { "/api/v1/ai/discovery" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.discovery.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns discovery results' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']).to be_an(Array)
    end

    it 'filters by scan_type' do
      get path, params: { scan_type: 'full_scan' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.discovery.read)
  # =========================================================================
  describe "GET /api/v1/ai/discovery/:id" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/discovery/#{discovery_result.id}", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/discovery/#{discovery_result.id}", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns discovery result details' do
      get "/api/v1/ai/discovery/#{discovery_result.id}", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['id']).to eq(discovery_result.id)
    end

    it 'returns 404 for nonexistent result' do
      get "/api/v1/ai/discovery/nonexistent", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # SCAN (ai.discovery.manage)
  # =========================================================================
  describe "POST /api/v1/ai/discovery/scan" do
    let(:path) { "/api/v1/ai/discovery/scan" }

    before do
      # Stub the worker job dispatch (migrated from Ai::DiscoveryScanJob)
      allow(WorkerJobService).to receive(:enqueue_job)
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.discovery.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a scan and returns accepted' do
      expect {
        post path, params: { scan_type: 'full_scan' }.to_json, headers: auth_headers_for(manage_user)
      }.to change(Ai::DiscoveryResult, :count).by(1)

      expect(response).to have_http_status(:accepted)
      expect(json_response['success']).to be true
    end
  end

  # =========================================================================
  # RECOMMEND (ai.discovery.manage)
  # =========================================================================
  describe "POST /api/v1/ai/discovery/recommend" do
    let(:path) { "/api/v1/ai/discovery/recommend" }
    let(:analyzer_service) { instance_double(Ai::Discovery::TaskAnalyzerService) }

    before do
      allow(Ai::Discovery::TaskAnalyzerService).to receive(:new).and_return(analyzer_service)
      allow(analyzer_service).to receive(:analyze).and_return({
        suggested_agents: [],
        suggested_tools: [],
        complexity: 'medium'
      })
    end

    it 'returns 401 when unauthenticated' do
      post path, params: { task_description: 'Build an API' }.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.discovery.manage permission' do
      post path, params: { task_description: 'Build an API' }.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns recommendations for a task' do
      post path, params: { task_description: 'Build an API' }.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
    end

    it 'returns error when task_description is missing' do
      post path, params: {}.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:bad_request)
    end
  end
end
