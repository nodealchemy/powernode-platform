require_relative '../base_job'

# Job for generating reports via the backend API
# Works with ReportRequest model for tracked report generation
class Reports::GenerateReportJob < BaseJob
  sidekiq_options queue: 'reports', 
                  retry: 2

  def execute(report_request_id)
    logger.info "Processing report request #{report_request_id}"
    
    # Get the report request details from backend
    report_request = with_api_retry do
      backend_api_client.get_report_request(report_request_id)
    end
    
    unless report_request
      logger.error "Report request #{report_request_id} not found"
      return false
    end
    
    # Mark request as processing
    with_api_retry do
      backend_api_client.update_report_request_status(report_request_id, 'processing')
    end
    
    logger.info "Generating #{report_request['type']} report in #{report_request['format']} format"
    
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
      
      logger.info "Successfully generated report #{report_request_id}"
      
    rescue StandardError => e
      logger.error "Failed to generate report #{report_request_id}: #{e.message}"
      
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
    logger.info "Generating #{report_request['report_type']} in #{report_request['format']} format"
    
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
    
    logger.info "Report file saved to #{file_path}"
    file_path
  end
  
  # Build download URL for the generated report
  def build_download_url(report_request_id)
    "#{ENV['BACKEND_API_URL'] || 'http://localhost:3000'}/api/v1/reports/requests/#{report_request_id}/download"
  end
  
  # Generate PDF report using backend API data
  def generate_pdf_report(report_request)
    # Get report data from backend API
    report_data = with_api_retry do
      backend_api_client.get_report_data(
        report_request['report_type'],
        report_request['account_id'],
        report_request['parameters'] || {}
      )
    end
    
    # Generate PDF using a simple HTML to PDF approach
    # In production, you'd use a proper PDF library like Prawn or wkhtmltopdf
    html_content = generate_html_report(report_data, report_request)
    
    # For now, return the HTML as a simple text-based PDF equivalent
    # In production, integrate with proper PDF generation library
    "PDF Report: #{report_request['name']}\n\n#{html_content}"
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
  
  # Generate XLSX report (Excel format)
  def generate_xlsx_report(report_request)
    # For now, generate CSV and return it
    # In production, use a library like axlsx or rubyXL
    generate_csv_report(report_request)
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
        logger.info "Sent completion notification to #{callback_url}"
      else
        logger.warn "Failed to send notification to #{callback_url}: #{response.status}"
      end
    rescue StandardError => e
      logger.error "Error sending notification to #{callback_url}: #{e.message}"
      # Don't fail the job for notification errors
    end
  end
end