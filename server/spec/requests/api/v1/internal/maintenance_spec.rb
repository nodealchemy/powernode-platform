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

      # IMP-8b25fb48368e should-fix #3: Database::Backup's after_update
      # callback (log_backup_status_change) used to always raise
      # ActiveModel::UnknownAttributeError on `details:` (not a real AuditLog
      # column), silently swallowed — every worker status PATCH went
      # unaudited regardless of created_by. Now the same write_backup_audit!
      # writer as creation; a system (created_by: nil) backup's transition is
      # attributed to the platform sentinel and produces exactly one row.
      context 'auditing a worker-owned (created_by: nil) backup transition' do
        let!(:sentinel) { create(:account, name: Audit::PlatformAccount::SENTINEL_NAME) }
        let(:system_backup) { create(:database_backup, created_by: nil, status: 'pending') }

        it 'writes exactly one NEW audit row (the transition, not the creation) attributed to the sentinel' do
          system_backup # eagerly create — its own after_create fires one "system_backup" row already
          audit_scope = AuditLog.where(resource_type: 'Database::Backup', resource_id: system_backup.id)
          expect(audit_scope.count).to eq(1)

          expect {
            patch "/api/v1/internal/maintenance/backups/#{system_backup.id}",
                  params: { status: 'running' },
                  headers: internal_headers,
                  as: :json
          }.to change(audit_scope, :count).by(1)

          expect_success_response

          row = audit_scope.order(:created_at).last
          expect(row.action).to eq('system_backup')
          expect(row.account_id).to eq(sentinel.id)
          expect(row.metadata['new_status']).to eq('running')
        end
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

      # The worker's Maintenance::ScheduledTaskExecutorJob sub-executors read
      # task['command'] (execute_custom_command) and task['configuration']
      # (execute_data_cleanup / _database_backup / _report_generation). Both are
      # stored in the parameters jsonb (the model has no dedicated columns), so
      # the serialized payload must surface them under the keys the worker reads,
      # or a manual custom_command run fails with "Command not allowed" and
      # config-driven runs silently ignore their configured parameters.
      context 'worker execution-contract fields' do
        let!(:custom_command_task) do
          create(:scheduled_task,
            name: 'Nightly Rake',
            task_type: 'custom_command',
            cron_expression: '0 5 * * *',
            is_active: true,
            next_run_at: 1.hour.ago,
            parameters: { 'command' => "rails runner 'puts 1'" }
          )
        end

        let!(:config_task) do
          create(:scheduled_task,
            name: 'Prune Audit Logs',
            task_type: 'data_cleanup',
            cron_expression: '0 6 * * *',
            is_active: true,
            next_run_at: 1.hour.ago,
            parameters: { 'cleanup_type' => 'audit_logs', 'days_to_keep' => 45 }
          )
        end

        it 'serializes command for a custom_command task so the worker can run it' do
          get '/api/v1/internal/maintenance/scheduled_tasks',
              params: { task_id: custom_command_task.id },
              headers: internal_headers

          expect_success_response
          task = json_response['data']['tasks'].first
          expect(task).to have_key('command')
          expect(task['command']).to eq("rails runner 'puts 1'")
        end

        it 'serializes configuration for a config-driven task so the worker honors it' do
          get '/api/v1/internal/maintenance/scheduled_tasks',
              params: { task_id: config_task.id },
              headers: internal_headers

          expect_success_response
          task = json_response['data']['tasks'].first
          expect(task).to have_key('configuration')
          expect(task['configuration']).to include('cleanup_type' => 'audit_logs', 'days_to_keep' => 45)
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

  # IMP-8b25fb48368e / IMP-19c753c1e8a9: create_backup used to be unreachable
  # end to end — `Database::Backup#created_by` was required by default (both
  # by the Rails association AND the DB column) and the worker-initiated
  # request never set it, so `backup.save` always failed before
  # `log_internal_audit("backup.create", ...)` (an unregistered,
  # account_id-less literal) was ever called. See git history for the
  # empirical trace. Fixed together at this one call site: `created_by` is
  # now optional (both in Rails and via migration
  # 20260918130300_allow_null_created_by_on_database_backups — the established
  # platform convention for worker/system-initiated rows, e.g. Devops::
  # Pipeline, ApiKey, WebhookEndpoint), and Database::Backup's own after_create
  # callback (not a separate controller-side audit call — see
  # database/backup.rb#write_backup_audit!) writes the single `system_backup`
  # audit row, attributed to the platform sentinel (Audit::PlatformAccount)
  # rather than a guessed tenant — that `|| Account.first` shape was already
  # rejected twice at this exact call site (internal_base_controller.rb's D1
  # comment, and this file's own prior "unreachable" comment).
  describe 'POST /api/v1/internal/maintenance/backups' do
    context 'with service token authentication' do
      context 'when the platform sentinel account exists' do
        # N1 (second review): uuid7 is NOT strictly monotonic within the same
        # millisecond, so two `create(:account)` calls issued back to back in
        # the same example could tie or flip — relying on natural insertion
        # order for "the decoy sorts first" would make this guard flaky
        # rather than deterministic. An explicit, deliberately-low id (all
        # zeros with a valid UUID v7 version/variant nibble) sorts before any
        # id the DB itself generates at a real 2026 timestamp regardless of
        # ordering races, so the decoy reliably occupies the `Account.first`
        # slot a regression to `|| Account.first` would read from.
        let!(:decoy) { create(:account, id: "00000000-0000-7000-8000-000000000000") }
        let!(:sentinel) { create(:account, name: Audit::PlatformAccount::SENTINEL_NAME) }

        before { expect(Account.first.id).to eq(decoy.id) }

        it 'creates exactly one Database::Backup row and attributes its one audit row to the sentinel, never a tenant' do
          expect {
            post '/api/v1/internal/maintenance/backups',
                 params: { backup_type: 'full', scheduled: true, description: 'nightly' },
                 headers: internal_headers,
                 as: :json
          }.to change(Database::Backup, :count).by(1)

          expect(response).to have_http_status(:accepted)

          backup = Database::Backup.last
          expect(backup.status).to eq('pending')
          expect(backup.backup_type).to eq('full')
          expect(backup.created_by_id).to be_nil
          # started_at is NOT NULL with no DB default; create_backup must set
          # it itself or the save raises ActiveRecord::NotNullViolation.
          expect(backup.started_at).to be_present
          # S1: the description COLUMN, not only metadata['description'] — the
          # admin endpoint's `name:` field and the creation audit's metadata
          # both read the column.
          expect(backup.description).to eq('nightly')

          audit_rows = AuditLog.where(resource_type: 'Database::Backup', resource_id: backup.id)
          expect(audit_rows.count).to eq(1)
          row = audit_rows.first
          expect(row.action).to eq('system_backup')
          expect(row.account_id).to eq(sentinel.id)
          expect(row.account_id).not_to eq(internal_account.id)
          expect(row.account_id).not_to eq(decoy.id)
        end
      end

      context 'when the platform sentinel account is absent' do
        before { expect(Account.where(name: Audit::PlatformAccount::SENTINEL_NAME)).to be_empty }

        it 'still creates the backup row and returns 202, but writes no audit row and emits the skip signal' do
          events = []
          subscriber = ActiveSupport::Notifications.subscribe(Auditable::SKIPPED_NOTIFICATION) do |*args|
            events << ActiveSupport::Notifications::Event.new(*args).payload
          end

          begin
            expect {
              post '/api/v1/internal/maintenance/backups',
                   params: { backup_type: 'full', scheduled: true, description: 'nightly' },
                   headers: internal_headers,
                   as: :json
            }.to change(Database::Backup, :count).by(1)
          ensure
            ActiveSupport::Notifications.unsubscribe(subscriber)
          end

          expect(response).to have_http_status(:accepted)

          backup = Database::Backup.last
          expect(AuditLog.where(resource_type: 'Database::Backup', resource_id: backup.id)).to be_empty

          payload = events.find { |e| e[:record_id] == backup.id }
          expect(payload).to be_present
          expect(payload[:reason]).to eq(Audit::PlatformAccount::MISSING_REASON)
          expect(payload[:action]).to eq('system_backup')
        end
      end

      # IMP-8b25fb48368e S2 (second review): write_backup_audit! now issues a
      # real INSERT inside the backup save's own transaction (before this
      # fix, `details:` always raised at Ruby attribute assignment, before
      # any SQL reached Postgres, so the surrounding transaction was never
      # actually at risk). A REAL Postgres-level failure on that INSERT — not
      # a plain `raise`, which proves nothing about transaction state — must
      # not abort the backup's own transaction. Forces a genuine
      # PG::UniqueViolation on audit_logs.sequence_number's partial unique
      # index: reserve a real sequence_number with a throwaway row, then stub
      # Audit::LogIntegrityService.apply_integrity to reuse it for the
      # backup's own audit write, so the actual database rejects the INSERT.
      context 'when the audit INSERT itself fails at the database level (not a Ruby exception)' do
        let!(:sentinel) { create(:account, name: Audit::PlatformAccount::SENTINEL_NAME) }
        let!(:reserved_sequence) do
          AuditLog.create!(
            account: sentinel, user: nil, action: 'system_backup', source: 'system',
            resource_type: 'Database::Backup', resource_id: SecureRandom.uuid, metadata: {}
          )
        end

        before do
          # Scoped to Database::Backup only — internal_headers (mTLS worker
          # auth) lazily creates the Worker used by this very request, and
          # Worker#log_creation writes its OWN AuditLog row first; an
          # unscoped stub would force that unrelated write to collide too.
          original_apply_integrity = Audit::LogIntegrityService.method(:apply_integrity)
          allow(Audit::LogIntegrityService).to receive(:apply_integrity) do |audit_log|
            if audit_log.resource_type == "Database::Backup"
              audit_log.sequence_number = reserved_sequence.sequence_number
              audit_log.previous_hash = reserved_sequence.previous_hash
              audit_log.integrity_hash = SecureRandom.hex(32)
            else
              original_apply_integrity.call(audit_log)
            end
          end
        end

        it 'still commits the backup and returns 202 despite the audit write aborting' do
          expect {
            post '/api/v1/internal/maintenance/backups',
                 params: { backup_type: 'full' },
                 headers: internal_headers,
                 as: :json
          }.to change(Database::Backup, :count).by(1)

          expect(response).to have_http_status(:accepted)

          backup = Database::Backup.last
          expect(backup.status).to eq('pending')
          # The forced PG::UniqueViolation means the audit row for THIS event
          # never actually lands — the savepoint contains the failure, it
          # doesn't paper over it with a fabricated success.
          expect(AuditLog.where(resource_type: 'Database::Backup', resource_id: backup.id)).to be_empty
        end
      end

      it 'rejects an invalid backup_type without creating a row' do
        expect {
          post '/api/v1/internal/maintenance/backups',
               params: { backup_type: 'bogus' },
               headers: internal_headers,
               as: :json
        }.not_to change(Database::Backup, :count)

        expect_error_response('invalid backup_type: bogus', 422)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/maintenance/backups', as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end
  end
end
