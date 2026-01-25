# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Maintenance::MaintenanceController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.maintenance.mode']) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  before do
    # Reset maintenance mode before each test
    Rails.application.config.maintenance_mode = false
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

  describe 'PUT /api/v1/admin/maintenance/mode' do
    context 'enabling maintenance mode' do
      it 'enables maintenance mode successfully' do
        put '/api/v1/admin/maintenance/mode',
            params: {
              enabled: true,
              message: 'System upgrade in progress',
              estimated_completion: '2025-01-25T12:00:00Z',
              bypass_ips: ['127.0.0.1']
            }.to_json,
            headers: headers

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
        put '/api/v1/admin/maintenance/mode',
            params: { enabled: false }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['enabled']).to be false
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/health/basic' do
    context 'with admin maintenance permission' do
      it 'returns basic health data' do
        allow(System::HealthService).to receive(:check_basic_health).and_return(
          { status: 'healthy', timestamp: Time.current.iso8601 }
        )

        get '/api/v1/admin/maintenance/health/basic', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('status' => 'healthy')
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/health/detailed' do
    context 'with admin maintenance permission' do
      it 'returns detailed health data' do
        allow(System::HealthService).to receive(:check_detailed_health).and_return(
          {
            database: { status: 'healthy' },
            redis: { status: 'healthy' },
            sidekiq: { status: 'healthy' }
          }
        )

        get '/api/v1/admin/maintenance/health/detailed', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('database', 'redis', 'sidekiq')
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/health/trigger' do
    context 'with admin maintenance permission' do
      it 'triggers comprehensive health check' do
        allow(System::HealthService).to receive(:trigger_comprehensive_check)

        post '/api/v1/admin/maintenance/health/trigger', headers: headers, as: :json

        expect_success_response
        expect(System::HealthService).to have_received(:trigger_comprehensive_check)
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/backups' do
    context 'with admin maintenance permission' do
      it 'returns list of backups' do
        allow(System::DatabaseBackupService).to receive(:list_backups).and_return([
          { id: '123', name: 'backup_1', size: 1024, created_at: Time.current.iso8601 }
        ])

        get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/backups' do
    context 'with admin maintenance permission' do
      it 'creates a new backup' do
        backup_job = { job_id: '456', status: 'pending' }
        allow(System::DatabaseBackupService).to receive(:create_backup).and_return(backup_job)

        post '/api/v1/admin/maintenance/backups',
             params: { type: 'full', description: 'Manual backup' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('job_id' => '456')
      end
    end
  end

  describe 'DELETE /api/v1/admin/maintenance/backups/:id' do
    context 'with admin maintenance permission' do
      it 'deletes a backup successfully' do
        allow(System::DatabaseBackupService).to receive(:delete_backup).and_return(
          { success: true }
        )

        delete '/api/v1/admin/maintenance/backups/123', headers: headers, as: :json

        expect_success_response
      end

      it 'returns error when deletion fails' do
        allow(System::DatabaseBackupService).to receive(:delete_backup).and_return(
          { success: false, error: 'Backup not found' }
        )

        delete '/api/v1/admin/maintenance/backups/123', headers: headers, as: :json

        expect_error_response('Backup not found', 422)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/backups/:id/restore' do
    context 'with admin maintenance permission' do
      it 'restores a backup successfully' do
        allow(System::DatabaseBackupService).to receive(:restore_backup).and_return(
          { success: true }
        )

        post '/api/v1/admin/maintenance/backups/123/restore', headers: headers, as: :json

        expect_success_response
      end

      it 'returns error when restore fails' do
        allow(System::DatabaseBackupService).to receive(:restore_backup).and_return(
          { success: false, error: 'Restore failed' }
        )

        post '/api/v1/admin/maintenance/backups/123/restore', headers: headers, as: :json

        expect_error_response('Restore failed', 422)
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/cleanup/stats' do
    context 'with admin maintenance permission' do
      it 'returns cleanup statistics' do
        allow(DataCleanupService).to receive(:get_cleanup_stats).and_return(
          { total_records: 1000, cleanup_candidates: 50 }
        )

        get '/api/v1/admin/maintenance/cleanup/stats', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('total_records', 'cleanup_candidates')
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/cleanup/audit_logs' do
    context 'with admin maintenance permission' do
      it 'cleans up old audit logs' do
        allow(DataCleanupService).to receive(:cleanup_audit_logs).and_return(
          { deleted_count: 100 }
        )

        post '/api/v1/admin/maintenance/cleanup/audit_logs',
             params: { days_old: 90 }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('deleted_count' => 100)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/cleanup/sessions' do
    context 'with admin maintenance permission' do
      it 'cleans up expired sessions' do
        allow(DataCleanupService).to receive(:cleanup_expired_sessions).and_return(
          { deleted_count: 25 }
        )

        post '/api/v1/admin/maintenance/cleanup/sessions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('deleted_count' => 25)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/cleanup/temp_files' do
    context 'with admin maintenance permission' do
      it 'cleans up temporary files' do
        allow(DataCleanupService).to receive(:cleanup_temp_files).and_return(
          { deleted_count: 15, freed_space_mb: 50 }
        )

        post '/api/v1/admin/maintenance/cleanup/temp_files', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('deleted_count', 'freed_space_mb')
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/cleanup/cache' do
    context 'with admin maintenance permission' do
      it 'clears application cache' do
        allow(DataCleanupService).to receive(:clear_application_cache).and_return(
          { cache_cleared: true }
        )

        post '/api/v1/admin/maintenance/cleanup/cache', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('cache_cleared')
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/operations' do
    context 'with admin maintenance permission' do
      it 'returns available operations' do
        allow(System::OperationsService).to receive(:get_available_operations).and_return(
          ['restart_services', 'reindex_database', 'optimize_database']
        )

        get '/api/v1/admin/maintenance/operations', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/operations/restart_services' do
    context 'with admin maintenance permission' do
      it 'restarts specified services' do
        allow(System::OperationsService).to receive(:restart_services).and_return(
          { status: 'initiated', services: ['all'] }
        )

        post '/api/v1/admin/maintenance/operations/restart_services',
             params: { services: ['all'] }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('status' => 'initiated')
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/operations/reindex_database' do
    context 'with admin maintenance permission' do
      it 'initiates database reindexing' do
        allow(System::OperationsService).to receive(:reindex_database).and_return(
          { status: 'initiated' }
        )

        post '/api/v1/admin/maintenance/operations/reindex_database', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('status' => 'initiated')
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/operations/optimize_database' do
    context 'with admin maintenance permission' do
      it 'initiates database optimization' do
        allow(System::OperationsService).to receive(:optimize_database).and_return(
          { status: 'initiated' }
        )

        post '/api/v1/admin/maintenance/operations/optimize_database', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('status' => 'initiated')
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
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data['task']).to include('id', 'name')
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
             }.to_json,
             headers: headers

        expect_error_response('Invalid cron schedule', 422)
      end
    end
  end

  describe 'PUT /api/v1/admin/maintenance/tasks/:id' do
    context 'with admin maintenance permission' do
      it 'updates a scheduled task' do
        allow(ScheduledTaskService).to receive(:update_task).and_return(
          { success: true, task: { id: '1', name: 'Updated Task' } }
        )

        put '/api/v1/admin/maintenance/tasks/1',
            params: {
              task: {
                name: 'Updated Task',
                enabled: false
              }
            }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['task']).to include('id', 'name')
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
        data = json_response_data
        expect(data['execution']).to include('id', 'status')
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
          'database_status',
          'redis_status',
          'sidekiq_status'
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
