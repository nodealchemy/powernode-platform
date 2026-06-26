# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the data-critical pg_restore job.
#
# Covers pg_restore success-vs-error *detection* in #execute_command: a non-zero
# exit (pg_restore emits severity-ERROR, e.g. "pg_restore: error: ... ERROR:",
# for constraint/type/missing-relation/disk-full failures — NOT just FATAL) must
# fail closed (mark the restore FAILED and raise), never report 'completed' and
# mask data corruption after --clean --if-exists has already dropped objects.
# Also exercises orthogonal, safe behavior — pg_restore command construction, the
# missing-backup-file guard clause, the status-update API contract, and the
# happy path with a clean (zero-exit) Open3 success. Nothing shells out or
# touches a real database/filesystem.
RSpec.describe Maintenance::DatabaseRestoreJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:restore_id) { 'restore-123' }
  let(:backup_path) { '/var/backups/powernode/full.dump' }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:log_warn)
  end

  describe 'job configuration' do
    it 'runs on the maintenance queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('maintenance')
    end

    it 'never auto-retries a restore' do
      expect(described_class.sidekiq_options['retry']).to eq(0)
    end
  end

  describe '#build_pg_restore_command' do
    let(:config) do
      {
        'host' => 'db.internal',
        'port' => '5432',
        'username' => 'postgres',
        'password' => 'super-secret-pw',
        'database' => 'powernode_restore'
      }
    end

    it 'builds a full-restore command with --clean/--if-exists and safe defaults' do
      command = job.send(:build_pg_restore_command, config, backup_path, clean: true, if_exists: true)

      expect(command.first).to eq('pg_restore')
      expect(command).to include('-h', 'db.internal')
      expect(command).to include('-p', '5432')
      expect(command).to include('-U', 'postgres')
      expect(command).to include('-d', 'powernode_restore')
      expect(command).to include('--clean')
      expect(command).to include('--if-exists')
      expect(command).to include('--no-owner')
      expect(command).to include('--no-privileges')
      expect(command).to include('-v')
      expect(command.last).to eq(backup_path)
      # The password must travel via the PGPASSWORD env var, never argv.
      expect(command).not_to include('super-secret-pw')
    end

    it 'adds --schema-only for a schema restore' do
      command = job.send(:build_pg_restore_command, config, backup_path, schema_only: true)

      expect(command).to include('--schema-only')
      expect(command).not_to include('--data-only')
    end

    it 'adds --data-only for a data restore' do
      command = job.send(:build_pg_restore_command, config, backup_path, data_only: true)

      expect(command).to include('--data-only')
      expect(command).not_to include('--schema-only')
    end
  end

  describe '#execute' do
    let(:restore) do
      {
        'id' => restore_id,
        'restore_type' => 'full',
        'backup_file_path' => backup_path,
        'target_database' => 'powernode_restore'
      }
    end

    before do
      allow(api_client).to receive(:get)
        .with("/api/v1/internal/maintenance/restores/#{restore_id}")
        .and_return('data' => restore)
      allow(api_client).to receive(:patch).and_return('success' => true)
      allow(File).to receive(:exist?).and_call_original
    end

    context 'when the backup file is missing (guard clause)' do
      before do
        allow(File).to receive(:exist?).with(backup_path).and_return(false)
      end

      it 'marks the restore failed and raises without shelling out' do
        expect(Open3).not_to receive(:capture3)
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/maintenance/restores/#{restore_id}", hash_including(status: 'failed'))

        expect { job.execute(restore_id) }.to raise_error(/Backup file not found/)
      end
    end

    context 'when pg_restore completes cleanly (zero-exit success)' do
      before do
        allow(File).to receive(:exist?).with(backup_path).and_return(true)
        allow(Open3).to receive(:capture3)
          .and_return(['restoring table foo', '', double('Process::Status', success?: true)])
      end

      it 'shells out to pg_restore with a --clean command targeting the database' do
        captured = nil
        allow(Open3).to receive(:capture3) do |_env, *cmd|
          captured = cmd
          ['restoring table foo', '', double('Process::Status', success?: true)]
        end

        job.execute(restore_id)

        expect(captured.first).to eq('pg_restore')
        expect(captured).to include('--clean')
        expect(captured).to include('-d', 'powernode_restore')
        expect(captured.last).to eq(backup_path)
      end

      it 'posts in_progress and then completed status updates in order' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/maintenance/restores/#{restore_id}", hash_including(status: 'in_progress'))
          .ordered
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/maintenance/restores/#{restore_id}", hash_including(status: 'completed'))
          .ordered

        job.execute(restore_id)
      end
    end

    context 'when pg_restore exits non-zero with an ERROR-level failure (no FATAL)' do
      # pg_restore reports constraint/type/missing-relation/disk-full failures
      # at severity ERROR (not FATAL) and exits non-zero. This stderr contains
      # neither 'FATAL' nor 'could not connect', so the old substring allowlist
      # would have masked it as success after --clean --if-exists dropped objects.
      let(:error_stderr) do
        'pg_restore: error: could not execute query: ERROR: relation "accounts" does not exist'
      end

      before do
        allow(File).to receive(:exist?).with(backup_path).and_return(true)
        allow(Open3).to receive(:capture3)
          .and_return(['', error_stderr, double('Process::Status', success?: false)])
      end

      it 'fails closed: marks the restore FAILED and raises, never completed' do
        expect(api_client).not_to receive(:patch)
          .with("/api/v1/internal/maintenance/restores/#{restore_id}", hash_including(status: 'completed'))
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/maintenance/restores/#{restore_id}", hash_including(status: 'failed'))

        expect { job.execute(restore_id) }.to raise_error(/Restore failed/)
      end

      it 'surfaces the pg_restore ERROR text in the failure error_message' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/maintenance/restores/#{restore_id}",
            hash_including(status: 'failed', error_message: a_string_including('relation "accounts" does not exist'))
          )

        expect { job.execute(restore_id) }.to raise_error(/Restore failed/)
      end
    end
  end
end
