# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Maintenance', type: :request do
  let(:account) { create(:account) }
  let(:user_with_maintenance_permission) { create(:user, account: account, permissions: [ 'admin.maintenance.mode', 'system.admin' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin/maintenance/mode' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    context 'with admin.maintenance.mode permission' do
      it 'returns maintenance mode status' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('enabled')
      end

      it 'includes maintenance message' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        data = json_response_data
        expect(data).to have_key('message')
      end

      it 'includes bypass_ips' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        data = json_response_data
        expect(data).to have_key('bypass_ips')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/maintenance/mode', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/mode' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    before do
      # Reset maintenance mode before each test. Admin::MaintenanceMode.disable!
      # is the real store write (not a config attribute) — no rescue needed,
      # it cannot raise for a fresh/never-enabled store.
      Admin::MaintenanceMode.disable!
    end

    context 'with admin.maintenance.mode permission' do
      it 'enables maintenance mode and writes a real audit row' do
        expect {
          post '/api/v1/admin/maintenance/mode',
               params: { enabled: true, message: 'Scheduled maintenance' },
               headers: headers,
               as: :json
        }.to change(AuditLog, :count).by(1)

        expect_success_response
        data = json_response_data

        expect(data['enabled']).to be true
        expect(AuditLog.last.action).to eq('maintenance_mode_enabled')
      end

      it 'disables maintenance mode and writes a real audit row' do
        Admin::MaintenanceMode.enable!(message: 'Scheduled maintenance')

        expect {
          post '/api/v1/admin/maintenance/mode',
               params: { enabled: false },
               headers: headers,
               as: :json
        }.to change(AuditLog, :count).by(1)

        expect_success_response
        data = json_response_data

        expect(data['enabled']).to be false
        expect(AuditLog.last.action).to eq('maintenance_mode_disabled')
      end

      it 'accepts estimated_completion parameter as a plain string' do
        post '/api/v1/admin/maintenance/mode',
             params: {
               enabled: true,
               message: 'Upgrading',
               estimated_completion: 1.hour.from_now.iso8601
             },
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response_data['estimated_completion']).to be_a(String)
      end

      it 'requires the enabled param' do
        post '/api/v1/admin/maintenance/mode', params: { message: 'Upgrading' }, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it 'rejects an invalid bypass IP with 422' do
        post '/api/v1/admin/maintenance/mode',
             params: { enabled: true, message: 'Upgrading', bypass_ips: [ 'not-an-ip' ] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'a legacy AdminSetting row under the OLD "maintenance_mode" key' do
    # Regression guard for the migration in
    # db/migrate/20260924020000_delete_legacy_maintenance_mode_admin_settings.rb:
    # Admin::MaintenanceMode reads a FRESH key namespace ("maintenance.enabled"
    # etc), so a leftover row from either of the two dead writers this replaced
    # must never switch maintenance on.
    it 'is never read by Admin::MaintenanceMode.enabled?' do
      AdminSetting.create!(key: 'maintenance_mode', value: 'true')

      expect(Admin::MaintenanceMode.enabled?).to be false
    end
  end

  describe 'GET /api/v1/admin/maintenance/status' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns system status' do
      get '/api/v1/admin/maintenance/status', headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data).to have_key('maintenance_mode')
      expect(data).to have_key('database_status')
    end

    # fc-47 review M1: the statuses come from Platform::Health::CoreChecks.
    # The Sidekiq one used Sidekiq::Stats, which this Sidekiq-free app cannot
    # load, so it always rescued to "unavailable".
    it 'reads database, redis and sidekiq through the shared core checks' do
      allow(Platform::Health::CoreChecks).to receive(:all).with(only: %i[database redis sidekiq]).and_return(
        database: { status: 'healthy' }, redis: { status: 'unhealthy', error_class: 'Redis::CannotConnectError' },
        sidekiq: { status: 'healthy', processes: 1 }
      )

      get '/api/v1/admin/maintenance/status', headers: headers, as: :json

      expect(json_response_data).to include(
        'database_status' => 'connected', 'redis_status' => 'unavailable', 'sidekiq_status' => 'running'
      )
    end

    it 'reports a stopped worker as stopped and an unreadable one as unavailable' do
      allow(Platform::Health::CoreChecks).to receive(:all).and_return(
        database: { status: 'unhealthy' }, redis: { status: 'healthy' }, sidekiq: { status: 'unhealthy', processes: 0 }
      )
      get '/api/v1/admin/maintenance/status', headers: headers, as: :json
      expect(json_response_data).to include('database_status' => 'disconnected', 'sidekiq_status' => 'stopped')

      allow(Platform::Health::CoreChecks).to receive(:all).and_return(
        database: { status: 'healthy' }, redis: { status: 'healthy' }, sidekiq: { status: 'unknown' }
      )
      get '/api/v1/admin/maintenance/status', headers: headers, as: :json
      expect(json_response_data).to include('sidekiq_status' => 'unavailable')
    end
  end

  describe 'GET /api/v1/admin/maintenance/health' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns overall health status' do
      get '/api/v1/admin/maintenance/health', headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data).to have_key('overall_status')
      expect(data).to have_key('checks')
    end

    it 'includes database health check' do
      get '/api/v1/admin/maintenance/health', headers: headers, as: :json

      data = json_response_data
      expect(data['checks']).to have_key('database')
    end
  end

  describe 'GET /api/v1/admin/maintenance/backups' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns list of backups' do
      get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin/maintenance/cleanup/stats' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    # Hits the real DataManagement::CleanupService (read-only). The controller
    # previously referenced a non-existent `DataCleanupService` constant, which
    # this spec masked by stub_const-ing it into existence — so production 500'd
    # with NameError while the spec stayed green.
    it 'returns cleanup statistics' do
      get '/api/v1/admin/maintenance/cleanup/stats', headers: headers, as: :json

      expect_success_response
      expect(json_response_data).to include('audit_logs', 'sessions', 'database')
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

    it 'returns list of maintenance tasks' do
      allow(ScheduledTaskService).to receive(:list_tasks).and_return([])

      get '/api/v1/admin/maintenance/tasks', headers: headers, as: :json

      expect_success_response
    end
  end
end
