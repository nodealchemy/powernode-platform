# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the data-critical pg_dump backup job.
#
# These specs never shell out, touch a real database, or write to the
# filesystem: Open3, FileUtils, and the relevant File methods are stubbed.
# The focus is on the load-bearing behavior — pg_dump command construction and
# the in_progress -> completed/failed status reporting contract.
RSpec.describe Maintenance::DatabaseBackupJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:backup_id) { 'backup-123' }

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

    it 'retries at most twice' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
    end

    it 'inherits the shared BaseJob behavior' do
      expect(job).to be_a(BaseJob)
    end
  end

  describe '#build_pg_dump_command' do
    let(:config) do
      {
        'host' => 'db.internal',
        'port' => '5432',
        'username' => 'postgres',
        'password' => 'super-secret-pw',
        'database' => 'powernode_test'
      }
    end

    it 'builds a custom-format command with connection and output args' do
      command = job.send(:build_pg_dump_command, config, '/var/backups/x.dump', custom_format: true)

      expect(command.first).to eq('pg_dump')
      expect(command).to include('-h', 'db.internal')
      expect(command).to include('-p', '5432')
      expect(command).to include('-U', 'postgres')
      expect(command).to include('-Fc') # custom format -> pg_restore compatible
      expect(command).to include('-f', '/var/backups/x.dump')
      expect(command.last).to eq('powernode_test') # database name is the final positional arg
      # The password must travel via the PGPASSWORD env var, never argv.
      expect(command).not_to include('super-secret-pw')
    end

    it 'falls back to plain SQL format when custom_format is not requested' do
      command = job.send(:build_pg_dump_command, config, '/tmp/x.sql', {})

      expect(command).to include('-Fp')
      expect(command).not_to include('-Fc')
    end

    it 'adds --schema-only for schema backups' do
      command = job.send(:build_pg_dump_command, config, '/tmp/x.dump', schema_only: true)

      expect(command).to include('--schema-only')
      expect(command).not_to include('--data-only')
    end

    it 'adds --data-only for incremental/data backups' do
      command = job.send(:build_pg_dump_command, config, '/tmp/x.dump', data_only: true)

      expect(command).to include('--data-only')
      expect(command).not_to include('--schema-only')
    end

    it 'appends an --exclude-table flag per excluded table' do
      command = job.send(:build_pg_dump_command, config, '/tmp/x.dump', exclude_tables: %w[audit_logs sessions])

      expect(command).to include('--exclude-table=audit_logs')
      expect(command).to include('--exclude-table=sessions')
    end
  end

  describe '#execute' do
    let(:backup) do
      {
        'id' => backup_id,
        'backup_type' => 'full',
        'database_name' => 'powernode'
      }
    end

    before do
      allow(api_client).to receive(:get)
        .with("/api/v1/internal/maintenance/backups/#{backup_id}")
        .and_return('data' => backup)
      allow(api_client).to receive(:patch).and_return('success' => true)
      # Never create the real backup directory or hash a real file.
      allow(job).to receive(:ensure_backup_directory)
      allow(job).to receive(:calculate_checksum).and_return('deadbeef')
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(a_string_matching(/\.dump\z/)).and_return(true)
      allow(File).to receive(:size).and_call_original
      allow(File).to receive(:size).with(a_string_matching(/\.dump\z/)).and_return(2048)
    end

    context 'when pg_dump succeeds' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['dump complete', '', double('Process::Status', success?: true)])
      end

      it 'shells out to pg_dump in custom format via Open3' do
        captured = nil
        allow(Open3).to receive(:capture3) do |_env, *cmd|
          captured = cmd
          ['dump complete', '', double('Process::Status', success?: true)]
        end

        job.execute(backup_id)

        expect(captured.first).to eq('pg_dump')
        expect(captured).to include('-Fc')
        expect(captured).to include('-f')
      end

      it 'reports in_progress first and then completed with file metadata' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/maintenance/backups/#{backup_id}", hash_including(status: 'in_progress'))
          .ordered
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/maintenance/backups/#{backup_id}",
            hash_including(status: 'completed', file_size: 2048, checksum: 'deadbeef')
          )
          .ordered

        job.execute(backup_id)
      end

      it 'returns a success result carrying the file metadata' do
        result = job.execute(backup_id)

        expect(result[:success]).to be true
        expect(result[:file_size]).to eq(2048)
        expect(result[:checksum]).to eq('deadbeef')
      end
    end

    context 'when the backup type is schema_only' do
      let(:backup) { super().merge('backup_type' => 'schema_only') }

      it 'runs a --schema-only pg_dump' do
        captured = nil
        allow(Open3).to receive(:capture3) do |_env, *cmd|
          captured = cmd
          ['ok', '', double('Process::Status', success?: true)]
        end

        job.execute(backup_id)

        expect(captured).to include('--schema-only')
      end
    end

    context 'when pg_dump fails' do
      before do
        allow(Open3).to receive(:capture3)
          .and_return(['', 'pg_dump: could not connect', double('Process::Status', success?: false)])
        # No output file is produced on failure.
        allow(File).to receive(:exist?).with(a_string_matching(/\.dump\z/)).and_return(false)
      end

      it 'reports the backup as failed and re-raises' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/maintenance/backups/#{backup_id}", hash_including(status: 'failed'))

        expect { job.execute(backup_id) }.to raise_error(/Backup failed/)
      end
    end
  end
end
