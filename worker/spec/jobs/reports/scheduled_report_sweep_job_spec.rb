# frozen_string_literal: true

require 'rails_helper'

# Reports::ScheduledReportSweepJob is the consumer for
# PdfReportService.generate_scheduled_reports ("Reports::ScheduledReportSweepJob",
# args: [], queue: "reports"). Before it existed the enqueue was refused with a
# 422 by the worker's JobsController#valid_job_class? and the failure was
# swallowed by the caller's best-effort rescue.
RSpec.describe Reports::ScheduledReportSweepJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  let(:api_client_double) { instance_double(BackendApiClient) }
  let(:job) { described_class.new }

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
  end

  describe 'producer contract' do
    it 'runs on the queue the producer enqueues to' do
      expect(described_class.sidekiq_options['queue']).to eq('reports')
    end

    # A retry would re-dispatch reports the first attempt already sent.
    it 'is not retried — the 15-minute cron is the recovery path' do
      expect(described_class.sidekiq_options['retry']).to eq(0)
    end

    # The producer sends args: [] — execute must accept being called with no
    # arguments at all, or every dispatch dies with ArgumentError.
    it 'accepts the zero-argument call the producer makes' do
      allow(api_client_double).to receive(:post_no_retry).and_return('success' => true, 'data' => {})

      expect { job.execute }.not_to raise_error
    end
  end

  describe '#execute' do
    # Dispatching reports is NOT idempotent: the default connection re-sends a
    # POST up to 5 times on a lost response, and each re-send would dispatch the
    # rows the first attempt had not yet reached.
    it 'asks the server to dispatch due scheduled reports on a NON-RETRYING connection' do
      expect(api_client_double).not_to receive(:post)
      expect(api_client_double).to receive(:post_no_retry)
        .with('/api/v1/internal/reports/process_scheduled')
        .and_return(
          'success' => true,
          'data' => { 'due_count' => 3, 'reports_processed' => 3, 'reports_skipped' => 0,
                      'reports_failed' => 0, 'remaining_count' => 0 }
        )

      result = job.execute

      expect(result['reports_processed']).to eq(3)
    end

    it 'logs the dispatch counts on success' do
      allow(api_client_double).to receive(:post_no_retry).and_return(
        'success' => true,
        'data' => { 'due_count' => 2, 'reports_processed' => 2, 'reports_skipped' => 0,
                    'reports_failed' => 0, 'remaining_count' => 0 }
      )
      capture_logs_for(job)

      job.execute

      expect_logged(:info, /Sweep completed/)
    end

    # BackendApiClient converts Faraday::ConnectionFailed to ApiError(503) and
    # Faraday::TimeoutError to ApiError(408) before either reaches the job, so
    # those are the only shapes a real backend outage can take here.
    it 'does not blow up the cron when the backend is unreachable' do
      allow(api_client_double).to receive(:post_no_retry)
        .and_raise(BackendApiClient::ApiError.new('Connection failed', 503))
      capture_logs_for(job)

      expect { job.execute }.not_to raise_error
      expect_logged(:info, /Backend unavailable \(503\)/)
    end

    it 'swallows a request timeout the same way' do
      allow(api_client_double).to receive(:post_no_retry)
        .and_raise(BackendApiClient::ApiError.new('Request timeout', 408))

      expect { job.execute }.not_to raise_error
    end

    # A real server-side bug must NOT be swallowed — it has to reach the dead
    # set, because retry: 0 means nothing else will surface it.
    it 'lets a genuine server error propagate' do
      allow(api_client_double).to receive(:post_no_retry)
        .and_raise(BackendApiClient::ApiError.new('Internal Server Error', 500))

      expect { job.execute }.to raise_error(BackendApiClient::ApiError)
    end
  end
end
