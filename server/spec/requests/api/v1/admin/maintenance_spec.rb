# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Maintenance', type: :request do
  let(:account) { create(:account) }
  let(:user_with_maintenance_permission) { create(:user, account: account, permissions: ['admin.maintenance.mode', 'system.admin']) }
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
      # Stub AuditLog.create! since enable/disable_maintenance_mode creates audit logs
      # that may fail due to current_account being nil in test context
      allow(AuditLog).to receive(:create!).and_return(true)
      # Reset maintenance mode before each test
      Rails.application.config.maintenance_mode = false rescue nil
    end

    context 'with admin.maintenance.mode permission' do
      it 'enables maintenance mode' do
        post '/api/v1/admin/maintenance/mode',
             params: { enabled: true, message: 'Scheduled maintenance' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data['enabled']).to be true
      end

      it 'disables maintenance mode' do
        post '/api/v1/admin/maintenance/mode',
             params: { enabled: false },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data['enabled']).to be false
      end

      it 'accepts estimated_completion parameter' do
        post '/api/v1/admin/maintenance/mode',
             params: {
               enabled: true,
               message: 'Upgrading',
               estimated_completion: 1.hour.from_now.iso8601
             },
             headers: headers,
             as: :json

        expect_success_response
      end
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

  describe 'GET /api/v1/admin/maintenance/health/detailed' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns detailed health information' do
      allow(System::HealthService).to receive(:check_detailed_health).and_return(
        { database: 'healthy', redis: 'healthy', sidekiq: 'healthy' }
      )

      get '/api/v1/admin/maintenance/health/detailed', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin/maintenance/metrics' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    it 'returns system metrics' do
      get '/api/v1/admin/maintenance/metrics', headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data).to have_key('database')
      expect(data).to have_key('background_jobs')
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
      allow(System::DatabaseBackupService).to receive(:create_backup).and_return(
        { job_id: SecureRandom.uuid, status: 'pending' }
      )

      post '/api/v1/admin/maintenance/backups',
           params: { type: 'full', description: 'Manual backup' },
           headers: headers,
           as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin/maintenance/cleanup/stats' do
    let(:headers) { auth_headers_for(user_with_maintenance_permission) }

    before do
      stub_const('DataCleanupService', Class.new do
        def self.get_cleanup_stats
          { total_records: 1000, cleanable_records: 100 }
        end
      end)
    end

    it 'returns cleanup statistics' do
      get '/api/v1/admin/maintenance/cleanup/stats', headers: headers, as: :json

      expect_success_response
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
