require_relative '../base_job'

class Notifications::EmailDeliveryJob < BaseJob
  sidekiq_options queue: 'email', retry: 3, backtrace: true

  def execute(email_data)
    validate_required_params(email_data, 'to', 'subject', 'body', 'email_type')
    
    log_info("Processing email delivery job", email_type: email_data['email_type'], to: email_data['to'])

    email_service = EmailDeliveryWorkerService.new
    
    result = email_service.send_email(
      to: email_data['to'],
      subject: email_data['subject'],
      body: email_data['body'],
      email_type: email_data['email_type'],
      account_id: email_data['account_id'],
      user_id: email_data['user_id'],
      template: email_data['template'],
      template_data: email_data['template_data'] || {},
      from: email_data['from'],
      reply_to: email_data['reply_to'],
      content_type: email_data['content_type'],
      attachments: email_data['attachments']
    )

    if result[:success]
      log_info("Email delivery job completed successfully", 
        delivery_id: result.dig(:data, :delivery_id),
        email_type: email_data['email_type']
      )
    else
      log_error("Email delivery job failed", nil, 
        error: result[:error],
        email_type: email_data['email_type']
      )
    end

    result
  end
end