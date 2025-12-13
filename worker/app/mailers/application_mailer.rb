# frozen_string_literal: true

require_relative '../services/email_configuration_service'

class ApplicationMailer < ActionMailer::Base
  # Dynamically set default from address
  default from: -> { default_from_address }
  
  layout 'mailer'
  
  # Ensure email configuration is up to date before sending
  before_action :ensure_email_configuration
  
  private
  
  def ensure_email_configuration
    # Get current email settings
    email_service = EmailConfigurationService.instance
    settings = email_service.settings
    
    # Apply configuration if not already set
    if settings.empty?
      email_service.fetch_settings
    end
  end
  
  def default_from_address
    email_service = EmailConfigurationService.instance
    settings = email_service.settings
    
    if settings[:smtp_from_name].present? && settings[:smtp_from_address].present?
      "#{settings[:smtp_from_name]} <#{settings[:smtp_from_address]}>"
    elsif settings[:smtp_from_address].present?
      settings[:smtp_from_address]
    else
      'noreply@powernode.dev'
    end
  end
end