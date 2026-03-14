# frozen_string_literal: true

class Api::V1::ReportsController < ApplicationController
  before_action :check_reports_permission
  before_action :set_date_range
  before_action :set_account_scope

  SUPPORTED_FORMATS = %w[pdf csv].freeze
  REPORT_TYPES = PdfReportService::REPORT_TYPES

  # GET /api/v1/reports/:report_type
  def show
    # Route provides :id param, treat as report_type
    params[:report_type] ||= params[:id]

    unless REPORT_TYPES.include?(params[:report_type])
      return render_error(
        "Invalid report type. Supported types: #{REPORT_TYPES.join(', ')}",
        :bad_request
      )
    end

    format = params[:format]&.downcase || "pdf"

    unless SUPPORTED_FORMATS.include?(format)
      return render_error(
        "Invalid format. Supported formats: #{SUPPORTED_FORMATS.join(', ')}",
        :bad_request
      )
    end

    case format
    when "pdf"
      generate_pdf_report
    when "csv"
      generate_csv_report
    end
  rescue StandardError => e
    render_internal_error("Report generation failed", exception: e)
  end

  # GET /api/v1/reports
  def index
    render_success(
      data: {
        available_reports: REPORT_TYPES.map do |report_type|
          {
            type: report_type,
            name: humanize_report_type(report_type),
            description: report_description(report_type),
            supported_formats: SUPPORTED_FORMATS
          }
        end,
        supported_formats: SUPPORTED_FORMATS,
        max_date_range_days: 730 # 2 years
      }
    )
  end

  # GET /api/v1/reports/templates
  def templates
    render_success(
      data: [
        {
          id: "revenue_analytics",
          name: "Revenue Analytics",
          description: "Comprehensive revenue analysis including MRR, ARR, growth trends, and forecasting",
          category: "financial",
          icon: "💰",
          formats: [ "pdf", "csv", "xlsx" ],
          parameters: {
            requires_date_range: true,
            filters: [
              {
                name: "plan_id",
                type: "select",
                label: "Plan",
                options: (defined?(Billing::Plan) ? Billing::Plan.pluck(:name) : []),
                required: false
              }
            ]
          }
        },
        {
          id: "customer_analytics",
          name: "Customer Analytics",
          description: "Customer growth, ARPU, LTV, and segmentation analysis",
          category: "customer",
          icon: "👥",
          formats: [ "pdf", "csv", "xlsx" ],
          parameters: {
            requires_date_range: true,
            filters: [
              {
                name: "status",
                type: "select",
                label: "Customer Status",
                options: [ "active", "inactive", "trial" ],
                required: false
              }
            ]
          }
        },
        {
          id: "churn_analysis",
          name: "Churn Analysis",
          description: "Customer and revenue churn rates, trends, and retention insights",
          category: "analytics",
          icon: "📉",
          formats: [ "pdf", "csv" ],
          parameters: {
            requires_date_range: true,
            filters: []
          }
        },
        {
          id: "growth_analytics",
          name: "Growth Analytics",
          description: "Growth rates, new revenue expansion metrics, and compound growth analysis",
          category: "analytics",
          icon: "📈",
          formats: [ "pdf", "csv" ],
          parameters: {
            requires_date_range: true,
            filters: []
          }
        },
        {
          id: "cohort_analysis",
          name: "Cohort Analysis",
          description: "Customer retention by cohort and tenure analysis",
          category: "analytics",
          icon: "🔄",
          formats: [ "pdf", "csv" ],
          parameters: {
            requires_date_range: false,
            filters: [
              {
                name: "cohort_period",
                type: "select",
                label: "Cohort Period",
                options: [ "monthly", "quarterly" ],
                required: false
              }
            ]
          }
        },
        {
          id: "comprehensive_report",
          name: "Executive Summary",
          description: "Complete business overview with all key metrics and insights",
          category: "executive",
          icon: "📊",
          formats: [ "pdf" ],
          parameters: {
            requires_date_range: true,
            filters: []
          }
        }
      ]
    )
  end

  # GET /api/v1/reports/requests
  def requests
    page = params[:page]&.to_i || 1
    limit = params[:limit]&.to_i || 20
    limit = [ limit, 100 ].min # Cap at 100

    report_requests = ReportRequest.for_account(@account_scope)
                                  .order(created_at: :desc)
                                  .limit(limit)
                                  .offset((page - 1) * limit)

    render_success(
      data: report_requests.map do |request|
        {
          id: request.id,
          name: request.name,
          type: request.report_type,
          format: request.format,
          status: request.status,
          requested_at: request.created_at.iso8601,
          completed_at: request.completed_at&.iso8601,
          file_url: request.file_url,
          file_size: request.file_size,
          error_message: request.error_message,
          parameters: request.parameters
        }
      end
    )
  end

  # GET /api/v1/reports/requests/:id
  def request_details
    request = ReportRequest.for_account(@account_scope).find(params[:id])

    render_success(
      data: {
        id: request.id,
        name: request.name,
        type: request.report_type,
        format: request.format,
        status: request.status,
        requested_at: request.created_at.iso8601,
        completed_at: request.completed_at&.iso8601,
        file_url: request.file_url,
        file_size: request.file_size,
        error_message: request.error_message,
        parameters: request.parameters
      }
    )
  rescue ActiveRecord::RecordNotFound
    render_error("Report request not found", status: :internal_server_error)
  end

  # POST /api/v1/reports/requests
  def create_request
    template_id = params[:template_id]
    name = params[:name]
    format = params[:format]
    parameters = params[:parameters] || {}

    # Validate template exists
    template_ids = [ "revenue_analytics", "customer_analytics", "churn_analysis", "growth_analytics", "cohort_analysis", "comprehensive_report" ]
    unless template_ids.include?(template_id)
      render_error("Invalid template ID", status: :internal_server_error)
      return
    end

    # Create the report request
    request = ReportRequest.create!(
      account: @account_scope,
      user: current_user,
      name: name,
      report_type: template_id,
      format: format,
      status: "pending",
      parameters: parameters
    )

    # Queue background job to generate the report (job lives in worker service)
    GenerateReportJob.perform_later(request.id)

    render_success(
      data: {
        id: request.id,
        name: request.name,
        status: request.status,
        requested_at: request.created_at.iso8601
      }
    )
  rescue StandardError => e
    render_internal_error("Failed to create report request", exception: e)
  end

  # PATCH /api/v1/reports/requests/:id
  def update_request
    request = ReportRequest.for_account(@account_scope).find(params[:id])

    update_params = params.permit(:status, :file_path, :file_url, :file_size, :error_message, :completed_at)

    request.update!(update_params)

    render_success(
      data: {
        id: request.id,
        status: request.status,
        updated_at: request.updated_at.iso8601
      }
    )
  rescue ActiveRecord::RecordNotFound
    render_not_found("Report request")
  rescue StandardError => e
    render_internal_error("Failed to update report request", exception: e)
  end

  # DELETE /api/v1/reports/requests/:id
  def cancel_request
    request = ReportRequest.for_account(@account_scope).find(params[:id])

    if request.status == "completed"
      render_error("Cannot cancel completed request", status: :internal_server_error)
      return
    end

    if request.status == "failed"
      render_error("Cannot cancel failed request", status: :internal_server_error)
      return
    end

    request.update!(status: "cancelled")

    render_success
  rescue ActiveRecord::RecordNotFound
    render_error("Report request not found", status: :internal_server_error)
  end

  # GET /api/v1/reports/requests/:id/download
  def download_request
    request = ReportRequest.for_account(@account_scope).find(params[:id])

    unless request.status == "completed" && request.file_url
      render_error("Report not ready for download", status: :internal_server_error)
      return
    end

    # In a real implementation, this would serve the file from storage (S3, etc.)
    # For now, we'll redirect to the file URL or serve it directly
    if request.file_path && File.exist?(request.file_path)
      # Security: Validate file path is within allowed reports directory
      reports_base = Rails.root.join("tmp", "reports").to_s
      expanded_path = File.expand_path(request.file_path)
      unless expanded_path.start_with?(reports_base)
        Rails.logger.error "Attempted access to file outside reports directory: #{request.file_path}"
        return render_error("Invalid report file path", status: :forbidden)
      end

      send_file request.file_path,
                filename: "#{request.name.parameterize}.#{request.format}",
                type: request.content_type,
                disposition: "attachment"
    else
      render_error("Report file not found", status: :internal_server_error)
    end
  rescue ActiveRecord::RecordNotFound
    render_error("Report request not found", status: :internal_server_error)
  end

  # GET /api/v1/reports/scheduled
  def scheduled
    reports = ScheduledReport.for_account(@account_scope)
                            .where(is_active: true)
                            .order(:next_run_at)

    render_success(
      data: reports.map do |report|
        {
          id: report.id,
          name: report.name || humanize_report_type(report.report_type),
          template_id: report.report_type,
          frequency: report.frequency,
          next_run: report.next_run_at&.iso8601,
          last_run: report.last_run_at&.iso8601,
          enabled: report.is_active,
          delivery_method: report.try(:delivery_method) || "email",
          recipients: report.recipients || [],
          parameters: report.parameters || {},
          format: report.format
        }
      end
    )
  end

  # POST /api/v1/reports/generate
  def generate
    report_requests = params[:reports] || []

    if report_requests.empty?
      render_error("No reports requested", status: :internal_server_error)
      return
    end

    generated_reports = []

    report_requests.each do |request|
      report_type = request[:type]
      format = request[:format] || "pdf"

      next unless REPORT_TYPES.include?(report_type) && SUPPORTED_FORMATS.include?(format)

      case format
      when "pdf"
        pdf_data = PdfReportService.new(
          report_type: report_type,
          account: @account_scope,
          start_date: @start_date,
          end_date: @end_date,
          user: current_user
        ).generate_pdf

        generated_reports << {
          type: report_type,
          format: format,
          filename: "#{report_type}_#{Date.current.strftime('%Y%m%d')}.pdf",
          data: Base64.encode64(pdf_data),
          content_type: "application/pdf",
          size: pdf_data.bytesize
        }
      when "csv"
        csv_data = generate_csv_data(report_type)

        generated_reports << {
          type: report_type,
          format: format,
          filename: "#{report_type}_#{Date.current.strftime('%Y%m%d')}.csv",
          data: Base64.encode64(csv_data),
          content_type: "text/csv",
          size: csv_data.bytesize
        }
      end
    end

    render_success(
      data: {
        reports: generated_reports,
        generated_at: Time.current.iso8601,
        account: @account_scope ? {
          id: @account_scope.id,
          name: @account_scope.name
        } : nil,
        period: {
          start_date: @start_date,
          end_date: @end_date
        }
      }
    )
  end

  # POST /api/v1/reports/schedule
  def schedule
    report_type = params[:report_type]
    frequency = params[:frequency] # daily, weekly, monthly
    recipients = params[:recipients] || []
    format = params[:format] || "pdf"

    unless REPORT_TYPES.include?(report_type)
      render_error("Invalid report type", status: :internal_server_error)
      return
    end

    unless %w[daily weekly monthly].include?(frequency)
      return render_error(
        "Invalid frequency. Use: daily, weekly, monthly",
        :bad_request
      )
    end

    # Create scheduled report record
    scheduled_report = ScheduledReport.create!(
      report_type: report_type,
      frequency: frequency,
      recipients: recipients,
      format: format,
      account: @account_scope,
      user: current_user,
      next_run_at: calculate_next_run_time(frequency),
      active: true
    )

    render_success(
      data: {
        id: scheduled_report.id,
        report_type: scheduled_report.report_type,
        frequency: scheduled_report.frequency,
        next_run_at: scheduled_report.next_run_at,
        recipients: scheduled_report.recipients
      }
    )
  rescue StandardError => e
    render_internal_error("Failed to schedule report", exception: e)
  end

  # GET /api/v1/reports/scheduled
  def scheduled_reports
    reports = ScheduledReport.for_account(@account_scope)
                            .where(active: true)
                            .order(:next_run_at)

    render_success(
      data: reports.map do |report|
        {
          id: report.id,
          report_type: report.report_type,
          frequency: report.frequency,
          next_run_at: report.next_run_at,
          recipients: report.recipients,
          last_run_at: report.last_run_at,
          created_at: report.created_at
        }
      end
    )
  end

  # DELETE /api/v1/reports/scheduled/:id
  def destroy_scheduled
    scheduled_report = ScheduledReport.for_account(@account_scope).find(params[:id])
    scheduled_report.update!(active: false)

    render_success(message: "Scheduled report cancelled")
  rescue ActiveRecord::RecordNotFound
    render_error("Scheduled report not found", status: :internal_server_error)
  end

  private

  def check_reports_permission
    unless current_user.has_permission?("analytics.export") || current_user.has_permission?("analytics.global")
      render_error("Report generation permission required", status: :internal_server_error)
    end
  end

  def set_date_range
    @start_date = params[:start_date]&.to_date || 12.months.ago.to_date.beginning_of_month
    @end_date = params[:end_date]&.to_date || Date.current.end_of_month

    # Validate date range
    if @start_date > @end_date
      render_error("Start date must be before end date", status: :internal_server_error)
      return
    end

    # Limit to reasonable range (2 years max)
    if @end_date - @start_date > 2.years
      render_error("Date range too large (max 2 years)", status: :internal_server_error)
      nil
    end
  end

  def set_account_scope
    # If user has global analytics permission, allow querying all accounts
    if current_user.has_permission?("analytics.global") && params[:account_id].blank?
      @account_scope = nil # Global analytics
    elsif params[:account_id].present? && current_user.has_permission?("analytics.global")
      @account_scope = Account.find(params[:account_id])
    else
      # Regular users can only generate reports for their own account
      @account_scope = current_user.account
    end
  end

  def generate_pdf_report
    pdf_data = PdfReportService.new(
      report_type: params[:report_type],
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date,
      user: current_user
    ).generate_pdf

    send_data pdf_data,
              filename: "#{params[:report_type]}_#{Date.current.strftime('%Y%m%d')}.pdf",
              type: "application/pdf",
              disposition: "attachment"
  end

  def generate_csv_report
    csv_data = generate_csv_data(params[:report_type])

    send_data csv_data,
              filename: "#{params[:report_type]}_#{Date.current.strftime('%Y%m%d')}.csv",
              type: "text/csv",
              disposition: "attachment"
  end

  def generate_csv_data(report_type)
    case report_type
    when "customer_report"
      return export_customer_data_csv
    when "subscription_report"
      return export_subscription_data_csv
    end

    unless Powernode::ExtensionRegistry.loaded?("business")
      return CSV.generate(headers: true) { |csv| csv << ["Business feature required"] }
    end

    analytics_service = Billing::RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    case report_type
    when "revenue_report"
      analytics_service.export_revenue_data_csv("monthly")
    else
      # Default to revenue data
      analytics_service.export_revenue_data_csv("monthly")
    end
  end

  def export_customer_data_csv
    require "csv"

    customers = @account_scope ? @account_scope.users : User.all
    customers = customers.joins(:account).where(accounts: { status: "active" })

    CSV.generate(headers: true) do |csv|
      csv << [ "Customer ID", "Name", "Email", "Account", "Plan", "Status", "Created", "Last Login" ]

      customers.each do |customer|
        subscription = customer.account.subscription
        csv << [
          customer.id,
          customer.full_name,
          customer.email,
          customer.account.name,
          subscription&.plan&.name || "No Plan",
          subscription&.status || "No Subscription",
          customer.created_at.strftime("%Y-%m-%d"),
          customer.last_login_at&.strftime("%Y-%m-%d %H:%M") || "Never"
        ]
      end
    end
  end

  def export_subscription_data_csv
    require "csv"

    subscription_class = defined?(Billing::Subscription) ? Billing::Subscription : nil
    subscriptions = if subscription_class
      @account_scope ? @account_scope.subscriptions : subscription_class.all
    else
      return CSV.generate(headers: true) { |csv| csv << ["Billing not available"] }
    end
    subscriptions = subscriptions.includes(:account, :plan)

    CSV.generate(headers: true) do |csv|
      csv << [ "Subscription ID", "Account", "Plan", "Status", "MRR", "Created", "Current Period End", "Trial End" ]

      subscriptions.each do |sub|
        csv << [
          sub.id,
          sub.account.name,
          sub.plan.name,
          sub.status,
          (sub.plan.price_cents / 100.0),
          sub.created_at.strftime("%Y-%m-%d"),
          sub.current_period_end&.strftime("%Y-%m-%d") || "N/A",
          sub.trial_end&.strftime("%Y-%m-%d") || "N/A"
        ]
      end
    end
  end

  def humanize_report_type(report_type)
    report_type.gsub("_", " ").titleize
  end

  def report_description(report_type)
    descriptions = {
      "revenue_report" => "Monthly recurring revenue analysis with trends and forecasts",
      "growth_report" => "Customer and revenue growth metrics with compound growth rates",
      "churn_report" => "Customer churn analysis with retention insights",
      "customer_report" => "Customer analytics including segmentation and lifetime value",
      "subscription_report" => "Subscription overview with plan distribution and status",
      "executive_summary" => "High-level business metrics summary for executives"
    }

    descriptions[report_type] || "Detailed analytics report"
  end

  def calculate_next_run_time(frequency)
    case frequency
    when "daily"
      1.day.from_now.beginning_of_day + 8.hours # 8 AM next day
    when "weekly"
      1.week.from_now.beginning_of_week + 8.hours # Monday 8 AM
    when "monthly"
      1.month.from_now.beginning_of_month + 8.hours # First day of month 8 AM
    end
  end
end
