# frozen_string_literal: true

module Admin
  # Service for admin security operations
  #
  # Provides:
  # - JWT secret rotation
  # - Token blacklist management
  # - Blacklist statistics
  # - Security audit summary
  #
  # Usage:
  #   service = Admin::SecurityConfigService.new(user: current_user)
  #   summary = service.security_audit_summary(days: 30)
  #
  class SecurityConfigService
    attr_reader :user, :account

    # Grace period for JWT secret rotation (hours)
    JWT_ROTATION_GRACE_PERIOD = 24

    def initialize(user:)
      @user = user
      @account = user.account
    end

    # get_config/update_config/test_config (fc-21): deleted along with the
    # only caller of the controller actions that called them
    # (security_config/update_security_config/test_security_config, deleted
    # from security_config_actions.rb) — the unrouted admin-dashboard
    # SecuritySettings.tsx had zero importers anywhere; the live routed
    # security tab (AdminSettingsSecurityTabPage.tsx) never called these.

    # Rotate the JWT signing key with a grace period for in-flight tokens.
    #
    # Algorithm-aware: RS256 (production) rotates the RSA keypair via
    # Security::JwtKeyStore; HS256 (dev/test) rotates the in-memory HMAC secret.
    # @param reason [String] Reason for regeneration
    # @return [Hash] Result (RS256 NEVER includes key material)
    def regenerate_jwt_secret(reason: nil)
      if Rails.application.config.jwt_algorithm == "RS256"
        regenerate_rs256_keypair(reason: reason)
      else
        regenerate_hmac_secret(reason: reason)
      end
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

    # RS256 rotation: generate + store a fresh RSA keypair via JwtKeyStore (key
    # generation happens IN CODE, never on a CLI). The previous public key is kept
    # for the grace window so in-flight tokens still verify; new tokens sign with
    # the new key once each process's key cache refreshes. Returns metadata only —
    # NO private key material is returned, logged, or rendered.
    def regenerate_rs256_keypair(reason: nil)
      result =
        begin
          Security::JwtKeyStore.rotate!(grace_hours: JWT_ROTATION_GRACE_PERIOD)
        rescue StandardError => e
          # Audit failed key ops too — a partial/failed rotation must not be silent.
          log_critical_security_event("jwt_secret_regenerated", {
            regenerated_by: user.email,
            algorithm: "RS256",
            status: "failed",
            error: e.class.name,
            reason: reason || "Admin-initiated rotation"
          })
          raise
        end

      log_critical_security_event("jwt_secret_regenerated", {
        regenerated_by: user.email,
        algorithm: "RS256",
        status: "success",
        grace_period_hours: JWT_ROTATION_GRACE_PERIOD,
        grace_period_ends_at: result[:grace_ends_at].iso8601,
        reason: reason || "Admin-initiated rotation"
      })

      {
        success: true,
        algorithm: "RS256",
        grace_period_hours: JWT_ROTATION_GRACE_PERIOD,
        grace_period_ends_at: result[:grace_ends_at].iso8601,
        message: "RSA signing keypair rotated. The new key is active across all " \
                 "servers within #{Security::JwtKeyStore::CACHE_TTL}s — no env update or restart required.",
        warning: "Tokens signed with the previous key remain valid until the grace period ends."
      }
    end

    # HS256 rotation of the user-token secret: JwtKeyStore stores a new secret
    # generated in code, keeps the retiring one in its grace keyring, and every
    # process picks the new one up within JwtKeyStore::CACHE_TTL (at once,
    # throttled, on a verification miss). The secret is durable in SecretStore,
    # and none is returned, logged or written to Rails.cache. Server-to-worker
    # job JWTs keep JWT_SECRET_KEY (JwtService.encode_for_worker).
    def regenerate_hmac_secret(reason: nil)
      result =
        begin
          Security::JwtKeyStore.rotate_hmac!(grace_hours: JWT_ROTATION_GRACE_PERIOD)
        rescue StandardError => e
          log_critical_security_event("jwt_secret_regenerated", {
            regenerated_by: user.email,
            algorithm: "HS256",
            status: "failed",
            error: e.class.name,
            reason: reason || "Admin-initiated rotation"
          })
          raise
        end

      log_critical_security_event("jwt_secret_regenerated", {
        regenerated_by: user.email,
        algorithm: "HS256",
        status: "success",
        grace_period_hours: JWT_ROTATION_GRACE_PERIOD,
        grace_period_ends_at: result[:grace_ends_at].iso8601,
        reason: reason || "Admin-initiated rotation"
      })

      {
        success: true,
        algorithm: "HS256",
        grace_period_hours: JWT_ROTATION_GRACE_PERIOD,
        grace_period_ends_at: result[:grace_ends_at].iso8601,
        message: "JWT signing secret rotated for the tokens this server issues (user, impersonation " \
                 "and API tokens). Every server process uses it within " \
                 "#{Security::JwtKeyStore::CACHE_TTL}s; no env update or restart is needed for those.",
        warning: "Tokens signed with the previous secret remain valid until the grace period ends. " \
                 "Server-to-worker job authentication is NOT rotated by this: it uses JWT_SECRET_KEY " \
                 "from the secrets file, which rotates by changing it on the server and the worker " \
                 "and restarting both."
      }
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
