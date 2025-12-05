# frozen_string_literal: true

require_relative '../mailers/notification_mailer'
require_relative '../services/system_worker_auth'

class TestEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: false
  
  def execute(email_address, account_id = nil)
    log_info("Starting TestEmailJob with email_address and account_id parameters")
    
    # Handle both old hash format and new simple args format
    if email_address.is_a?(Hash)
      hash_args = email_address
      log_info("Processing hash args (email and account_id parameters)")
      email_address = hash_args['email'] || hash_args[:email]
      account_id = hash_args['account_id'] || hash_args[:account_id]
      log_info("Extracted parameters from hash format")
    end
    
    unless email_address.present?
      log_warn("No email address provided")
      return
    end
    
    log_info("Sending test email to configured recipient: #{email_address}")
    
    # In test environment, fake email delivery for testing purposes
    if PowernodeWorker.application.env == 'test'
      log_info("Test environment detected - simulating email delivery")
      log_info("Test email would be sent to: #{email_address}")
      log_info("Email delivery simulation completed successfully")
    else
      # Ensure we have the latest email configuration by forcing a refresh
      log_info("Refreshing email settings from backend...")
      EmailConfigurationService.instance.fetch_settings(force_refresh: true)
      log_info("Email settings refreshed successfully")
      
      # Send the test email
      log_info("Sending email via NotificationMailer...")
      NotificationMailer.test_email(email_address).deliver_now
      log_info("Email sent successfully")
    end
    
    
    # Log to backend for audit using system worker authentication if account_id provided
    begin
      log_info("Creating audit log...")
      client = if account_id
                 SystemWorkerAuth.instance.create_api_client(account_id)
               else
                 api_client
               end
      
      log_info("Getting provider from settings...")
      settings = EmailConfigurationService.instance.settings
      log_info("Retrieved email settings configuration")
      provider = settings[:provider] rescue 'unknown'
      log_info("Email provider configured")
               
      client.post("/api/v1/audit_logs", {
        action: 'test_email_sent',
        resource_type: 'TestEmail', 
        resource_id: 'test_email_job',  # Don't store actual email address
        source: 'worker',
        details: {
          # recipient email removed for privacy
          timestamp: Time.now.iso8601,
          provider: provider,
          account_provided: account_id ? 'yes' : 'no',
          authentication_method: account_id ? 'system_worker' : 'default_worker'
        }
      })
      log_info("Audit log created successfully")
    rescue StandardError => audit_error
      log_warn("Audit log failed: #{audit_error.message}")
    end
  rescue StandardError => e
    log_error("TestEmailJob failed: #{e.message}")
    
    # Report failure to backend using system worker authentication if account_id provided
    begin
      client = if account_id
                 SystemWorkerAuth.instance.create_api_client(account_id)
               else
                 api_client
               end
               
      client.post("/api/v1/audit_logs", {
        action: 'test_email_failed',
        resource_type: 'TestEmail',
        resource_id: 'test_email_job',  # Don't store actual email address
        source: 'worker',
        details: {
          # recipient email removed for privacy
          error: e.message,
          timestamp: Time.now.iso8601,
          account_provided: account_id ? 'yes' : 'no',
          authentication_method: account_id ? 'system_worker' : 'default_worker'
        }
      })
    rescue StandardError => audit_error
      log_warn("Audit log for failure failed: #{audit_error.message}")
    end
    
    raise e
  end
  
  private
  
  def api_client
    @api_client ||= ApiClient.new
  end
end