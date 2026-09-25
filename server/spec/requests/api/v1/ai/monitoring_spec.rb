# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Monitoring', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.monitoring.read', 'ai.monitoring.manage' ]) }
  let(:limited_user) { create(:user, account: account, permissions: [ 'ai.monitoring.read' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  # fc-42 review item 0: the specs above use the `permissions:` factory trait,
  # which mints an AD-HOC role holding exactly those literal strings — it never
  # exercises whether a REAL, catalog-synced role (Role.sync_from_config!,
  # from Permissions.permissions_for_role) actually grants ai.monitoring.read/
  # .manage. That question was live: ai.monitoring.read/.manage are generated
  # by the `resource :monitoring, actions: %i[read manage]` DSL call in
  # permissions.rb (namespace "ai"), not a literal hash entry — the kind of
  # permission a plain grep for the string misses (fc-40 precedent). Verified
  # via Permissions.permission_exists?/permissions_for_role before writing
  # this: both exist, granted to exactly admin/ai_specialist/manager/owner —
  # the same roster that holds ai.analytics.read — so no permissions.rb change
  # was needed. This spec proves it end-to-end through a REAL "manager" role
  # rather than re-deriving the same conclusion by reading the DSL.
  describe 'a non-admin ROLE (not an ad-hoc permission list) reaching Observability endpoints' do
    let(:manager) { create(:user, :manager, account: account) }
    let(:manager_headers) { auth_headers_for(manager) }

    it 'GET /ai/monitoring/dashboard returns 200 for a manager, the same roster ai.analytics.read grants to' do
      allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard).and_return({})

      get '/api/v1/ai/monitoring/dashboard', headers: manager_headers, as: :json

      expect_success_response
    end

    it 'POST /ai/monitoring/circuit_breakers/:service_name/reset (ai.monitoring.manage) returns 200 for a manager' do
      post '/api/v1/ai/monitoring/circuit_breakers/openai/reset', headers: manager_headers, as: :json

      expect_success_response
    end
  end

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
        user_without_permissions = create(:user, account: account, permissions: [])
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

      # E7b, the SECOND call site of the deleted concern method. The lead's
      # brief named `get_system_overview`; `check_system_health` called it too,
      # and that one reaches the wire through collect_component_metrics("system")
      # on THIS endpoint. Deliberately unstubbed, so the real concern runs.
      it 'returns the system component checks with no rival status string' do
        get '/api/v1/ai/monitoring/metrics?components=system', headers: headers, as: :json

        expect_success_response
        system_metrics = json_response_data['metrics']['system']
        expect(system_metrics['health']).to be_present
        expect(system_metrics['health']).to have_key('components')
        expect(system_metrics['health']).not_to have_key('status')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/overview' do
    context 'with proper permissions' do
      before do
        allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_system_overview)
          .and_return({ total_requests: 1000 })
      end

      # E7: the rollup is not stubbed. The whole point of deleting the rival
      # producer is that this number now comes from Platform::ComponentStatus
      # rows, so the oracle reads real rows through the real Query and Rollup.
      it 'answers with the status-plane rollup, computed from the account rows' do
        create(:platform_component_status, account: account, verdict: 'ok')
        create(:platform_component_status, :degraded, account: account)

        get '/api/v1/ai/monitoring/overview', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['overview']).to be_present
        expect(data['rollup']['verdict']).to eq('degraded')
        expect(data['rollup']['total']).to eq(2)
        expect(data['rollup']['counts_by_verdict']).to include('ok' => 1, 'degraded' => 1)
      end

      # The OTHER arm of the same oracle. A rollup that appears while the old
      # keys also survive is the two-rival-producers defect E7 exists to remove,
      # and it would pass every assertion above.
      it 'no longer answers with the deleted health score or its derived status' do
        create(:platform_component_status, :down, account: account)

        get '/api/v1/ai/monitoring/overview', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).not_to have_key('health_score')
        expect(data).not_to have_key('health_status')
        expect(data['rollup']['verdict']).to eq('down')
      end

      # Shared rows are split out, never summed in: one process-wide breaker
      # must not read as this tenant's outage.
      it 'keeps a shared row out of the account verdict' do
        create(:platform_component_status, account: account, verdict: 'ok')
        create(:platform_component_status, :shared, :down)

        get '/api/v1/ai/monitoring/overview', headers: headers, as: :json

        data = json_response_data
        expect(data['rollup']['verdict']).to eq('ok')
        expect(data['shared']['verdict']).to eq('down')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/health' do
    context 'with proper permissions' do
      # E7b: the service is stubbed with MEASUREMENTS ONLY, which is the whole
      # claim — after this increment it has no verdict of its own to return.
      before do
        allow_any_instance_of(Ai::MonitoringHealthService).to receive(:comprehensive_health_check)
          .and_return({ database: { status: 'healthy' }, redis: { status: 'healthy' } })
      end

      it 'answers with the status-plane rollup beside the measurements' do
        create(:platform_component_status, :degraded, account: account)

        get '/api/v1/ai/monitoring/health', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['database']['status']).to eq('healthy')
        expect(data['rollup']['verdict']).to eq('degraded')
      end

      it 'no longer answers with a health score or a service-derived status' do
        create(:platform_component_status, account: account, verdict: 'ok')

        get '/api/v1/ai/monitoring/health', headers: headers, as: :json

        data = json_response_data
        expect(data).not_to have_key('health_score')
        expect(data).not_to have_key('status')
        expect(data['rollup']['verdict']).to eq('ok')
      end

      # E7 review low 1. The audit row carries the verdict and the per-verdict
      # counts UNDER METADATA. Passed as bare keywords they were dropped without
      # a word: AuditLog.log_action keeps metadata and a few named columns, and
      # nothing else.
      it 'audits the check with the rollup verdict and counts_by_verdict' do
        create(:platform_component_status, :degraded, account: account)

        get '/api/v1/ai/monitoring/health', headers: headers, as: :json

        row = AuditLog.where(action: 'ai.monitoring.health_check', account_id: account.id).sole
        expect(row.metadata).to include('verdict' => 'degraded')
        expect(row.metadata['counts_by_verdict']).to include('degraded' => 1)
        expect(row.metadata).not_to have_key('unhealthy_components')
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

  describe 'alert acknowledge / resolve' do
    let(:manager) { create(:user, account: account, permissions: [ 'ai.monitoring.read', 'ai.aiops.manage' ]) }
    let(:manager_headers) { auth_headers_for(manager) }
    let(:other_account) { create(:account) }
    let(:redis) { Powernode::Redis.client }

    let(:seed_score) { 1_780_000_000 }

    def seed_alert(owner, id: SecureRandom.uuid, **state)
      redis.zadd("alerts:#{owner.id}", seed_score, {
        id: id, alert_type: 'high_latency', severity: 'medium', message: 'Alert triggered: High latency',
        timestamp: Time.current.iso8601, account_id: owner.id, acknowledged: false, resolved: false
      }.merge(state).to_json)
      id
    end

    def stored_score(owner)
      redis.zrange("alerts:#{owner.id}", 0, -1, with_scores: true).first&.last
    end

    def stored_alert(owner, id)
      redis.zrange("alerts:#{owner.id}", 0, -1).map { |raw| JSON.parse(raw) }.find { |a| a['id'] == id }
    end

    after do
      redis.del("alerts:#{account.id}", "alerts:#{other_account.id}")
    end

    describe 'POST /api/v1/ai/monitoring/alerts/:id/acknowledge' do
      it 'acknowledges the alert, records who and why, and persists it' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", params: { note: 'looking' }, headers: manager_headers, as: :json

        expect_success_response
        alert = json_response_data['alert']
        expect(alert).to include('id' => id, 'acknowledged' => true, 'acknowledged_by' => manager.id, 'acknowledgement_note' => 'looking')
        expect(alert['acknowledged_at']).to be_present
        expect(stored_alert(account, id)).to include('acknowledged' => true, 'resolved' => false)
        expect(redis.zcard("alerts:#{account.id}")).to eq(1)
        expect(stored_score(account)).to eq(seed_score)
      end

      it 'is forbidden without ai.aiops.manage and leaves the alert untouched' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", headers: limited_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('ai.aiops.manage')
        expect(stored_alert(account, id)['acknowledged']).to be false
      end

      it 'is forbidden to a worker principal even when its role grants ai.aiops.manage' do
        worker = create(:worker, account: account, status: 'active')
        role = Role.create!(name: 'aiops_alert_worker', display_name: 'AIOps alert worker', role_type: 'user', description: 'grants ai.aiops.manage')
        role.role_permissions.create!(permission_name: 'ai.aiops.manage')
        worker.worker_roles.create!(role: role)
        expect(worker.reload.has_permission?('ai.aiops.manage')).to be true
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", headers: {
          'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
          'Content-Type' => 'application/json'
        }

        expect(response).to have_http_status(:forbidden)
        expect(stored_alert(account, id)['acknowledged']).to be false
      end

      it 'rejects a non-string note with 422 and leaves the alert untouched' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", params: { note: { text: 'x' } }, headers: manager_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(stored_alert(account, id)['acknowledged']).to be false
      end

      it 'rejects a note over 1000 characters with 422 and leaves the alert untouched' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", params: { note: 'x' * 1001 }, headers: manager_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(stored_alert(account, id)['acknowledged']).to be false
      end

      it 'refuses to re-acknowledge an acknowledged alert and keeps the first actor' do
        id = seed_alert(account, acknowledged: true, acknowledged_by: 'first-actor')

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", headers: manager_headers, as: :json

        expect(response).to have_http_status(:conflict)
        expect(json_response['error']).to eq('Alert already acknowledged')
        expect(stored_alert(account, id)['acknowledged_by']).to eq('first-actor')
      end

      it 'returns 409, not 404, when every compare-and-set attempt loses a race' do
        id = seed_alert(account)
        allow(Powernode::Redis.client).to receive(:eval).and_return(0)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", headers: manager_headers, as: :json

        expect(response).to have_http_status(:conflict)
        expect(Powernode::Redis.client).to have_received(:eval).exactly(3).times
      end

      it "returns not found for another account's alert and leaves it untouched" do
        id = seed_alert(other_account)

        post "/api/v1/ai/monitoring/alerts/#{id}/acknowledge", headers: manager_headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Alert not found')
        expect(stored_alert(other_account, id)['acknowledged']).to be false
      end
    end

    describe 'POST /api/v1/ai/monitoring/alerts/:id/resolve' do
      it 'resolves the alert, records who and why, and persists it' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/resolve", params: { note: 'fixed' }, headers: manager_headers, as: :json

        expect_success_response
        alert = json_response_data['alert']
        expect(alert).to include('id' => id, 'resolved' => true, 'resolved_by' => manager.id, 'resolution_note' => 'fixed')
        expect(alert['resolved_at']).to be_present
        expect(stored_alert(account, id)).to include('resolved' => true)
        expect(redis.zcard("alerts:#{account.id}")).to eq(1)
        expect(stored_score(account)).to eq(seed_score)
      end

      it 'is forbidden without ai.aiops.manage and leaves the alert untouched' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/resolve", headers: limited_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(stored_alert(account, id)['resolved']).to be false
      end

      it "returns not found for another account's alert and leaves it untouched" do
        id = seed_alert(other_account)

        post "/api/v1/ai/monitoring/alerts/#{id}/resolve", headers: manager_headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Alert not found')
        expect(stored_alert(other_account, id)['resolved']).to be false
      end

      it 'resolves an alert that is already acknowledged, keeping the acknowledger' do
        id = seed_alert(account, acknowledged: true, acknowledged_by: 'first-actor')

        post "/api/v1/ai/monitoring/alerts/#{id}/resolve", headers: manager_headers, as: :json

        expect_success_response
        expect(stored_alert(account, id)).to include('resolved' => true, 'acknowledged_by' => 'first-actor', 'resolved_by' => manager.id)
      end

      it 'refuses to re-resolve a resolved alert and keeps the first actor' do
        id = seed_alert(account, acknowledged: true, resolved: true, resolved_by: 'first-actor')

        post "/api/v1/ai/monitoring/alerts/#{id}/resolve", headers: manager_headers, as: :json

        expect(response).to have_http_status(:conflict)
        expect(json_response['error']).to eq('Alert already resolved')
        expect(stored_alert(account, id)['resolved_by']).to eq('first-actor')
      end

      it 'rejects a note over 1000 characters with 422' do
        id = seed_alert(account)

        post "/api/v1/ai/monitoring/alerts/#{id}/resolve", params: { note: 'x' * 1001 }, headers: manager_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(stored_alert(account, id)['resolved']).to be false
      end

      it 'returns not found for an unknown id' do
        post "/api/v1/ai/monitoring/alerts/#{SecureRandom.uuid}/resolve", headers: manager_headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Alert not found')
      end
    end
  end

  describe 'GET /api/v1/ai/monitoring/circuit_breakers' do
    context 'with proper permissions' do
      it 'returns all circuit breaker states' do
        allow(Ai::CircuitBreakerRegistry).to receive(:all_states).and_return([])
        allow(Ai::CircuitBreakerRegistry).to receive(:health_summary)
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
        breaker = double('CircuitBreaker', circuit_stats: { state: 'closed', failure_count: 0 })
        allow(Ai::CircuitBreakerRegistry).to receive(:get_breaker).and_return(breaker)

        get '/api/v1/ai/monitoring/circuit_breakers/test_service', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['service_name']).to eq('test_service')
        expect(data).to have_key('stats')
      end

      it 'returns error for non-existent breaker' do
        allow(Ai::CircuitBreakerRegistry).to receive(:get_breaker).and_return(nil)

        get '/api/v1/ai/monitoring/circuit_breakers/nonexistent', headers: headers, as: :json

        expect_error_response('Circuit breaker not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset' do
    context 'with proper permissions' do
      it 'resets the circuit breaker' do
        breaker = double('CircuitBreaker', reset_circuit!: true, circuit_stats: { state: 'closed' })
        allow(Ai::CircuitBreakerRegistry).to receive(:get_or_create_breaker)
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
        breaker = double('CircuitBreaker', force_open!: true, circuit_stats: { state: 'open' })
        allow(Ai::CircuitBreakerRegistry).to receive(:get_or_create_breaker)
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
        breaker = double('CircuitBreaker', force_close!: true, circuit_stats: { state: 'closed' })
        allow(Ai::CircuitBreakerRegistry).to receive(:get_or_create_breaker)
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
        allow(Ai::CircuitBreakerRegistry).to receive(:reset_all!).and_return(true)
        allow(Ai::CircuitBreakerRegistry).to receive(:health_summary)
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
        allow(Ai::CircuitBreakerRegistry).to receive(:category_states).and_return([])

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
        allow(Ai::CircuitBreakerRegistry).to receive(:reset_category!)
          .with('providers')
          .and_return(true)
        allow(Ai::CircuitBreakerRegistry).to receive(:category_states)
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
        breaker = double('CircuitBreaker', circuit_stats: { state: 'closed', failure_count: 0 })
        allow(Ai::CircuitBreakerRegistry).to receive(:get_breaker)
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

      # `resolve_broadcast_account` deliberately falls back to the CALLER'S OWN
      # account; a supplied account_id is honoured only for holders of
      # ai.analytics.global. Two examples here asserted 400 for a missing
      # account_id and 404 for an unknown one while signing in an actor holding
      # neither permission — both describe a contract this endpoint never had,
      # and both got the fallback's 200.
      context 'account resolution' do
        before do
          allow_any_instance_of(Monitoring::UnifiedService).to receive(:get_dashboard)
            .and_return({ system_status: 'healthy' })
          allow(ActionCable.server).to receive(:broadcast).and_return(true)
        end

        it "falls back to the caller's own account when account_id is omitted" do
          post '/api/v1/ai/monitoring/broadcast', headers: headers, as: :json

          expect_success_response
          expect(json_response_data['account_id']).to eq(account.id)
        end

        # The tenancy control: lacking ai.analytics.global, a supplied account_id
        # must not aim the broadcast at another tenant's channel.
        it "ignores another account's id from a caller without ai.analytics.global" do
          other_account = create(:account)

          post '/api/v1/ai/monitoring/broadcast',
               params: { account_id: other_account.id }.to_json,
               headers: headers

          expect_success_response
          expect(json_response_data['account_id']).to eq(account.id)
          expect(ActionCable.server).to have_received(:broadcast)
            .with("ai_orchestration_#{account.id}", anything)
        end

        context 'as a holder of ai.analytics.global' do
          let(:global_user) do
            create(:user, account: account, permissions: %w[ai.monitoring.manage ai.analytics.global])
          end

          it 'returns not_found for an unknown account_id' do
            post '/api/v1/ai/monitoring/broadcast',
                 params: { account_id: SecureRandom.uuid }.to_json,
                 headers: auth_headers_for(global_user)

            expect(response).to have_http_status(:not_found)
            expect(json_response['success']).to be false
            expect(json_response['error']).to include('not found')
          end
        end
      end
    end
  end

  describe 'POST /api/v1/ai/monitoring/start' do
    context 'with proper permissions' do
      it 'starts real-time monitoring' do
        allow(WorkerJobService).to receive(:enqueue_job).and_return({ 'status' => 'queued' })

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
