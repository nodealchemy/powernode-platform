# frozen_string_literal: true

require 'rails_helper'

# Reports::CleanupOldReportsJob is the consumer for
# PdfReportService.cleanup_old_reports, which sends a SINGLE options hash:
#   args: [{ "days_old" => 30 }]
#
# It destroys report rows and their stored artifacts, so the two safeties below
# are the point of the class, not decoration: it counts before it deletes, and
# every destructive pass is capped.
RSpec.describe Reports::CleanupOldReportsJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  let(:api_client_double) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
  end

  def dry_run_response(candidates)
    { 'success' => true,
      'data' => { 'candidate_count' => candidates, 'deleted_count' => 0, 'files_deleted' => 0,
                  'remaining_count' => candidates, 'dry_run' => true } }
  end

  def delete_response(candidates:, deleted:, remaining:)
    { 'success' => true,
      'data' => { 'candidate_count' => candidates, 'deleted_count' => deleted, 'files_deleted' => deleted,
                  'remaining_count' => remaining, 'dry_run' => false } }
  end

  # The dry-run count goes out on the normal (retrying) connection; the
  # DESTRUCTIVE pass must go out on the non-retrying one.
  def stub_transport(candidates:, deleted: nil, remaining: nil)
    deleted = candidates if deleted.nil?
    remaining = candidates - deleted if remaining.nil?
    allow(api_client_double).to receive(:post) { dry_run_response(candidates) }
    allow(api_client_double).to receive(:post_no_retry) do
      delete_response(candidates: candidates, deleted: deleted, remaining: remaining)
    end
  end

  describe 'producer contract' do
    it 'runs on the queue the producer enqueues to' do
      expect(described_class.sidekiq_options['queue']).to eq('reports')
    end

    # Sidekiq re-running the destructive pass would delete another batch on top
    # of the one the first attempt already removed.
    it 'is not retried' do
      expect(described_class.sidekiq_options['retry']).to eq(0)
    end

    # The producer sends exactly one positional arg, a hash with STRING keys.
    it 'accepts the single string-keyed options hash the producer sends' do
      stub_transport(candidates: 0)

      expect { job.execute('days_old' => 30) }.not_to raise_error
    end

    it 'honours days_old from the producer payload' do
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/reports/cleanup_old', hash_including(days_old: 7, dry_run: true))
        .and_return(dry_run_response(0))

      job.execute('days_old' => 7)
    end

    it 'defaults to 30 days when the producer sends an empty payload' do
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/reports/cleanup_old', hash_including(days_old: 30, dry_run: true))
        .and_return(dry_run_response(0))

      job.execute({})
    end
  end

  describe 'transport safety' do
    # The default connection retries POST up to 5 times on a lost response.
    # Re-sending a completed cleanup deletes another batch each time, which
    # would make "capped at 100" mean ~1200.
    it 'sends the DESTRUCTIVE pass on the non-retrying connection' do
      allow(api_client_double).to receive(:post).and_return(dry_run_response(5))
      expect(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/reports/cleanup_old', hash_including(dry_run: false))
        .once
        .and_return(delete_response(candidates: 5, deleted: 5, remaining: 0))

      job.execute('days_old' => 30)
    end

    it 'never sends a destructive pass on the retrying connection' do
      destructive_on_retrying = false
      allow(api_client_double).to receive(:post) do |_path, body|
        destructive_on_retrying = true unless body[:dry_run]
        dry_run_response(5)
      end
      allow(api_client_double).to receive(:post_no_retry)
        .and_return(delete_response(candidates: 5, deleted: 5, remaining: 0))

      job.execute('days_old' => 30)

      expect(destructive_on_retrying).to be false
    end
  end

  describe 'count-before-delete safety' do
    it 'issues a dry-run count BEFORE any destructive call' do
      calls = []
      allow(api_client_double).to receive(:post) do |_path, body|
        calls << [:count, body[:dry_run]]
        dry_run_response(5)
      end
      allow(api_client_double).to receive(:post_no_retry) do |_path, body|
        calls << [:destroy, body[:dry_run]]
        delete_response(candidates: 5, deleted: 5, remaining: 0)
      end

      job.execute('days_old' => 30)

      expect(calls).to eq([[:count, true], [:destroy, false]])
    end

    it 'logs the candidate count before deleting' do
      stub_transport(candidates: 42)
      capture_logs_for(job)

      job.execute('days_old' => 30)

      expect_logged(:info, /Retention candidates counted/)
      expect(@captured_logs[:info].index { |m| m =~ /Retention candidates counted/ })
        .to be < @captured_logs[:info].index { |m| m =~ /Cleanup completed/ }
    end

    it 'deletes NOTHING when dry_run is requested' do
      expect(api_client_double).not_to receive(:post_no_retry)
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/reports/cleanup_old', hash_including(dry_run: true))
        .once
        .and_return(dry_run_response(999))

      result = job.execute('days_old' => 30, 'dry_run' => true)

      expect(result['dry_run']).to be true
      expect(result['deleted_count']).to eq(0)
    end

    it 'skips the destructive call entirely when nothing is past the boundary' do
      expect(api_client_double).not_to receive(:post_no_retry)
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/reports/cleanup_old', hash_including(dry_run: true))
        .once
        .and_return(dry_run_response(0))

      job.execute('days_old' => 30)
    end
  end

  describe 'bounding' do
    it 'never asks for more than MAX_DELETIONS_PER_RUN in one pass' do
      requested_limits = []
      allow(api_client_double).to receive(:post) do |_path, body|
        requested_limits << body[:limit]
        dry_run_response(10_000)
      end
      allow(api_client_double).to receive(:post_no_retry) do |_path, body|
        requested_limits << body[:limit]
        delete_response(candidates: 10_000, deleted: 100, remaining: 9_900)
      end

      job.execute('days_old' => 30)

      expect(requested_limits.uniq).to eq([described_class::MAX_DELETIONS_PER_RUN])
    end

    it 'clamps an over-large caller-supplied limit down to the cap' do
      requested_limits = []
      allow(api_client_double).to receive(:post) do |_path, body|
        requested_limits << body[:limit]
        dry_run_response(0)
      end

      job.execute('days_old' => 30, 'limit' => 100_000)

      expect(requested_limits.uniq).to eq([described_class::MAX_DELETIONS_PER_RUN])
    end

    it 'reports the remaining backlog instead of looping to drain it' do
      stub_transport(candidates: 250, deleted: 100, remaining: 150)
      capture_logs_for(job)

      result = job.execute('days_old' => 30)

      expect(result['remaining_count']).to eq(150)
      expect_logged(:info, /Backlog remains/)
    end
  end

  # For a DESTRUCTIVE sweep the safe direction to fail is toward MORE retention.
  # A garbage days_old that collapsed to the 1-day floor would delete nearly
  # everything, so every rejected value falls back to the 30-day DEFAULT.
  describe 'retention coercion fails safe' do
    def expect_days_old(sent, expected)
      expect(api_client_double).to receive(:post)
        .with('/api/v1/internal/reports/cleanup_old', hash_including(days_old: expected))
        .and_return(dry_run_response(0))

      job.execute('days_old' => sent)
    end

    it 'falls back to the default for a zero-day window' do
      expect_days_old(0, described_class::DEFAULT_RETENTION_DAYS)
    end

    it 'falls back to the default for a negative window' do
      expect_days_old(-5, described_class::DEFAULT_RETENTION_DAYS)
    end

    it 'falls back to the default for an unparseable window' do
      expect_days_old('abc', described_class::DEFAULT_RETENTION_DAYS)
    end

    it 'falls back to the default for an empty string' do
      expect_days_old('', described_class::DEFAULT_RETENTION_DAYS)
    end

    it 'falls back to the default for an absurdly large window' do
      expect_days_old(1_000_000_000, described_class::DEFAULT_RETENTION_DAYS)
    end

    it 'accepts a legitimate numeric string' do
      expect_days_old('7', 7)
    end
  end

  describe 'error handling' do
    it 'lets a transport-level failure of the count pass propagate' do
      allow(api_client_double).to receive(:post)
        .and_raise(BackendApiClient::ApiError.new('Connection failed', 503))

      expect { job.execute('days_old' => 30) }.to raise_error(BackendApiClient::ApiError)
    end

    it 'raises when the server rejects the cleanup so Sidekiq records the failure' do
      allow(api_client_double).to receive(:post).and_return('success' => false, 'error' => 'nope')

      expect { job.execute('days_old' => 30) }.to raise_error(BackendApiClient::ApiError, /nope/)
    end
  end
end
