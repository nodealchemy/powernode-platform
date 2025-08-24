require_relative '../services/email_configuration_service'

class RefreshEmailSettingsJob < BaseJob
  sidekiq_options queue: 'email', retry: 1

  def execute(args = {})
    email_service = EmailConfigurationService.instance
    
    settings = email_service.fetch_settings(force_refresh: true)
    
    if settings.present?
    else
    end
    
    # Schedule next refresh in 5 minutes
    RefreshEmailSettingsJob.perform_in(5.minutes)
  rescue StandardError => e
    
    # Retry in 10 minutes on error
    RefreshEmailSettingsJob.perform_in(10.minutes)
  end
end