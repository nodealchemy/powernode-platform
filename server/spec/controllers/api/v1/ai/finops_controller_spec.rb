# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::FinopsController", type: :request do
  let(:account) { create(:account) }
  let(:read_user) { user_with_permissions('ai.finops.view', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Stub services to avoid deep dependency issues
  before do
    cost_service = instance_double(Ai::Analytics::CostAnalysisService)
    allow(Ai::Analytics::CostAnalysisService).to receive(:new).and_return(cost_service)
    allow(cost_service).to receive(:calculate_total_cost).and_return(150.0)
    allow(cost_service).to receive(:calculate_cost_trend).and_return({ current: 150.0, previous: 120.0, change: 25.0 })
    allow(cost_service).to receive(:budget_analysis).and_return({ budget: 500.0, spent: 150.0, utilization: 30.0 })
    allow(cost_service).to receive(:cost_breakdown_by_provider).and_return([])
    allow(cost_service).to receive(:cost_breakdown_by_model).and_return([])
    allow(cost_service).to receive(:cost_breakdown_by_workflow).and_return([])
    allow(cost_service).to receive(:cost_breakdown_by_agent).and_return([])
    allow(cost_service).to receive(:daily_cost_breakdown).and_return([])
    allow(cost_service).to receive(:generate_budget_forecast).and_return({})
    allow(cost_service).to receive(:detect_cost_anomalies).and_return([])

    token_service = instance_double(Ai::Finops::TokenAnalyticsService)
    allow(Ai::Finops::TokenAnalyticsService).to receive(:new).and_return(token_service)
    allow(token_service).to receive(:optimization_score).and_return({ score: 85 })
    allow(token_service).to receive(:usage_summary).and_return({ by_model: [], total_tokens: 0 })
    allow(token_service).to receive(:waste_analysis).and_return({ wasted_tokens: 0 })
    allow(token_service).to receive(:forecast).and_return({ months: [] })
  end

  # =========================================================================
  # INDEX (GET /api/v1/ai/finops)
  # =========================================================================
  describe "GET /api/v1/ai/finops" do
    let(:path) { "/api/v1/ai/finops" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['overview']).to be_a(Hash)
    end
  end

  # =========================================================================
  # COST BREAKDOWN (GET /api/v1/ai/finops/cost_breakdown)
  # =========================================================================
  describe "GET /api/v1/ai/finops/cost_breakdown" do
    let(:path) { "/api/v1/ai/finops/cost_breakdown" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['cost_breakdown']).to be_a(Hash)
    end
  end

  # =========================================================================
  # TRENDS (GET /api/v1/ai/finops/trends)
  # =========================================================================
  describe "GET /api/v1/ai/finops/trends" do
    let(:path) { "/api/v1/ai/finops/trends" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['trends']).to be_a(Hash)
    end
  end

  # =========================================================================
  # BUDGET UTILIZATION (GET /api/v1/ai/finops/budget_utilization)
  # =========================================================================
  describe "GET /api/v1/ai/finops/budget_utilization" do
    let(:path) { "/api/v1/ai/finops/budget_utilization" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['budget']).to be_a(Hash)
    end
  end

  # =========================================================================
  # TOKEN ANALYTICS (GET /api/v1/ai/finops/token_analytics)
  # =========================================================================
  describe "GET /api/v1/ai/finops/token_analytics" do
    let(:path) { "/api/v1/ai/finops/token_analytics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['token_analytics']).to be_a(Hash)
    end
  end

  # =========================================================================
  # WASTE ANALYSIS (GET /api/v1/ai/finops/waste_analysis)
  # =========================================================================
  describe "GET /api/v1/ai/finops/waste_analysis" do
    let(:path) { "/api/v1/ai/finops/waste_analysis" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['waste_analysis']).to be_a(Hash)
    end
  end

  # =========================================================================
  # FORECAST (GET /api/v1/ai/finops/forecast)
  # =========================================================================
  describe "GET /api/v1/ai/finops/forecast" do
    let(:path) { "/api/v1/ai/finops/forecast" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['forecast']).to be_a(Hash)
    end
  end

  # =========================================================================
  # OPTIMIZATION SCORE (GET /api/v1/ai/finops/optimization_score)
  # =========================================================================
  describe "GET /api/v1/ai/finops/optimization_score" do
    let(:path) { "/api/v1/ai/finops/optimization_score" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.finops.view permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.finops.view permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['optimization']).to be_a(Hash)
    end
  end
end
