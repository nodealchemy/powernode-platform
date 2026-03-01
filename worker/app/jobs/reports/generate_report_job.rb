# frozen_string_literal: true

require_relative '../base_job'

# Job for generating reports via the backend API
# Works with ReportRequest model for tracked report generation
class Reports::GenerateReportJob < BaseJob
  include Reports::PdfReportConcern
  include Reports::XlsxReportConcern
  include Reports::CsvJsonReportConcern

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
end
