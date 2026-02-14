# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ExecutionResourcesController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.agents.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Mock services
  let(:aggregator_service) { instance_double(Ai::ExecutionResourceAggregatorService) }
  let(:detail_service) { instance_double(Ai::ExecutionResourceDetailService) }

  before do
    allow(Ai::ExecutionResourceAggregatorService).to receive(:new).and_return(aggregator_service)
    allow(Ai::ExecutionResourceDetailService).to receive(:new).and_return(detail_service)
  end

  # =========================================================================
  # INDEX (ai.agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_resources" do
    let(:path) { "/api/v1/ai/execution_resources" }

    before do
      allow(aggregator_service).to receive(:aggregate).and_return([
        { id: 'r1', type: 'worktree', name: 'Session 1', status: 'active' },
        { id: 'r2', type: 'sandbox', name: 'Sandbox 1', status: 'running' }
      ])
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.agents.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns paginated execution resources' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['items']).to be_an(Array)
      expect(json_response['data']['pagination']).to include(
        'current_page', 'total_pages', 'total_count', 'per_page'
      )
    end

    it 'respects pagination parameters' do
      get path, params: { page: 1, per_page: 1 }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['items'].length).to be <= 1
      expect(json_response['data']['pagination']['current_page']).to eq(1)
    end
  end

  # =========================================================================
  # COUNTS (ai.agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_resources/counts" do
    let(:path) { "/api/v1/ai/execution_resources/counts" }

    before do
      allow(aggregator_service).to receive(:counts).and_return({
        worktree: 3, sandbox: 2, workflow_run: 5, total: 10
      })
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns resource counts' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['counts']).to be_a(Hash)
    end
  end

  # =========================================================================
  # SHOW (ai.agents.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_resources/:resource_type/:id" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/execution_resources/worktree/some-id", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/execution_resources/worktree/some-id", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns resource details when found' do
      allow(detail_service).to receive(:fetch).with('worktree', 'some-id').and_return({
        id: 'some-id', type: 'worktree', name: 'Session 1', status: 'active'
      })

      get "/api/v1/ai/execution_resources/worktree/some-id", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['resource']).to be_present
    end

    it 'returns 404 when resource not found' do
      allow(detail_service).to receive(:fetch).with('worktree', 'nonexistent').and_return(nil)

      get "/api/v1/ai/execution_resources/worktree/nonexistent", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
