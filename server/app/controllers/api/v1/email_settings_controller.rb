# frozen_string_literal: true

class Api::V1::EmailSettingsController < ApplicationController
  before_action :authenticate_service_token
  
  # GET /api/v1/email_settings
  # Used by worker service to fetch SMTP configuration
  def show
    email_settings = fetch_email_settings
    
    render json: {
      data: email_settings,
      status: 'success'
    }
  end
  
  # PUT /api/v1/email_settings
  # Update email configuration
  def update
    begin
      email_params = params.require(:email_settings).permit(
        :email_provider, :smtp_enabled, :smtp_host, :smtp_port, :smtp_username, 
        :smtp_password, :smtp_encryption, :smtp_authentication, :smtp_from_address, 
        :smtp_from_name, :smtp_domain, :sendgrid_api_key, :ses_access_key, 
        :ses_secret_key, :ses_region, :mailgun_api_key, :mailgun_domain,
        :email_verification_expiry_hours, :password_reset_expiry_hours,
        :max_email_retries, :email_retry_delay_seconds
      )
      
      # Update each setting
      email_params.each do |key, value|
        if key.ends_with?('_password') || key.ends_with?('_api_key') || key.ends_with?('_secret_key')
          # Encrypt sensitive values
          AdminSetting.set("#{key}_encrypted", encrypt_password(value))
        else
          AdminSetting.set(key, value)
        end
      end
      
      # Trigger email settings refresh in worker
      begin
        WorkerJobService.enqueue_refresh_email_settings
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.warn "Failed to notify worker of email settings change: #{e.message}"
        # Continue - don't fail the update if worker notification fails
      end
      
      render json: {
        message: 'Email settings updated successfully',
        status: 'success'
      }
    rescue StandardError => e
      Rails.logger.error "Failed to update email settings: #{e.message}"
      render json: {
        error: 'Failed to update email settings',
        details: e.message,
        status: 'error'
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/email_settings/test
  # Test email configuration
  def test
    test_email = params[:email]
    
    unless test_email.present?
      render json: { error: 'Email address is required' }, status: :unprocessable_entity
      return
    end
    
    # Send test email request to worker service
    begin
      # Use WorkerJobService to enqueue the test email job
      WorkerJobService.enqueue_test_email(test_email)
      
      render json: {
        message: "Test email queued for delivery to #{test_email}",
        status: 'success'
      }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue test email: #{e.message}"
      render json: {
        error: 'Failed to queue test email. Please check worker service status.',
        status: 'error'
      }, status: :service_unavailable
    rescue StandardError => e
      Rails.logger.error "Failed to queue test email: #{e.message}"
      render json: {
        error: 'Failed to queue test email. Please check worker service status.',
        status: 'error'
      }, status: :service_unavailable
    end
  end
  
  private
  
  def fetch_email_settings
    {
      provider: AdminSetting.get('email_provider', 'smtp'),
      smtp_enabled: AdminSetting.get('smtp_enabled', false),
      smtp_host: AdminSetting.get('smtp_host', ''),
      smtp_port: AdminSetting.get('smtp_port', 587),
      smtp_username: AdminSetting.get('smtp_username', ''),
      smtp_password: decrypt_password(AdminSetting.get('smtp_password_encrypted', '')),
      smtp_encryption: AdminSetting.get('smtp_encryption', 'tls'),
      smtp_authentication: AdminSetting.get('smtp_authentication', true),
      smtp_from_address: AdminSetting.get('smtp_from_address', 'noreply@powernode.dev'),
      smtp_from_name: AdminSetting.get('smtp_from_name', 'Powernode'),
      smtp_domain: AdminSetting.get('smtp_domain', 'powernode.dev'),
      
      # Additional provider settings
      sendgrid_api_key: decrypt_password(AdminSetting.get('sendgrid_api_key_encrypted', '')),
      ses_access_key: AdminSetting.get('ses_access_key', ''),
      ses_secret_key: decrypt_password(AdminSetting.get('ses_secret_key_encrypted', '')),
      ses_region: AdminSetting.get('ses_region', 'us-east-1'),
      mailgun_api_key: decrypt_password(AdminSetting.get('mailgun_api_key_encrypted', '')),
      mailgun_domain: AdminSetting.get('mailgun_domain', ''),
      
      # Email behavior settings
      email_verification_expiry_hours: AdminSetting.get('email_verification_expiry_hours', 24),
      password_reset_expiry_hours: AdminSetting.get('password_reset_expiry_hours', 2),
      max_email_retries: AdminSetting.get('max_email_retries', 3),
      email_retry_delay_seconds: AdminSetting.get('email_retry_delay_seconds', 60)
    }
  end
  
  def decrypt_password(encrypted_value)
    return '' if encrypted_value.blank?
    
    # In production, use Rails credentials or encryption
    # For now, return as-is (assuming it's stored encrypted)
    encrypted_value
  end
  
  def encrypt_password(value)
    return '' if value.blank?
    
    # In production, use proper encryption
    # For now, store as-is
    value
  end
  
  def authenticate_service_token
    # Accept either service token or admin JWT
    token = request.headers['Authorization']&.split(' ')&.last
    
    if token.present?
      # Check if it's a service token
      if token.starts_with?('swt_')
        service = Service.find_by(token: token, status: 'active')
        return if service.present?
      end
      
      # Otherwise check JWT for admin user
      begin
        payload = JWT.decode(token, Rails.application.config.jwt_secret_key)[0]
        user = User.find_by(id: payload['user_id'])
        return if user&.admin?
      rescue JWT::DecodeError
        # Invalid token
      end
    end
    
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end
end