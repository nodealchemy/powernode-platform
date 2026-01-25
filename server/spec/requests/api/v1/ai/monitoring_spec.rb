# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Monitoring', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.monitoring.read', 'ai.monitoring.manage']) }
  let(:limited_user) { create(:user, account: account, permissions: ['ai.monitoring.read']) }
  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/ai/monitoring/dashboard' do
    context 'with proper permissions' do
      it 'returns dashboard data' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard)
          .and_return({ system_status: 'healthy', metrics: {} })

        get '/api/v1/ai/monitoring/dashboard', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['dashboard']).to be_present
        expect(data).to have_key('generated_at')
      end

      it 'accepts time range parameter' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard)
          .and_return({})

        get '/api/v1/ai/monitoring/dashboard?time_range=3600', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by components' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard)
          .and_return({})

        get '/api/v1/ai/monitoring/dashboard?components=system,providers', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        user_without_permissions = create(:user, account: account)
        headers_without_permissions = auth_headers_for(user_without_permissions)

        get '/api/v1/ai/monitoring/dashboard', headers: headers_without_permissions, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('ai.monitoring.read')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/metrics' do
    context 'with proper permissions' do
      it 'returns metrics data' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:collect_component_metrics)
          .and_return({ requests: 100, errors: 5 })

        get '/api/v1/ai/monitoring/metrics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['metrics']).to be_present
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/overview' do
    context 'with proper permissions' do
      it 'returns system overview' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_system_overview)
          .and_return({ total_requests: 1000 })
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:calculate_health_score)
          .and_return(95.5)
        allow_any_instance_of(Ai::MonitoringHealthService).to receive(:determine_health_status)
          .and_return('healthy')

        get '/api/v1/ai/monitoring/overview', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['overview']).to be_present
        expect(data).to have_key('health_score')
        expect(data).to have_key('health_status')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/health' do
    context 'with proper permissions' do
      it 'returns comprehensive health check' do
        allow_any_instance_of(Ai::MonitoringHealthService).to receive(:comprehensive_health_check)
          .and_return({ health_score: 95, status: 'healthy', checks: [] })

        get '/api/v1/ai/monitoring/health', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/health/detailed' do
    context 'with proper permissions' do
      it 'returns detailed health information' do
        allow_any_instance_of(Ai::MonitoringHealthService).to receive(:detailed_health)
          .and_return({ components: [], services: [] })

        get '/api/v1/ai/monitoring/health/detailed', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/health/connectivity' do
    context 'with proper permissions' do
      it 'returns connectivity check results' do
        allow_any_instance_of(Ai::MonitoringHealthService).to receive(:connectivity_check)
          .and_return({ database: 'connected', redis: 'connected' })

        get '/api/v1/ai/monitoring/health/connectivity', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/alerts' do
    context 'with proper permissions' do
      it 'returns list of alerts' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts)
          .and_return({ total_alerts: 5, alerts: [] })

        get '/api/v1/ai/monitoring/alerts', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['alerts']).to be_present
      end

      it 'filters by severity' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts)
          .and_return({ total_alerts: 0, alerts: [] })

        get '/api/v1/ai/monitoring/alerts?severity=critical', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by status' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_alerts)
          .and_return({ total_alerts: 0, alerts: [] })

        get '/api/v1/ai/monitoring/alerts?status=active', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/alerts/check' do
    context 'with proper permissions' do
      it 'checks and triggers alerts' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:check_and_trigger_alerts)
          .and_return([])

        post '/api/v1/ai/monitoring/alerts/check', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['alerts_checked']).to be true
        expect(data).to have_key('triggered_alerts')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/circuit_breakers' do
    context 'with proper permissions' do
      it 'returns all circuit breaker states' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:all_states).and_return([])
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:health_summary)
          .and_return({ total: 10, healthy: 8, unhealthy: 2 })

        get '/api/v1/ai/monitoring/circuit_breakers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['circuit_breakers']).to be_an(Array)
        expect(data).to have_key('summary')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/circuit_breakers/:service_name' do
    context 'with proper permissions' do
      it 'returns specific circuit breaker state' do
        breaker = double('CircuitBreaker', stats: { state: 'closed', failure_count: 0 })
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_breaker).and_return(breaker)

        get '/api/v1/ai/monitoring/circuit_breakers/test_service', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['service_name']).to eq('test_service')
        expect(data).to have_key('stats')
      end

      it 'returns error for non-existent breaker' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_breaker).and_return(nil)

        get '/api/v1/ai/monitoring/circuit_breakers/nonexistent', headers: headers, as: :json

        expect_error_response('Circuit breaker not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset' do
    context 'with proper permissions' do
      it 'resets the circuit breaker' do
        breaker = double('CircuitBreaker', reset!: true, stats: { state: 'closed' })
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_or_create_breaker)
          .with('test_service')
          .and_return(breaker)

        post '/api/v1/ai/monitoring/circuit_breakers/test_service/reset', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['service_name']).to eq('test_service')
        expect(data).to have_key('state')
      end
    end

    context 'without manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/monitoring/circuit_breakers/test_service/reset',
             headers: limited_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('ai.monitoring.manage')
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/circuit_breakers/:service_name/open' do
    context 'with proper permissions' do
      it 'opens the circuit breaker' do
        breaker = double('CircuitBreaker', open!: true, stats: { state: 'open' })
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_or_create_breaker)
          .with('test_service')
          .and_return(breaker)

        post '/api/v1/ai/monitoring/circuit_breakers/test_service/open', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['service_name']).to eq('test_service')
        expect(data).to have_key('state')
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/circuit_breakers/:service_name/close' do
    context 'with proper permissions' do
      it 'closes the circuit breaker' do
        breaker = double('CircuitBreaker', close!: true, stats: { state: 'closed' })
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_or_create_breaker)
          .with('test_service')
          .and_return(breaker)

        post '/api/v1/ai/monitoring/circuit_breakers/test_service/close', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['service_name']).to eq('test_service')
        expect(data).to have_key('state')
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/circuit_breakers/reset_all' do
    context 'with proper permissions' do
      it 'resets all circuit breakers' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:reset_all!).and_return(true)
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:health_summary)
          .and_return({ total: 5, healthy: 5, unhealthy: 0 })

        post '/api/v1/ai/monitoring/circuit_breakers/reset_all', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('summary')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/circuit_breakers/category/:category' do
    context 'with proper permissions' do
      it 'returns circuit breakers for category' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:category_states).and_return([])

        get '/api/v1/ai/monitoring/circuit_breakers/category/providers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']).to eq('providers')
        expect(data['circuit_breakers']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/circuit_breakers/category/:category/reset' do
    context 'with proper permissions' do
      it 'resets circuit breakers in category' do
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:reset_category!)
          .with('providers')
          .and_return(true)
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:category_states)
          .with('providers')
          .and_return([])

        post '/api/v1/ai/monitoring/circuit_breakers/category/providers/reset',
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']).to eq('providers')
        expect(data).to have_key('circuit_breakers')
      end
    end
  end

  # NOTE: Due to route ordering, /circuit_breakers/monitor is matched by
  # /circuit_breakers/:service_name before the explicit monitor route.
  # This test validates the current behavior (circuit_breaker_show with service_name='monitor').
  # The route ordering in routes.rb should ideally be fixed to put specific routes first.
  describe 'GET /api/v1/ai/monitoring/circuit_breakers/monitor' do
    context 'with proper permissions' do
      it 'returns monitoring data for monitor service' do
        breaker = double('CircuitBreaker', stats: { state: 'closed', failure_count: 0 })
        allow(Ai::WorkflowCircuitBreakerManager).to receive(:get_breaker)
          .with('monitor')
          .and_return(breaker)

        get '/api/v1/ai/monitoring/circuit_breakers/monitor', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['service_name']).to eq('monitor')
        expect(data).to have_key('stats')
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/broadcast' do
    context 'with proper permissions' do
      it 'broadcasts metrics to account channel' do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard)
          .and_return({ system_status: 'healthy' })
        allow(ActionCable.server).to receive(:broadcast).and_return(true)

        post '/api/v1/ai/monitoring/broadcast',
             params: { account_id: account.id }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data['account_id']).to eq(account.id)
        expect(data).to have_key('timestamp')
      end

      it 'returns error for missing account_id' do
        post '/api/v1/ai/monitoring/broadcast', headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('account_id')
      end

      it 'returns error for invalid account' do
        post '/api/v1/ai/monitoring/broadcast',
             params: { account_id: SecureRandom.uuid }.to_json,
             headers: headers

        expect(response).to have_http_status(:not_found)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('not found')
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/start' do
    context 'with proper permissions' do
      it 'starts real-time monitoring' do
        allow(Ai::MonitoringHealthCheckJob).to receive(:perform_later)
          .with(user.account_id)
          .and_return(true)

        post '/api/v1/ai/monitoring/start', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['account_id']).to eq(user.account_id)
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/stop' do
    context 'with proper permissions' do
      it 'stops real-time monitoring' do
        post '/api/v1/ai/monitoring/stop', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['account_id']).to eq(user.account_id)
        expect(data).to have_key('timestamp')
      end
    end
  end
end
