# frozen_string_literal: true

class AdminSettingsUpdateService
  def initialize(user:, params:)
    @user = user
    @params = params
    @errors = []
  end

  def call
    result = { success: true, data: {}, errors: [] }

    # Verify admin permissions
    unless @user.owner? || @user.admin?
      result[:success] = false
      result[:errors] = ['Access denied: Admin privileges required']
      return result
    end

    ActiveRecord::Base.transaction do
      update_system_settings if system_settings_changed?
      update_security_settings if security_settings_changed?
      update_feature_flags if feature_flags_changed?
      log_admin_changes

      raise ActiveRecord::Rollback if @errors.any?
    end

    if @errors.any?
      result[:success] = false
      result[:errors] = @errors
    else
      result[:data] = {
        system_settings: updated_system_settings,
        message: "Admin settings updated successfully"
      }
    end

    result
  end

  private

  def system_settings_changed?
    %w[maintenance_mode registration_enabled email_verification_required 
       password_complexity_level session_timeout_minutes max_failed_login_attempts
       account_lockout_duration].any? { |key| @params.key?(key) }
  end

  def security_settings_changed?
    @params.key?(:max_failed_login_attempts) || @params.key?(:account_lockout_duration)
  end

  def feature_flags_changed?
    @params.key?(:feature_flags)
  end

  def update_system_settings
    # In a real implementation, these would be stored in a system settings table or Redis
    # For now, we'll log the changes and simulate the update
    
    if @params[:maintenance_mode].present?
      # Would toggle maintenance mode
      log_setting_change('maintenance_mode', @params[:maintenance_mode])
    end

    if @params[:registration_enabled].present?
      # Would enable/disable registration
      log_setting_change('registration_enabled', @params[:registration_enabled])
    end

    if @params[:email_verification_required].present?
      log_setting_change('email_verification_required', @params[:email_verification_required])
    end

    if @params[:password_complexity_level].present?
      unless %w[low medium high].include?(@params[:password_complexity_level])
        @errors << "Invalid password complexity level"
        return
      end
      log_setting_change('password_complexity_level', @params[:password_complexity_level])
    end

    if @params[:session_timeout_minutes].present?
      timeout = @params[:session_timeout_minutes].to_i
      unless timeout.between?(5, 480) # 5 minutes to 8 hours
        @errors << "Session timeout must be between 5 and 480 minutes"
        return
      end
      log_setting_change('session_timeout_minutes', timeout)
    end
  end

  def update_security_settings
    if @params[:max_failed_login_attempts].present?
      attempts = @params[:max_failed_login_attempts].to_i
      unless attempts.between?(3, 10)
        @errors << "Max failed login attempts must be between 3 and 10"
        return
      end
      
      # Update the User model constant - in reality this would be in a settings table
      log_setting_change('max_failed_login_attempts', attempts)
    end

    if @params[:account_lockout_duration].present?
      duration = @params[:account_lockout_duration].to_i
      unless duration.between?(5, 1440) # 5 minutes to 24 hours
        @errors << "Account lockout duration must be between 5 and 1440 minutes"
        return
      end
      
      log_setting_change('account_lockout_duration', duration)
    end
  end

  def update_feature_flags
    return unless @params[:feature_flags].is_a?(Hash)

    # Validate feature flags
    valid_flags = %w[new_dashboard beta_features advanced_analytics maintenance_mode]
    
    @params[:feature_flags].each do |flag, enabled|
      unless valid_flags.include?(flag)
        @errors << "Invalid feature flag: #{flag}"
        next
      end

      unless [true, false, 'true', 'false'].include?(enabled)
        @errors << "Feature flag #{flag} must be true or false"
        next
      end

      log_setting_change("feature_flag_#{flag}", enabled)
    end
  end

  def log_admin_changes
    return if @params.empty?

    AuditLog.create!(
      user: @user,
      account: @user.account,
      action: 'admin_settings_update',
      resource_type: 'SystemSettings',
      resource_id: nil,
      source: 'admin_panel',
      metadata: {
        changes: @params.to_h,
        admin_user: @user.email,
        timestamp: Time.current.iso8601
      }
    )
  end

  def log_setting_change(setting_name, new_value)
    Rails.logger.info "[ADMIN] #{@user.email} changed #{setting_name} to #{new_value}"
    
    # In a real implementation, you'd update the actual setting here
    # For example: SystemSetting.find_or_create_by(name: setting_name).update(value: new_value)
  end

  def updated_system_settings
    {
      maintenance_mode: @params[:maintenance_mode] || false,
      registration_enabled: @params[:registration_enabled] || true,
      email_verification_required: @params[:email_verification_required] || true,
      password_complexity_level: @params[:password_complexity_level] || 'high',
      session_timeout_minutes: @params[:session_timeout_minutes] || 60,
      max_failed_login_attempts: @params[:max_failed_login_attempts] || 5,
      account_lockout_duration: @params[:account_lockout_duration] || 30,
      last_updated_by: @user.email,
      last_updated_at: Time.current.iso8601
    }
  end
end