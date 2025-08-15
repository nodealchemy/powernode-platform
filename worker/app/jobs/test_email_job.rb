require_relative '../mailers/notification_mailer'

class TestEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: false
  
  def execute(args)
    email_address = args['email'] || args[:email]
    account_id = args['account_id'] || args[:account_id]
    
    unless email_address.present?
      puts "TestEmailJob: No email address provided"
      return
    end
    
    puts "Sending test email to #{email_address} (account: #{account_id || 'default'})"
    
    # Ensure we have the latest email configuration
    EmailConfigurationService.instance.fetch_settings
    
    # Send the test email
    NotificationMailer.test_email(email_address).deliver_now
    
    puts "Test email sent successfully to #{email_address}"
    
    # Log to backend for audit using primary service authentication if account_id provided
    begin
      client = if account_id
                 PrimaryServiceAuth.instance.create_api_client(account_id)
               else
                 api_client
               end
               
      client.post("/api/v1/audit_logs", {
        action: 'test_email_sent',
        resource_type: 'TestEmail', 
        resource_id: email_address,
        source: 'worker',
        details: {
          recipient: email_address,
          timestamp: Time.current.iso8601,
          provider: EmailConfigurationService.instance.settings[:provider],
          account_id: account_id,
          authentication_method: account_id ? 'primary_service' : 'default_service'
        }
      })
      puts "Audit log created for successful test email to #{email_address}"
    rescue StandardError => audit_error
      puts "Failed to create audit log: #{audit_error.message}"
    end
  rescue StandardError => e
    puts "Failed to send test email to #{email_address}: #{e.message}"
    puts e.backtrace.join("\n")
    
    # Report failure to backend using primary service authentication if account_id provided
    begin
      client = if account_id
                 PrimaryServiceAuth.instance.create_api_client(account_id)
               else
                 api_client
               end
               
      client.post("/api/v1/audit_logs", {
        action: 'test_email_failed',
        resource_type: 'TestEmail',
        resource_id: email_address,
        source: 'worker',
        details: {
          recipient: email_address,
          error: e.message,
          timestamp: Time.current.iso8601,
          account_id: account_id,
          authentication_method: account_id ? 'primary_service' : 'default_service'
        }
      })
      puts "Audit log created for failed test email to #{email_address}"
    rescue StandardError => audit_error
      puts "Failed to create audit log: #{audit_error.message}"
    end
    
    raise e
  end
  
  private
  
  def api_client
    @api_client ||= ApiClient.new
  end
end