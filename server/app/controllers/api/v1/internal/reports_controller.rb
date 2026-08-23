# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Worker-facing endpoints for the async report pipeline.
      #
      # Both actions exist because the corresponding work can only be done
      # server-side: dispatching a scheduled report creates a ReportRequest row
      # (ScheduledReport#execute_report!), and the retention sweep destroys rows
      # plus their stored artifacts. The worker owns the *schedule*
      # (Reports::ScheduledReportSweepJob under sidekiq-scheduler) and calls in.
      class ReportsController < InternalBaseController
        # Ceiling on scheduled reports dispatched by one sweep. Report
        # generation is expensive; a large due backlog is drained across
        # successive sweeps rather than fanned out all at once.
        MAX_REPORTS_PER_SWEEP = 25

        # Wall-clock ceiling for one sweep. Each dispatch makes a SYNCHRONOUS
        # HTTP call to the worker (WorkerJobService, 10s read timeout), so a
        # slow worker could otherwise hold this request past the caller's own
        # timeout — at which point the caller sees a failure for work that is
        # still running, and a re-send would dispatch the same rows twice.
        # Stopping early is safe: the leftovers stay due and the next cron tick
        # picks them up.
        MAX_SWEEP_SECONDS = 45

        DEFAULT_RETENTION_DAYS = 30

        # Floor on the retention window. days_old: 0 would put the boundary at
        # "now" and sweep away artifacts a user is still downloading.
        MIN_RETENTION_DAYS = 1

        # Above this a `days_old` is a caller bug, not an instruction.
        MAX_RETENTION_DAYS = 3650

        MAX_CLEANUP_LIMIT = 500

        # POST /api/v1/internal/reports/process_scheduled
        #
        # Dispatch every ScheduledReport whose next_run_at has passed. Each
        # dispatch creates a ReportRequest and enqueues Reports::GenerateReportJob
        # via PdfReportService.enqueue!, then advances the schedule.
        def process_scheduled
          due = ScheduledReport.due_for_execution
          due_count = due.count

          processed = 0
          skipped = 0
          failed = 0

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MAX_SWEEP_SECONDS

          due.includes(:account, :user).order(:next_run_at).limit(MAX_REPORTS_PER_SWEEP).to_a.each do |scheduled_report|
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              Rails.logger.warn "[ScheduledReportSweep] Hit the #{MAX_SWEEP_SECONDS}s budget; leaving the rest for the next tick"
              break
            end

            begin
              if scheduled_report.execute_report!
                processed += 1
              else
                skipped += 1
              end
            rescue StandardError => e
              Rails.logger.error "[ScheduledReportSweep] Failed to dispatch scheduled report #{scheduled_report.id}: #{e.message}"
              failed += 1
              begin
                scheduled_report.reschedule_after_failure!
              rescue StandardError => reschedule_error
                Rails.logger.error "[ScheduledReportSweep] Failed to advance schedule for #{scheduled_report.id}: #{reschedule_error.message}"
              end
            end
          end

          render_success(
            data: {
              due_count: due_count,
              reports_processed: processed,
              reports_skipped: skipped,
              reports_failed: failed,
              remaining_count: [ due_count - (processed + skipped + failed), 0 ].max
            }
          )
        end

        # POST /api/v1/internal/reports/cleanup_old
        #
        # DESTRUCTIVE. Removes finished ReportRequest rows past the retention
        # boundary along with their stored artifacts. Bounded on every call and
        # supports dry_run so the backlog can be counted before anything is
        # deleted.
        def cleanup_old
          days_old = retention_days(params[:days_old])
          limit = deletion_limit(params[:limit])
          dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) ? true : false
          retention_boundary = days_old.days.ago

          summary = ReportRequest.cleanup_old_requests(
            older_than: days_old.days,
            limit: limit,
            dry_run: dry_run
          )

          Rails.logger.info(
            "[ReportCleanup] days_old=#{days_old} limit=#{limit} dry_run=#{dry_run} " \
            "candidates=#{summary[:candidate_count]} deleted=#{summary[:deleted_count]} " \
            "files_deleted=#{summary[:files_deleted]} remaining=#{summary[:remaining_count]}"
          )

          # One audit entry per destroyed row. AuditLog requires an account and a
          # resource id, and a bulk sweep spans accounts, so a single aggregate
          # row cannot be recorded truthfully. Bounded by `limit` like the
          # deletion itself.
          summary[:deleted_records].each do |record|
            log_internal_audit(
              "report_request_cleanup_deleted",
              "ReportRequest",
              record[:id],
              account_id: record[:account_id],
              days_old: days_old,
              retention_boundary: retention_boundary.iso8601
            )
          end

          render_success(data: summary.except(:deleted_records).merge(days_old: days_old, limit: limit))
        end

        private

        # Anything unparseable, below the floor, or absurdly large falls back to
        # the DEFAULT — never to the floor. For a destructive sweep the safe
        # direction to fail is toward MORE retention: coercing "abc" to 1 day
        # would delete nearly everything.
        def retention_days(raw)
          parsed = Integer(raw, exception: false)
          return DEFAULT_RETENTION_DAYS if parsed.nil?
          return DEFAULT_RETENTION_DAYS if parsed < MIN_RETENTION_DAYS || parsed > MAX_RETENTION_DAYS

          parsed
        end

        def deletion_limit(raw)
          parsed = Integer(raw, exception: false)
          return ReportRequest::DEFAULT_CLEANUP_LIMIT if parsed.nil?

          parsed.clamp(1, MAX_CLEANUP_LIMIT)
        end
      end
    end
  end
end
