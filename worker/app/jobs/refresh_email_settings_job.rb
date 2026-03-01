# frozen_string_literal: true

require_relative '../services/email_configuration_service'

class RefreshEmailSettingsJob < BaseJob
  sidekiq_options queue: 'email', retry: 1

  def execute(args = {})
    log_info("Starting RefreshEmailSettingsJob - refreshing email configuration from backend")
    
    email_service = EmailConfigurationService.instance
    
    settings = email_service.fetch_settings(force_refresh: true)
    
    if settings.present?
      log_info("Email settings refreshed successfully from backend")
      log_info("Provider: #{settings[:provider]}")
      log_info("SMTP Enabled: #{settings[:smtp_enabled]}") if settings[:provider] == 'smtp'
      log_info("From Address: #{settings[:smtp_from_address]}") if settings[:smtp_from_address]
    else
      log_warn("No email settings retrieved from backend, using fallback configuration")
    end
  rescue StandardError => e
    log_error("RefreshEmailSettingsJob failed: #{e.message}")
    log_error(e.backtrace.join("\n"))
    raise # Allow Sidekiq retry mechanism to handle retries
  end
end