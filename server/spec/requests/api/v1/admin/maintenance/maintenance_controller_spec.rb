# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Maintenance::MaintenanceController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'admin.maintenance.mode' ]) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  before do
    # Reset maintenance mode before each test
    Rails.application.config.maintenance_mode = false

    # Stub non-existent classes that the controller references
    unless defined?(DataCleanupService)
      stub_const('DataCleanupService', Class.new do
        def self.get_cleanup_stats = { total_records: 0, cleanable_records: 0 }
        def self.cleanup_audit_logs(_days) = { deleted: 0 }
        def self.cleanup_expired_sessions = { deleted: 0 }
        def self.cleanup_temp_files = { deleted: 0 }
        def self.clear_application_cache = { cleared: true }
      end)
    end

    unless defined?(Database::Backup)
      stub_const('Database::Backup', Class.new do
        def self.order(*) = self
        def self.first = nil
        def self.limit(*) = []
        def self.map(&) = []
      end)
    end
  end

  describe 'GET /api/v1/admin/maintenance/mode' do
    context 'with admin maintenance permission' do
      it 'returns maintenance mode status' do
        get '/api/v1/admin/maintenance/mode', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'enabled' => false,
          'message' => kind_of(String)
        )
        expect(data).to have_key('enabled_at')
        expect(data).to have_key('estimated_completion')
        expect(data).to have_key('bypass_ips')
      end
    end

    context 'without admin maintenance permission' do
      it 'returns forbidden error' do
        get '/api/v1/admin/maintenance/mode', headers: non_admin_headers, as: :json

        expect_error_response('Permission denied: requires admin maintenance permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/mode' do
    before do
      # Stub AuditLog.create! since enable/disable_maintenance_mode creates audit logs
      # that may fail due to current_account being nil in test context
      allow(AuditLog).to receive(:create!).and_return(true)
    end

    context 'enabling maintenance mode' do
      it 'enables maintenance mode successfully' do
        post '/api/v1/admin/maintenance/mode',
            params: {
              enabled: true,
              message: 'System upgrade in progress',
              estimated_completion: '2025-01-25T12:00:00Z',
              bypass_ips: [ '127.0.0.1' ]
            },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['enabled']).to be true
        expect(data['message']).to eq('System upgrade in progress')
      end
    end

    context 'disabling maintenance mode' do
      before do
        Rails.application.config.maintenance_mode = true
      end

      it 'disables maintenance mode successfully' do
        post '/api/v1/admin/maintenance/mode',
            params: { enabled: false },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['enabled']).to be false
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/backups' do
    context 'with admin maintenance permission' do
      it 'returns list of backups' do
        get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

        expect_success_response
      end

      context 'when database backup service fails' do
        before do
          allow(Database::Backup).to receive(:order).and_raise(StandardError.new('Connection failed'))
        end

        it 'returns service unavailable error' do
          get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

          expect(response).to have_http_status(:service_unavailable)
          expect_error_response('Unable to retrieve database backups')
        end
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/tasks' do
    context 'with admin maintenance permission' do
      it 'returns list of scheduled tasks' do
        allow(ScheduledTaskService).to receive(:list_tasks).and_return([
          { id: '1', name: 'Daily Backup', enabled: true }
        ])

        get '/api/v1/admin/maintenance/tasks', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/tasks' do
    context 'with admin maintenance permission' do
      it 'creates a new scheduled task' do
        allow(ScheduledTaskService).to receive(:create_task).and_return(
          { success: true, task: { id: '2', name: 'Weekly Cleanup' } }
        )

        post '/api/v1/admin/maintenance/tasks',
             params: {
               task: {
                 name: 'Weekly Cleanup',
                 description: 'Clean up old data',
                 cron_schedule: '0 0 * * 0',
                 enabled: true,
                 command: 'cleanup',
                 type: 'maintenance'
               }
             },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'returns error when creation fails' do
        allow(ScheduledTaskService).to receive(:create_task).and_return(
          { success: false, error: 'Invalid cron schedule' }
        )

        post '/api/v1/admin/maintenance/tasks',
             params: {
               task: {
                 name: 'Bad Task',
                 cron_schedule: 'invalid'
               }
             },
             headers: headers,
             as: :json

        expect_error_response('Invalid cron schedule', 422)
      end
    end
  end

  describe 'PATCH /api/v1/admin/maintenance/tasks/:id' do
    context 'with admin maintenance permission' do
      it 'updates a scheduled task' do
        allow(ScheduledTaskService).to receive(:update_task).and_return(
          { success: true, task: { id: '1', name: 'Updated Task' } }
        )

        patch '/api/v1/admin/maintenance/tasks/1',
            params: {
              task: {
                name: 'Updated Task',
                enabled: false
              }
            },
            headers: headers,
            as: :json

        expect_success_response
      end
    end
  end

  describe 'DELETE /api/v1/admin/maintenance/tasks/:id' do
    context 'with admin maintenance permission' do
      it 'deletes a scheduled task' do
        allow(ScheduledTaskService).to receive(:delete_task).and_return(
          { success: true }
        )

        delete '/api/v1/admin/maintenance/tasks/1', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/tasks/:id/execute' do
    context 'with admin maintenance permission' do
      it 'executes a scheduled task' do
        allow(ScheduledTaskService).to receive(:execute_task).and_return(
          { success: true, execution: { id: 'exec-1', status: 'running' } }
        )

        post '/api/v1/admin/maintenance/tasks/1/execute', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/status' do
    context 'with admin maintenance permission' do
      it 'returns overall maintenance status' do
        get '/api/v1/admin/maintenance/status', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'maintenance_mode',
          'database_status'
        )
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/health' do
    context 'with admin maintenance permission' do
      it 'returns health check results' do
        get '/api/v1/admin/maintenance/health', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'overall_status',
          'checks',
          'timestamp'
        )
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/metrics' do
    context 'with admin maintenance permission' do
      it 'returns system metrics' do
        get '/api/v1/admin/maintenance/metrics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'database',
          'cache',
          'background_jobs',
          'storage'
        )
      end
    end
  end
end
