# frozen_string_literal: true

require 'rails_helper'

# Ensure the namespaced job class exists for stubbing
# The controller uses Ai::MonitoringHealthCheckJob.perform_later
unless defined?(Ai::MonitoringHealthCheckJob)
  module Ai
    class MonitoringHealthCheckJob < ApplicationJob; end
  end
end

RSpec.describe Api::V1::Ai::MonitoringController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:worker) { create(:worker) }

  # Permission-based users
  let(:monitoring_read_user) { create(:user, account: account, permissions: [ 'ai.monitoring.read' ]) }
  let(:monitoring_manage_user) { create(:user, account: account, permissions: [ 'ai.monitoring.read', 'ai.monitoring.manage' ]) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    # Mock Monitoring::UnifiedService
    allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard).and_return({
      system: { status: 'healthy' },
      providers: { total: 2, healthy: 2 },
      agents: { total: 5, active: 4 },
      workflows: { total: 3, active: 2 }
    })

    allow_any_instance_of(Monitoring::UnifiedService).to receive(:collect_component_metrics).and_return({
      requests: 150,
      latency_ms: 45.2,
      error_rate: 0.02
    })

    allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_system_overview).and_return({
      total_providers: 2,
      total_workflows: 3,
      total_agents: 5
    })

    allow_any_instance_of(Monitoring::UnifiedService).to receive(:calculate_health_score).and_return(95)

    allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts).and_return({
      alerts: [],
      total_alerts: 0
    })

    allow_any_instance_of(Monitoring::UnifiedService).to receive(:check_and_trigger_alerts).and_return([])

    # Mock Ai::MonitoringHealthService#determine_health_status (used by overview action)
    allow_any_instance_of(Ai::MonitoringHealthService).to receive(:determine_health_status).and_return('healthy')
  end

  # =============================================================================
  # DASHBOARD & METRICS
  # =============================================================================

  describe 'GET #dashboard' do
    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns monitoring dashboard data' do
        get :dashboard

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['dashboard']).to be_present
        expect(json['data']['generated_at']).to be_present
      end

      it 'supports custom time range' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard).with(
          hash_including(time_range: 7200.seconds)
        )

        get :dashboard, params: { time_range: 7200 }

        expect(response).to have_http_status(:success)
      end

      it 'filters by specific components' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard).with(
          hash_including(components: [ 'system', 'providers' ])
        )

        get :dashboard, params: { components: 'system,providers' }

        expect(response).to have_http_status(:success)
      end

      it 'defaults to 1 hour time range' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard).with(
          hash_including(time_range: 1.hour)
        )

        get :dashboard

        expect(response).to have_http_status(:success)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden error' do
        get :dashboard

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #metrics' do
    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns component metrics' do
        get :metrics

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['metrics']).to be_present
        expect(json['data']['timestamp']).to be_present
      end

      it 'includes time range in response' do
        get :metrics, params: { time_range: 3600 }

        json = JSON.parse(response.body)
        expect(json['data']['time_range_seconds']).to eq(3600)
      end

      it 'collects metrics for specified components' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:collect_component_metrics).at_least(:once)

        get :metrics, params: { components: 'system,providers' }

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET #overview' do
    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns system overview' do
        get :overview

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['overview']).to be_present
        expect(json['data']['health_score']).to eq(95)
        expect(json['data']['health_status']).to eq('healthy')
      end

      it 'includes timestamp' do
        get :overview

        json = JSON.parse(response.body)
        expect(json['data']['timestamp']).to be_present
      end
    end
  end

  # =============================================================================
  # HEALTH CHECKS
  # =============================================================================

  describe 'GET #health' do
    before do
      # Mock Redis connection
      allow_any_instance_of(Redis).to receive(:ping).and_return('PONG')
      allow_any_instance_of(Redis).to receive(:info).and_return({
        'used_memory_human' => '10M',
        'connected_clients' => '5'
      })

      # Mock circuit breaker
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:health_summary).and_return({
        total: 5,
        healthy: 5,
        degraded: 0,
        unhealthy: 0
      })
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns comprehensive health data' do
        get :health

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include(
          'system',
          'database',
          'redis',
          'providers',
          'workers',
          'circuit_breakers'
        )
      end

      it 'includes health score' do
        get :health

        json = JSON.parse(response.body)
        expect(json['data']['health_score']).to be_a(Integer)
        expect(json['data']['status']).to be_present
      end

      it 'includes timestamp and time range' do
        get :health, params: { time_range: 7200 }

        json = JSON.parse(response.body)
        expect(json['data']['timestamp']).to be_present
        expect(json['data']['time_range_seconds']).to eq(7200)
      end

      it 'checks database health' do
        connection = ActiveRecord::Base.connection
        allow(connection).to receive(:execute).with('SELECT 1').and_return(true)

        get :health

        json = JSON.parse(response.body)
        expect(json['data']['database']['status']).to eq('healthy')
      end

      it 'checks Redis health' do
        redis_mock = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis_mock)
        allow(redis_mock).to receive(:ping).and_return('PONG')
        allow(redis_mock).to receive(:info).and_return({
          'used_memory_human' => '1.2M',
          'connected_clients' => '5'
        })

        get :health

        json = JSON.parse(response.body)
        expect(json['data']['redis']['status']).to eq('healthy')
      end

      it 'handles database connection errors' do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError, 'Connection failed')

        get :health

        json = JSON.parse(response.body)
        expect(json['data']['database']['status']).to eq('unhealthy')
        expect(json['data']['database']['error']).to be_present
      end

      it 'handles Redis connection errors' do
        allow_any_instance_of(Redis).to receive(:ping).and_raise(StandardError, 'Redis unavailable')

        get :health

        json = JSON.parse(response.body)
        expect(json['data']['redis']['status']).to eq('unhealthy')
      end
    end
  end

  describe 'GET #health_detailed' do
    before do
      allow_any_instance_of(Redis).to receive(:ping).and_return('PONG')
      allow_any_instance_of(Redis).to receive(:info).and_return({
        'redis_version' => '7.0',
        'used_memory_human' => '10M',
        'used_memory_peak_human' => '15M',
        'connected_clients' => '5',
        'uptime_in_days' => '30'
      })
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns detailed health information' do
        get :health_detailed

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['services']).to include(
          'database',
          'redis',
          'providers',
          'workflows',
          'agents',
          'workers'
        )
      end

      it 'includes recent activity summary' do
        get :health_detailed

        json = JSON.parse(response.body)
        expect(json['data']['recent_activity']).to be_present
      end

      it 'includes error analysis' do
        get :health_detailed

        json = JSON.parse(response.body)
        expect(json['data']['error_analysis']).to be_present
      end

      it 'includes performance metrics' do
        get :health_detailed

        json = JSON.parse(response.body)
        expect(json['data']['performance_metrics']).to be_present
      end

      it 'includes resource metrics' do
        get :health_detailed

        json = JSON.parse(response.body)
        expect(json['data']['resource_metrics']).to be_present
      end
    end
  end

  describe 'GET #health_connectivity' do
    before do
      allow_any_instance_of(Redis).to receive(:ping).and_return('PONG')
      allow_any_instance_of(Redis).to receive(:info).and_return({
        'used_memory_human' => '10M',
        'connected_clients' => '5'
      })
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'tests connectivity to all services' do
        get :health_connectivity

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include(
          'database',
          'redis',
          'providers',
          'workers',
          'external_services'
        )
      end

      it 'measures database response time' do
        get :health_connectivity

        json = JSON.parse(response.body)
        expect(json['data']['database']['response_time_ms']).to be_a(Float)
      end

      it 'tests Redis connectivity' do
        redis_mock = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis_mock)
        allow(redis_mock).to receive(:ping).and_return('PONG')
        allow(redis_mock).to receive(:info).and_return({
          'used_memory_human' => '1.2M',
          'connected_clients' => '5'
        })

        get :health_connectivity

        json = JSON.parse(response.body)
        expect(json['data']['redis']['status']).to eq('connected')
      end
    end
  end

  # =============================================================================
  # ALERTS
  # =============================================================================

  describe 'GET #alerts' do
    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns alerts' do
        get :alerts

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['alerts']).to be_present
      end

      it 'filters by severity' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts).with(
          hash_including(severity: 'critical')
        )

        get :alerts, params: { severity: 'critical' }

        expect(response).to have_http_status(:success)
      end

      it 'filters by alert type' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts).with(
          hash_including(type: 'performance')
        )

        get :alerts, params: { alert_type: 'performance' }

        expect(response).to have_http_status(:success)
      end

      it 'defaults to active status' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts).with(
          hash_including(status: 'active')
        )

        get :alerts

        expect(response).to have_http_status(:success)
      end

      it 'includes timestamp' do
        get :alerts

        json = JSON.parse(response.body)
        expect(json['data']['timestamp']).to be_present
      end
    end
  end

  describe 'POST #alerts_check' do
    before do
      allow_any_instance_of(Monitoring::UnifiedService).to receive(:check_and_trigger_alerts).and_return([
        { type: 'performance', severity: 'warning', message: 'High latency detected' }
      ])
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'checks and triggers alerts' do
        expect_any_instance_of(Monitoring::UnifiedService).to receive(:check_and_trigger_alerts)

        post :alerts_check

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['alerts_checked']).to be true
      end

      it 'returns triggered alerts' do
        post :alerts_check

        json = JSON.parse(response.body)
        expect(json['data']['triggered_alerts']).to be_an(Array)
        expect(json['data']['count']).to eq(1)
      end
    end
  end

  # =============================================================================
  # CIRCUIT BREAKERS
  # =============================================================================

  describe 'GET #circuit_breakers_index' do
    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:all_states).and_return([
        { name: 'provider_openai', state: 'closed', failure_count: 0 },
        { name: 'workflow_execution', state: 'open', failure_count: 5 }
      ])

      allow(Ai::WorkflowCircuitBreakerManager).to receive(:health_summary).and_return({
        total: 2,
        healthy: 1,
        degraded: 0,
        unhealthy: 1
      })
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns all circuit breaker states' do
        get :circuit_breakers_index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['circuit_breakers']).to be_an(Array)
        expect(json['data']['circuit_breakers'].length).to eq(2)
      end

      it 'includes summary data' do
        get :circuit_breakers_index

        json = JSON.parse(response.body)
        expect(json['data']['summary']).to include(
          'total' => 2,
          'healthy' => 1,
          'unhealthy' => 1
        )
      end
    end
  end

  describe 'GET #circuit_breaker_show' do
    let(:mock_breaker) { double('Monitoring::CircuitBreaker', stats: { state: 'closed', failure_count: 0, success_count: 10 }) }

    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_breaker).with('provider_openai').and_return(mock_breaker)
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns specific circuit breaker stats' do
        get :circuit_breaker_show, params: { service_name: 'provider_openai' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['service_name']).to eq('provider_openai')
        expect(json['data']['stats']).to be_present
      end

      it 'returns not found for unknown circuit breaker' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_breaker).with('unknown').and_return(nil)

        get :circuit_breaker_show, params: { service_name: 'unknown' }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('not found')
      end
    end
  end

  describe 'POST #circuit_breaker_reset' do
    let(:mock_breaker) do
      double('Monitoring::CircuitBreaker',
        reset!: true,
        stats: { state: 'closed', failure_count: 0 }
      )
    end

    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_or_create_breaker).with('provider_openai').and_return(mock_breaker)
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'resets the circuit breaker' do
        expect(mock_breaker).to receive(:reset!)

        post :circuit_breaker_reset, params: { service_name: 'provider_openai' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to include('reset')
      end

      it 'returns updated circuit breaker state' do
        post :circuit_breaker_reset, params: { service_name: 'provider_openai' }

        json = JSON.parse(response.body)
        expect(json['data']['state']).to be_present
      end
    end

    context 'without manage permission' do
      before { sign_in monitoring_read_user }

      it 'returns forbidden error' do
        post :circuit_breaker_reset, params: { service_name: 'provider_openai' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #circuit_breaker_open' do
    let(:mock_breaker) do
      double('Monitoring::CircuitBreaker',
        open!: true,
        stats: { state: 'open', failure_count: 0 }
      )
    end

    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_or_create_breaker).with('provider_openai').and_return(mock_breaker)
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'opens the circuit breaker' do
        expect(mock_breaker).to receive(:open!)

        post :circuit_breaker_open, params: { service_name: 'provider_openai' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['message']).to include('opened')
      end
    end
  end

  describe 'POST #circuit_breaker_close' do
    let(:mock_breaker) do
      double('Monitoring::CircuitBreaker',
        close!: true,
        stats: { state: 'closed', failure_count: 0 }
      )
    end

    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_or_create_breaker).with('provider_openai').and_return(mock_breaker)
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'closes the circuit breaker' do
        expect(mock_breaker).to receive(:close!)

        post :circuit_breaker_close, params: { service_name: 'provider_openai' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['message']).to include('closed')
      end
    end
  end

  describe 'POST #circuit_breakers_reset_all' do
    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:reset_all!)
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:health_summary).and_return({
        total: 5,
        healthy: 5,
        degraded: 0,
        unhealthy: 0
      })
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'resets all circuit breakers' do
        expect(Ai::WorkflowCircuitBreakerManager).to receive(:reset_all!)

        post :circuit_breakers_reset_all

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to include('All circuit breakers reset')
      end

      it 'returns updated summary' do
        post :circuit_breakers_reset_all

        json = JSON.parse(response.body)
        expect(json['data']['summary']).to be_present
      end
    end
  end

  describe 'GET #circuit_breakers_category' do
    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:category_states).with('providers').and_return([
        { name: 'provider_openai', state: 'closed' },
        { name: 'provider_anthropic', state: 'closed' }
      ])
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'returns circuit breakers for category' do
        get :circuit_breakers_category, params: { category: 'providers' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['category']).to eq('providers')
        expect(json['data']['circuit_breakers'].length).to eq(2)
        expect(json['data']['count']).to eq(2)
      end
    end
  end

  describe 'POST #circuit_breakers_category_reset' do
    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:reset_category!)
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:category_states).with('providers').and_return([])
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'resets circuit breakers in category' do
        expect(Ai::WorkflowCircuitBreakerManager).to receive(:reset_category!).with('providers')

        post :circuit_breakers_category_reset, params: { category: 'providers' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['message']).to include('reset for category: providers')
      end
    end
  end

  describe 'GET #circuit_breakers_monitor' do
    before do
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:monitor_and_alert).and_return({
        total: 5,
        healthy: 4,
        degraded: 1,
        unhealthy: 0
      })
    end

    context 'with valid permissions' do
      before { sign_in monitoring_read_user }

      it 'monitors circuit breakers and returns alerts' do
        expect(Ai::WorkflowCircuitBreakerManager).to receive(:monitor_and_alert)

        get :circuit_breakers_monitor

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['summary']).to be_present
        expect(json['data']['alerts_triggered']).to be true
      end

      it 'indicates when no alerts triggered' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:monitor_and_alert).and_return({
          total: 5,
          healthy: 5,
          degraded: 0,
          unhealthy: 0
        })

        get :circuit_breakers_monitor

        json = JSON.parse(response.body)
        expect(json['data']['alerts_triggered']).to be false
      end
    end
  end

  # =============================================================================
  # REAL-TIME MONITORING
  # =============================================================================

  describe 'POST #broadcast_metrics' do
    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'broadcasts metrics via WebSocket' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "ai_orchestration_#{account.id}",
          hash_including(type: 'system_metrics_update')
        )

        post :broadcast_metrics, params: { account_id: account.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to include('broadcasted successfully')
      end

      it 'returns error when account not found' do
        post :broadcast_metrics, params: { account_id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Account not found')
      end

      it 'returns error when account_id missing' do
        post :broadcast_metrics

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Missing account_id')
      end
    end
  end

  describe 'POST #start_monitoring' do
    before do
      allow(Ai::MonitoringHealthCheckJob).to receive(:perform_later)
    end

    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'starts real-time monitoring' do
        expect(Ai::MonitoringHealthCheckJob).to receive(:perform_later).with(account.id)

        post :start_monitoring

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to include('monitoring started')
      end

      it 'handles job scheduling errors' do
        allow(Ai::MonitoringHealthCheckJob).to receive(:perform_later).and_raise(StandardError, 'Job scheduling failed')

        post :start_monitoring

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Failed to start monitoring')
      end
    end
  end

  describe 'POST #stop_monitoring' do
    context 'with valid permissions' do
      before { sign_in monitoring_manage_user }

      it 'stops monitoring' do
        post :stop_monitoring

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['message']).to include('stop requested')
      end
    end
  end

  # =============================================================================
  # WORKER CONTEXT
  # =============================================================================

  describe 'worker authentication' do
    before do
      # Set WORKER_TOKEN environment variable for worker authentication
      ENV['WORKER_TOKEN'] = worker.auth_token
      @request.headers['X-Worker-Token'] = worker.auth_token
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:all_states).and_return([])
      allow(Ai::WorkflowCircuitBreakerManager).to receive(:health_summary).and_return({ total: 0 })
    end

    after do
      # Clean up environment variable
      ENV.delete('WORKER_TOKEN')
    end

    it 'allows workers to access monitoring endpoints' do
      get :circuit_breakers_index

      expect(response).to have_http_status(:success)
    end

    it 'bypasses permission checks for workers' do
      get :dashboard

      expect(response).to have_http_status(:success)
    end
  end
end
