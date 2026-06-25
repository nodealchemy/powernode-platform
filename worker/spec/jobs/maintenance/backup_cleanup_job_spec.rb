# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the retention-purge job.
#
# The data-critical guarantees here are: (1) it only ever asks the backend for
# COMPLETED backups older than RETENTION_DAYS — it never deletes within-retention
# backups — and (2) it caps deletions at MAX_DELETIONS_PER_RUN so a runaway run
# cannot wipe an unbounded number of backups. All deletions go through the mocked
# backend API client; nothing real is removed.
RSpec.describe Maintenance::BackupCleanupJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:log_warn)
  end

  def backup_fixture(id)
    { 'id' => id, 'status' => 'completed' }
  end

  describe 'job configuration' do
    it 'runs on the maintenance queue' do
      expect(described_class.sidekiq_options['queue']).to eq('maintenance')
    end
  end

  describe 'retention window (does not delete within-retention backups)' do
    it 'requests only completed backups created before the RETENTION_DAYS cutoff' do
      frozen_now = Time.utc(2026, 6, 25, 12, 0, 0)
      freeze_time_at(frozen_now)
      expected_cutoff = (frozen_now - described_class::RETENTION_DAYS.days).iso8601

      expect(api_client).to receive(:get)
        .with(
          '/api/v1/internal/maintenance/backups',
          { created_before: expected_cutoff, status: 'completed' }
        )
        .and_return('data' => [])

      job.execute
    end
  end

  describe '#execute' do
    context 'when there are no expired backups' do
      before do
        allow(api_client).to receive(:get).and_return('data' => [])
      end

      it 'deletes nothing and reports a clean run' do
        expect(api_client).not_to receive(:delete)

        result = job.execute

        expect(result[:success]).to be true
        expect(result[:deleted_count]).to eq(0)
      end
    end

    context 'when the number of expired backups is within the per-run cap' do
      let(:expired) { Array.new(3) { |i| backup_fixture("backup-#{i}") } }

      before do
        allow(api_client).to receive(:get).and_return('data' => expired)
        allow(api_client).to receive(:delete).and_return('success' => true)
      end

      it 'deletes each expired backup exactly once by id' do
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/maintenance/backups/backup-0').and_return('success' => true)
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/maintenance/backups/backup-1').and_return('success' => true)
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/maintenance/backups/backup-2').and_return('success' => true)

        result = job.execute

        expect(result[:deleted_count]).to eq(3)
        expect(result[:remaining_count]).to eq(0)
        expect(result[:success]).to be true
      end
    end

    context 'when expired backups exceed MAX_DELETIONS_PER_RUN' do
      let(:cap) { described_class::MAX_DELETIONS_PER_RUN }
      let(:expired) { Array.new(cap + 50) { |i| backup_fixture("backup-#{i}") } }

      before do
        allow(api_client).to receive(:get).and_return('data' => expired)
        allow(api_client).to receive(:delete).and_return('success' => true)
      end

      it 'caps deletions at MAX_DELETIONS_PER_RUN and defers the remainder' do
        expect(api_client).to receive(:delete).exactly(cap).times.and_return('success' => true)

        result = job.execute

        expect(result[:deleted_count]).to eq(cap)
        expect(result[:remaining_count]).to eq(50)
      end
    end

    context 'when some deletions fail' do
      let(:expired) { [backup_fixture('ok'), backup_fixture('bad')] }

      before do
        allow(api_client).to receive(:get).and_return('data' => expired)
        allow(api_client).to receive(:delete)
          .with('/api/v1/internal/maintenance/backups/ok').and_return('success' => true)
        allow(api_client).to receive(:delete)
          .with('/api/v1/internal/maintenance/backups/bad').and_return('success' => false, 'error' => 'locked')
      end

      it 'counts failures separately and reports overall failure' do
        result = job.execute

        expect(result[:deleted_count]).to eq(1)
        expect(result[:failed_count]).to eq(1)
        expect(result[:success]).to be false
      end
    end

    context 'when a deletion raises' do
      let(:expired) { [backup_fixture('boom')] }

      before do
        allow(api_client).to receive(:get).and_return('data' => expired)
        allow(api_client).to receive(:delete).and_raise(StandardError.new('network down'))
      end

      it 'treats the raised deletion as a failure without aborting the whole run' do
        result = job.execute

        expect(result[:deleted_count]).to eq(0)
        expect(result[:failed_count]).to eq(1)
        expect(result[:success]).to be false
      end
    end

    context 'when fetching expired backups fails' do
      before do
        allow(api_client).to receive(:get).and_raise(StandardError.new('backend down'))
      end

      it 'returns an empty cleanup result instead of raising' do
        result = job.execute

        expect(result[:success]).to be true
        expect(result[:deleted_count]).to eq(0)
      end
    end
  end
end
