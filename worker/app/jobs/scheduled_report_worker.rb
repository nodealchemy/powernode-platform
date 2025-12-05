# frozen_string_literal: true

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

        # Send email with PDF attachment to all recipients
        recipients = report_data[:recipients] || []
        if recipients.any? && result[:data]
          send_report_emails(
            recipients: recipients,
            report_type: report_data[:report_type],
            pdf_data: result[:data][:pdf_data] || result[:data]['pdf_data'],
            account_id: report_data[:account_id],
            user_id: report_data[:user_id]
          )
        end

        log_info("Scheduled report processed successfully",
          report_id: scheduled_report_id,
          report_type: report_data[:report_type],
          recipients_count: recipients.length
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

  def send_report_emails(recipients:, report_type:, pdf_data:, account_id:, user_id:)
    return if recipients.empty? || pdf_data.blank?

    email_service = EmailDeliveryWorkerService.new
    formatted_type = report_type.to_s.titleize.gsub('_', ' ')
    filename = "#{report_type}_report_#{Date.today.iso8601}.pdf"

    # Decode base64 PDF data if encoded
    decoded_pdf = pdf_data.is_a?(String) && pdf_data.start_with?('JVBERi') ? Base64.decode64(pdf_data) : pdf_data

    recipients.each do |recipient|
      begin
        email_service.send_email(
          to: recipient[:email] || recipient,
          subject: "Your #{formatted_type} Report - #{Date.today.strftime('%B %d, %Y')}",
          body: build_report_email_body(formatted_type, recipient),
          email_type: 'report_generated',
          account_id: account_id,
          user_id: user_id,
          attachments: [{
            data: decoded_pdf,
            filename: filename,
            content_type: 'application/pdf'
          }]
        )

        log_info("Report email sent",
          recipient: recipient[:email] || recipient,
          report_type: report_type
        )
      rescue StandardError => e
        log_error("Failed to send report email", e,
          recipient: recipient[:email] || recipient,
          report_type: report_type
        )
      end
    end
  end

  def build_report_email_body(report_type, recipient)
    recipient_name = recipient.is_a?(Hash) ? recipient[:name] : 'User'
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: #4F46E5; color: white; padding: 20px; text-align: center; }
          .content { padding: 20px; background: #f9f9f9; }
          .footer { padding: 20px; text-align: center; color: #666; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>#{report_type} Report</h1>
          </div>
          <div class="content">
            <p>Hello #{recipient_name},</p>
            <p>Your scheduled #{report_type.downcase} report has been generated and is attached to this email.</p>
            <p>This report covers the period ending #{Date.today.strftime('%B %d, %Y')}.</p>
            <p>If you have any questions about this report, please contact your account administrator.</p>
          </div>
          <div class="footer">
            <p>This is an automated report from Powernode.</p>
            <p>&copy; #{Date.today.year} Powernode. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    HTML
  end

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