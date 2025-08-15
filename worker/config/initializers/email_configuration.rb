# Email Configuration Initializer
# Fetches email settings from backend API on worker startup
# and periodically refreshes them

require_relative '../../app/services/email_configuration_service'

Rails.application.config.after_initialize do
  # Initial configuration on startup
  begin
    Rails.logger.info "Initializing email configuration from backend..."
    email_service = EmailConfigurationService.instance
    settings = email_service.fetch_settings(force_refresh: true)
    
    if settings.present?
      Rails.logger.info "Email configuration loaded successfully"
      Rails.logger.info "Provider: #{settings[:provider]}"
      Rails.logger.info "SMTP Enabled: #{settings[:smtp_enabled]}" if settings[:provider] == 'smtp'
    else
      Rails.logger.warn "No email settings found, using fallback configuration"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to initialize email configuration: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Rails.logger.warn "Worker will continue with fallback email configuration"
  end
  
  # Schedule periodic refresh of email settings (every 5 minutes)
  if defined?(Sidekiq)
    RefreshEmailSettingsJob.perform_in(5.minutes)
  end
end