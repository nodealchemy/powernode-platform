# frozen_string_literal: true

require 'mail'
require_relative '../services/email_configuration_service'

# Job to send a test email to verify SMTP configuration
# Sends email directly via Mail gem using SMTP settings
class TestEmailJob < BaseJob
  sidekiq_options queue: 'email', retry: 1

  def execute(email_address, account_id = nil)
    logger.info "Sending test email to #{email_address}"

    # Ensure we have the latest email settings
    refresh_email_settings

    # Configure mail delivery settings
    configure_mail_settings

    # Create and send the email
    mail = build_test_email(email_address)
    mail.deliver!

    logger.info "Test email sent successfully to #{email_address}"
    { success: true, email: email_address, sent_at: Time.current.iso8601 }
  rescue Net::SMTPAuthenticationError => e
    logger.error "SMTP authentication failed: #{e.message}"
    raise "SMTP authentication failed. Please check your username and password."
  rescue Net::SMTPServerBusy => e
    logger.error "SMTP server busy: #{e.message}"
    raise "SMTP server is busy. Please try again later."
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    logger.error "SMTP connection timeout: #{e.message}"
    raise "Could not connect to SMTP server. Please check the host and port."
  rescue StandardError => e
    logger.error "Test email failed: #{e.class} - #{e.message}"
    raise "Failed to send test email: #{e.message}"
  end

  private

  def refresh_email_settings
    # Fetch latest email settings from backend and update environment
    EmailConfigurationService.instance.fetch_settings(force_refresh: true)
  rescue StandardError => e
    logger.warn "Failed to refresh email settings: #{e.message} - using cached settings"
  end

  def configure_mail_settings
    settings = EmailConfigurationService.instance.settings

    Mail.defaults do
      delivery_method :smtp, {
        address: settings[:smtp_host] || ENV['SMTP_HOST'] || 'localhost',
        port: (settings[:smtp_port] || ENV['SMTP_PORT'] || 587).to_i,
        domain: settings[:smtp_domain] || ENV['SMTP_DOMAIN'] || 'powernode.dev',
        user_name: settings[:smtp_username] || ENV['SMTP_USERNAME'],
        password: settings[:smtp_password] || ENV['SMTP_PASSWORD'],
        authentication: settings[:smtp_authentication] ? :plain : nil,
        enable_starttls_auto: (settings[:smtp_encryption] || ENV['SMTP_ENCRYPTION'] || 'tls') == 'tls',
        ssl: settings[:smtp_encryption] == 'ssl'
      }.compact
    end
  end

  def build_test_email(to_address)
    body_content = test_email_body
    settings = EmailConfigurationService.instance.settings
    from_address = settings[:smtp_from_address] || ENV['SMTP_FROM_ADDRESS'] || 'noreply@powernode.dev'

    Mail.new do
      from    from_address
      to      to_address
      subject 'Powernode Test Email'

      html_part do
        content_type 'text/html; charset=UTF-8'
        body body_content
      end

      text_part do
        content_type 'text/plain; charset=UTF-8'
        body body_content.gsub(/<[^>]+>/, '').gsub(/\s+/, ' ').strip
      end
    end
  end

  def test_email_body
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: #4F46E5; color: white; padding: 20px; border-radius: 8px 8px 0 0; text-align: center; }
          .content { background: #f8f9fa; padding: 20px; border-radius: 0 0 8px 8px; }
          .success { color: #10B981; font-weight: bold; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
        </style>
      </head>
      <body>
        <div class="header">
          <h1>🎉 Test Email Successful</h1>
        </div>
        <div class="content">
          <p>Congratulations! Your email configuration is <span class="success">working correctly</span>.</p>
          <p>This test email was sent from your Powernode platform to verify that:</p>
          <ul>
            <li>SMTP server connection is established</li>
            <li>Authentication credentials are valid</li>
            <li>Email delivery is functioning</li>
          </ul>
          <p><strong>Sent at:</strong> #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}</p>
        </div>
        <div class="footer">
          <p>Powernode Platform - Email Configuration Test</p>
        </div>
      </body>
      </html>
    HTML
  end
end
