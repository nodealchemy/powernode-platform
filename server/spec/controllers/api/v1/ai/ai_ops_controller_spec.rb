# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AiOpsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.aiops.read', 'ai.aiops.write']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.aiops.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:dashboard_service) { instance_double(Ai::Analytics::DashboardService) }

  before do
    sign_in_as_user(user)
    allow(Ai::Analytics::DashboardService).to receive(:new).and_return(dashboard_service)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :dashboard
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for dashboard' do
        get :dashboard
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for health' do
        get :health
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for record_metrics' do
        post :record_metrics, params: { provider_id: 'some-id' }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permission' do
      before { sign_in_as_user(read_only_user) }

      it 'allows dashboard access' do
        allow(dashboard_service).to receive(:aiops_dashboard).and_return({})
        get :dashboard
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for record_metrics (requires write)' do
        post :record_metrics, params: { provider_id: 'some-id' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # DASHBOARD
  # ============================================================================

  describe 'GET #dashboard' do
    it 'returns dashboard data' do
      allow(dashboard_service).to receive(:aiops_dashboard).and_return({
        total_executions: 100, active_workflows: 5, error_rate: 0.02
      })

      get :dashboard
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['dashboard']).to be_present
      expect(json_response['data']['time_range']).to be_present
    end

    it 'accepts time_range parameter' do
      allow(dashboard_service).to receive(:aiops_dashboard).and_return({})

      get :dashboard, params: { time_range: '24h' }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # HEALTH
  # ============================================================================

  describe 'GET #health' do
    it 'returns system health data' do
      allow(dashboard_service).to receive(:system_health).and_return({
        status: 'healthy', providers: [], agents: []
      })

      get :health
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['health']).to be_present
      expect(json_response['data']['timestamp']).to be_present
    end
  end

  # ============================================================================
  # OVERVIEW
  # ============================================================================

  describe 'GET #overview' do
    it 'returns system overview' do
      allow(dashboard_service).to receive(:system_overview).and_return({
        running_workflows: 3, active_agents: 10
      })

      get :overview
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['overview']).to be_present
    end
  end

  # ============================================================================
  # PROVIDERS
  # ============================================================================

  describe 'GET #providers' do
    it 'returns provider metrics' do
      allow(dashboard_service).to receive(:ops_provider_metrics).and_return([])

      get :providers
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('providers')
    end
  end

  describe 'GET #provider_metrics' do
    let(:provider) { create(:ai_provider, :openai, account: account) }

    it 'returns metrics for a specific provider' do
      create(:ai_provider_metric, account: account, provider: provider)

      get :provider_metrics, params: { id: provider.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['provider']['id']).to eq(provider.id)
    end

    it 'returns 404 for non-existent provider' do
      get :provider_metrics, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET #provider_comparison' do
    it 'returns provider comparison data' do
      allow(dashboard_service).to receive(:ops_provider_comparison).and_return({})

      get :provider_comparison
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('comparison')
    end
  end

  # ============================================================================
  # WORKFLOW & AGENT METRICS
  # ============================================================================

  describe 'GET #workflows' do
    it 'returns workflow metrics' do
      allow(dashboard_service).to receive(:ops_workflow_metrics).and_return([])

      get :workflows
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('workflows')
    end
  end

  describe 'GET #agents' do
    it 'returns agent metrics' do
      allow(dashboard_service).to receive(:ops_agent_metrics).and_return([])

      get :agents
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('agents')
    end
  end

  # ============================================================================
  # COST ANALYSIS
  # ============================================================================

  describe 'GET #cost_analysis' do
    it 'returns cost analysis data' do
      allow(dashboard_service).to receive(:ops_cost_analysis).and_return({
        total_cost: 45.67, cost_by_provider: {}
      })

      get :cost_analysis
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('cost_analysis')
    end
  end

  # ============================================================================
  # ALERTS & CIRCUIT BREAKERS
  # ============================================================================

  describe 'GET #alerts' do
    it 'returns active alerts' do
      allow(dashboard_service).to receive(:active_alerts).and_return([])

      get :alerts
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['alerts']).to be_an(Array)
    end
  end

  describe 'GET #circuit_breakers' do
    it 'returns circuit breaker status' do
      allow(dashboard_service).to receive(:circuit_breaker_status).and_return({})

      get :circuit_breakers
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('circuit_breakers')
    end
  end

  # ============================================================================
  # REAL TIME
  # ============================================================================

  describe 'GET #real_time' do
    it 'returns real-time metrics' do
      allow(dashboard_service).to receive(:aiops_real_time_metrics).and_return({
        active_executions: 3, queue_depth: 12
      })

      get :real_time
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # RECORD METRICS
  # ============================================================================

  describe 'POST #record_metrics' do
    let(:provider) { create(:ai_provider, :openai, account: account) }

    it 'records metrics successfully' do
      allow(dashboard_service).to receive(:record_execution_metrics).and_return(true)

      post :record_metrics, params: {
        provider_id: provider.id,
        success: true,
        latency_ms: 250,
        input_tokens: 100,
        output_tokens: 50
      }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['message']).to include('recorded')
    end

    it 'returns 404 for non-existent provider' do
      post :record_metrics, params: { provider_id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end
end
