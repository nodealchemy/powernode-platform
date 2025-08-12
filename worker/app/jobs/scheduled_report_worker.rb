require_relative 'base_job'

# Job for processing scheduled reports
class ScheduledReportWorker < BaseJob
  sidekiq_options queue: 'reports', retry: 3, backtrace: true

  def execute(scheduled_report_id)
    log_info("Processing scheduled report", report_id: scheduled_report_id)
    
    begin
      # Get scheduled report details from API
      scheduled_report = api_client.get("/api/v1/reports/scheduled/#{scheduled_report_id}")
      
      unless scheduled_report[:success]
        log_error("Failed to fetch scheduled report", nil, report_id: scheduled_report_id)
        return
      end

      report_data = scheduled_report[:data]
      
      # Generate the report
      result = api_client.generate_pdf_report(
        report_data[:report_type],
        account_id: report_data[:account_id],
        start_date: Date.today - 30, # approximately 1 month ago
        end_date: Date.today,
        user_id: report_data[:user_id]
      )

      if result[:success]
        # Update the scheduled report with last run time
        api_client.update_scheduled_report(scheduled_report_id, {
          last_run_at: Time.now.utc.iso8601,
          next_run_at: calculate_next_run_time(report_data[:frequency])
        })

        # TODO: Send email with PDF attachment
        # This would typically involve:
        # 1. Decode base64 PDF data
        # 2. Send email via email service API
        # 3. Include recipients from report_data[:recipients]
        
        log_info("Scheduled report processed successfully", 
          report_id: scheduled_report_id,
          report_type: report_data[:report_type],
          recipients_count: report_data[:recipients]&.length || 0
        )

        # Create audit log
        create_audit_log(
          account_id: report_data[:account_id],
          action: 'generate',
          resource_type: 'ScheduledReport',
          resource_id: scheduled_report_id,
          user_id: report_data[:user_id],
          metadata: {
            report_type: report_data[:report_type],
            frequency: report_data[:frequency],
            format: report_data[:format]
          }
        )
      else
        log_error("Failed to generate scheduled report", nil, 
          report_id: scheduled_report_id,
          error: result[:error]
        )
      end
      
    rescue ApiClient::ApiError => e
      handle_api_error(e, report_id: scheduled_report_id)
    rescue => e
      log_error("Unexpected error processing scheduled report", e, report_id: scheduled_report_id)
      raise
    end
  end

  private

  def calculate_next_run_time(frequency)
    base_time = Time.now
    case frequency
    when 'daily'
      (base_time + (24 * 60 * 60) + (8 * 60 * 60)).utc.iso8601 # Next day + 8 hours
    when 'weekly' 
      (base_time + (7 * 24 * 60 * 60) + (8 * 60 * 60)).utc.iso8601 # Next week + 8 hours
    when 'monthly'
      (base_time + (30 * 24 * 60 * 60) + (8 * 60 * 60)).utc.iso8601 # Next month + 8 hours
    else
      (base_time + (24 * 60 * 60)).utc.iso8601 # Default to next day
    end
  end
end