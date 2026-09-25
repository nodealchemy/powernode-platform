# frozen_string_literal: true

module AdminSettings
  module SecurityConfigActions
    extend ActiveSupport::Concern

    included do
      # Each security-config action requires admin.settings.security. Use a
      # before_action (halts on render) instead of inline require_permission —
      # inline does not halt the action body, so a denied user's mutation
      # (e.g. regenerate_jwt_secret) would run before the 403.
      #
      # security_config/update_security_config/test_security_config (fc-21):
      # deleted along with their only frontend caller, the unrouted
      # admin-dashboard SecuritySettings.tsx — AdminSettingsSecurityTabPage.tsx
      # is the live, routed security tab, and it never called these three.
      before_action -> { require_permission("admin.settings.security") }, only: %i[
        regenerate_jwt_secret clear_blacklisted_tokens
        blacklist_statistics security_audit_summary
      ]
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

    def security_service
      @security_service ||= ::Admin::SecurityConfigService.new(user: current_user)
    end
  end
end
