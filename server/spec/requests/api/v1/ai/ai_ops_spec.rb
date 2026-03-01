# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::AiOps', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.aiops.read', 'ai.aiops.write' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.aiops.read' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  let(:service) { instance_double('Ai::Analytics::DashboardService') }

  before do
    allow(Ai::Analytics::DashboardService).to receive(:new).and_return(service)
  end

  describe 'GET /api/v1/ai/aiops/dashboard' do
    let(:dashboard_data) do
      {
        total_executions: 1000,
        success_rate: 98.5,
        avg_latency_ms: 150.0,
        total_cost_usd: 50.0
      }
    end

    before do
      allow(service).to receive(:aiops_dashboard).and_return(dashboard_data)
    end

    context 'with ai.aiops.read permission' do
      it 'returns dashboard data' do
        get '/api/v1/ai/aiops/dashboard',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('dashboard')
        expect(data).to have_key('time_range')
      end

      it 'accepts time_range parameter' do
        get '/api/v1/ai/aiops/dashboard?time_range=24h',
            headers: headers

        expect_success_response
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/ai/aiops/dashboard',
            headers: auth_headers_for(regular_user)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/health' do
    let(:health_data) do
      {
        status: 'healthy',
        uptime_percentage: 99.9,
        active_providers: 3
      }
    end

    before do
      allow(service).to receive(:system_health).and_return(health_data)
    end

    context 'with permission' do
      it 'returns system health data' do
        get '/api/v1/ai/aiops/health',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('health')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/overview' do
    let(:overview_data) do
      {
        total_requests: 5000,
        errors: 10,
        avg_cost: 0.05
      }
    end

    before do
      allow(service).to receive(:system_overview).and_return(overview_data)
    end

    context 'with permission' do
      it 'returns system overview' do
        get '/api/v1/ai/aiops/overview',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('overview')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/providers' do
    let(:provider_data) do
      [
        { id: SecureRandom.uuid, name: 'OpenAI', status: 'active' }
      ]
    end

    before do
      allow(service).to receive(:ops_provider_metrics).and_return(provider_data)
    end

    context 'with permission' do
      it 'returns provider metrics' do
        get '/api/v1/ai/aiops/providers',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('providers')
        expect(data).to have_key('time_range')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/providers/:id/metrics' do
    let(:provider_record) { create(:ai_provider, :openai, account: account) }

    let(:metrics) do
      double(map: [], current_page: 1)
    end

    before do
      allow_any_instance_of(Account).to receive_message_chain(:ai_providers, :find).and_return(provider_record)
      allow(Ai::ProviderMetric).to receive_message_chain(
        :for_provider, :for_account, :recent, :ordered_by_time, :limit
      ).and_return(metrics)
    end

    context 'with permission' do
      it 'returns provider-specific metrics' do
        get "/api/v1/ai/aiops/providers/#{provider_record.id}/metrics",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('provider')
        expect(data).to have_key('metrics')
        expect(data).to have_key('time_range')
      end
    end

    context 'when provider not found' do
      before do
        allow_any_instance_of(Account).to receive_message_chain(:ai_providers, :find)
          .and_raise(ActiveRecord::RecordNotFound)
      end

      it 'returns not found error' do
        get "/api/v1/ai/aiops/providers/#{SecureRandom.uuid}/metrics",
            headers: headers

        expect_error_response('Provider not found', 404)
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/providers/comparison' do
    let(:comparison_data) do
      {
        providers: [
          { name: 'OpenAI', avg_latency: 100, cost: 0.05 },
          { name: 'Anthropic', avg_latency: 120, cost: 0.04 }
        ]
      }
    end

    before do
      allow(service).to receive(:ops_provider_comparison).and_return(comparison_data)
    end

    context 'with permission' do
      it 'returns provider comparison data' do
        get '/api/v1/ai/aiops/providers/comparison',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('comparison')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/workflows' do
    let(:workflow_data) do
      [
        { id: SecureRandom.uuid, name: 'Test Workflow', executions: 100 }
      ]
    end

    before do
      allow(service).to receive(:ops_workflow_metrics).and_return(workflow_data)
    end

    context 'with permission' do
      it 'returns workflow metrics' do
        get '/api/v1/ai/aiops/workflows',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('workflows')
        expect(data).to have_key('time_range')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/agents' do
    let(:agent_data) do
      [
        { id: SecureRandom.uuid, name: 'Test Agent', executions: 50 }
      ]
    end

    before do
      allow(service).to receive(:ops_agent_metrics).and_return(agent_data)
    end

    context 'with permission' do
      it 'returns agent metrics' do
        get '/api/v1/ai/aiops/agents',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('agents')
        expect(data).to have_key('time_range')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/cost_analysis' do
    let(:cost_data) do
      {
        total_cost: 100.0,
        cost_by_provider: { 'openai' => 60.0, 'anthropic' => 40.0 },
        cost_trend: []
      }
    end

    before do
      allow(service).to receive(:ops_cost_analysis).and_return(cost_data)
    end

    context 'with permission' do
      it 'returns cost analysis data' do
        get '/api/v1/ai/aiops/cost_analysis',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('cost_analysis')
        expect(data).to have_key('time_range')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/alerts' do
    let(:alerts_data) do
      [
        { id: SecureRandom.uuid, type: 'high_error_rate', severity: 'warning' }
      ]
    end

    before do
      allow(service).to receive(:active_alerts).and_return(alerts_data)
    end

    context 'with permission' do
      it 'returns active alerts' do
        get '/api/v1/ai/aiops/alerts',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('alerts')
        expect(data).to have_key('count')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/circuit_breakers' do
    let(:cb_status) do
      [
        { name: 'openai_circuit', state: 'closed', failure_count: 0 }
      ]
    end

    before do
      allow(service).to receive(:circuit_breaker_status).and_return(cb_status)
    end

    context 'with permission' do
      it 'returns circuit breaker status' do
        get '/api/v1/ai/aiops/circuit_breakers',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('circuit_breakers')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/aiops/real_time' do
    let(:real_time_data) do
      {
        current_requests: 5,
        requests_per_second: 2.5,
        active_connections: 10
      }
    end

    before do
      allow(service).to receive(:aiops_real_time_metrics).and_return(real_time_data)
    end

    context 'with permission' do
      it 'returns real-time metrics' do
        get '/api/v1/ai/aiops/real_time',
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('current_requests')
      end
    end
  end

  describe 'POST /api/v1/ai/aiops/record_metrics' do
    let(:provider_record) { create(:ai_provider, :openai, account: account) }

    before do
      allow_any_instance_of(Account).to receive_message_chain(:ai_providers, :find).and_return(provider_record)
      allow(service).to receive(:record_execution_metrics).and_return(true)
    end

    context 'with ai.aiops.write permission' do
      it 'records metrics successfully' do
        post '/api/v1/ai/aiops/record_metrics',
             params: {
               provider_id: provider_record.id,
               success: true,
               input_tokens: 100,
               output_tokens: 50,
               latency_ms: 150,
               cost_usd: 0.01
             },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Metrics recorded successfully')
      end
    end

    context 'when provider not found' do
      before do
        allow_any_instance_of(Account).to receive_message_chain(:ai_providers, :find)
          .and_raise(ActiveRecord::RecordNotFound)
      end

      it 'returns not found error' do
        post '/api/v1/ai/aiops/record_metrics',
             params: { provider_id: SecureRandom.uuid },
             headers: headers,
             as: :json

        expect_error_response('Provider not found', 404)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/aiops/record_metrics',
             params: { provider_id: provider_record.id },
             headers: auth_headers_for(read_only_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
