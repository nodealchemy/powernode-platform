# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ModelRouterAnalyticsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/model_router" }

  # Users
  let(:read_user) { user_with_permissions('ai.routing.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.routing.manage', account: account) }
  let(:optimize_user) { user_with_permissions('ai.routing.optimize', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Service double
  let(:router_service) { instance_double(Ai::ModelRouterService) }

  before do
    allow(Ai::ModelRouterService).to receive(:new).and_return(router_service)
    # Stub AuditLogging to prevent re-raise in test env
    allow(Audit::LoggingService).to receive_message_chain(:instance, :log)
  end

  # =========================================================================
  # ROUTE (ai.routing.manage)
  # =========================================================================
  describe "POST /api/v1/ai/model_router/route" do
    let(:path) { "#{base_path}/route" }
    let(:provider) { create(:ai_provider, account: account) }
    let(:route_params) do
      { request_type: "completion", estimated_tokens: 100 }
    end
    let(:routing_result) do
      {
        provider: provider,
        decision_id: SecureRandom.uuid,
        strategy_used: "cost_optimized",
        estimated_cost: 0.01,
        estimated_latency_ms: 200,
        scoring: {}
      }
    end

    before do
      allow(router_service).to receive(:route).and_return(routing_result)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: route_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.routing.manage permission' do
      post path, params: route_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns routing result with provider info' do
      post path, params: route_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['routing']['provider_id']).to eq(provider.id)
      expect(json_response['data']['routing']['strategy_used']).to eq('cost_optimized')
    end

    it 'handles no providers available' do
      allow(router_service).to receive(:route).and_raise(
        Ai::ModelRouterService::NoProvidersAvailableError.new("No providers available")
      )
      post path, params: route_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  # =========================================================================
  # STATISTICS (ai.routing.read)
  # =========================================================================
  describe "GET /api/v1/ai/model_router/statistics" do
    let(:path) { "#{base_path}/statistics" }

    before do
      allow(router_service).to receive(:statistics).and_return({
        total_requests: 100, success_rate: 0.95
      })
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.routing.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns statistics with time range' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['statistics']).to be_present
      expect(json_response['data']['time_range']).to be_present
    end
  end

  # =========================================================================
  # COST ANALYSIS (ai.routing.read)
  # =========================================================================
  describe "GET /api/v1/ai/model_router/cost_analysis" do
    let(:path) { "#{base_path}/cost_analysis" }

    before do
      allow(router_service).to receive(:analyze_cost_savings).and_return({
        total_cost: 100.0, savings: 20.0
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

    it 'returns cost analysis data with time range' do
      get path, params: { time_range: '7d' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['cost_analysis']).to be_present
      expect(json_response['data']['time_range']['period']).to eq('7d')
    end
  end

  # =========================================================================
  # PROVIDER RANKINGS (ai.routing.read)
  # =========================================================================
  describe "GET /api/v1/ai/model_router/provider_rankings" do
    let(:path) { "#{base_path}/provider_rankings" }

    before do
      allow(router_service).to receive(:provider_rankings).and_return([])
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns provider rankings' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['rankings']).to be_an(Array)
    end
  end

  # =========================================================================
  # RECOMMENDATIONS (ai.routing.read)
  # =========================================================================
  describe "GET /api/v1/ai/model_router/recommendations" do
    let(:path) { "#{base_path}/recommendations" }

    before do
      allow(router_service).to receive(:get_optimization_recommendations).and_return([])
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns optimization recommendations' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['recommendations']).to be_an(Array)
      expect(json_response['data']['generated_at']).to be_present
    end
  end

  # =========================================================================
  # OPTIMIZATIONS INDEX (ai.routing.read)
  # =========================================================================
  describe "GET /api/v1/ai/model_router/optimizations" do
    let(:path) { "#{base_path}/optimizations" }

    before do
      create(:ai_cost_optimization_log, account: account)
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns paginated optimizations list' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['optimizations']).to be_an(Array)
      expect(json_response['data']['pagination']).to be_present
      expect(json_response['data']['stats']).to be_present
    end
  end

  # =========================================================================
  # IDENTIFY OPTIMIZATIONS (ai.routing.optimize)
  # =========================================================================
  describe "POST /api/v1/ai/model_router/optimizations/identify" do
    let(:path) { "#{base_path}/optimizations/identify" }

    before do
      allow(Ai::CostOptimizationLog).to receive(:identify_opportunities_for).and_return([])
    end

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.routing.optimize permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'identifies and returns optimization opportunities' do
      post path, headers: auth_headers_for(optimize_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['opportunities_found']).to eq(0)
      expect(json_response['data']['message']).to include('complete')
    end
  end

  # =========================================================================
  # APPLY OPTIMIZATION (ai.routing.optimize)
  # =========================================================================
  describe "POST /api/v1/ai/model_router/optimizations/:id/apply" do
    let(:optimization) { create(:ai_cost_optimization_log, account: account, status: 'identified') }
    let(:path) { "#{base_path}/optimizations/#{optimization.id}/apply" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.routing.optimize permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'applies the optimization successfully' do
      post path, headers: auth_headers_for(optimize_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['optimization']['status']).to eq('applied')
      expect(json_response['data']['message']).to include('applied')
    end

    it 'returns not found for nonexistent optimization' do
      post "#{base_path}/optimizations/#{SecureRandom.uuid}/apply", headers: auth_headers_for(optimize_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
