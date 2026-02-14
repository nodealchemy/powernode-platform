# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::RoiCalculationsController", type: :request do
  let(:account) { create(:account) }
  let(:read_user) { user_with_permissions('ai.roi.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.roi.read', 'ai.roi.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  let(:base_path) { "/api/v1/ai/roi/calculations" }

  # Service mock
  let(:mock_cost_service) { instance_double(::Ai::Analytics::CostAnalysisService) }

  before do
    allow(::Ai::Analytics::CostAnalysisService).to receive(:new).and_return(mock_cost_service)
    allow(Audit::LoggingService).to receive_message_chain(:instance, :log)
  end

  # =========================================================================
  # METRICS (ai.roi.read)
  # =========================================================================
  describe "GET /api/v1/ai/roi/calculations/metrics" do
    let(:path) { "#{base_path}/metrics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.roi.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.roi.read permission' do
      create(:ai_roi_metric, account: account)
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('metrics')
    end
  end

  # =========================================================================
  # SHOW METRIC (ai.roi.read)
  # =========================================================================
  describe "GET /api/v1/ai/roi/calculations/metrics/:id" do
    let!(:metric) { create(:ai_roi_metric, account: account) }
    let(:path) { "#{base_path}/metrics/#{metric.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.roi.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('metric')
    end

    it 'returns 404 for non-existent metric' do
      get "#{base_path}/metrics/#{SecureRandom.uuid}", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # PROJECTIONS (ai.roi.read)
  # =========================================================================
  describe "GET /api/v1/ai/roi/calculations/projections" do
    let(:path) { "#{base_path}/projections" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with projections data' do
      allow(mock_cost_service).to receive(:roi_projections).and_return({
        projected_roi: 150.0, confidence: 0.85
      })

      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('projections')
    end
  end

  # =========================================================================
  # RECOMMENDATIONS (ai.roi.read)
  # =========================================================================
  describe "GET /api/v1/ai/roi/calculations/recommendations" do
    let(:path) { "#{base_path}/recommendations" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with recommendations' do
      allow(mock_cost_service).to receive(:roi_recommendations).and_return([
        { action: "optimize_provider", impact: "high" }
      ])

      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('recommendations')
    end
  end

  # =========================================================================
  # COMPARE (ai.roi.read)
  # =========================================================================
  describe "GET /api/v1/ai/roi/calculations/compare" do
    let(:path) { "#{base_path}/compare" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with comparison data' do
      allow(mock_cost_service).to receive(:roi_compare_periods).and_return({
        current: { roi: 200.0 }, previous: { roi: 150.0 }, change: 33.3
      })

      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('comparison')
    end
  end

  # =========================================================================
  # CALCULATE (ai.roi.manage)
  # =========================================================================
  describe "POST /api/v1/ai/roi/calculations/calculate" do
    let(:path) { "#{base_path}/calculate" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.roi.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when calculating for today' do
      metric = create(:ai_roi_metric, account: account)
      allow(mock_cost_service).to receive(:roi_calculate_for_date).and_return(metric)

      post path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end

    it 'returns success when calculating for a specific date' do
      metric = create(:ai_roi_metric, account: account)
      allow(mock_cost_service).to receive(:roi_calculate_for_date).and_return(metric)

      post path, params: { date: Date.current.to_s },
                 headers: auth_headers_for(manage_user),
                 as: :json
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # AGGREGATE (ai.roi.manage)
  # =========================================================================
  describe "POST /api/v1/ai/roi/calculations/aggregate" do
    let(:path) { "#{base_path}/aggregate" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.roi.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when aggregating metrics' do
      allow(mock_cost_service).to receive(:roi_aggregate_metrics).and_return({
        period_type: "weekly", aggregated: true
      })

      post path, params: { period_type: "weekly" },
                 headers: auth_headers_for(manage_user),
                 as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
