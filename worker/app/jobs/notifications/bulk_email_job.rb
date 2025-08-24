# frozen_string_literal: true

require_relative '../base_job'

class Notifications::BulkEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: 2, backtrace: true

  def execute(bulk_email_data)
    validate_required_params(bulk_email_data, 'recipients', 'subject', 'body', 'email_type')
    
    recipients = bulk_email_data['recipients']
    log_info("Processing bulk email job", 
      email_type: bulk_email_data['email_type'], 
      recipient_count: recipients.size
    )

    email_service = EmailDeliveryWorkerService.new
    
    result = email_service.send_bulk_emails(
      recipients: recipients,
      subject: bulk_email_data['subject'],
      body: bulk_email_data['body'],
      email_type: bulk_email_data['email_type'],
      account_id: bulk_email_data['account_id'],
      template: bulk_email_data['template'],
      template_data: bulk_email_data['template_data'] || {},
      from: bulk_email_data['from'],
      reply_to: bulk_email_data['reply_to'],
      content_type: bulk_email_data['content_type']
    )

    if result[:success]
      summary = result.dig(:data, :summary)
      log_info("Bulk email job completed", 
        total: summary['total'],
        successful: summary['successful'],
        failed: summary['failed']
      )
    else
      log_error("Bulk email job failed", nil, error: result[:error])
    end

    result
  end
end