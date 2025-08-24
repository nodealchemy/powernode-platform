require_relative '../mailers/notification_mailer'
require_relative '../services/email_configuration_service'
require_relative '../services/api_client'

class SendNotificationEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: 3
  
  def execute(args)
    email_type = args['type'] || args[:type]
    params = args['params'] || args[:params] || {}
    
    unless email_type.present?
      return
    end
    
    
    # Ensure we have the latest email configuration
    EmailConfigurationService.instance.fetch_settings
    
    # Route to appropriate mailer method
    case email_type.to_s
    when 'welcome'
      NotificationMailer.welcome_email(params['user_id']).deliver_now
    when 'password_reset'
      NotificationMailer.password_reset(params['user_id'], params['reset_token']).deliver_now
    when 'email_verification'
      NotificationMailer.email_verification(params['user_id'], params['verification_token']).deliver_now
    when 'subscription_renewal'
      NotificationMailer.subscription_renewal(params['account_id']).deliver_now
    when 'payment_failed'
      NotificationMailer.payment_failed(
        params['account_id'],
        params['amount'],
        params['retry_date']
      ).deliver_now
    when 'subscription_cancelled'
      NotificationMailer.subscription_cancelled(
        params['account_id'],
        params['end_date']
      ).deliver_now
    else
      return
    end
    
    
    # Log to backend for tracking
    api_client.post("/api/v1/notifications", {
      notification_type: 'email',
      email_type: email_type,
      status: 'sent',
      params: params,
      timestamp: Time.current
    })
  rescue StandardError => e
    
    # Report failure to backend
    api_client.post("/api/v1/notifications", {
      notification_type: 'email',
      email_type: email_type,
      status: 'failed',
      error: e.message,
      params: params,
      timestamp: Time.current
    })
    
    raise e # Re-raise for Sidekiq retry
  end
  
  private
  
  def api_client
    @api_client ||= ApiClient.new
  end
end