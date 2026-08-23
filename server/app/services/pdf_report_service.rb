# frozen_string_literal: true

# PdfReportService — thin enqueue helper for the async report pipeline.
#
# All report generation happens in the worker via `Reports::GenerateReportJob`.
# The server's role is to create a `ReportRequest` row and dispatch the job through
# `WorkerJobService`. Polling and download go through `Api::V1::ReportsController`.
#
# Canonical report types follow the `*_analytics` / `*_analysis` taxonomy and are
# validated identically on `ReportRequest`.
class PdfReportService
  REPORT_TYPES = %w[
    revenue_analytics
    customer_analytics
    churn_analysis
    growth_analytics
    cohort_analysis
    comprehensive_report
  ].freeze

  SUPPORTED_FORMATS = %w[pdf csv].freeze

  class << self
    # Create a ReportRequest and dispatch the worker job. Returns the persisted request.
    def enqueue!(report_type:, account:, user:, format: "pdf", name: nil, start_date: nil, end_date: nil, parameters: {})
      raise ArgumentError, "Unsupported report type: #{report_type}" unless REPORT_TYPES.include?(report_type)
      raise ArgumentError, "Unsupported format: #{format}" unless SUPPORTED_FORMATS.include?(format)

      start_date ||= 12.months.ago.to_date.beginning_of_month
      end_date ||= Date.current.end_of_month

      request_params = parameters.to_h.deep_dup
      request_params["date_range"] ||= {
        "start_date" => start_date.iso8601,
        "end_date" => end_date.iso8601
      }

      report_request = ReportRequest.create!(
        account: account,
        user: user,
        name: name.presence || default_name(report_type),
        report_type: report_type,
        format: format,
        status: "pending",
        parameters: request_params,
        requested_at: Time.current
      )

      begin
        WorkerJobService.enqueue_job(
          "Reports::GenerateReportJob",
          args: [report_request.id],
          queue: "reports"
        )
      rescue WorkerJobService::WorkerServiceError => e
        # The row is already committed. If the enqueue failed, nothing will ever
        # process it, and a "pending" row is excluded from the retention sweep
        # (ReportRequest::CLEANUP_STATUSES) — so leaving it pending creates a row
        # that can never be reaped. Mark it failed and re-raise.
        Rails.logger.error "Failed to enqueue report generation for #{report_request.id}: #{e.message}"
        report_request.mark_failed!("Could not enqueue report generation: #{e.message}")
        raise
      end

      report_request
    end

    def generate_scheduled_reports
      Rails.logger.info "Dispatching scheduled report sweep to worker"
      WorkerJobService.enqueue_job("Reports::ScheduledReportSweepJob", args: [], queue: "reports")
      { success: true, message: "Scheduled report sweep queued" }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to dispatch scheduled report sweep: #{e.message}"
      { success: false, error: e.message }
    end

    def cleanup_old_reports(days_old: 30)
      Rails.logger.info "Dispatching report cleanup to worker"
      WorkerJobService.enqueue_job(
        "Reports::CleanupOldReportsJob",
        args: [{ "days_old" => days_old }],
        queue: "reports"
      )
      { success: true, message: "Report cleanup queued" }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to dispatch report cleanup: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def default_name(report_type)
      "#{report_type.humanize} (#{Date.current.iso8601})"
    end
  end
end
