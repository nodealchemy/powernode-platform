# frozen_string_literal: true

module Mcp
  # Periodic housekeeping for the MCP OAuth surface. Prunes the debris left by
  # normal connect/disconnect churn so it doesn't accumulate unbounded:
  #
  #   * stale/expired MCP SSE sessions (delegates to McpSession.cleanup_expired!),
  #   * revoked Doorkeeper access tokens past a retention window,
  #   * spent/expired Doorkeeper access grants (single-use authorization codes),
  #   * orphaned Dynamic-Client-Registration apps (registered_via mcp_dynamic_registration)
  #     that no longer hold any usable token.
  #
  # SAFETY: this never deletes a token or app that a client could still reconnect
  # with. A non-revoked AccessToken row whose *access* token has expired still
  # carries a valid refresh token (refresh tokens are not expired in our Doorkeeper
  # config), so it is intentionally retained — pruning it would force the very
  # re-authentication this whole change exists to eliminate. Only REVOKED tokens and
  # apps with ZERO non-revoked tokens are removed.
  #
  # Pure server-side logic; invoked from the worker on a schedule via
  # POST /api/v1/internal/mcp/housekeeping. Idempotent.
  class HousekeepingService
    # Expired/revoked MCP sessions older than this are deleted.
    SESSION_RETENTION = 48.hours
    # Revoked tokens / spent grants older than this are deleted.
    TOKEN_RETENTION = 7.days
    # Orphaned DCR client registrations older than this (with no usable token) are deleted.
    DCR_APP_RETENTION = 7.days
    # Tag written by Api::V1::Oauth::RegistrationsController on dynamic registration.
    DCR_REGISTRATION_TAG = "mcp_dynamic_registration"

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(now: Time.current,
                   session_retention: SESSION_RETENTION,
                   token_retention: TOKEN_RETENTION,
                   app_retention: DCR_APP_RETENTION)
      @now = now
      @session_retention = session_retention
      @token_retention = token_retention
      @app_retention = app_retention
    end

    def call
      summary = {
        sessions_deleted: prune_sessions,
        access_tokens_deleted: prune_revoked_tokens,
        access_grants_deleted: prune_dead_grants,
        dcr_apps_deleted: prune_orphaned_dcr_apps
      }
      Rails.logger.info "[Mcp::HousekeepingService] #{summary.to_json}"
      summary
    end

    private

    # Reuse the model's bulk cleanup (also reaps orphaned MCP client agents).
    def prune_sessions
      McpSession.cleanup_expired!(older_than: @session_retention)
    end

    # Only REVOKED tokens — never a non-revoked row (its refresh token may still be live).
    def prune_revoked_tokens
      Doorkeeper::AccessToken
        .where.not(revoked_at: nil)
        .where(revoked_at: ..token_cutoff)
        .delete_all
    end

    # Grants are single-use, short-lived authorization codes; once revoked or past the
    # retention window they are dead. (Expiry is enforced separately at exchange time.)
    def prune_dead_grants
      Doorkeeper::AccessGrant
        .where("revoked_at IS NOT NULL OR created_at < ?", token_cutoff)
        .delete_all
    end

    # DCR registrations with no usable (non-revoked) token, past the retention window.
    # `dependent: :delete_all` on OauthApplication cascades the token/grant rows.
    # Eager-loads access_tokens and filters in memory (no per-app query).
    def prune_orphaned_dcr_apps
      cutoff = @now - @app_retention
      candidates = OauthApplication
        .where("metadata ->> 'registered_via' = ?", DCR_REGISTRATION_TAG)
        .where(created_at: ...cutoff)
        .includes(:access_tokens)

      orphaned = candidates.select do |app|
        tokens = app.access_tokens
        tokens.none? { |t| t.revoked_at.nil? } &&
          (tokens.empty? || tokens.map(&:created_at).max < cutoff)
      end
      orphaned.each(&:destroy!)
      orphaned.size
    end

    def token_cutoff
      @now - @token_retention
    end
  end
end
