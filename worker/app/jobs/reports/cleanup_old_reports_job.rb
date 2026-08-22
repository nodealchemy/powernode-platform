# frozen_string_literal: true

require_relative '../base_job'

# DESTRUCTIVE retention sweep for the async report pipeline.
#
# Removes finished ReportRequest rows past the retention boundary along with
# their stored artifacts. The deletion itself happens server-side (only the
# server owns the rows); this job is the trigger.
#
# Enqueued by PdfReportService.cleanup_old_reports with a single options hash:
#   args: [{ "days_old" => 30 }]
#
# Deliberately NOT on a cron. Unlike the sweep, this job destroys data, and the
# backlog it faces on a deployment where it has never run is of unknown size.
# It runs only when something explicitly asks for it.
#
# Three safeties, all unconditional:
#   1. Every run first performs a dry-run count against the server and LOGS the
#      candidate count before anything is deleted.
#   2. The destructive pass is capped at MAX_DELETIONS_PER_RUN rows; whatever
#      is left over is reported as remaining_count for a later run.
#   3. The destructive call goes out on a NON-RETRYING connection, and the job
#      itself is retry: 0. Both matter: the default connection re-sends a POST
#      up to 5 times on a lost response, and Sidekiq would re-run the job on top
#      of that — so the "capped at 100" bound would really have been ~1200.
class Reports::CleanupOldReportsJob < BaseJob
  sidekiq_options queue: 'reports',
                  retry: 0,
                  dead: true

  CLEANUP_PATH = '/api/v1/internal/reports/cleanup_old'

  DEFAULT_RETENTION_DAYS = 30

  # A retention window of 0 days would put the boundary at "now" and sweep away
  # artifacts a user is still downloading.
  MIN_RETENTION_DAYS = 1

  # Nothing legitimate asks to keep reports for longer than this; a value above
  # it is a bug in the caller, not an instruction.
  MAX_RETENTION_DAYS = 3650

  # Hard ceiling on rows a single run may delete. The server clamps as well;
  # this is the worker-side half of the same bound.
  MAX_DELETIONS_PER_RUN = 100

  def execute(options = {})
    options = normalize_options(options)

    days_old = retention_days(options['days_old'])
    limit = deletion_limit(options['limit'])
    dry_run = truthy?(options['dry_run'])

    # Count BEFORE deleting — always, even on a destructive run. The size of
    # the backlog is on the record before a single row goes away. The count is
    # read-only, so it may go out on the retrying connection.
    preview = request_cleanup(days_old: days_old, limit: limit, dry_run: true)
    candidate_count = preview['candidate_count'].to_i

    log_info('[ReportCleanup] Retention candidates counted',
             days_old: days_old,
             limit: limit,
             candidate_count: candidate_count,
             dry_run: dry_run)

    if dry_run
      log_info('[ReportCleanup] Dry run — nothing deleted', candidate_count: candidate_count)
      return preview
    end

    if candidate_count.zero?
      log_info('[ReportCleanup] Nothing past the retention boundary')
      return preview
    end

    result = request_cleanup(days_old: days_old, limit: limit, dry_run: false)

    log_info('[ReportCleanup] Cleanup completed',
             deleted_count: result['deleted_count'],
             files_deleted: result['files_deleted'],
             remaining_count: result['remaining_count'])

    if result['remaining_count'].to_i.positive?
      log_info('[ReportCleanup] Backlog remains; capped at limit for this run',
               remaining_count: result['remaining_count'],
               limit: limit)
    end

    result
  end

  private

  # Unparseable, out-of-range, or below the floor all fall back to the DEFAULT,
  # never to the floor. For a destructive sweep the safe direction to fail is
  # toward MORE retention: coercing "abc" to 1 day would delete nearly
  # everything, which is exactly the accident this job must not have.
  def retention_days(raw)
    parsed = Integer(raw, exception: false)
    return DEFAULT_RETENTION_DAYS if parsed.nil?
    return DEFAULT_RETENTION_DAYS if parsed < MIN_RETENTION_DAYS || parsed > MAX_RETENTION_DAYS

    parsed
  end

  def deletion_limit(raw)
    parsed = Integer(raw, exception: false)
    return MAX_DELETIONS_PER_RUN if parsed.nil?

    parsed.clamp(1, MAX_DELETIONS_PER_RUN)
  end

  def request_cleanup(days_old:, limit:, dry_run:)
    body = { days_old: days_old, limit: limit, dry_run: dry_run }

    # The destructive call must NOT be re-sent on a lost response — a request
    # the server completed would delete another batch on every retry.
    response = if dry_run
                 api_client.post(CLEANUP_PATH, body)
               else
                 api_client.post_no_retry(CLEANUP_PATH, body)
               end

    unless response['success']
      raise BackendApiClient::ApiError.new("Report cleanup failed: #{response['error']}")
    end

    response['data'] || {}
  end

  def normalize_options(options)
    return {} unless options.is_a?(Hash)

    options.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
  end

  def truthy?(value)
    [true, 'true', 'True', 1, '1'].include?(value)
  end
end
