require_relative '../base_job'

class Notifications::TransactionalEmailJob < BaseJob
  sidekiq_options queue: 'emails', retry: 3, backtrace: true

  def execute(email_data)
    validate_required_params(email_data, 'email_type', 'recipient')
    
    log_info("Processing transactional email job", 
      email_type: email_data['email_type'], 
      recipient: email_data['recipient']
    )

    email_service = EmailDeliveryWorkerService.new
    
    result = email_service.send_transactional_email(
      email_type: email_data['email_type'],
      recipient: email_data['recipient'],
      data: email_data['data'] || {},
      account_id: email_data['account_id'],
      user_id: email_data['user_id']
    )

    if result[:success]
      log_info("Transactional email job completed successfully", 
        delivery_id: result.dig(:data, :delivery_id),
        email_type: email_data['email_type']
      )
    else
      log_error("Transactional email job failed", nil, 
        error: result[:error],
        email_type: email_data['email_type']
      )
    end

    result
  end
end