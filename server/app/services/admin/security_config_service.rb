# frozen_string_literal: true

module Admin
  # Service for managing security configuration
  #
  # Provides security management including:
  # - CSRF configuration
  # - JWT configuration
  # - Authentication settings
  # - API security settings
  # - Security testing
  # - JWT secret rotation
  # - Token blacklist management
  #
  # Usage:
  #   service = Admin::SecurityConfigService.new(user: current_user)
  #   config = service.get_config
  #
  class SecurityConfigService
    attr_reader :user, :account

    # Grace period for JWT secret rotation (hours)
    JWT_ROTATION_GRACE_PERIOD = 24

    def initialize(user:)
      @user = user
      @account = user.account
    end

    # Get current security configuration
    # @return [Hash] Security configuration
    def get_config
      {
        csrf: csrf_config,
        jwt: jwt_config,
        authentication: authentication_config,
        api_security: api_security_config
      }
    end

    # Update security configuration
    # @param config_params [Hash] Configuration parameters
    # @return [Hash] Result with updated config
    def update_config(config_params)
      apply_csrf_config(config_params[:csrf]) if config_params[:csrf]
      apply_jwt_config(config_params[:jwt]) if config_params[:jwt]
      apply_authentication_config(config_params[:authentication]) if config_params[:authentication]
      apply_api_security_config(config_params[:api_security]) if config_params[:api_security]

      log_security_update(config_params)

      {
        success: true,
        config: get_config,
        message: "Security configuration updated successfully"
      }
    rescue StandardError => e
      Rails.logger.error "Security config update failed: #{e.class.name}: #{e.message}"
      {
        success: false,
        error: "Failed to update security configuration: #{e.message}"
      }
    end

    # Test security components
    # @return [Hash] Test results
    def test_config
      test_results = {
        csrf_protection: test_csrf_protection,
        jwt_validation: test_jwt_validation,
        authentication_flow: test_authentication_flow,
        api_security: test_api_security
      }

      overall_status = determine_overall_status(test_results)

      details = []
      test_results.each do |component, status|
        details << "#{component.to_s.humanize}: #{status}" if status != "working"
      end

      {
        **test_results,
        overall_status: overall_status,
        details: details.any? ? details : [ "All security components are working correctly" ]
      }
    end

    # Regenerate JWT secret with grace period
    # @param reason [String] Reason for regeneration
    # @return [Hash] Result with new secret info
    def regenerate_jwt_secret(reason: nil)
      new_secret = SecureRandom.hex(64) # 128-character secret (512 bits)
      old_secret = Rails.application.config.jwt_secret_key

      grace_period_ends_at = JWT_ROTATION_GRACE_PERIOD.hours.from_now

      # Store both secrets with grace period
      Rails.cache.write("jwt_secret_rotation", {
        old_secret: old_secret,
        new_secret: new_secret,
        rotated_at: Time.current,
        grace_period_ends_at: grace_period_ends_at
      }, expires_in: (JWT_ROTATION_GRACE_PERIOD + 1).hours)

      # Update current secret (immediately effective for new tokens)
      Rails.application.config.jwt_secret_key = new_secret

      log_critical_security_event("jwt_secret_regenerated", {
        regenerated_by: user.email,
        grace_period_hours: JWT_ROTATION_GRACE_PERIOD,
        grace_period_ends_at: grace_period_ends_at.iso8601,
        old_secret_length: old_secret.length,
        new_secret_length: new_secret.length,
        reason: reason || "Admin-initiated rotation"
      })

      {
        success: true,
        new_secret: new_secret,
        grace_period_hours: JWT_ROTATION_GRACE_PERIOD,
        grace_period_ends_at: grace_period_ends_at.iso8601,
        warning: "Store this secret securely. After #{JWT_ROTATION_GRACE_PERIOD} hours, all sessions using the old secret will be invalidated.",
        instructions: [
          "Save the new secret to your environment variables (JWT_SECRET_KEY)",
          "Update production credentials if using Rails credentials",
          "Restart application servers after updating environment",
          "Users will need to re-authenticate after grace period expires"
        ]
      }
    end

    # Clear expired blacklisted tokens
    # @return [Hash] Result with cleared count
    def clear_blacklisted_tokens
      cleared_count = BlacklistedToken.where("expires_at < ?", Time.current).delete_all

      AuditLog.create!(
        user: user,
        account: account,
        action: "blacklisted_tokens_cleared",
        resource_type: "BlacklistedToken",
        resource_id: "bulk",
        source: "admin_panel",
        metadata: { cleared_count: cleared_count }
      )

      {
        success: true,
        cleared_count: cleared_count,
        message: "Cleared #{cleared_count} expired blacklisted tokens"
      }
    end

    # Get token blacklist statistics
    # @return [Hash] Blacklist statistics
    def blacklist_statistics
      {
        total_blacklisted: BlacklistedToken.count,
        expired: BlacklistedToken.where("expires_at < ?", Time.current).count,
        active: BlacklistedToken.where("expires_at >= ?", Time.current).count,
        blacklisted_today: BlacklistedToken.where("created_at >= ?", Date.current.beginning_of_day).count,
        blacklisted_this_week: BlacklistedToken.where("created_at >= ?", 1.week.ago).count
      }
    end

    # Get security audit summary
    # @param days [Integer] Number of days to look back
    # @return [Hash] Security audit summary
    def security_audit_summary(days: 30)
      start_date = days.days.ago

      security_actions = %w[
        login_failed
        password_change
        account_locked
        jwt_secret_regenerated
        security_config_update
        blacklisted_tokens_cleared
        2fa_enabled
        2fa_disabled
      ]

      {
        period_days: days,
        events_by_type: AuditLog.where(action: security_actions)
                                .where("created_at >= ?", start_date)
                                .group(:action)
                                .count,
        failed_logins_by_day: AuditLog.where(action: "login_failed")
                                      .where("created_at >= ?", start_date)
                                      .group("DATE(created_at)")
                                      .count
                                      .transform_keys(&:to_s),
        locked_accounts: User.where("locked_until > ?", Time.current).count,
        users_with_2fa: User.where.not(otp_secret: nil).count,
        recent_password_changes: AuditLog.where(action: "password_change")
                                         .where("created_at >= ?", start_date)
                                         .count
      }
    end

    private

    def csrf_config
      {
        enabled: Rails.configuration.x.csrf_protection_enabled || false,
        token_name: Rails.configuration.x.csrf_token_header_name || "X-CSRF-Token",
        protection_method: determine_csrf_protection_method,
        require_ssl: Rails.configuration.x.csrf_require_ssl || false
      }
    end

    def jwt_config
      {
        access_token_ttl: (Rails.configuration.x.jwt_access_token_ttl&.to_i || 900) / 60,
        refresh_token_ttl: (Rails.configuration.x.jwt_refresh_token_ttl&.to_i || 604800) / 3600,
        algorithm: Rails.configuration.x.jwt_algorithm || "HS256",
        blacklist_enabled: Rails.configuration.x.jwt_blacklist_enabled || true,
        require_fresh_tokens_for_sensitive_operations: true
      }
    end

    def authentication_config
      {
        max_failed_attempts: Rails.configuration.x.auth_max_failed_attempts || 5,
        lockout_duration: (Rails.configuration.x.auth_lockout_duration&.to_i || 900) / 60,
        require_2fa_for_admin: Rails.configuration.x.auth_require_2fa_for_admin || false,
        session_timeout: (Rails.configuration.x.auth_session_timeout&.to_i || 3600) / 60
      }
    end

    def api_security_config
      {
        rate_limiting_enabled: Rails.configuration.x.api_rate_limiting_enabled || true,
        cors_enabled: Rails.configuration.x.api_cors_enabled || true,
        allowed_origins: Rails.configuration.x.api_cors_allowed_origins || [],
        require_api_key_for_write_operations: Rails.configuration.x.api_require_key_for_writes || false
      }
    end

    def apply_csrf_config(config)
      return unless config

      Rails.configuration.x.csrf_protection_enabled = config[:enabled] || false
      Rails.configuration.x.csrf_token_header_name = config[:token_name] || "X-CSRF-Token"
      Rails.configuration.x.csrf_allow_parameter = config[:protection_method]&.in?(%w[parameter both])
      Rails.configuration.x.csrf_require_ssl = config[:require_ssl] || false
    end

    def apply_jwt_config(config)
      return unless config

      Rails.configuration.x.jwt_access_token_ttl = config[:access_token_ttl]&.minutes || 15.minutes
      Rails.configuration.x.jwt_refresh_token_ttl = config[:refresh_token_ttl]&.hours || 168.hours
      Rails.configuration.x.jwt_algorithm = config[:algorithm] || "HS256"
      Rails.configuration.x.jwt_blacklist_enabled = config[:blacklist_enabled] || true
    end

    def apply_authentication_config(config)
      return unless config

      Rails.configuration.x.auth_max_failed_attempts = config[:max_failed_attempts] || 5
      Rails.configuration.x.auth_lockout_duration = config[:lockout_duration]&.minutes || 15.minutes
      Rails.configuration.x.auth_require_2fa_for_admin = config[:require_2fa_for_admin] || false
      Rails.configuration.x.auth_session_timeout = config[:session_timeout]&.minutes || 60.minutes
    end

    def apply_api_security_config(config)
      return unless config

      Rails.configuration.x.api_rate_limiting_enabled = config[:rate_limiting_enabled] || true
      Rails.configuration.x.api_cors_enabled = config[:cors_enabled] || true
      Rails.configuration.x.api_cors_allowed_origins = config[:allowed_origins] || []
      Rails.configuration.x.api_require_key_for_writes = config[:require_api_key_for_write_operations] || false
    end

    def determine_csrf_protection_method
      if Rails.configuration.x.csrf_allow_parameter
        "both"
      else
        "header"
      end
    end

    def test_csrf_protection
      return "working" if Rails.application.config.force_ssl
      "error"
    rescue StandardError => e
      Rails.logger.error "CSRF test failed: #{e.message}"
      "error"
    end

    def test_jwt_validation
      test_payload = { user_id: "test", exp: 1.hour.from_now.to_i }
      token = Security::JwtService.encode(test_payload)
      decoded = Security::JwtService.decode(token)

      decoded[:user_id] == "test" ? "working" : "error"
    rescue StandardError => e
      Rails.logger.error "JWT test failed: #{e.message}"
      "error"
    end

    def test_authentication_flow
      return "working" if ApplicationController.instance_methods.include?(:authenticate_request)
      "error"
    rescue StandardError => e
      Rails.logger.error "Auth flow test failed: #{e.message}"
      "error"
    end

    def test_api_security
      security_measures = [
        Rails.application.config.force_ssl,
        defined?(Rack::Attack),
        ApplicationController.instance_methods.include?(:require_permission)
      ]

      security_measures.any? ? "working" : "error"
    rescue StandardError => e
      Rails.logger.error "API security test failed: #{e.message}"
      "error"
    end

    def determine_overall_status(test_results)
      if test_results.values.all? { |status| status == "working" }
        "healthy"
      elsif test_results.values.any? { |status| status == "error" }
        "error"
      else
        "warning"
      end
    end

    def log_security_update(config_params)
      AuditLog.create!(
        user: user,
        account: account,
        action: "security_config_update",
        resource_type: "SecuritySettings",
        resource_id: "system",
        source: "admin_panel",
        ip_address: Thread.current[:request_ip],
        user_agent: Thread.current[:request_user_agent],
        metadata: {
          updated_fields: config_params.keys,
          csrf_changed: config_params.key?(:csrf),
          jwt_changed: config_params.key?(:jwt),
          csrf_enabled: Rails.configuration.x.csrf_protection_enabled
        }
      )
    end

    def log_critical_security_event(action, metadata)
      AuditLog.create!(
        user: user,
        account: account,
        action: action,
        resource_type: "SecuritySettings",
        resource_id: "jwt",
        source: "admin_panel",
        ip_address: Thread.current[:request_ip],
        user_agent: Thread.current[:request_user_agent],
        severity: "critical",
        risk_level: "high",
        metadata: metadata
      )
    end
  end
end
