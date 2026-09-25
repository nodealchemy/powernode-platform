# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Maintenance::MaintenanceController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'admin.maintenance.mode' ]) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:backup_only_user) { create(:user, account: account, permissions: [ 'admin.maintenance.backup' ]) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  before do
    # Reset maintenance mode before each test
    Admin::MaintenanceMode.disable!

    # Stub Database::Backup which the backups-list action references.
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

    context 'with only a backup/cleanup/restore/tasks permission (no admin.maintenance.mode, no system.admin)' do
      it 'returns forbidden — this is a narrower gate than the controller-wide one' do
        get '/api/v1/admin/maintenance/mode', headers: auth_headers_for(backup_only_user), as: :json

        expect_error_response('Permission denied: requires admin.maintenance.mode or system.admin', 403)
      end
    end
  end

  describe 'POST /api/v1/admin/maintenance/mode' do
    context 'with only a backup permission' do
      it 'cannot enable maintenance mode — it would have no way to disable it again' do
        post '/api/v1/admin/maintenance/mode', params: { enabled: true, message: 'Upgrading' }, headers: auth_headers_for(backup_only_user), as: :json

        expect_error_response('Permission denied: requires admin.maintenance.mode or system.admin', 403)
        expect(Admin::MaintenanceMode.enabled?).to be false
      end
    end

    context 'enabling maintenance mode' do
      it 'enables maintenance mode successfully and writes a real audit row' do
        expect {
          post '/api/v1/admin/maintenance/mode',
              params: {
                enabled: true,
                message: 'System upgrade in progress',
                estimated_completion: '2025-01-25T12:00:00Z'
              },
              headers: headers,
              as: :json
        }.to change(AuditLog, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data['enabled']).to be true
        expect(data['message']).to eq('System upgrade in progress')

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('maintenance_mode_enabled')
        expect(audit_log.user).to eq(admin_user)
      end

      it 'rejects ANY bypass IP with 422 when TRUSTED_PROXY_CIDRS is unset — even a well-formed one' do
        expect {
          post '/api/v1/admin/maintenance/mode',
              params: { enabled: true, message: 'Upgrading', bypass_ips: [ '203.0.113.5' ] },
              headers: headers,
              as: :json
        }.not_to change(AuditLog, :count)

        expect_error_response('TRUSTED_PROXY_CIDRS', 422)
        expect(Admin::MaintenanceMode.enabled?).to be false
      end

      it 'rejects an unparseable bypass IP with 422 once TRUSTED_PROXY_CIDRS is configured' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          expect {
            post '/api/v1/admin/maintenance/mode',
                params: { enabled: true, message: 'Upgrading', bypass_ips: [ 'not-an-ip' ] },
                headers: headers,
                as: :json
          }.not_to change(AuditLog, :count)

          expect_error_response('not-an-ip', 422)
          expect(Admin::MaintenanceMode.enabled?).to be false
        end
      end

      it 'accepts a valid bypass IP once TRUSTED_PROXY_CIDRS is configured' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          post '/api/v1/admin/maintenance/mode',
              params: { enabled: true, message: 'Upgrading', bypass_ips: [ '203.0.113.5' ] },
              headers: headers,
              as: :json

          expect_success_response
          expect(json_response_data['bypass_ips']).to eq([ '203.0.113.5' ])
        end
      end

      it 'requires the enabled param' do
        post '/api/v1/admin/maintenance/mode', params: { message: 'Upgrading' }, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'disabling maintenance mode' do
      before do
        Admin::MaintenanceMode.enable!(message: 'System upgrade in progress')
      end

      it 'disables maintenance mode successfully and writes a real audit row' do
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
    end
  end

  describe 'PATCH /api/v1/admin/maintenance/mode' do
    context 'without admin.maintenance.mode (only a backup permission)' do
      it 'returns forbidden' do
        patch '/api/v1/admin/maintenance/mode', params: { message: 'Staged' }, headers: auth_headers_for(backup_only_user), as: :json

        expect_error_response('Permission denied: requires admin.maintenance.mode or system.admin', 403)
      end
    end

    context 'while maintenance is OFF' do
      it 'persists the staged message/bypass IPs WITHOUT enabling maintenance mode (Save-while-OFF regression)' do
        with_trusted_proxy_cidrs('10.10.10.10/32') do
          expect {
            patch '/api/v1/admin/maintenance/mode',
                params: { message: 'Staged message', bypass_ips: [ '203.0.113.5' ] },
                headers: headers,
                as: :json
          }.to change(AuditLog, :count).by(1)
        end

        expect_success_response
        data = json_response_data
        expect(data['enabled']).to be false
        expect(data['message']).to eq('Staged message')
        expect(data['bypass_ips']).to eq([ '203.0.113.5' ])
        expect(AuditLog.last.action).to eq('maintenance_mode_updated')
      end
    end

    context 'while maintenance is ON' do
      before { Admin::MaintenanceMode.enable!(message: 'System upgrade in progress') }

      it 'does not reset enabled_at (Save-while-ON regression)' do
        original_enabled_at = Admin::MaintenanceMode.status[:enabled_at]

        travel_to(1.hour.from_now) do
          patch '/api/v1/admin/maintenance/mode', params: { message: 'Almost done' }, headers: headers, as: :json

          expect_success_response
          data = json_response_data
          expect(data['enabled']).to be true
          expect(data['message']).to eq('Almost done')
          expect(data['enabled_at']).to eq(original_enabled_at)
        end
      end
    end

    it 'rejects an invalid bypass IP with 422, same as update_mode' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        patch '/api/v1/admin/maintenance/mode', params: { message: 'Upgrading', bypass_ips: [ 'not-an-ip' ] }, headers: headers, as: :json

        expect_error_response('not-an-ip', 422)
      end
    end

    # Item 7a: a caller (e.g. a lighter-weight future control, or a plain
    # curl PATCH) that sends only `message` must not wipe the other fields —
    # the controller only forwards params.key?-present keys.
    it 'a message-only PATCH does not wipe bypass_ips or estimated_completion' do
      with_trusted_proxy_cidrs('10.10.10.10/32') do
        patch '/api/v1/admin/maintenance/mode',
            params: { message: 'first', estimated_completion: '10 minutes', bypass_ips: [ '203.0.113.5' ] },
            headers: headers, as: :json
        expect_success_response

        patch '/api/v1/admin/maintenance/mode', params: { message: 'second' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('second')
        expect(data['estimated_completion']).to eq('10 minutes')
        expect(data['bypass_ips']).to eq([ '203.0.113.5' ])
      end
    end
  end

  describe 'GET /api/v1/admin/maintenance/backups' do
    context 'with admin maintenance permission' do
      it 'returns list of backups' do
        get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

        expect_success_response
      end

      # IMP-8b25fb48368e: this action's `backup.name` / `.size` / `.location`
      # calls raised NoMethodError (503) on any non-empty result — invisible
      # in every prior spec because the table was always empty. A real row
      # (via the actual, non-stubbed Database::Backup model — the `before`
      # block's stub_const is a no-op once the model is loaded) exercises the
      # mapping to real columns.
      context 'with a real backup row' do
        let!(:backup) do
          create(:database_backup,
            description: 'nightly full',
            file_path: '/var/backups/pg/2026-09-18.sql',
            file_size_bytes: 2_048,
            status: 'completed'
          )
        end

        it 'serializes the row without raising' do
          get '/api/v1/admin/maintenance/backups', headers: headers, as: :json

          expect_success_response
          row = json_response_data.first
          expect(row).to include(
            'id' => backup.id,
            'name' => 'nightly full',
            'size' => 2_048,
            'status' => 'completed',
            'location' => '/var/backups/pg/2026-09-18.sql'
          )
        end
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
end
