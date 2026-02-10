# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Finops', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.finops.view']) }
  let(:headers) { auth_headers_for(user) }

  let(:cost_service) { instance_double(Ai::Analytics::CostAnalysisService) }
  let(:token_service) { instance_double(Ai::Finops::TokenAnalyticsService) }

  before do
    allow(Ai::Analytics::CostAnalysisService).to receive(:new).and_return(cost_service)
    allow(Ai::Finops::TokenAnalyticsService).to receive(:new).and_return(token_service)
  end

  describe 'GET /api/v1/ai/finops' do
    before do
      allow(cost_service).to receive(:calculate_total_cost).and_return({ total: 100.0 })
      allow(cost_service).to receive(:calculate_cost_trend).and_return({ change_percentage: 5.0 })
      allow(cost_service).to receive(:budget_analysis).and_return({ monthly_budget: 500 })
      allow(token_service).to receive(:optimization_score).and_return({ score: 75, grade: "C" })
      allow(token_service).to receive(:usage_summary).and_return({ by_model: [] })
    end

    it 'returns finops overview' do
      get '/api/v1/ai/finops', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['overview']).to be_present
      expect(data['overview']['total_cost']).to be_present
      expect(data['time_range']).to be_present
    end

    it 'accepts time_range parameter' do
      get '/api/v1/ai/finops?time_range=7d', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['time_range']['period']).to eq('7d')
    end

    context 'without permission' do
      let(:user_no_perms) { create(:user, account: account, permissions: []) }
      let(:no_perm_headers) { auth_headers_for(user_no_perms) }

      it 'returns forbidden' do
        get '/api/v1/ai/finops', headers: no_perm_headers, as: :json

        expect_error_response('Permission denied: ai.finops.view', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/finops/cost_breakdown' do
    before do
      allow(cost_service).to receive(:cost_breakdown_by_provider).and_return([])
      allow(cost_service).to receive(:cost_breakdown_by_model).and_return([])
      allow(cost_service).to receive(:cost_breakdown_by_workflow).and_return([])
      allow(cost_service).to receive(:cost_breakdown_by_agent).and_return([])
      allow(cost_service).to receive(:daily_cost_breakdown).and_return({})
    end

    it 'returns cost breakdown data' do
      get '/api/v1/ai/finops/cost_breakdown', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['cost_breakdown']).to be_present
      expect(data['cost_breakdown']).to have_key('by_provider')
      expect(data['cost_breakdown']).to have_key('by_model')
    end
  end

  describe 'GET /api/v1/ai/finops/trends' do
    before do
      allow(cost_service).to receive(:calculate_cost_trend).and_return({ trend: "up" })
      allow(cost_service).to receive(:daily_cost_breakdown).and_return({})
      allow(cost_service).to receive(:generate_budget_forecast).and_return(nil)
      allow(cost_service).to receive(:detect_cost_anomalies).and_return([])
    end

    it 'returns trend data' do
      get '/api/v1/ai/finops/trends', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['trends']).to be_present
      expect(data['trends']).to have_key('cost_trend')
    end
  end

  describe 'GET /api/v1/ai/finops/budget_utilization' do
    before do
      allow(cost_service).to receive(:budget_analysis).and_return({ monthly_budget: 500 })
    end

    it 'returns budget utilization data' do
      get '/api/v1/ai/finops/budget_utilization', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['budget']).to be_present
      expect(data['agent_budgets']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/ai/finops/token_analytics' do
    before do
      allow(token_service).to receive(:usage_summary).and_return({
        total_tokens: 50_000,
        prompt_tokens: 30_000,
        completion_tokens: 20_000,
        total_cost: 0.5
      })
    end

    it 'returns token analytics' do
      get '/api/v1/ai/finops/token_analytics', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['token_analytics']).to be_present
      expect(data['token_analytics']['total_tokens']).to eq(50_000)
    end
  end

  describe 'GET /api/v1/ai/finops/waste_analysis' do
    before do
      allow(token_service).to receive(:waste_analysis).and_return({
        redundant_context_ratio: 15.0,
        cache_miss_rate: 30.0,
        recommendations: []
      })
    end

    it 'returns waste analysis' do
      get '/api/v1/ai/finops/waste_analysis', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['waste_analysis']).to be_present
      expect(data['waste_analysis']['redundant_context_ratio']).to eq(15.0)
    end
  end

  describe 'GET /api/v1/ai/finops/forecast' do
    before do
      allow(token_service).to receive(:forecast).and_return({
        projections: [
          { month: 1, projected_cost: 100.0 },
          { month: 2, projected_cost: 110.0 },
          { month: 3, projected_cost: 120.0 }
        ]
      })
    end

    it 'returns forecast data' do
      get '/api/v1/ai/finops/forecast', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['forecast']).to be_present
      expect(data['forecast']['projections'].length).to eq(3)
    end

    it 'accepts months parameter' do
      allow(token_service).to receive(:forecast).with(months: 6).and_return({ projections: [] })

      get '/api/v1/ai/finops/forecast?months=6', headers: headers, as: :json

      expect_success_response
      expect(token_service).to have_received(:forecast).with(months: 6)
    end
  end

  describe 'GET /api/v1/ai/finops/optimization_score' do
    before do
      allow(token_service).to receive(:optimization_score).and_return({
        score: 82,
        grade: "B",
        breakdown: {
          cache_hit_rate: { score: 70, weight: 0.3 },
          tier_utilization: { score: 90, weight: 0.25 },
          waste_ratio: { score: 85, weight: 0.25 },
          budget_efficiency: { score: 80, weight: 0.2 }
        },
        recommendations: ["Enable prefix caching"]
      })
    end

    it 'returns optimization score' do
      get '/api/v1/ai/finops/optimization_score', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['optimization']).to be_present
      expect(data['optimization']['score']).to eq(82)
      expect(data['optimization']['grade']).to eq("B")
    end
  end
end
