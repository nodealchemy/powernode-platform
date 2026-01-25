# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Maintenance', type: :request do
  # Service token authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/maintenance/backups/:id' do
    let(:backup) do
      Database::Backup.create!(
        filename: 'backup_20250124.sql',
        file_path: '/backups/backup_20250124.sql',
        backup_type: 'full',
        status: 'pending',
        description: 'Daily backup',
        database_name: 'powernode_production'
      )
    end

    context 'with service token authentication' do
      it 'returns backup details' do
        get "/api/v1/internal/maintenance/backups/#{backup.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => backup.id,
          'filename' => 'backup_20250124.sql',
          'file_path' => '/backups/backup_20250124.sql',
          'backup_type' => 'full',
          'status' => 'pending',
          'description' => 'Daily backup',
          'database_name' => 'powernode_production'
        )
      end

      it 'includes all backup fields' do
        get "/api/v1/internal/maintenance/backups/#{backup.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        expect(response_data['data']).to include(
          'id', 'filename', 'file_path', 'backup_type', 'status',
          'description', 'file_size', 'database_name', 'metadata',
          'user_id', 'started_at', 'completed_at', 'created_at'
        )
      end
    end

    context 'when backup does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/maintenance/backups/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Backup not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/maintenance/backups/#{backup.id}", as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/maintenance/backups/:id' do
    let(:backup) do
      Database::Backup.create!(
        filename: 'backup_20250124.sql',
        file_path: '/backups/backup_20250124.sql',
        backup_type: 'full',
        status: 'pending',
        database_name: 'powernode_production'
      )
    end

    context 'with service token authentication' do
      it 'updates backup status to in_progress' do
        patch "/api/v1/internal/maintenance/backups/#{backup.id}",
              params: { status: 'in_progress' },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'status' => 'in_progress'
        )

        backup.reload
        expect(backup.status).to eq('in_progress')
        expect(backup.started_at).to be_present
      end

      it 'updates backup status to completed with file details' do
        patch "/api/v1/internal/maintenance/backups/#{backup.id}",
              params: {
                status: 'completed',
                file_path: '/backups/completed_backup.sql',
                file_size: 1024000,
                duration_seconds: 45,
                checksum: 'abc123def456'
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        backup.reload
        expect(backup.status).to eq('completed')
        expect(backup.completed_at).to be_present
        expect(backup.file_path).to eq('/backups/completed_backup.sql')
        expect(backup.file_size).to eq(1024000)
        expect(backup.duration_seconds).to eq(45)
        expect(backup.checksum).to eq('abc123def456')
      end

      it 'updates backup status to failed with error message' do
        patch "/api/v1/internal/maintenance/backups/#{backup.id}",
              params: {
                status: 'failed',
                error_message: 'Database connection timeout',
                duration_seconds: 120
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        backup.reload
        expect(backup.status).to eq('failed')
        expect(backup.completed_at).to be_present
        expect(backup.error_message).to eq('Database connection timeout')
        expect(backup.duration_seconds).to eq(120)
      end
    end

    context 'when backup does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/maintenance/backups/nonexistent-id',
              params: { status: 'completed' },
              headers: internal_headers,
              as: :json

        expect_error_response('Backup not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/maintenance/backups/#{backup.id}",
              params: { status: 'completed' },
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'GET /api/v1/internal/maintenance/restores/:id' do
    let(:backup) { create(:database_backup) }
    let(:restore) do
      Database::Restore.create!(
        database_backup: backup,
        status: 'pending',
        restore_type: 'full',
        target_database: 'powernode_test'
      )
    end

    context 'with service token authentication' do
      it 'returns restore details' do
        get "/api/v1/internal/maintenance/restores/#{restore.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => restore.id,
          'database_backup_id' => backup.id,
          'status' => 'pending',
          'restore_type' => 'full',
          'target_database' => 'powernode_test'
        )
      end

      it 'includes backup file path' do
        get "/api/v1/internal/maintenance/restores/#{restore.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('backup_file_path')
      end
    end

    context 'when restore does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/maintenance/restores/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Restore not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/maintenance/restores/#{restore.id}", as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/maintenance/restores/:id' do
    let(:backup) { create(:database_backup) }
    let(:restore) do
      Database::Restore.create!(
        database_backup: backup,
        status: 'pending',
        restore_type: 'full',
        target_database: 'powernode_test'
      )
    end

    context 'with service token authentication' do
      it 'updates restore status to in_progress' do
        patch "/api/v1/internal/maintenance/restores/#{restore.id}",
              params: { status: 'in_progress' },
              headers: internal_headers,
              as: :json

        expect_success_response

        restore.reload
        expect(restore.status).to eq('in_progress')
        expect(restore.started_at).to be_present
      end

      it 'updates restore status to completed with statistics' do
        patch "/api/v1/internal/maintenance/restores/#{restore.id}",
              params: {
                status: 'completed',
                duration_seconds: 60,
                tables_restored: 25,
                rows_restored: 10000
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        restore.reload
        expect(restore.status).to eq('completed')
        expect(restore.completed_at).to be_present
        expect(restore.duration_seconds).to eq(60)
        expect(restore.tables_restored).to eq(25)
        expect(restore.rows_restored).to eq(10000)
      end

      it 'updates restore status to failed with error message' do
        patch "/api/v1/internal/maintenance/restores/#{restore.id}",
              params: {
                status: 'failed',
                error_message: 'Invalid backup file',
                duration_seconds: 10
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        restore.reload
        expect(restore.status).to eq('failed')
        expect(restore.error_message).to eq('Invalid backup file')
      end
    end

    context 'when restore does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/maintenance/restores/nonexistent-id',
              params: { status: 'completed' },
              headers: internal_headers,
              as: :json

        expect_error_response('Restore not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/maintenance/restores/#{restore.id}",
              params: { status: 'completed' },
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'GET /api/v1/internal/maintenance/scheduled_tasks' do
    let!(:due_task) do
      ScheduledTask.create!(
        name: 'Backup Database',
        task_type: 'backup',
        command: 'rake db:backup',
        cron_schedule: '0 2 * * *',
        enabled: true,
        next_run_at: 1.hour.ago
      )
    end

    let!(:future_task) do
      ScheduledTask.create!(
        name: 'Cleanup Logs',
        task_type: 'cleanup',
        command: 'rake logs:cleanup',
        cron_schedule: '0 3 * * *',
        enabled: true,
        next_run_at: 2.hours.from_now
      )
    end

    let!(:disabled_task) do
      ScheduledTask.create!(
        name: 'Disabled Task',
        task_type: 'other',
        command: 'echo test',
        cron_schedule: '0 4 * * *',
        enabled: false,
        next_run_at: 1.hour.ago
      )
    end

    context 'with service token authentication' do
      it 'returns tasks due for execution' do
        get '/api/v1/internal/maintenance/scheduled_tasks',
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['tasks'].size).to eq(1)
        task = response_data['data']['tasks'].first
        expect(task['id']).to eq(due_task.id)
        expect(task['name']).to eq('Backup Database')
      end

      it 'respects due_before parameter' do
        get '/api/v1/internal/maintenance/scheduled_tasks',
            params: { due_before: 30.minutes.ago.iso8601 },
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['tasks'].size).to eq(1)
      end

      it 'respects limit parameter' do
        get '/api/v1/internal/maintenance/scheduled_tasks',
            params: { limit: 1 },
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['tasks'].size).to be <= 1
      end

      it 'includes task details' do
        get '/api/v1/internal/maintenance/scheduled_tasks',
            headers: internal_headers,
            as: :json

        response_data = json_response
        task = response_data['data']['tasks'].first

        expect(task).to include(
          'id', 'name', 'task_type', 'command',
          'cron_schedule', 'configuration', 'next_run_at',
          'last_run_at', 'user_id'
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/maintenance/scheduled_tasks', as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/maintenance/scheduled_tasks/:id/executions' do
    let(:task) do
      ScheduledTask.create!(
        name: 'Test Task',
        task_type: 'backup',
        command: 'rake test',
        cron_schedule: '0 0 * * *',
        enabled: true,
        next_run_at: Time.current
      )
    end

    context 'with service token authentication' do
      it 'creates task execution' do
        post "/api/v1/internal/maintenance/scheduled_tasks/#{task.id}/executions",
             params: { job_id: 'job_123' },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'execution_id',
          'task_id' => task.id,
          'status' => 'pending'
        )

        execution = TaskExecution.find(response_data['data']['execution_id'])
        expect(execution.job_id).to eq('job_123')
      end

      it 'updates task last_run_at and next_run_at' do
        allow_any_instance_of(Api::V1::Internal::MaintenanceController)
          .to receive(:calculate_next_run).and_return(1.day.from_now)

        post "/api/v1/internal/maintenance/scheduled_tasks/#{task.id}/executions",
             headers: internal_headers,
             as: :json

        expect_success_response

        task.reload
        expect(task.last_run_at).to be_within(1.minute).of(Time.current)
        expect(task.next_run_at).to be_present
      end
    end

    context 'when task does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/maintenance/scheduled_tasks/nonexistent-id/executions',
             headers: internal_headers,
             as: :json

        expect_error_response('Task not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/maintenance/scheduled_tasks/#{task.id}/executions",
             as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/maintenance/task_executions/:id' do
    let(:task) { create(:scheduled_task) }
    let(:execution) do
      TaskExecution.create!(
        scheduled_task: task,
        status: 'pending',
        started_at: Time.current
      )
    end

    context 'with service token authentication' do
      it 'updates execution status to running' do
        patch "/api/v1/internal/maintenance/task_executions/#{execution.id}",
              params: { status: 'running' },
              headers: internal_headers,
              as: :json

        expect_success_response

        execution.reload
        expect(execution.status).to eq('running')
      end

      it 'updates execution status to completed with result' do
        patch "/api/v1/internal/maintenance/task_executions/#{execution.id}",
              params: {
                status: 'completed',
                duration_seconds: 30,
                output: 'Backup completed successfully',
                result: { files_created: 1 }
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        execution.reload
        expect(execution.status).to eq('completed')
        expect(execution.completed_at).to be_present
        expect(execution.duration_seconds).to eq(30)
        expect(execution.output).to eq('Backup completed successfully')
      end

      it 'updates execution status to failed with error details' do
        patch "/api/v1/internal/maintenance/task_executions/#{execution.id}",
              params: {
                status: 'failed',
                duration_seconds: 15,
                error_message: 'Connection failed',
                error_details: { code: 'TIMEOUT' }
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        execution.reload
        expect(execution.status).to eq('failed')
        expect(execution.error_message).to eq('Connection failed')
      end
    end

    context 'when execution does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/maintenance/task_executions/nonexistent-id',
              params: { status: 'completed' },
              headers: internal_headers,
              as: :json

        expect_error_response('Execution not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/maintenance/task_executions/#{execution.id}",
              params: { status: 'completed' },
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/maintenance/backups/:id/cleanup' do
    let!(:old_backup) do
      Database::Backup.create!(
        filename: 'old_backup.sql',
        file_path: '/tmp/old_backup.sql',
        backup_type: 'full',
        status: 'completed',
        database_name: 'test',
        created_at: 45.days.ago
      )
    end

    let!(:recent_backup) do
      Database::Backup.create!(
        filename: 'recent_backup.sql',
        file_path: '/tmp/recent_backup.sql',
        backup_type: 'full',
        status: 'completed',
        database_name: 'test',
        created_at: 15.days.ago
      )
    end

    context 'with service token authentication' do
      it 'cleans up old backups based on days_to_keep' do
        post '/api/v1/internal/maintenance/backups/cleanup',
             params: { days_to_keep: 30 },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'deleted_count' => 1,
          'failed_count' => 0
        )

        expect(Database::Backup.exists?(old_backup.id)).to be false
        expect(Database::Backup.exists?(recent_backup.id)).to be true
      end

      it 'uses default 30 days when days_to_keep not specified' do
        post '/api/v1/internal/maintenance/backups/cleanup',
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include('deleted_count', 'cutoff_date')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/maintenance/backups/cleanup', as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end
end
