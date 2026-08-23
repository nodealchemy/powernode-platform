# frozen_string_literal: true

require_relative '../base_job'

# Periodic sweep for the scheduled-report pipeline.
#
# Takes no arguments — it is a cron trigger, registered in config/sidekiq.yml
# under sidekiq-scheduler. It asks the server to dispatch every ScheduledReport
# whose next_run_at has passed; the server creates the ReportRequest rows and
# enqueues Reports::GenerateReportJob for each, because only the server can
# write those rows.
#
# Also reachable on demand from the server via
# PdfReportService.generate_scheduled_reports (args: []).
#
# retry: 0 — the sweep has a per-call side effect (it dispatches reports), so a
# retry of a request the server already acted on would dispatch them twice. The
# cron re-runs every 15 minutes, which is the recovery path; a failed sweep goes
# to the dead set for visibility rather than being re-sent.
class Reports::ScheduledReportSweepJob < BaseJob
  sidekiq_options queue: 'reports',
                  retry: 0,
                  dead: true

  SWEEP_PATH = '/api/v1/internal/reports/process_scheduled'

  # Statuses that mean "the backend is not reachable right now" rather than
  # "the sweep is broken". BackendApiClient converts Faraday::ConnectionFailed
  # to ApiError(503) and Faraday::TimeoutError to ApiError(408) before either
  # reaches this job, so those are the shapes to match on.
  TRANSIENT_STATUSES = [ 408, 502, 503, 504 ].freeze

  def execute(*_args)
    log_info('[ScheduledReportSweep] Checking for due scheduled reports')

    # post_no_retry: dispatching reports is NOT idempotent. The default
    # connection would re-send this POST up to 5 times on a timeout, and each
    # re-send would dispatch the reports the first one had not yet reached.
    response = api_client.post_no_retry(SWEEP_PATH)
    data = response['data'] || {}

    log_info('[ScheduledReportSweep] Sweep completed',
             due_count: data['due_count'],
             reports_processed: data['reports_processed'],
             reports_skipped: data['reports_skipped'],
             reports_failed: data['reports_failed'],
             remaining_count: data['remaining_count'])

    data
  rescue BackendApiClient::ApiError => e
    raise unless TRANSIENT_STATUSES.include?(e.status)

    log_info("[ScheduledReportSweep] Backend unavailable (#{e.status}), skipping until the next cron tick")
    {}
  end
end
