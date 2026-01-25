# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Maintenance', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_maintenance_permission) { create(:user, account: account, permissions: ['admin.maintenance.mode']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin/maintenance/mode' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    context 'with admin.maintenance.mode permission' do
      it 'returns maintenance mode status' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('enabled')
      end

      it 'includes maintenance message' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('message')
      end

      it 'includes bypass_ips' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('bypass_ips')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/maintenance/mode', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PUT /api/v1/admin/maintenance/mode' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    context 'with admin.maintenance.mode permission' do
      it 'enables maintenance mode' do
        put '/api/v1/admin/maintenance/mode',
            params: { enabled: true, message: 'Scheduled maintenance' },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['enabled']).to be true
      end

      it 'disables maintenance mode' do
        put '/api/v1/admin/maintenance/mode',
            params: { enabled: false },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['enabled']).to be false
      end

      it 'accepts estimated_completion parameter' do
        put '/api/v1/admin/maintenance/mode',
            params: {
              enabled: true,
              message: 'Upgrading',
              estimated_completion: 1.hour.from_now.iso8601
            },
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'creates audit log for maintenance mode change' do
        expect {
          put '/api/v1/admin/maintenance/mode',
              params: { enabled: true, message: 'Test' },
              headers: headers,
              as: :json
        }.to change(AuditLog, :count).by_at_least(1)
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/system_health' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns system health data' do
      get '/api/v1/admin/maintenance/system_health', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin/maintenance/detailed_health' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns detailed health data' do
      get '/api/v1/admin/maintenance/detailed_health', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/admin/maintenance/trigger_health_check' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'triggers comprehensive health check' do
      post '/api/v1/admin/maintenance/trigger_health_check', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('triggered')
    end
  end

  describe 'GET /api/v1/admin/maintenance/backups' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns list of backups' do
      get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/admin/maintenance/backups' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'creates a database backup' do
      post '/api/v1/admin/maintenance/backups',
           params: { type: 'full', description: 'Manual backup' },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('initiated')
    end
  end

  describe 'GET /api/v1/admin/maintenance/cleanup_stats' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns cleanup statistics' do
      get '/api/v1/admin/maintenance/cleanup_stats', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/admin/maintenance/cleanup_audit_logs' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'cleans up audit logs' do
      post '/api/v1/admin/maintenance/cleanup_audit_logs',
           params: { days_old: 90 },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('cleanup completed')
    end
  end

  describe 'POST /api/v1/admin/maintenance/cleanup_sessions' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'cleans up expired sessions' do
      post '/api/v1/admin/maintenance/cleanup_sessions', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/admin/maintenance/clear_cache' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'clears application cache' do
      post '/api/v1/admin/maintenance/clear_cache', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('cache cleared')
    end
  end

  describe 'GET /api/v1/admin/maintenance/status' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns system status' do
      get '/api/v1/admin/maintenance/status', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('maintenance_mode')
      expect(response_data['data']).to have_key('database_status')
    end
  end

  describe 'GET /api/v1/admin/maintenance/health' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns overall health status' do
      get '/api/v1/admin/maintenance/health', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('overall_status')
      expect(response_data['data']).to have_key('checks')
    end

    it 'includes database health check' do
      get '/api/v1/admin/maintenance/health', headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['checks']).to have_key('database')
    end
  end

  describe 'GET /api/v1/admin/maintenance/metrics' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns system metrics' do
      get '/api/v1/admin/maintenance/metrics', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('database')
      expect(response_data['data']).to have_key('background_jobs')
    end
  end

  describe 'GET /api/v1/admin/maintenance/schedules' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns scheduled tasks' do
      get '/api/v1/admin/maintenance/schedules', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin/maintenance/tasks' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns list of scheduled tasks' do
      get '/api/v1/admin/maintenance/tasks', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin/maintenance/operations' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns available system operations' do
      get '/api/v1/admin/maintenance/operations', headers: headers, as: :json

      expect_success_response
    end
  end
end
