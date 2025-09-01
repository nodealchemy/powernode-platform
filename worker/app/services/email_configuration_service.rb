# frozen_string_literal: true

require 'net/http'
require 'json'
require 'singleton'

class EmailConfigurationService
  include Singleton
  
  attr_reader :settings
  
  def initialize
    @settings = {}
    @last_fetched = nil
    @cache_duration = 300 # 5 minutes in seconds
  end
  
  # Fetch and cache email settings from the backend
  def fetch_settings(force_refresh: false)
    # Use cached settings if still valid
    if !force_refresh && @last_fetched && (Time.now - @last_fetched) < @cache_duration
      return @settings
    end
    
    begin
      # Get worker token for authentication
      worker_token = PowernodeWorker.application.config.worker_token
      backend_url = ENV['BACKEND_URL'] || 'http://localhost:3000'
      
      uri = URI("#{backend_url}/api/v1/email_settings")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 10
      http.open_timeout = 5
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{worker_token}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      
      response = http.request(request)
      
      if response.code == '200'
        data = JSON.parse(response.body)
        @settings = symbolize_keys(data['data'])
        @last_fetched = Time.now
        
        configure_action_mailer!
        
        @settings
      else
        use_fallback_settings
      end
    rescue StandardError => e
      use_fallback_settings
    end
  end
  
  # Configure ActionMailer with the fetched settings
  def configure_action_mailer!
    return unless @settings[:smtp_enabled] || @settings[:provider] != 'smtp'
    
    case @settings[:provider]
    when 'smtp'
      configure_smtp!
    when 'sendgrid'
      configure_sendgrid!
    when 'ses'
      configure_ses!
    when 'mailgun'
      configure_mailgun!
    else
    end
    
    # Set default from address
    if @settings[:smtp_from_address].present?
      ActionMailer::Base.default from: format_from_address
    end
  end
  
  private
  
  def configure_smtp!
    return unless @settings[:smtp_enabled]
    
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = {
      address: @settings[:smtp_host],
      port: @settings[:smtp_port],
      domain: @settings[:smtp_domain] || extract_domain(@settings[:smtp_from_address]),
      user_name: @settings[:smtp_username],
      password: @settings[:smtp_password],
      authentication: @settings[:smtp_authentication] ? :plain : nil,
      enable_starttls_auto: @settings[:smtp_encryption] == 'tls',
      ssl: @settings[:smtp_encryption] == 'ssl',
      tls: @settings[:smtp_encryption] == 'ssl',
      open_timeout: 5,
      read_timeout: 10
    }.compact
    
  end
  
  def configure_sendgrid!
    if @settings[:sendgrid_api_key].present?
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: 'smtp.sendgrid.net',
        port: 587,
        domain: extract_domain(@settings[:smtp_from_address]),
        user_name: 'apikey',
        password: @settings[:sendgrid_api_key],
        authentication: :plain,
        enable_starttls_auto: true
      }
    else
      use_fallback_settings
    end
  end
  
  def configure_ses!
    if @settings[:ses_access_key].present? && @settings[:ses_secret_key].present?
      # For AWS SES, we'd typically use the aws-sdk-ses gem
      # For now, configure as SMTP
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: "email-smtp.#{@settings[:ses_region]}.amazonaws.com",
        port: 587,
        domain: extract_domain(@settings[:smtp_from_address]),
        user_name: @settings[:ses_access_key],
        password: @settings[:ses_secret_key],
        authentication: :plain,
        enable_starttls_auto: true
      }
    else
      use_fallback_settings
    end
  end
  
  def configure_mailgun!
    if @settings[:mailgun_api_key].present? && @settings[:mailgun_domain].present?
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: 'smtp.mailgun.org',
        port: 587,
        domain: @settings[:mailgun_domain],
        user_name: "postmaster@#{@settings[:mailgun_domain]}",
        password: @settings[:mailgun_api_key],
        authentication: :plain,
        enable_starttls_auto: true
      }
    else
      use_fallback_settings
    end
  end
  
  def format_from_address
    if @settings[:smtp_from_name].present?
      "#{@settings[:smtp_from_name]} <#{@settings[:smtp_from_address]}>"
    else
      @settings[:smtp_from_address]
    end
  end
  
  def extract_domain(email)
    return 'localhost' if email.blank?
    email.split('@').last || 'localhost'
  end
  
  def use_fallback_settings
    # Fallback to environment variables or default settings
    @settings = {
      provider: 'smtp',
      smtp_enabled: ENV['SMTP_ENABLED'] == 'true',
      smtp_host: ENV['SMTP_HOST'] || 'localhost',
      smtp_port: ENV['SMTP_PORT']&.to_i || 1025,
      smtp_username: ENV['SMTP_USERNAME'],
      smtp_password: ENV['SMTP_PASSWORD'],
      smtp_encryption: ENV['SMTP_ENCRYPTION'] || 'none',
      smtp_authentication: ENV['SMTP_AUTH'] != 'false',
      smtp_from_address: ENV['SMTP_FROM_ADDRESS'] || 'noreply@powernode.dev',
      smtp_from_name: ENV['SMTP_FROM_NAME'] || 'Powernode',
      smtp_domain: ENV['SMTP_DOMAIN'] || 'powernode.dev'
    }
    
    configure_action_mailer!
    
    @settings
  end
  
  # Helper method to symbolize hash keys recursively
  def symbolize_keys(hash)
    return hash unless hash.is_a?(Hash)
    
    hash.each_with_object({}) do |(key, value), result|
      new_key = key.is_a?(String) ? key.to_sym : key
      new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
      result[new_key] = new_value
    end
  end
end