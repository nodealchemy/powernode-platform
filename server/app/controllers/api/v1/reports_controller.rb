# frozen_string_literal: true

# Async-only reports API. The server creates a ReportRequest row and dispatches
# the worker job through PdfReportService.enqueue!; the worker renders the file
# and updates the request. Clients poll request_details and download via
# download_request once status is "completed".
class Api::V1::ReportsController < ApplicationController
  before_action :check_reports_permission
  before_action :set_date_range, only: %i[index templates]
  before_action :set_account_scope

  REPORT_TYPES = PdfReportService::REPORT_TYPES
  SUPPORTED_FORMATS = PdfReportService::SUPPORTED_FORMATS

  # GET /api/v1/reports
  def index
    render_success(
      data: {
        available_reports: REPORT_TYPES.map { |type| { type: type, name: humanize(type), formats: SUPPORTED_FORMATS } },
        supported_formats: SUPPORTED_FORMATS,
        max_date_range_days: 730
      }
    )
  end

  # GET /api/v1/reports/templates
  def templates
    render_success(data: REPORT_TYPES.map { |type| template_descriptor(type) })
  end

  # GET /api/v1/reports/requests
  def requests
    page = [(params[:page]&.to_i || 1), 1].max
    limit = (params[:limit]&.to_i || 20).clamp(1, 100)

    report_requests = scoped_report_requests
                                   .order(created_at: :desc)
                                   .limit(limit)
                                   .offset((page - 1) * limit)

    render_success(data: report_requests.map { |r| serialize_request(r) })
  end

  # GET /api/v1/reports/requests/:id
  def request_details
    report_request = scoped_report_requests.find(params[:id])
    render_success(data: serialize_request(report_request))
  rescue ActiveRecord::RecordNotFound
    render_error("Report request not found", status: :not_found)
  end

  # POST /api/v1/reports/requests
  def create_request
    template_id = params[:template_id]
    format = params[:format] || "pdf"
    name = params[:name]
    parameters = params[:parameters].is_a?(ActionController::Parameters) ? params[:parameters].to_unsafe_h : (params[:parameters] || {})

    unless REPORT_TYPES.include?(template_id)
      return render_error("Invalid template ID. Allowed: #{REPORT_TYPES.join(', ')}", status: :unprocessable_content)
    end
    unless SUPPORTED_FORMATS.include?(format)
      return render_error("Invalid format. Allowed: #{SUPPORTED_FORMATS.join(', ')}", status: :unprocessable_content)
    end

    date_range = parameters["date_range"] || {}

    report_request = PdfReportService.enqueue!(
      report_type: template_id,
      account: @account_scope || current_user.account,
      user: current_user,
      format: format,
      name: name,
      start_date: parse_date(date_range["start_date"]),
      end_date: parse_date(date_range["end_date"]),
      parameters: parameters
    )

    render_success(data: serialize_request(report_request), status: :accepted)
  rescue ArgumentError => e
    render_error(e.message, status: :unprocessable_content)
  rescue StandardError => e
    render_internal_error("Failed to create report request", exception: e)
  end

  # PATCH /api/v1/reports/requests/:id  (worker callback)
  def update_request
    report_request = scoped_report_requests.find(params[:id])
    permitted = params.permit(:status, :file_path, :file_url, :file_size, :content_type, :error_message, :completed_at)
    report_request.update!(permitted)
    render_success(data: serialize_request(report_request))
  rescue ActiveRecord::RecordNotFound
    render_not_found("Report request")
  rescue StandardError => e
    render_internal_error("Failed to update report request", exception: e)
  end

  # DELETE /api/v1/reports/requests/:id
  def cancel_request
    report_request = scoped_report_requests.find(params[:id])

    return render_error("Cannot cancel completed request", status: :unprocessable_content) if report_request.completed?
    return render_error("Cannot cancel failed request", status: :unprocessable_content) if report_request.failed?

    report_request.cancel!
    render_success(data: serialize_request(report_request))
  rescue ActiveRecord::RecordNotFound
    render_error("Report request not found", status: :not_found)
  end

  # GET /api/v1/reports/requests/:id/download
  def download_request
    report_request = scoped_report_requests.find(params[:id])

    return render_error("Report not ready for download", status: :unprocessable_content) unless report_request.completed?
    return render_error("Report file missing", status: :not_found) unless report_request.file_path.present? && File.exist?(report_request.file_path)

    allowed_roots = [
      Rails.root.join("tmp", "reports").to_s,
      Rails.root.parent.join("worker", "storage", "reports").to_s
    ]
    expanded_path = File.expand_path(report_request.file_path)
    unless allowed_roots.any? { |root| expanded_path.start_with?(root) }
      Rails.logger.error "Blocked access to file outside reports directories: #{report_request.file_path}"
      return render_error("Invalid report file path", status: :forbidden)
    end

    send_file report_request.file_path,
              filename: report_request.generate_filename,
              type: report_request.content_type || "application/pdf",
              disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    render_error("Report request not found", status: :not_found)
  end

  # GET /api/v1/reports/scheduled
  def scheduled
    reports = scoped_scheduled_reports.active.order(:next_run_at)

    render_success(
      data: reports.map do |report|
        {
          id: report.id,
          name: report.name || humanize(report.report_type),
          template_id: report.report_type,
          frequency: report.frequency,
          next_run: report.next_run_at&.iso8601,
          last_run: report.last_run_at&.iso8601,
          enabled: report.is_active,
          delivery_method: report.try(:delivery_method) || "email",
          recipients: report.recipients_list,
          parameters: report.parameters || {},
          format: report.format
        }
      end
    )
  end

  private

  def scoped_report_requests
    @account_scope ? ReportRequest.for_account(@account_scope) : ReportRequest.all
  end

  def scoped_scheduled_reports
    @account_scope ? ScheduledReport.for_account(@account_scope) : ScheduledReport.all
  end

  def check_reports_permission
    return if worker_authenticated?
    return if has_permission?("analytics.export")

    render_error("Report generation permission required", status: :forbidden)
  end

  def set_date_range
    @start_date = parse_date(params[:start_date]) || 12.months.ago.to_date.beginning_of_month
    @end_date = parse_date(params[:end_date]) || Date.current.end_of_month

    if @start_date > @end_date
      render_error("Start date must be before end date", status: :unprocessable_content) and return
    end

    if (@end_date - @start_date) > 2.years
      render_error("Date range too large (max 2 years)", status: :unprocessable_content) and return
    end
  end

  def set_account_scope
    # Workers operate across all accounts when they call back to update report state.
    return @account_scope = nil if worker_authenticated?

    if has_permission?("analytics.global") && params[:account_id].present?
      @account_scope = Account.find(params[:account_id])
    elsif has_permission?("analytics.global") && params[:account_id].blank?
      @account_scope = nil
    else
      @account_scope = current_user.account
    end
  end

  def parse_date(value)
    return nil if value.blank?
    value.is_a?(Date) ? value : Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def humanize(report_type)
    report_type.to_s.tr("_", " ").titleize
  end

  TEMPLATE_DESCRIPTORS = {
    "revenue_analytics" => {
      name: "Revenue Analytics",
      description: "Comprehensive revenue analysis including MRR, ARR, growth trends, and forecasting",
      category: "financial",
      icon: "revenue",
      formats: %w[pdf csv]
    },
    "customer_analytics" => {
      name: "Customer Analytics",
      description: "Customer growth, ARPU, LTV, and segmentation analysis",
      category: "customer",
      icon: "customers",
      formats: %w[pdf csv]
    },
    "churn_analysis" => {
      name: "Churn Analysis",
      description: "Customer and revenue churn rates, trends, and retention insights",
      category: "analytics",
      icon: "churn",
      formats: %w[pdf csv]
    },
    "growth_analytics" => {
      name: "Growth Analytics",
      description: "Growth rates, new revenue expansion metrics, and compound growth analysis",
      category: "analytics",
      icon: "growth",
      formats: %w[pdf csv]
    },
    "cohort_analysis" => {
      name: "Cohort Analysis",
      description: "Customer retention by cohort and tenure analysis",
      category: "analytics",
      icon: "cohort",
      formats: %w[pdf csv]
    },
    "comprehensive_report" => {
      name: "Executive Summary",
      description: "Complete business overview with all key metrics and insights",
      category: "executive",
      icon: "summary",
      formats: %w[pdf]
    }
  }.freeze

  def template_descriptor(report_type)
    descriptor = TEMPLATE_DESCRIPTORS.fetch(report_type)
    descriptor.merge(
      id: report_type,
      parameters: { requires_date_range: report_type != "cohort_analysis", filters: [] }
    )
  end

  def serialize_request(report_request)
    {
      id: report_request.id,
      name: report_request.name,
      type: report_request.report_type,
      format: report_request.format,
      status: report_request.status,
      requested_at: report_request.created_at.iso8601,
      completed_at: report_request.completed_at&.iso8601,
      file_url: report_request.file_url,
      file_size: report_request.file_size,
      error_message: report_request.error_message,
      parameters: report_request.parameters || {}
    }
  end
end
