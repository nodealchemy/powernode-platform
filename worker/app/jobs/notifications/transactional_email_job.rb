# frozen_string_literal: true

require_relative '../base_job'

class Notifications::TransactionalEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: 3, backtrace: true

  def execute(email_data)
    validate_required_params(email_data, 'email_type', 'recipient')

    email_type = email_data['email_type']
    recipient = email_data['recipient']

    log_info("Processing transactional email job",
      email_type: email_type,
      recipient: recipient
    )

    begin
      email_service = EmailDeliveryWorkerService.new

      result = email_service.send_transactional_email(
        email_type: email_type,
        recipient: recipient,
        data: email_data['data'] || {},
        account_id: email_data['account_id'],
        user_id: email_data['user_id']
      )

      if result[:success]
        log_info("Transactional email job completed successfully",
          delivery_id: result.dig(:data, :delivery_id),
          email_type: email_type
        )
      else
        log_error("Transactional email job failed", nil,
          error: result[:error],
          email_type: email_type
        )
      end

      result
    rescue StandardError => e
      log_error("Transactional email job encountered an exception",
        error: e.message,
        error_class: e.class.name,
        email_type: email_type,
        recipient: recipient
      )
      raise
    end
  end
end