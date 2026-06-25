# frozen_string_literal: true

module AdminSettings
  module SecurityConfigActions
    extend ActiveSupport::Concern

    included do
      # Each security-config action requires admin.settings.security. Use a
      # before_action (halts on render) instead of inline require_permission —
      # inline does not halt the action body, so a denied user's mutation
      # (e.g. regenerate_jwt_secret) would run before the 403.
      before_action -> { require_permission("admin.settings.security") }, only: %i[
        security_config update_security_config test_security_config
        regenerate_jwt_secret clear_blacklisted_tokens
        blacklist_statistics security_audit_summary
      ]
    end

    # GET /api/v1/admin_settings/security
    def security_config
      render_success(security_service.get_config)
    rescue StandardError => e
      Rails.logger.error "Security config load failed: #{e.class.name}: #{e.message}"
      render_error("Failed to load security configuration: #{e.message}")
    end

    # PUT /api/v1/admin_settings/security
    def update_security_config
      result = security_service.update_config(security_config_params)

      if result[:success]
        render_success(
          config: result[:config],
          message: result[:message]
        )
      else
        render_error(result[:error], status: :unprocessable_content)
      end
    rescue StandardError => e
      Rails.logger.error "Security config update failed: #{e.class.name}: #{e.message}"
      render_error("Failed to update security configuration: #{e.message}")
    end

    # POST /api/v1/admin_settings/security/test
    def test_security_config
      result = security_service.test_config

      render_success(result)
    end

    # POST /api/v1/admin_settings/security/regenerate_jwt_secret
    def regenerate_jwt_secret
      result = security_service.regenerate_jwt_secret(reason: params[:reason])

      if result[:success]
        # Render the algorithm-specific result as-is. RS256 carries no key
        # material (keypair is rotated + stored server-side); HS256 (dev/test)
        # returns the new secret + env-update instructions.
        render_success(result.except(:success))
      else
        render_error(result[:error], status: :unprocessable_content)
      end
    end

    # DELETE /api/v1/admin_settings/security/blacklisted_tokens
    def clear_blacklisted_tokens
      result = security_service.clear_blacklisted_tokens

      if result[:success]
        render_success(
          cleared_count: result[:cleared_count],
          message: result[:message]
        )
      else
        render_error(result[:error], status: :unprocessable_content)
      end
    end

    # GET /api/v1/admin_settings/security/blacklist_stats
    def blacklist_statistics
      render_success(security_service.blacklist_statistics)
    end

    # GET /api/v1/admin_settings/security/audit_summary
    def security_audit_summary
      days = params[:days]&.to_i || 30
      render_success(security_service.security_audit_summary(days: days))
    end

    private

    def security_config_params
      params.require(:security_config).permit(
        csrf: [ :enabled, :token_name, :protection_method, :require_ssl ],
        jwt: [ :access_token_ttl, :refresh_token_ttl, :algorithm, :blacklist_enabled, :require_fresh_tokens_for_sensitive_operations ],
        authentication: [ :max_failed_attempts, :lockout_duration, :require_2fa_for_admin, :session_timeout ],
        api_security: [ :rate_limiting_enabled, :cors_enabled, :require_api_key_for_write_operations, allowed_origins: [] ]
      )
    end

    def security_service
      @security_service ||= ::Admin::SecurityConfigService.new(user: current_user)
    end
  end
end
