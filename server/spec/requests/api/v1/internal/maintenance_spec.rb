# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Maintenance', type: :request do
  # Worker JWT authentication via InternalBaseController
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'GET /api/v1/internal/maintenance/backups/:id' do
    let(:backup) do
      create(:database_backup,
        file_path: '/backups/backup_20250124.sql',
        backup_type: 'full',
        status: 'pending',
        description: 'Daily backup'
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
          'file_path' => '/backups/backup_20250124.sql',
          'backup_type' => 'full',
          'status' => 'pending',
          'description' => 'Daily backup'
        )
      end

      it 'includes all backup fields' do
        get "/api/v1/internal/maintenance/backups/#{backup.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        expect(response_data['data']).to include(
          'id', 'file_path', 'backup_type', 'status',
          'description', 'file_size_bytes', 'metadata',
          'started_at', 'completed_at', 'created_at'
        )
      end
    end

    context 'when backup does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/maintenance/backups/00000000-0000-0000-0000-000000000000',
            headers: internal_headers,
            as: :json

        expect_error_response('Backup not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/maintenance/backups/#{backup.id}", as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/maintenance/backups/:id' do
    let(:backup) do
      create(:database_backup,
        file_path: '/backups/backup_20250124.sql',
        backup_type: 'full',
        status: 'pending'
      )
    end

    context 'with service token authentication' do
      it 'updates backup status to running' do
        patch "/api/v1/internal/maintenance/backups/#{backup.id}",
              params: { status: 'running' },
              headers: internal_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'status' => 'running'
        )

        backup.reload
        expect(backup.status).to eq('running')
        expect(backup.started_at).to be_present
      end

      it 'updates backup status to completed with file details' do
        patch "/api/v1/internal/maintenance/backups/#{backup.id}",
              params: {
                status: 'completed',
                file_path: '/backups/completed_backup.sql',
                file_size_bytes: 1024000,
                duration_seconds: 45
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        backup.reload
        expect(backup.status).to eq('completed')
        expect(backup.completed_at).to be_present
        expect(backup.file_path).to eq('/backups/completed_backup.sql')
        expect(backup.file_size_bytes).to eq(1024000)
        expect(backup.duration_seconds).to eq(45)
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
        patch '/api/v1/internal/maintenance/backups/00000000-0000-0000-0000-000000000000',
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

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'GET /api/v1/internal/maintenance/restores/:id' do
    let(:backup) { create(:database_backup) }
    let(:restore) do
      create(:database_restore,
        database_backup: backup,
        status: 'pending'
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
          'status' => 'pending'
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
        get '/api/v1/internal/maintenance/restores/00000000-0000-0000-0000-000000000000',
            headers: internal_headers,
            as: :json

        expect_error_response('Restore not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/maintenance/restores/#{restore.id}", as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/maintenance/restores/:id' do
    let(:backup) { create(:database_backup) }
    let(:restore) do
      create(:database_restore,
        database_backup: backup,
        status: 'pending'
      )
    end

    context 'with service token authentication' do
      it 'updates restore status to running' do
        patch "/api/v1/internal/maintenance/restores/#{restore.id}",
              params: { status: 'running' },
              headers: internal_headers,
              as: :json

        expect_success_response

        restore.reload
        expect(restore.status).to eq('running')
        expect(restore.started_at).to be_present
      end

      it 'updates restore status to completed with statistics' do
        patch "/api/v1/internal/maintenance/restores/#{restore.id}",
              params: {
                status: 'completed',
                duration_seconds: 60
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        restore.reload
        expect(restore.status).to eq('completed')
        expect(restore.completed_at).to be_present
        expect(restore.duration_seconds).to eq(60)
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
        patch '/api/v1/internal/maintenance/restores/00000000-0000-0000-0000-000000000000',
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

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'GET /api/v1/internal/maintenance/scheduled_tasks' do
    let!(:due_task) do
      create(:scheduled_task,
        name: 'Backup Database',
        task_type: 'database_backup',
        cron_expression: '0 2 * * *',
        is_active: true,
        next_run_at: 1.hour.ago
      )
    end

    let!(:future_task) do
      create(:scheduled_task,
        name: 'Cleanup Logs',
        task_type: 'data_cleanup',
        cron_expression: '0 3 * * *',
        is_active: true,
        next_run_at: 2.hours.from_now
      )
    end

    let!(:disabled_task) do
      create(:scheduled_task,
        name: 'Disabled Task',
        task_type: 'custom_command',
        cron_expression: '0 4 * * *',
        is_active: false,
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
            headers: internal_headers

        expect_success_response
        response_data = json_response

        expect(response_data['data']['tasks'].size).to eq(1)
      end

      it 'respects limit parameter' do
        get '/api/v1/internal/maintenance/scheduled_tasks',
            params: { limit: 1 },
            headers: internal_headers

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
          'id', 'name', 'task_type',
          'cron_expression', 'parameters', 'next_run_at',
          'last_run_at'
        )
      end

      context 'when a specific task_id is requested (manual "run now")' do
        it 'returns that task even when its next_run_at is not yet due' do
          get '/api/v1/internal/maintenance/scheduled_tasks',
              params: { task_id: future_task.id },
              headers: internal_headers

          expect_success_response
          tasks = json_response['data']['tasks']
          expect(tasks.map { |t| t['id'] }).to eq([future_task.id])
        end

        it 'returns a disabled task by id (the manual run is already authorized)' do
          get '/api/v1/internal/maintenance/scheduled_tasks',
              params: { task_id: disabled_task.id },
              headers: internal_headers

          expect_success_response
          tasks = json_response['data']['tasks']
          expect(tasks.map { |t| t['id'] }).to eq([disabled_task.id])
        end
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/maintenance/scheduled_tasks', as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/maintenance/scheduled_tasks/:id/executions' do
    let(:task) do
      create(:scheduled_task,
        name: 'Test Task',
        task_type: 'database_backup',
        cron_expression: '0 0 * * *',
        is_active: true,
        next_run_at: Time.current
      )
    end

    context 'with service token authentication' do
      it 'creates task execution' do
        post "/api/v1/internal/maintenance/scheduled_tasks/#{task.id}/executions",
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'execution_id',
          'task_id' => task.id,
          'status' => 'running'
        )
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
        post '/api/v1/internal/maintenance/scheduled_tasks/00000000-0000-0000-0000-000000000000/executions',
             headers: internal_headers,
             as: :json

        expect_error_response('Task not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/maintenance/scheduled_tasks/#{task.id}/executions",
             as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/maintenance/task_executions/:id' do
    let(:task) { create(:scheduled_task) }
    let(:execution) do
      create(:task_execution,
        scheduled_task: task,
        status: 'running',
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
                duration_ms: 30000,
                log_output: 'Backup completed successfully',
                result: { files_created: 1 }
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        execution.reload
        expect(execution.status).to eq('completed')
        expect(execution.completed_at).to be_present
        expect(execution.duration_ms).to eq(30000)
        expect(execution.log_output).to eq('Backup completed successfully')
      end

      it 'updates execution status to failed with error details' do
        patch "/api/v1/internal/maintenance/task_executions/#{execution.id}",
              params: {
                status: 'failed',
                duration_ms: 15000,
                error_message: 'Connection failed'
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
        patch '/api/v1/internal/maintenance/task_executions/00000000-0000-0000-0000-000000000000',
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

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/maintenance/backups/:id/cleanup' do
    let!(:old_backup) do
      create(:database_backup, :completed,
        file_path: '/tmp/old_backup.sql',
        backup_type: 'full',
        description: 'Old backup',
        created_at: 45.days.ago
      )
    end

    let!(:recent_backup) do
      create(:database_backup, :completed,
        file_path: '/tmp/recent_backup.sql',
        backup_type: 'full',
        description: 'Recent backup',
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

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/maintenance/cleanup_auth_artifacts' do
    # Doorkeeper stores the refresh_token as a column on the oauth_access_tokens row, so purging
    # an expired-but-recent access token also destroys a still-usable refresh token and forces MCP
    # clients to re-authenticate. Cleanup must only purge tokens idle (no refresh) beyond the
    # REFRESH_TOKEN_RETENTION window; active sessions keep minting fresh rows and must survive.
    let(:retention) { Api::V1::Internal::MaintenanceController::REFRESH_TOKEN_RETENTION }

    # Backdate created_at directly (bypasses Rails timestamp machinery) so Doorkeeper's
    # `expired?` (created_at + expires_in) reflects the intended age.
    def backdate!(token, created_at:)
      token.update_columns(created_at: created_at)
      token
    end

    context 'with service token authentication' do
      it 'preserves an expired but recently-issued token (refresh still possible)' do
        token = backdate!(create(:oauth_access_token, :expired), created_at: 2.hours.ago)

        post '/api/v1/internal/maintenance/cleanup_auth_artifacts',
             headers: internal_headers, as: :json

        expect_success_response
        expect(Doorkeeper::AccessToken.exists?(token.id)).to be(true)
        expect(json_response['data']['results']['expired_tokens_purged']).to eq(0)
      end

      it 'purges an expired token idle beyond the retention window' do
        token = backdate!(create(:oauth_access_token, :expired), created_at: retention.ago - 1.day)

        post '/api/v1/internal/maintenance/cleanup_auth_artifacts',
             headers: internal_headers, as: :json

        expect_success_response
        expect(Doorkeeper::AccessToken.exists?(token.id)).to be(false)
        expect(json_response['data']['results']['expired_tokens_purged']).to eq(1)
      end

      it 'purges revoked tokens older than 7 days but keeps recent revocations' do
        old_revoked = create(:oauth_access_token, revoked_at: 10.days.ago)
        recent_revoked = create(:oauth_access_token, revoked_at: 1.day.ago)

        post '/api/v1/internal/maintenance/cleanup_auth_artifacts',
             headers: internal_headers, as: :json

        expect_success_response
        expect(Doorkeeper::AccessToken.exists?(old_revoked.id)).to be(false)
        expect(Doorkeeper::AccessToken.exists?(recent_revoked.id)).to be(true)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/maintenance/cleanup_auth_artifacts', as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end
end
