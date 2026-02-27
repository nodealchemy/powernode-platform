# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::ModelRouter', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.routing.read', 'ai.routing.manage', 'ai.routing.optimize' ]) }
  let(:limited_user) { create(:user, account: account, permissions: [ 'ai.routing.read' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  before do
    allow_any_instance_of(Api::V1::Ai::ModelRouterController).to receive(:log_audit_event)
    allow_any_instance_of(Api::V1::Ai::ModelRouterAnalyticsController).to receive(:log_audit_event)
  end

  describe 'GET /api/v1/ai/model_router/rules' do
    let!(:rule1) { create(:ai_model_routing_rule, account: account, rule_type: 'cost_based') }
    let!(:rule2) { create(:ai_model_routing_rule, account: account, rule_type: 'latency_based') }

    context 'with proper permissions' do
      it 'returns list of routing rules' do
        get '/api/v1/ai/model_router/rules', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['rules']).to be_an(Array)
        expect(data).to have_key('pagination')
      end

      it 'filters by rule type' do
        get '/api/v1/ai/model_router/rules?rule_type=cost_based', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by active status' do
        get '/api/v1/ai/model_router/rules?active=true', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        user_without_permissions = create(:user, account: account)
        headers_without_permissions = auth_headers_for(user_without_permissions)

        get '/api/v1/ai/model_router/rules', headers: headers_without_permissions, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/rules/:id' do
    let(:rule) { create(:ai_model_routing_rule, account: account) }

    context 'with proper permissions' do
      it 'returns rule details' do
        get "/api/v1/ai/model_router/rules/#{rule.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['rule']).to include('id', 'name', 'rule_type', 'conditions')
        expect(data['rule']).to have_key('stats')
        expect(data['rule']).to have_key('thresholds')
      end
    end

    context 'with invalid rule id' do
      it 'returns not found error' do
        get "/api/v1/ai/model_router/rules/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Routing rule not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/model_router/rules' do
    let(:rule_params) do
      {
        rule: {
          name: 'Cost Optimization Rule',
          rule_type: 'cost_based',
          priority: 1,
          conditions: { max_cost: 0.01 },
          target: { strategy: 'cost_optimized' }
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new routing rule' do
        expect {
          post '/api/v1/ai/model_router/rules', params: rule_params, headers: headers, as: :json
        }.to change { account.ai_model_routing_rules.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['rule']).to be_present
        expect(data['message']).to eq('Routing rule created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { rule: { name: nil } }

        post '/api/v1/ai/model_router/rules', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/model_router/rules', params: rule_params, headers: limited_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/ai/model_router/rules/:id' do
    let(:rule) { create(:ai_model_routing_rule, account: account) }
    let(:update_params) do
      {
        rule: {
          name: 'Updated Rule Name',
          priority: 5
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the routing rule' do
        patch "/api/v1/ai/model_router/rules/#{rule.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['rule']).to be_present
        expect(data['message']).to eq('Routing rule updated successfully')
      end
    end
  end

  describe 'DELETE /api/v1/ai/model_router/rules/:id' do
    let!(:rule) { create(:ai_model_routing_rule, account: account) }

    context 'with proper permissions' do
      it 'deletes the routing rule' do
        expect {
          delete "/api/v1/ai/model_router/rules/#{rule.id}", headers: headers, as: :json
        }.to change { account.ai_model_routing_rules.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Routing rule deleted successfully')
      end
    end
  end

  describe 'POST /api/v1/ai/model_router/rules/:id/toggle' do
    let(:rule) { create(:ai_model_routing_rule, account: account, is_active: false) }

    context 'with proper permissions' do
      it 'toggles the rule active status' do
        post "/api/v1/ai/model_router/rules/#{rule.id}/toggle", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('activated')
      end
    end
  end

  describe 'POST /api/v1/ai/model_router/route' do
    let(:route_params) do
      {
        request_type: 'completion',
        capabilities: [ 'text-generation' ],
        estimated_tokens: 1000
      }
    end

    context 'with proper permissions' do
      it 'routes the request and returns provider' do
        provider = create(:ai_provider, account: account)
        allow_any_instance_of(Ai::ModelRouterService).to receive(:route)
          .and_return({
            provider: provider,
            decision_id: SecureRandom.uuid,
            strategy_used: 'cost_optimized',
            estimated_cost: 0.001,
            estimated_latency_ms: 500,
            scoring: {}
          })

        post '/api/v1/ai/model_router/route', params: route_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['routing']).to include('provider_id', 'decision_id', 'strategy_used')
      end

      it 'returns error when no providers available' do
        allow_any_instance_of(Ai::ModelRouterService).to receive(:route)
          .and_raise(Ai::ModelRouterService::NoProvidersAvailableError, 'No providers available')

        post '/api/v1/ai/model_router/route', params: route_params, headers: headers, as: :json

        expect_error_response('No providers available', 503)
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/decisions' do
    let!(:decision) { create(:ai_routing_decision, account: account) }

    context 'with proper permissions' do
      it 'returns list of routing decisions' do
        get '/api/v1/ai/model_router/decisions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['decisions']).to be_an(Array)
        expect(data).to have_key('pagination')
        expect(data).to have_key('time_range')
      end

      it 'filters by strategy' do
        get '/api/v1/ai/model_router/decisions?strategy=cost_optimized', headers: headers, as: :json

        expect_success_response
      end

      it 'accepts time range parameter' do
        get '/api/v1/ai/model_router/decisions?time_range=7d', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/decisions/:id' do
    let(:decision) { create(:ai_routing_decision, account: account) }

    context 'with proper permissions' do
      it 'returns decision details' do
        get "/api/v1/ai/model_router/decisions/#{decision.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['decision']).to include('id', 'request_type', 'strategy_used')
        expect(data['decision']).to have_key('cost')
        expect(data['decision']).to have_key('performance')
      end
    end

    context 'accessing decision from different account' do
      let(:other_account) { create(:account) }
      let(:other_decision) { create(:ai_routing_decision, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/model_router/decisions/#{other_decision.id}", headers: headers, as: :json

        expect_error_response('Decision not found', 404)
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/statistics' do
    context 'with proper permissions' do
      it 'returns routing statistics' do
        allow_any_instance_of(Ai::ModelRouterService).to receive(:statistics)
          .and_return({ total_requests: 100, success_rate: 0.95 })

        get '/api/v1/ai/model_router/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['statistics']).to be_present
        expect(data).to have_key('time_range')
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/cost_analysis' do
    context 'with proper permissions' do
      it 'returns cost analysis' do
        allow_any_instance_of(Ai::ModelRouterService).to receive(:analyze_cost_savings)
          .and_return({ total_cost: 10.0, total_savings: 2.0, savings_percentage: 20 })

        get '/api/v1/ai/model_router/cost_analysis', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['cost_analysis']).to be_present
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/provider_rankings' do
    context 'with proper permissions' do
      it 'returns provider rankings' do
        allow_any_instance_of(Ai::ModelRouterService).to receive(:provider_rankings)
          .and_return([ { provider_id: 'openai', rank: 1, score: 0.95 } ])

        get '/api/v1/ai/model_router/provider_rankings', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['rankings']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/recommendations' do
    context 'with proper permissions' do
      it 'returns optimization recommendations' do
        allow_any_instance_of(Ai::ModelRouterService).to receive(:get_optimization_recommendations)
          .and_return([ { type: 'cost', description: 'Switch to cheaper provider' } ])

        get '/api/v1/ai/model_router/recommendations', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['recommendations']).to be_an(Array)
        expect(data).to have_key('generated_at')
      end
    end
  end

  describe 'GET /api/v1/ai/model_router/optimizations' do
    let!(:optimization) { create(:ai_cost_optimization_log, account: account) }

    context 'with proper permissions' do
      it 'returns list of optimizations' do
        allow(Ai::CostOptimizationLog).to receive(:stats_for_account).and_return({})

        get '/api/v1/ai/model_router/optimizations', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['optimizations']).to be_an(Array)
        expect(data).to have_key('stats')
      end

      it 'filters by type' do
        get '/api/v1/ai/model_router/optimizations?type=provider_switch', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/model_router/optimizations/identify' do
    context 'with proper permissions' do
      it 'identifies optimization opportunities' do
        allow(Ai::CostOptimizationLog).to receive(:identify_opportunities_for)
          .and_return([
            {
              optimization_type: 'provider_switch',
              resource_type: 'workflow',
              resource_id: SecureRandom.uuid,
              description: 'Switch to cheaper provider',
              current_cost_usd: 1.0,
              potential_savings_usd: 0.2,
              recommendation: { 'suggestion' => 'Use provider X' }
            }
          ])

        post '/api/v1/ai/model_router/optimizations/identify', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('opportunities_found')
        expect(data).to have_key('new_optimizations_created')
      end
    end

    context 'without optimize permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/model_router/optimizations/identify', headers: limited_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/model_router/optimizations/:id/apply' do
    let(:optimization) { create(:ai_cost_optimization_log, account: account, status: 'identified') }

    context 'with proper permissions' do
      it 'applies the optimization' do
        allow_any_instance_of(Ai::CostOptimizationLog).to receive(:apply!).and_return(true)

        post "/api/v1/ai/model_router/optimizations/#{optimization.id}/apply", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Optimization applied successfully')
      end

      it 'returns error for invalid status' do
        optimization.update!(status: 'applied')

        post "/api/v1/ai/model_router/optimizations/#{optimization.id}/apply", headers: headers, as: :json

        expect_error_response('Optimization cannot be applied in current status', 422)
      end
    end

    context 'accessing optimization from different account' do
      let(:other_account) { create(:account) }
      let(:other_optimization) { create(:ai_cost_optimization_log, account: other_account) }

      it 'returns not found error' do
        post "/api/v1/ai/model_router/optimizations/#{other_optimization.id}/apply", headers: headers, as: :json

        expect_error_response('Optimization not found', 404)
      end
    end
  end
end
