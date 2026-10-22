# frozen_string_literal: true

# MCP OAuth 2.1 authentication for Streamable HTTP endpoints.
# Accepts Doorkeeper OAuth access tokens only (Bearer tokens from the OAuth 2.1 flow).
# Returns HTTP 401 with WWW-Authenticate header on auth failure to trigger
# the MCP client's OAuth discovery and token refresh flow (RFC 9728).
module McpTokenAuthentication
  extend ActiveSupport::Concern

  PROTECTED_RESOURCE_PATH = "/.well-known/oauth-protected-resource"

  # Federation auth-failure lockout: after this many failed attempts from one
  # client IP for one organization within the window, a failure answers
  # federation_throttled instead of federation_invalid. Credentials are checked
  # FIRST, so every attempt still costs a bcrypt and a valid token is never
  # refused; the per-request bcrypt work is bounded by the IP-keyed Rack::Attack
  # throttles, not by this counter.
  FEDERATION_AUTH_FAILURE_LIMIT = 20
  FEDERATION_AUTH_FAILURE_WINDOW = 60 # seconds

  private

  def authenticate_mcp_request
    # mTLS arm (AI/MCP workload substrate L2): an enrolled fleet instance presents
    # its node client cert (Traefik-forwarded). Verify it against OUR CA and resolve
    # the NodeInstance as the MCP principal. Falls through to the OAuth path when a
    # cert is absent or doesn't verify — the existing User/OAuth flow is unchanged.
    return if authenticate_via_node_mtls

    # Federation arm (cross-plane MCP): a peer Powernode deployment presents its
    # shared bearer token + X-Federation-Organization header. Only fires when that
    # header is present (OAuth/mTLS clients never send it), so those paths are
    # unchanged. A federation-signalled request that fails verification is
    # rejected here — it never falls through to the OAuth path.
    return if authenticate_via_federation_partner

    token_string = extract_bearer_token

    unless token_string.present?
      render_oauth_unauthorized("No access token provided", error_code: "missing_token")
      return
    end

    doorkeeper_token = Doorkeeper::AccessToken.by_token(token_string)

    if doorkeeper_token&.accessible?
      authenticate_via_doorkeeper_token(doorkeeper_token)
    else
      render_oauth_unauthorized("Invalid or expired access token", error_code: "token_invalid")
    end
  end

  # mTLS principal arm. Returns true when a verified node client cert resolves to a
  # live NodeInstance (now the MCP principal); false otherwise (caller falls through
  # to OAuth). Fail-closed: no cert, unverifiable cert, or no injected resolver →
  # false. Only fires when a cert is actually presented, so OAuth clients (no cert)
  # are unaffected. Instance principals are sessionless (request/response only).
  def authenticate_via_node_mtls
    return false unless ::Security::MtlsTrust.client_cert_presented?(request)

    cn = ::Security::MtlsTrust.verify_request(request)
    return false if cn.blank?

    principal = ::Mcp::Principal.for_instance_cn(cn)
    return false if principal.nil? || !principal.account&.active?

    @current_mcp_principal = principal
    @current_account = principal.account
    @current_user = nil
    true
  end

  # Federation principal arm. Returns true when the request carries a federation
  # signal (X-Federation-Organization header) — either resolving a verified peer
  # to a default-deny federation principal, or rejecting an invalid one with 401.
  # Returns false only when NO federation header is present, so a non-federation
  # request falls through to the OAuth path untouched. Fail-closed throughout.
  def authenticate_via_federation_partner
    org = request.headers["X-Federation-Organization"]
    return false if org.blank?

    # From here the request is federation-signalled: it succeeds or is rejected,
    # never silently downgraded to OAuth.
    #
    # Credentials FIRST: a partner's token is high-entropy, so a valid one is
    # never refused by the failure counter below. The counter is keyed by the
    # organisation AND the client IP. Keyed by the attacker-chosen org header
    # alone and checked before credentials, it let anyone keep a real partner
    # locked out. The per-request bcrypt it used to bound is left to the
    # IP-keyed Rack::Attack throttles.
    partner = ::FederationPartner.for_inbound(organization_id: org, token: extract_bearer_token)
    unless partner
      failures = record_federation_auth_failure(org)
      if failures.to_i > FEDERATION_AUTH_FAILURE_LIMIT
        render_oauth_unauthorized("Too many federation authentication attempts", error_code: "federation_throttled")
      else
        render_oauth_unauthorized("Invalid federation credentials", error_code: "federation_invalid")
      end
      return true
    end

    unless partner.account&.active?
      render_oauth_unauthorized("Federation account inactive", error_code: "account_inactive")
      return true
    end

    @current_mcp_principal = ::Mcp::Principal.for_federation_partner(partner)
    @current_account = partner.account
    @current_user = nil
    partner.increment_request_count!
    true
  end

  def federation_auth_failure_key(org)
    "mcp:fed_auth_fail:#{Digest::SHA256.hexdigest("#{org}|#{request.remote_ip}")}"
  end

  # Atomic increment that carries the window itself. Rails 8.1 stores create a
  # missing key on increment (returning 1, never nil), so a TTL written only
  # when increment returned nil never ran and the counter had no expiry
  # (IMP-24a25a083497). With expires_in, the first failure starts the window and
  # later increments keep that entry's expiry. Returns the new count (increment
  # returns it on every store, including RedisCacheStore, where a plain #read
  # of the raw counter returns nil).
  def record_federation_auth_failure(org)
    Rails.cache.increment(federation_auth_failure_key(org), 1, expires_in: FEDERATION_AUTH_FAILURE_WINDOW)
  end

  def current_mcp_principal
    @current_mcp_principal
  end

  def authenticate_via_doorkeeper_token(doorkeeper_token)
    user = User.find_by(id: doorkeeper_token.resource_owner_id)

    unless user&.active? && user&.account&.active?
      render_oauth_unauthorized("User or account inactive", error_code: "user_inactive")
      return
    end

    # User#has_permission? directly (not the delegation-aware controller
    # method in Authentication) is correct here: a Doorkeeper access token
    # never carries an account-switch delegation_id, so there is no
    # delegation scope to resolve against.
    if Admin::MaintenanceMode.blocked?(request.remote_ip) { |perm| user.has_permission?(perm) }
      render_mcp_maintenance_response
      return
    end

    @current_user = user
    @current_account = user.account
    @current_mcp_principal = ::Mcp::Principal.for_user(user)
    @doorkeeper_token = doorkeeper_token

    # Capture OAuth application on the MCP session if present
    link_mcp_session_to_application(doorkeeper_token)
  end

  # An MCP-shaped 503 (not ApiResponse's render_error — this concern's own
  # render_oauth_unauthorized doesn't use it either, since MCP clients expect
  # this module's { error, error_code } body shape, not the success/data
  # envelope). See Admin::MaintenanceMode.blocked? for exactly which requests
  # reach this.
  def render_mcp_maintenance_response
    status = Admin::MaintenanceMode.status
    render json: {
      error: status[:message],
      error_code: "maintenance_mode",
      estimated_completion: status[:estimated_completion]
    }, status: :service_unavailable
  end

  def link_mcp_session_to_application(doorkeeper_token)
    return unless doorkeeper_token.application_id.present?

    session = McpSession.active
      .where(user: @current_user, account: @current_account)
      .order(created_at: :desc)
      .first

    # Reconnect recovery: if no active session exists but a recently-revoked one does
    # (e.g., server restart dropped the SSE connection), reactivate it.
    if session.nil?
      session_token = request.headers["Mcp-Session-Id"]
      if session_token.present?
        revoked = McpSession.find_by(session_token: session_token)
        # Only the token holder's OWN session: another principal presenting a
        # borrowed session id must not bring that session back to life.
        if revoked&.reactivatable? && revoked.account_id == @current_account&.id && revoked.user_id == @current_user&.id
          revoked.reactivate!
          session = revoked
        end
      end
    end

    return unless session

    session.update_columns(oauth_application_id: doorkeeper_token.application_id) if session.oauth_application_id.nil?
  end

  def render_oauth_unauthorized(message, error_code: nil)
    resource_url = "#{request.base_url}#{PROTECTED_RESOURCE_PATH}"
    response.set_header(
      "WWW-Authenticate",
      %(Bearer resource_metadata="#{resource_url}")
    )
    body = { error: message, error_code: error_code }

    # Include session hint so the daemon can distinguish "token expired"
    # from "session revoked" and choose the right recovery path.
    session_token = request.headers["Mcp-Session-Id"]
    if session_token.present? && error_code == "token_invalid"
      session = McpSession.find_by(session_token: session_token)
      if session
        body[:session_status] = session.status
        body[:session_reactivatable] = session.reactivatable? if session.revoked?
      else
        body[:session_status] = "not_found"
      end
    end

    render json: body, status: :unauthorized
  end

  def extract_bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.split(" ", 2).last
  end
end
