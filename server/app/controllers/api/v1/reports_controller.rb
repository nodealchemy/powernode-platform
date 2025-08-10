class Api::V1::ReportsController < ApplicationController
  before_action :check_reports_permission
  before_action :set_date_range
  before_action :set_account_scope

  SUPPORTED_FORMATS = %w[pdf csv].freeze
  REPORT_TYPES = PdfReportService::REPORT_TYPES

  # GET /api/v1/reports/:report_type
  def show
    unless REPORT_TYPES.include?(params[:report_type])
      render json: { 
        success: false, 
        error: "Invalid report type. Supported types: #{REPORT_TYPES.join(', ')}" 
      }, status: 400
      return
    end

    format = params[:format]&.downcase || 'pdf'
    
    unless SUPPORTED_FORMATS.include?(format)
      render json: { 
        success: false, 
        error: "Invalid format. Supported formats: #{SUPPORTED_FORMATS.join(', ')}" 
      }, status: 400
      return
    end

    case format
    when 'pdf'
      generate_pdf_report
    when 'csv'
      generate_csv_report
    end
  rescue => e
    Rails.logger.error "Report generation failed: #{e.message}"
    render json: { success: false, error: e.message }, status: 500
  end

  # GET /api/v1/reports
  def index
    render json: {
      success: true,
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
    }
  end

  # POST /api/v1/reports/generate
  def generate
    report_requests = params[:reports] || []
    
    if report_requests.empty?
      render json: { success: false, error: "No reports requested" }, status: 400
      return
    end

    generated_reports = []
    
    report_requests.each do |request|
      report_type = request[:type]
      format = request[:format] || 'pdf'
      
      next unless REPORT_TYPES.include?(report_type) && SUPPORTED_FORMATS.include?(format)
      
      case format
      when 'pdf'
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
      when 'csv'
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

    render json: {
      success: true,
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
    }
  end

  # POST /api/v1/reports/schedule
  def schedule
    report_type = params[:report_type]
    frequency = params[:frequency] # daily, weekly, monthly
    recipients = params[:recipients] || []
    format = params[:format] || 'pdf'

    unless REPORT_TYPES.include?(report_type)
      render json: { success: false, error: "Invalid report type" }, status: 400
      return
    end

    unless %w[daily weekly monthly].include?(frequency)
      render json: { success: false, error: "Invalid frequency. Use: daily, weekly, monthly" }, status: 400
      return
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

    render json: {
      success: true,
      data: {
        id: scheduled_report.id,
        report_type: scheduled_report.report_type,
        frequency: scheduled_report.frequency,
        next_run_at: scheduled_report.next_run_at,
        recipients: scheduled_report.recipients
      }
    }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # GET /api/v1/reports/scheduled
  def scheduled_reports
    reports = ScheduledReport.for_account(@account_scope)
                            .where(active: true)
                            .order(:next_run_at)

    render json: {
      success: true,
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
    }
  end

  # DELETE /api/v1/reports/scheduled/:id
  def destroy_scheduled
    scheduled_report = ScheduledReport.for_account(@account_scope).find(params[:id])
    scheduled_report.update!(active: false)

    render json: { success: true, message: "Scheduled report cancelled" }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: "Scheduled report not found" }, status: 404
  end

  private

  def check_reports_permission
    unless current_user.has_permission?("analytics.export") || current_user.has_permission?("analytics.global")
      render json: { success: false, error: "Report generation permission required" }, status: 403
    end
  end

  def set_date_range
    @start_date = params[:start_date]&.to_date || 12.months.ago.to_date.beginning_of_month
    @end_date = params[:end_date]&.to_date || Date.current.end_of_month

    # Validate date range
    if @start_date > @end_date
      render json: { success: false, error: "Start date must be before end date" }, status: 400
      return
    end

    # Limit to reasonable range (2 years max)
    if @end_date - @start_date > 2.years
      render json: { success: false, error: "Date range too large (max 2 years)" }, status: 400
      return
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
              disposition: 'attachment'
  end

  def generate_csv_report
    csv_data = generate_csv_data(params[:report_type])
    
    send_data csv_data,
              filename: "#{params[:report_type]}_#{Date.current.strftime('%Y%m%d')}.csv",
              type: "text/csv",
              disposition: 'attachment'
  end

  def generate_csv_data(report_type)
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    case report_type
    when 'revenue_report'
      analytics_service.export_revenue_data_csv("monthly")
    when 'customer_report'
      export_customer_data_csv
    when 'subscription_report'
      export_subscription_data_csv
    else
      # Default to revenue data
      analytics_service.export_revenue_data_csv("monthly")
    end
  end

  def export_customer_data_csv
    require 'csv'
    
    customers = @account_scope ? @account_scope.users : User.all
    customers = customers.joins(:account).where(accounts: { status: 'active' })

    CSV.generate(headers: true) do |csv|
      csv << ["Customer ID", "Name", "Email", "Account", "Plan", "Status", "Created", "Last Login"]
      
      customers.each do |customer|
        subscription = customer.account.subscription
        csv << [
          customer.id,
          "#{customer.first_name} #{customer.last_name}",
          customer.email,
          customer.account.name,
          subscription&.plan&.name || "No Plan",
          subscription&.status || "No Subscription",
          customer.created_at.strftime('%Y-%m-%d'),
          customer.last_login_at&.strftime('%Y-%m-%d %H:%M') || "Never"
        ]
      end
    end
  end

  def export_subscription_data_csv
    require 'csv'
    
    subscriptions = @account_scope ? @account_scope.subscriptions : Subscription.all
    subscriptions = subscriptions.includes(:account, :plan)

    CSV.generate(headers: true) do |csv|
      csv << ["Subscription ID", "Account", "Plan", "Status", "MRR", "Created", "Current Period End", "Trial End"]
      
      subscriptions.each do |sub|
        csv << [
          sub.id,
          sub.account.name,
          sub.plan.name,
          sub.status,
          (sub.plan.price_cents / 100.0),
          sub.created_at.strftime('%Y-%m-%d'),
          sub.current_period_end&.strftime('%Y-%m-%d') || "N/A",
          sub.trial_end&.strftime('%Y-%m-%d') || "N/A"
        ]
      end
    end
  end

  def humanize_report_type(report_type)
    report_type.gsub('_', ' ').titleize
  end

  def report_description(report_type)
    descriptions = {
      'revenue_report' => 'Monthly recurring revenue analysis with trends and forecasts',
      'growth_report' => 'Customer and revenue growth metrics with compound growth rates',
      'churn_report' => 'Customer churn analysis with retention insights',
      'customer_report' => 'Customer analytics including segmentation and lifetime value',
      'subscription_report' => 'Subscription overview with plan distribution and status',
      'executive_summary' => 'High-level business metrics summary for executives'
    }
    
    descriptions[report_type] || 'Detailed analytics report'
  end

  def calculate_next_run_time(frequency)
    case frequency
    when 'daily'
      1.day.from_now.beginning_of_day + 8.hours # 8 AM next day
    when 'weekly'
      1.week.from_now.beginning_of_week + 8.hours # Monday 8 AM
    when 'monthly'
      1.month.from_now.beginning_of_month + 8.hours # First day of month 8 AM
    end
  end
end