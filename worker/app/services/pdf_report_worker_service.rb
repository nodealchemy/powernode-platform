require_relative 'base_worker_service'
require 'prawn'
require 'prawn/table'
require 'base64'

# Suppress Prawn international text warning
Prawn::Fonts::AFM.hide_m17n_warning = true

class PdfReportWorkerService < BaseWorkerService
  include ActionView::Helpers::NumberHelper
  
  REPORT_TYPES = %w[
    revenue_report
    growth_report
    churn_report
    customer_report
    subscription_report
    executive_summary
  ].freeze

  def initialize
    super
    @temp_files = []
  end

  # Generate PDF report via worker service
  def generate_report(report_type:, account_id: nil, start_date: nil, end_date: nil, user_id: nil, format: 'pdf')
    @report_type = report_type
    @account_id = account_id
    @start_date = start_date ? Date.parse(start_date.to_s) : 12.months.ago.to_date.beginning_of_month
    @end_date = end_date ? Date.parse(end_date.to_s) : Date.current.end_of_month
    @user_id = user_id
    @format = format

    log_info("Generating #{@report_type} report", 
      account_id: @account_id, 
      start_date: @start_date, 
      end_date: @end_date,
      format: @format
    )

    begin
      unless REPORT_TYPES.include?(@report_type)
        return { success: false, error: "Unsupported report type: #{@report_type}" }
      end

      # Get account details if specific account
      if @account_id
        account_response = api_client.get("/api/v1/accounts/#{@account_id}")
        unless account_response[:success]
          return { success: false, error: "Account not found" }
        end
        @account = account_response[:data]
      end

      # Get analytics data for the report
      analytics_data = fetch_analytics_data

      unless analytics_data[:success]
        return { success: false, error: "Failed to fetch analytics data: #{analytics_data[:error]}" }
      end

      @analytics = analytics_data[:data]

      # Generate the report based on format
      case @format.downcase
      when 'pdf'
        result = generate_pdf_report
      when 'csv'
        result = generate_csv_report
      when 'json'
        result = generate_json_report
      else
        return { success: false, error: "Unsupported format: #{@format}" }
      end

      if result[:success]
        log_info("Report generated successfully", 
          report_type: @report_type,
          file_size: result[:file_data]&.length || 0,
          format: @format
        )
      end

      result

    rescue => e
      log_error("Report generation failed", e, report_type: @report_type, account_id: @account_id)
      { success: false, error: e.message }
    ensure
      cleanup_temp_files
    end
  end

  private

  def fetch_analytics_data
    begin
      # Fetch analytics data from the API
      analytics_params = {
        account_id: @account_id,
        start_date: @start_date.iso8601,
        end_date: @end_date.iso8601
      }

      case @report_type
      when 'revenue_report'
        response = api_client.get("/api/v1/analytics/revenue", analytics_params)
      when 'growth_report'
        response = api_client.get("/api/v1/analytics/growth", analytics_params)
      when 'churn_report'
        response = api_client.get("/api/v1/analytics/churn", analytics_params)
      when 'customer_report'
        response = api_client.get("/api/v1/analytics/customers", analytics_params)
      when 'subscription_report'
        response = api_client.get("/api/v1/subscriptions", analytics_params.merge(include_cancelled: true))
      when 'executive_summary'
        # For executive summary, we need multiple data sources
        revenue_response = api_client.get("/api/v1/analytics/revenue", analytics_params)
        growth_response = api_client.get("/api/v1/analytics/growth", analytics_params)
        
        if revenue_response[:success] && growth_response[:success]
          response = {
            success: true,
            data: {
              revenue: revenue_response[:data],
              growth: growth_response[:data]
            }
          }
        else
          response = { success: false, error: "Failed to fetch executive summary data" }
        end
      else
        response = { success: false, error: "Unknown report type" }
      end

      response

    rescue => e
      log_error("Failed to fetch analytics data", e, report_type: @report_type)
      { success: false, error: e.message }
    end
  end

  def generate_pdf_report
    begin
      # Create temporary file for PDF
      temp_file = Tempfile.new(['report', '.pdf'])
      @temp_files << temp_file

      # Generate PDF using Prawn
      Prawn::Document.generate(temp_file.path, page_layout: :portrait, page_size: 'A4') do |pdf|
        generate_pdf_content(pdf)
      end

      # Read the generated PDF file
      pdf_data = File.read(temp_file.path)
      base64_data = Base64.strict_encode64(pdf_data)

      {
        success: true,
        file_data: base64_data,
        content_type: 'application/pdf',
        filename: generate_filename('pdf'),
        file_size: pdf_data.length
      }

    rescue => e
      log_error("PDF generation failed", e, report_type: @report_type)
      { success: false, error: "PDF generation failed: #{e.message}" }
    end
  end

  def generate_csv_report
    begin
      require 'csv'
      
      csv_data = CSV.generate do |csv|
        generate_csv_content(csv)
      end

      base64_data = Base64.strict_encode64(csv_data)

      {
        success: true,
        file_data: base64_data,
        content_type: 'text/csv',
        filename: generate_filename('csv'),
        file_size: csv_data.length
      }

    rescue => e
      log_error("CSV generation failed", e, report_type: @report_type)
      { success: false, error: "CSV generation failed: #{e.message}" }
    end
  end

  def generate_json_report
    begin
      json_data = {
        report_type: @report_type,
        account: @account,
        period: {
          start_date: @start_date,
          end_date: @end_date
        },
        generated_at: Time.current.iso8601,
        data: @analytics
      }.to_json

      base64_data = Base64.strict_encode64(json_data)

      {
        success: true,
        file_data: base64_data,
        content_type: 'application/json',
        filename: generate_filename('json'),
        file_size: json_data.length
      }

    rescue => e
      log_error("JSON generation failed", e, report_type: @report_type)
      { success: false, error: "JSON generation failed: #{e.message}" }
    end
  end

  def generate_pdf_content(pdf)
    # Header
    pdf.font "Helvetica", size: 24
    pdf.text "#{@report_type.humanize}", align: :center
    pdf.move_down 10

    if @account
      pdf.font "Helvetica", size: 14
      pdf.text "Account: #{@account['name']}", align: :center
    end

    pdf.font "Helvetica", size: 12
    pdf.text "Period: #{@start_date.strftime('%B %Y')} - #{@end_date.strftime('%B %Y')}", align: :center
    pdf.text "Generated: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}", align: :center
    
    pdf.move_down 30

    # Content based on report type
    case @report_type
    when 'revenue_report'
      generate_revenue_content(pdf)
    when 'growth_report'
      generate_growth_content(pdf)
    when 'churn_report'
      generate_churn_content(pdf)
    when 'customer_report'
      generate_customer_content(pdf)
    when 'subscription_report'
      generate_subscription_content(pdf)
    when 'executive_summary'
      generate_executive_summary_content(pdf)
    end

    # Footer
    pdf.number_pages "Page <page> of <total>", at: [pdf.bounds.right - 150, 0]
  end

  def generate_revenue_content(pdf)
    pdf.font "Helvetica", size: 16
    pdf.text "Revenue Summary", style: :bold
    pdf.move_down 15

    revenue_data = @analytics || {}
    
    # Revenue metrics table
    revenue_table_data = [
      ["Metric", "Amount"],
      ["Monthly Recurring Revenue", format_currency(revenue_data['mrr_cents'])],
      ["Annual Recurring Revenue", format_currency(revenue_data['arr_cents'])],
      ["Total Revenue", format_currency(revenue_data['total_revenue_cents'])],
      ["Net Revenue", format_currency(revenue_data['net_revenue_cents'])],
      ["Refunds", format_currency(revenue_data['refunds_cents'])]
    ]

    pdf.table(revenue_table_data, header: true, width: pdf.bounds.width) do
      style(row(0), background_color: 'E5E5E5', font_style: :bold)
    end
  end

  def generate_growth_content(pdf)
    pdf.font "Helvetica", size: 16
    pdf.text "Growth Analysis", style: :bold
    pdf.move_down 15

    growth_data = @analytics || {}
    
    # Growth metrics
    pdf.text "Growth Rate: #{growth_data['growth_rate'] || 0}%"
    pdf.text "New Subscriptions: #{growth_data['new_subscriptions'] || 0}"
    pdf.text "Active Subscriptions: #{growth_data['active_subscriptions'] || 0}"
  end

  def generate_churn_content(pdf)
    pdf.font "Helvetica", size: 16
    pdf.text "Churn Analysis", style: :bold
    pdf.move_down 15

    churn_data = @analytics || {}
    
    pdf.text "Churn Rate: #{churn_data['churn_rate'] || 0}%"
    pdf.text "Cancelled Subscriptions: #{churn_data['cancelled_subscriptions'] || 0}"
  end

  def generate_customer_content(pdf)
    pdf.font "Helvetica", size: 16
    pdf.text "Customer Report", style: :bold
    pdf.move_down 15

    customer_data = @analytics || {}
    
    pdf.text "Total Customers: #{customer_data['total_customers'] || 0}"
    pdf.text "Average Revenue Per User: #{format_currency(customer_data['arpu_cents'])}"
    pdf.text "Customer Lifetime Value: #{format_currency(customer_data['ltv_cents'])}"
  end

  def generate_subscription_content(pdf)
    pdf.font "Helvetica", size: 16
    pdf.text "Subscription Report", style: :bold
    pdf.move_down 15

    subscriptions = @analytics.is_a?(Array) ? @analytics : []
    
    if subscriptions.any?
      subscription_table_data = [["Plan", "Status", "Start Date", "Amount"]]
      
      subscriptions.first(20).each do |sub| # Limit to first 20 for PDF space
        subscription_table_data << [
          sub.dig('plan', 'name') || 'Unknown',
          sub['status'] || 'unknown',
          Date.parse(sub['created_at']).strftime('%m/%d/%Y') rescue 'N/A',
          format_currency(sub.dig('plan', 'price_cents'))
        ]
      end

      pdf.table(subscription_table_data, header: true, width: pdf.bounds.width) do
        style(row(0), background_color: 'E5E5E5', font_style: :bold)
      end
    else
      pdf.text "No subscription data available for this period."
    end
  end

  def generate_executive_summary_content(pdf)
    pdf.font "Helvetica", size: 16
    pdf.text "Executive Summary", style: :bold
    pdf.move_down 15

    revenue_data = @analytics.dig('revenue') || {}
    growth_data = @analytics.dig('growth') || {}

    # Key metrics overview
    pdf.font "Helvetica", size: 14
    pdf.text "Key Performance Indicators", style: :bold
    pdf.move_down 10

    kpi_table_data = [
      ["Metric", "Current", "Change"],
      ["Monthly Recurring Revenue", format_currency(revenue_data['mrr_cents']), "#{growth_data['growth_rate'] || 0}%"],
      ["Active Subscriptions", "#{revenue_data['active_subscriptions'] || 0}", "+#{revenue_data['new_subscriptions'] || 0}"],
      ["Churn Rate", "#{revenue_data['churn_rate'] || 0}%", ""],
      ["Average Revenue Per User", format_currency(revenue_data['arpu_cents']), ""]
    ]

    pdf.table(kpi_table_data, header: true, width: pdf.bounds.width) do
      style(row(0), background_color: 'E5E5E5', font_style: :bold)
    end
  end

  def generate_csv_content(csv)
    case @report_type
    when 'revenue_report'
      csv << ["Metric", "Amount (Cents)", "Amount (Formatted)"]
      revenue_data = @analytics || {}
      csv << ["MRR", revenue_data['mrr_cents'], format_currency(revenue_data['mrr_cents'])]
      csv << ["ARR", revenue_data['arr_cents'], format_currency(revenue_data['arr_cents'])]
      csv << ["Total Revenue", revenue_data['total_revenue_cents'], format_currency(revenue_data['total_revenue_cents'])]
    
    when 'subscription_report'
      csv << ["Plan Name", "Status", "Created Date", "Price (Cents)", "Price (Formatted)"]
      subscriptions = @analytics.is_a?(Array) ? @analytics : []
      subscriptions.each do |sub|
        csv << [
          sub.dig('plan', 'name'),
          sub['status'],
          sub['created_at'],
          sub.dig('plan', 'price_cents'),
          format_currency(sub.dig('plan', 'price_cents'))
        ]
      end
    
    else
      csv << ["Report Type", "Data"]
      csv << [@report_type, @analytics.to_json]
    end
  end

  def generate_filename(extension)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    account_suffix = @account ? "_#{@account['name'].parameterize}" : ""
    "#{@report_type}#{account_suffix}_#{timestamp}.#{extension}"
  end

  def format_currency(amount_cents)
    return "$0.00" unless amount_cents
    amount = amount_cents.to_f / 100
    "$#{number_with_precision(amount, precision: 2, delimiter: ',')}"
  end

  def cleanup_temp_files
    @temp_files.each do |file|
      file.close
      file.unlink
    rescue => e
      log_error("Failed to cleanup temp file", e, file: file.path)
    end
    @temp_files.clear
  end
end