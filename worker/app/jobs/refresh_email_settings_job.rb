# frozen_string_literal: true

require_relative '../services/email_configuration_service'

class RefreshEmailSettingsJob < BaseJob
  sidekiq_options queue: 'email', retry: 1

  def execute(args = {})
    logger.info "Starting RefreshEmailSettingsJob - refreshing email configuration from backend"
    
    email_service = EmailConfigurationService.instance
    
    settings = email_service.fetch_settings(force_refresh: true)
    
    if settings.present?
      logger.info "Email settings refreshed successfully from backend"
      logger.info "Provider: #{settings[:provider]}"
      logger.info "SMTP Enabled: #{settings[:smtp_enabled]}" if settings[:provider] == 'smtp'
      logger.info "From Address: #{settings[:smtp_from_address]}" if settings[:smtp_from_address]
    else
      logger.warn "No email settings retrieved from backend, using fallback configuration"
    end
    
    # Schedule next refresh in 5 minutes
    logger.info "Scheduling next email settings refresh in 5 minutes"
    RefreshEmailSettingsJob.perform_in(5.minutes)
    
  rescue StandardError => e
    logger.error "RefreshEmailSettingsJob failed: #{e.message}"
    logger.error e.backtrace.join("\n")
    logger.info "Retrying email settings refresh in 10 minutes due to error"
    
    # Retry in 10 minutes on error
    RefreshEmailSettingsJob.perform_in(10.minutes)
  end
end