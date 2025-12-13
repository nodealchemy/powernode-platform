# frozen_string_literal: true

require_relative '../base_job'

# Job for generating reports via the backend API
# Works with ReportRequest model for tracked report generation
class Reports::GenerateReportJob < BaseJob
  sidekiq_options queue: 'reports', 
                  retry: 2

  def execute(report_request_id)
    log_info("Processing report request #{report_request_id}")
    
    # Get the report request details from backend
    report_request = with_api_retry do
      backend_api_client.get_report_request(report_request_id)
    end
    
    unless report_request
      log_error("Report request #{report_request_id} not found")
      return false
    end
    
    # Mark request as processing
    with_api_retry do
      backend_api_client.update_report_request_status(report_request_id, 'processing')
    end
    
    log_info("Generating #{report_request['type']} report in #{report_request['format']} format")
    
    begin
      # Generate the report file
      file_data = generate_report_file(report_request)
      
      # Save file to storage
      file_path = save_report_file(report_request, file_data)
      
      # Mark request as completed with file info
      with_api_retry do
        backend_api_client.complete_report_request(
          report_request_id, 
          file_path: file_path,
          file_size: file_data.bytesize,
          file_url: build_download_url(report_request_id)
        )
      end
      
      log_info("Successfully generated report #{report_request_id}")
      
    rescue StandardError => e
      log_error("Failed to generate report #{report_request_id}: #{e.message}")
      
      # Mark request as failed
      with_api_retry do
        backend_api_client.fail_report_request(report_request_id, e.message)
      end
      
      raise e
    end
  end
  
  private
  
  # Generate the actual report file based on type and parameters
  def generate_report_file(report_request)
    log_info("Generating #{report_request['report_type']} in #{report_request['format']} format")
    
    case report_request['format']
    when 'pdf'
      generate_pdf_report(report_request)
    when 'csv'
      generate_csv_report(report_request)
    when 'xlsx'
      generate_xlsx_report(report_request)
    when 'json'
      generate_json_report(report_request)
    else
      raise "Unsupported format: #{report_request['format']}"
    end
  end
  
  # Save the generated report file to storage
  def save_report_file(report_request, file_data)
    # Create reports directory if it doesn't exist
    reports_dir = File.join(PowernodeWorker.application.root, 'storage', 'reports')
    FileUtils.mkdir_p(reports_dir)
    
    # Generate unique filename
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    sanitized_name = report_request['name'].gsub(/[^0-9A-Za-z.\-]/, '_')
    filename = "#{sanitized_name}_#{timestamp}.#{report_request['format']}"
    file_path = File.join(reports_dir, filename)
    
    # Write file to storage
    File.write(file_path, file_data, mode: 'wb')
    
    log_info("Report file saved to #{file_path}")
    file_path
  end
  
  # Build download URL for the generated report
  def build_download_url(report_request_id)
    "#{ENV['BACKEND_API_URL'] || 'http://localhost:3000'}/api/v1/reports/requests/#{report_request_id}/download"
  end
  
  # Generate PDF report using Prawn
  def generate_pdf_report(report_request)
    require 'prawn'
    require 'prawn/table'

    # Get report data from backend API
    report_data = with_api_retry do
      backend_api_client.get_report_data(
        report_request['report_type'],
        report_request['account_id'],
        report_request['parameters'] || {}
      )
    end

    Prawn::Document.new(page_size: 'A4', margin: 40) do |pdf|
      # Header
      pdf.font_size(20) do
        pdf.text report_request['name'], style: :bold, align: :center
      end
      pdf.move_down 10

      pdf.font_size(10) do
        pdf.text "Generated: #{Time.now.strftime('%B %d, %Y at %I:%M %p')}", align: :center, color: '666666'
        pdf.text "Report Type: #{report_request['report_type'].to_s.titlecase}", align: :center, color: '666666'
      end
      pdf.move_down 20

      # Horizontal line
      pdf.stroke_horizontal_rule
      pdf.move_down 20

      # Generate report-specific content
      case report_request['report_type']
      when 'revenue_analytics'
        generate_revenue_pdf_content(pdf, report_data)
      when 'customer_analytics'
        generate_customer_pdf_content(pdf, report_data)
      when 'churn_analysis'
        generate_churn_pdf_content(pdf, report_data)
      when 'growth_analytics'
        generate_growth_pdf_content(pdf, report_data)
      when 'cohort_analysis'
        generate_cohort_pdf_content(pdf, report_data)
      when 'comprehensive_report'
        generate_executive_pdf_content(pdf, report_data)
      else
        generate_generic_pdf_content(pdf, report_data, report_request['report_type'])
      end

      # Footer with page numbers
      pdf.number_pages 'Page <page> of <total>',
                       at: [pdf.bounds.right - 100, 0],
                       align: :right,
                       size: 9
    end.render
  end

  def generate_revenue_pdf_content(pdf, data)
    pdf.font_size(14) { pdf.text 'Revenue Analytics', style: :bold }
    pdf.move_down 10

    if data && data['summary']
      summary = data['summary']
      summary_table = [
        ['Metric', 'Value'],
        ['Monthly Recurring Revenue (MRR)', format_currency(summary['mrr'])],
        ['Annual Recurring Revenue (ARR)', format_currency(summary['arr'])],
        ['Growth Rate', "#{summary['growth_rate']}%"],
        ['Net Revenue Retention', "#{summary['net_revenue_retention']}%"],
        ['Average Revenue Per User', format_currency(summary['arpu'])]
      ]

      pdf.table(summary_table, header: true, width: pdf.bounds.width) do
        row(0).background_color = '4A90D9'
        row(0).text_color = 'FFFFFF'
        row(0).font_style = :bold
        cells.padding = 8
        cells.borders = [:bottom]
        cells.border_color = 'DDDDDD'
      end
    end

    if data && data['data']
      pdf.move_down 20
      pdf.font_size(12) { pdf.text 'Revenue Trend', style: :bold }
      pdf.move_down 10

      headers = get_csv_headers('revenue_analytics')
      table_data = [headers] + (data['data'] || []).map do |row|
        extract_csv_row(row, headers)
      end

      if table_data.length > 1
        pdf.table(table_data, header: true, width: pdf.bounds.width) do
          row(0).background_color = 'EEEEEE'
          row(0).font_style = :bold
          cells.padding = 6
          cells.size = 9
        end
      end
    end
  end

  def generate_customer_pdf_content(pdf, data)
    pdf.font_size(14) { pdf.text 'Customer Analytics', style: :bold }
    pdf.move_down 10

    if data && data['summary']
      summary = data['summary']
      summary_table = [
        ['Metric', 'Value'],
        ['Total Customers', summary['total_customers'].to_s],
        ['Active Customers', summary['active_customers'].to_s],
        ['Customer Lifetime Value (LTV)', format_currency(summary['ltv'])],
        ['Customer Acquisition Cost (CAC)', format_currency(summary['cac'])],
        ['LTV/CAC Ratio', summary['ltv_cac_ratio'].to_s]
      ]

      pdf.table(summary_table, header: true, width: pdf.bounds.width) do
        row(0).background_color = '4A90D9'
        row(0).text_color = 'FFFFFF'
        row(0).font_style = :bold
        cells.padding = 8
      end
    end

    if data && data['data']
      pdf.move_down 20
      pdf.font_size(12) { pdf.text 'Customer List', style: :bold }
      pdf.move_down 10

      headers = get_csv_headers('customer_analytics')
      table_data = [headers] + (data['data'] || []).first(50).map do |row|
        extract_csv_row(row, headers)
      end

      if table_data.length > 1
        pdf.table(table_data, header: true, width: pdf.bounds.width) do
          row(0).background_color = 'EEEEEE'
          row(0).font_style = :bold
          cells.padding = 4
          cells.size = 8
        end
      end
    end
  end

  def generate_churn_pdf_content(pdf, data)
    pdf.font_size(14) { pdf.text 'Churn Analysis', style: :bold }
    pdf.move_down 10

    if data && data['summary']
      summary = data['summary']
      summary_table = [
        ['Metric', 'Value'],
        ['Customer Churn Rate', "#{summary['customer_churn_rate']}%"],
        ['Revenue Churn Rate', "#{summary['revenue_churn_rate']}%"],
        ['Churned Customers', summary['churned_customers'].to_s],
        ['Churned Revenue', format_currency(summary['churned_revenue'])],
        ['Average Days to Churn', summary['avg_days_to_churn'].to_s]
      ]

      pdf.table(summary_table, header: true, width: pdf.bounds.width) do
        row(0).background_color = 'D94A4A'
        row(0).text_color = 'FFFFFF'
        row(0).font_style = :bold
        cells.padding = 8
      end
    end

    generate_trend_table(pdf, data, 'churn_analysis')
  end

  def generate_growth_pdf_content(pdf, data)
    pdf.font_size(14) { pdf.text 'Growth Analytics', style: :bold }
    pdf.move_down 10

    if data && data['summary']
      summary = data['summary']
      summary_table = [
        ['Metric', 'Value'],
        ['New Customers', summary['new_customers'].to_s],
        ['Customer Growth Rate', "#{summary['growth_rate']}%"],
        ['MRR Growth', format_currency(summary['mrr_growth'])],
        ['Expansion Revenue', format_currency(summary['expansion_revenue'])],
        ['Net Revenue Retention', "#{summary['net_revenue_retention']}%"]
      ]

      pdf.table(summary_table, header: true, width: pdf.bounds.width) do
        row(0).background_color = '4AD98C'
        row(0).text_color = 'FFFFFF'
        row(0).font_style = :bold
        cells.padding = 8
      end
    end

    generate_trend_table(pdf, data, 'growth_analytics')
  end

  def generate_cohort_pdf_content(pdf, data)
    pdf.font_size(14) { pdf.text 'Cohort Analysis', style: :bold }
    pdf.move_down 10

    if data && data['cohorts']
      headers = ['Cohort', 'Size'] + (0..12).map { |i| "M#{i}" }
      table_data = [headers]

      (data['cohorts'] || []).each do |cohort|
        row = [cohort['name'], cohort['size'].to_s]
        (cohort['retention'] || []).each do |retention|
          row << "#{retention}%"
        end
        table_data << row
      end

      if table_data.length > 1
        pdf.table(table_data, header: true, width: pdf.bounds.width) do
          row(0).background_color = '9B59B6'
          row(0).text_color = 'FFFFFF'
          row(0).font_style = :bold
          cells.padding = 4
          cells.size = 8
        end
      end
    else
      pdf.text 'No cohort data available', color: '999999'
    end
  end

  def generate_executive_pdf_content(pdf, data)
    pdf.font_size(14) { pdf.text 'Executive Summary', style: :bold }
    pdf.move_down 10

    if data && data['summary']
      summary = data['summary']

      # Key Metrics
      pdf.font_size(12) { pdf.text 'Key Metrics', style: :bold }
      pdf.move_down 5

      metrics_table = [
        ['Metric', 'Current', 'Previous', 'Change'],
        ['MRR', format_currency(summary['mrr']), format_currency(summary['previous_mrr']), "#{summary['mrr_change']}%"],
        ['ARR', format_currency(summary['arr']), format_currency(summary['previous_arr']), "#{summary['arr_change']}%"],
        ['Customers', summary['customers'].to_s, summary['previous_customers'].to_s, "#{summary['customer_change']}%"],
        ['Churn Rate', "#{summary['churn_rate']}%", "#{summary['previous_churn_rate']}%", "#{summary['churn_change']}%"]
      ]

      pdf.table(metrics_table, header: true, width: pdf.bounds.width) do
        row(0).background_color = '2C3E50'
        row(0).text_color = 'FFFFFF'
        row(0).font_style = :bold
        cells.padding = 8
      end
    end

    generate_trend_table(pdf, data, 'comprehensive_report')
  end

  def generate_generic_pdf_content(pdf, data, report_type)
    pdf.font_size(14) { pdf.text report_type.to_s.titlecase, style: :bold }
    pdf.move_down 10

    if data && data['data']
      pdf.text data['data'].to_json, size: 9
    else
      pdf.text 'No data available for this report.', color: '999999'
    end
  end

  def generate_trend_table(pdf, data, report_type)
    return unless data && data['data']

    pdf.move_down 20
    pdf.font_size(12) { pdf.text 'Trend Data', style: :bold }
    pdf.move_down 10

    headers = get_csv_headers(report_type)
    table_data = [headers] + (data['data'] || []).map do |row|
      extract_csv_row(row, headers)
    end

    if table_data.length > 1
      pdf.table(table_data, header: true, width: pdf.bounds.width) do
        row(0).background_color = 'EEEEEE'
        row(0).font_style = :bold
        cells.padding = 6
        cells.size = 9
      end
    end
  end

  def format_currency(amount)
    return '$0.00' unless amount

    cents = amount.is_a?(Integer) ? amount : (amount * 100).to_i
    dollars = cents / 100.0
    "$#{format('%.2f', dollars).gsub(/\B(?=(\d{3})+(?!\d))/, ',')}"
  end
  
  # Generate CSV report
  def generate_csv_report(report_request)
    require 'csv'
    
    # Get report data from backend API
    report_data = with_api_retry do
      backend_api_client.get_report_data(
        report_request['report_type'],
        report_request['account_id'], 
        report_request['parameters'] || {}
      )
    end
    
    CSV.generate do |csv|
      # Add headers based on report type
      headers = get_csv_headers(report_request['report_type'])
      csv << headers
      
      # Add data rows
      if report_data && report_data['data']
        report_data['data'].each do |row|
          csv << extract_csv_row(row, headers)
        end
      end
    end
  end
  
  # Generate XLSX report (Excel format) using caxlsx
  def generate_xlsx_report(report_request)
    require 'caxlsx'

    # Get report data from backend API
    report_data = with_api_retry do
      backend_api_client.get_report_data(
        report_request['report_type'],
        report_request['account_id'],
        report_request['parameters'] || {}
      )
    end

    package = Axlsx::Package.new
    workbook = package.workbook

    # Define styles
    styles = define_xlsx_styles(workbook)

    case report_request['report_type']
    when 'revenue_analytics'
      generate_revenue_xlsx(workbook, styles, report_data, report_request)
    when 'customer_analytics'
      generate_customer_xlsx(workbook, styles, report_data, report_request)
    when 'churn_analysis'
      generate_churn_xlsx(workbook, styles, report_data, report_request)
    when 'growth_analytics'
      generate_growth_xlsx(workbook, styles, report_data, report_request)
    when 'cohort_analysis'
      generate_cohort_xlsx(workbook, styles, report_data, report_request)
    when 'comprehensive_report'
      generate_executive_xlsx(workbook, styles, report_data, report_request)
    else
      generate_generic_xlsx(workbook, styles, report_data, report_request)
    end

    package.to_stream.read
  end

  def define_xlsx_styles(workbook)
    {
      title: workbook.styles.add_style(
        b: true, sz: 16, alignment: { horizontal: :center }
      ),
      header: workbook.styles.add_style(
        b: true, bg_color: '4A90D9', fg_color: 'FFFFFF',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      ),
      header_green: workbook.styles.add_style(
        b: true, bg_color: '4AD98C', fg_color: 'FFFFFF',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      ),
      header_red: workbook.styles.add_style(
        b: true, bg_color: 'D94A4A', fg_color: 'FFFFFF',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      ),
      header_purple: workbook.styles.add_style(
        b: true, bg_color: '9B59B6', fg_color: 'FFFFFF',
        alignment: { horizontal: :center },
        border: { style: :thin, color: '000000' }
      ),
      cell: workbook.styles.add_style(
        alignment: { horizontal: :left },
        border: { style: :thin, color: 'DDDDDD' }
      ),
      currency: workbook.styles.add_style(
        num_fmt: 8, # Currency format
        alignment: { horizontal: :right },
        border: { style: :thin, color: 'DDDDDD' }
      ),
      percent: workbook.styles.add_style(
        num_fmt: 10, # Percentage format
        alignment: { horizontal: :right },
        border: { style: :thin, color: 'DDDDDD' }
      ),
      number: workbook.styles.add_style(
        num_fmt: 3, # Number with commas
        alignment: { horizontal: :right },
        border: { style: :thin, color: 'DDDDDD' }
      ),
      date: workbook.styles.add_style(
        num_fmt: 14, # Date format
        alignment: { horizontal: :center },
        border: { style: :thin, color: 'DDDDDD' }
      ),
      subtitle: workbook.styles.add_style(
        sz: 10, i: true, alignment: { horizontal: :center }
      )
    }
  end

  def generate_revenue_xlsx(workbook, styles, data, report_request)
    # Summary sheet
    workbook.add_worksheet(name: 'Summary') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['summary']
        summary = data['summary']
        sheet.add_row []
        sheet.add_row ['Key Metrics'], style: styles[:title]
        sheet.add_row []
        sheet.add_row ['Metric', 'Value'], style: [styles[:header], styles[:header]]
        sheet.add_row ['Monthly Recurring Revenue (MRR)', summary['mrr'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['Annual Recurring Revenue (ARR)', summary['arr'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['Growth Rate', summary['growth_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
        sheet.add_row ['Net Revenue Retention', summary['net_revenue_retention'].to_f / 100], style: [styles[:cell], styles[:percent]]
        sheet.add_row ['Average Revenue Per User', summary['arpu'].to_f / 100], style: [styles[:cell], styles[:currency]]
      end

      sheet.column_widths 35, 20
    end

    # Data sheet
    if data && data['data']
      workbook.add_worksheet(name: 'Revenue Trend') do |sheet|
        headers = get_csv_headers('revenue_analytics')
        sheet.add_row headers, style: Array.new(headers.length, styles[:header])

        (data['data'] || []).each do |row|
          sheet.add_row extract_csv_row(row, headers), style: styles[:cell]
        end

        sheet.column_widths(*Array.new(headers.length, 15))
      end
    end
  end

  def generate_customer_xlsx(workbook, styles, data, report_request)
    workbook.add_worksheet(name: 'Summary') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['summary']
        summary = data['summary']
        sheet.add_row []
        sheet.add_row ['Customer Metrics'], style: styles[:title]
        sheet.add_row []
        sheet.add_row ['Metric', 'Value'], style: [styles[:header], styles[:header]]
        sheet.add_row ['Total Customers', summary['total_customers']], style: [styles[:cell], styles[:number]]
        sheet.add_row ['Active Customers', summary['active_customers']], style: [styles[:cell], styles[:number]]
        sheet.add_row ['Customer Lifetime Value', summary['ltv'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['Customer Acquisition Cost', summary['cac'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['LTV/CAC Ratio', summary['ltv_cac_ratio']], style: [styles[:cell], styles[:number]]
      end

      sheet.column_widths 35, 20
    end

    if data && data['data']
      workbook.add_worksheet(name: 'Customers') do |sheet|
        headers = get_csv_headers('customer_analytics')
        sheet.add_row headers, style: Array.new(headers.length, styles[:header])

        (data['data'] || []).each do |row|
          sheet.add_row extract_csv_row(row, headers), style: styles[:cell]
        end

        sheet.column_widths(*Array.new(headers.length, 18))
      end
    end
  end

  def generate_churn_xlsx(workbook, styles, data, report_request)
    workbook.add_worksheet(name: 'Churn Analysis') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['summary']
        summary = data['summary']
        sheet.add_row []
        sheet.add_row ['Churn Metrics'], style: styles[:title]
        sheet.add_row []
        sheet.add_row ['Metric', 'Value'], style: [styles[:header_red], styles[:header_red]]
        sheet.add_row ['Customer Churn Rate', summary['customer_churn_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
        sheet.add_row ['Revenue Churn Rate', summary['revenue_churn_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
        sheet.add_row ['Churned Customers', summary['churned_customers']], style: [styles[:cell], styles[:number]]
        sheet.add_row ['Churned Revenue', summary['churned_revenue'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['Average Days to Churn', summary['avg_days_to_churn']], style: [styles[:cell], styles[:number]]
      end

      sheet.column_widths 35, 20
    end

    add_trend_worksheet(workbook, styles, data, 'churn_analysis', 'Churn Trend')
  end

  def generate_growth_xlsx(workbook, styles, data, report_request)
    workbook.add_worksheet(name: 'Growth Analytics') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['summary']
        summary = data['summary']
        sheet.add_row []
        sheet.add_row ['Growth Metrics'], style: styles[:title]
        sheet.add_row []
        sheet.add_row ['Metric', 'Value'], style: [styles[:header_green], styles[:header_green]]
        sheet.add_row ['New Customers', summary['new_customers']], style: [styles[:cell], styles[:number]]
        sheet.add_row ['Customer Growth Rate', summary['growth_rate'].to_f / 100], style: [styles[:cell], styles[:percent]]
        sheet.add_row ['MRR Growth', summary['mrr_growth'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['Expansion Revenue', summary['expansion_revenue'].to_f / 100], style: [styles[:cell], styles[:currency]]
        sheet.add_row ['Net Revenue Retention', summary['net_revenue_retention'].to_f / 100], style: [styles[:cell], styles[:percent]]
      end

      sheet.column_widths 35, 20
    end

    add_trend_worksheet(workbook, styles, data, 'growth_analytics', 'Growth Trend')
  end

  def generate_cohort_xlsx(workbook, styles, data, report_request)
    workbook.add_worksheet(name: 'Cohort Analysis') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['cohorts']
        sheet.add_row []
        headers = ['Cohort', 'Size'] + (0..12).map { |i| "Month #{i}" }
        sheet.add_row headers, style: Array.new(headers.length, styles[:header_purple])

        (data['cohorts'] || []).each do |cohort|
          row = [cohort['name'], cohort['size']]
          (cohort['retention'] || []).each do |retention|
            row << retention.to_f / 100
          end
          row_styles = [styles[:cell], styles[:number]] + Array.new(row.length - 2, styles[:percent])
          sheet.add_row row, style: row_styles
        end

        sheet.column_widths(*Array.new(headers.length, 12))
      else
        sheet.add_row []
        sheet.add_row ['No cohort data available']
      end
    end
  end

  def generate_executive_xlsx(workbook, styles, data, report_request)
    workbook.add_worksheet(name: 'Executive Summary') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['summary']
        summary = data['summary']
        sheet.add_row []
        sheet.add_row ['Key Performance Indicators'], style: styles[:title]
        sheet.add_row []
        sheet.add_row ['Metric', 'Current', 'Previous', 'Change'], style: Array.new(4, styles[:header])
        sheet.add_row ['MRR', summary['mrr'].to_f / 100, summary['previous_mrr'].to_f / 100, summary['mrr_change'].to_f / 100],
                      style: [styles[:cell], styles[:currency], styles[:currency], styles[:percent]]
        sheet.add_row ['ARR', summary['arr'].to_f / 100, summary['previous_arr'].to_f / 100, summary['arr_change'].to_f / 100],
                      style: [styles[:cell], styles[:currency], styles[:currency], styles[:percent]]
        sheet.add_row ['Customers', summary['customers'], summary['previous_customers'], summary['customer_change'].to_f / 100],
                      style: [styles[:cell], styles[:number], styles[:number], styles[:percent]]
        sheet.add_row ['Churn Rate', summary['churn_rate'].to_f / 100, summary['previous_churn_rate'].to_f / 100, summary['churn_change'].to_f / 100],
                      style: [styles[:cell], styles[:percent], styles[:percent], styles[:percent]]
      end

      sheet.column_widths 25, 18, 18, 15
    end

    add_trend_worksheet(workbook, styles, data, 'comprehensive_report', 'Trend Data')
  end

  def generate_generic_xlsx(workbook, styles, data, report_request)
    workbook.add_worksheet(name: 'Report') do |sheet|
      add_report_header(sheet, styles, report_request['name'])

      if data && data['data']
        sheet.add_row []
        sheet.add_row ['Data'], style: styles[:header]
        sheet.add_row [data['data'].to_json], style: styles[:cell]
      else
        sheet.add_row []
        sheet.add_row ['No data available']
      end
    end
  end

  def add_report_header(sheet, styles, title)
    sheet.add_row [title], style: styles[:title]
    sheet.add_row ["Generated: #{Time.now.strftime('%B %d, %Y at %I:%M %p')}"], style: styles[:subtitle]
  end

  def add_trend_worksheet(workbook, styles, data, report_type, sheet_name)
    return unless data && data['data']

    workbook.add_worksheet(name: sheet_name) do |sheet|
      headers = get_csv_headers(report_type)
      sheet.add_row headers, style: Array.new(headers.length, styles[:header])

      (data['data'] || []).each do |row|
        sheet.add_row extract_csv_row(row, headers), style: styles[:cell]
      end

      sheet.column_widths(*Array.new(headers.length, 15))
    end
  end
  
  # Generate JSON report
  def generate_json_report(report_request)
    # Get report data from backend API
    report_data = with_api_retry do
      backend_api_client.get_report_data(
        report_request['report_type'],
        report_request['account_id'],
        report_request['parameters'] || {}
      )
    end
    
    JSON.pretty_generate({
      report_name: report_request['name'],
      report_type: report_request['report_type'],
      generated_at: Time.now.iso8601,
      data: report_data
    })
  end
  
  # Generate HTML content for PDF conversion
  def generate_html_report(report_data, report_request)
    case report_request['report_type']
    when 'revenue_analytics'
      generate_revenue_html(report_data)
    when 'customer_analytics'
      generate_customer_html(report_data)
    when 'churn_analysis'
      generate_churn_html(report_data)
    when 'growth_analytics'
      generate_growth_html(report_data)
    when 'cohort_analysis'
      generate_cohort_html(report_data)
    when 'comprehensive_report'
      generate_executive_html(report_data)
    else
      "Report Type: #{report_request['report_type']}\nData: #{report_data.inspect}"
    end
  end
  
  # Get CSV headers based on report type
  def get_csv_headers(report_type)
    case report_type
    when 'revenue_analytics'
      ['Period', 'MRR', 'ARR', 'Growth Rate', 'New Revenue', 'Churn Revenue']
    when 'customer_analytics' 
      ['Customer ID', 'Name', 'Email', 'Plan', 'Status', 'MRR', 'LTV', 'Created']
    when 'churn_analysis'
      ['Period', 'Customer Churn Rate', 'Revenue Churn Rate', 'Churned Customers', 'Churned Revenue']
    when 'growth_analytics'
      ['Period', 'New Customers', 'Growth Rate', 'Compound Growth', 'Net Revenue Retention']
    when 'cohort_analysis'
      ['Cohort', 'Period 0', 'Period 1', 'Period 2', 'Period 3', 'Period 6', 'Period 12']
    when 'comprehensive_report'
      ['Metric', 'Current Value', 'Previous Value', 'Change', 'Percentage Change']
    else
      ['Data']
    end
  end
  
  # Extract CSV row from data object
  def extract_csv_row(row_data, headers)
    headers.map { |header| row_data[header.downcase.gsub(' ', '_')] || '' }
  end
  
  # Generate revenue-specific HTML
  def generate_revenue_html(data)
    "Revenue Analytics Report\n" + 
    "======================\n\n" +
    "Data: #{data.inspect}"
  end
  
  # Generate customer-specific HTML
  def generate_customer_html(data)
    "Customer Analytics Report\n" +
    "========================\n\n" +
    "Data: #{data.inspect}"
  end
  
  # Generate churn-specific HTML
  def generate_churn_html(data)
    "Churn Analysis Report\n" +
    "====================\n\n" +
    "Data: #{data.inspect}"
  end
  
  # Generate growth-specific HTML
  def generate_growth_html(data)
    "Growth Analytics Report\n" +
    "======================\n\n" +
    "Data: #{data.inspect}"
  end
  
  # Generate cohort-specific HTML
  def generate_cohort_html(data)
    "Cohort Analysis Report\n" +
    "=====================\n\n" +
    "Data: #{data.inspect}"
  end
  
  # Generate executive-specific HTML
  def generate_executive_html(data)
    "Executive Summary Report\n" +
    "=======================\n\n" +
    "Data: #{data.inspect}"
  end
  
  def send_completion_notification(callback_url, report_result)
    return unless callback_url.is_a?(String) && callback_url.start_with?('http')
    
    notification_payload = {
      event: 'report_generated',
      report_id: report_result['id'],
      report_type: report_result['report_type'],
      account_id: report_result['account_id'],
      status: 'completed',
      generated_at: Time.now.iso8601,
      download_url: report_result['download_url']
    }
    
    begin
      # Use Faraday to send webhook notification
      connection = Faraday.new do |conn|
        conn.request :json
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 10
      end
      
      response = connection.post(callback_url, notification_payload)
      
      if response.success?
        log_info("Sent completion notification to #{callback_url}")
      else
        log_warn("Failed to send notification to #{callback_url}: #{response.status}")
      end
    rescue StandardError => e
      log_error("Error sending notification to #{callback_url}: #{e.message}")
      # Don't fail the job for notification errors
    end
  end
end