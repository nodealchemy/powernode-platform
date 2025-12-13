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
    
    # Schedule next refresh in 5 minutes
    log_info("Scheduling next email settings refresh in 5 minutes")
    RefreshEmailSettingsJob.perform_in(5.minutes)
    
  rescue StandardError => e
    log_error("RefreshEmailSettingsJob failed: #{e.message}")
    log_error(e.backtrace.join("\n"))
    log_info("Retrying email settings refresh in 10 minutes due to error")
    
    # Retry in 10 minutes on error
    RefreshEmailSettingsJob.perform_in(10.minutes)
  end
end