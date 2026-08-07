# frozen_string_literal: true

# MCP OAuth 2.1 authentication for Streamable HTTP endpoints.
# Accepts Doorkeeper OAuth access tokens only (Bearer tokens from the OAuth 2.1 flow).
# Returns HTTP 401 with WWW-Authenticate header on auth failure to trigger
# the MCP client's OAuth discovery and token refresh flow (RFC 9728).
module McpTokenAuthentication
  extend ActiveSupport::Concern

  PROTECTED_RESOURCE_PATH = "/.well-known/oauth-protected-resource"

  # Bound the bcrypt work an attacker can force on the federation arm: after this
  # many failed attempts for an organization within the window, reject fast (no
  # bcrypt) until it expires. Valid callers never fail, so are never throttled.
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
    if federation_auth_throttled?(org)
      render_oauth_unauthorized("Too many federation authentication attempts", error_code: "federation_throttled")
      return true
    end

    partner = ::FederationPartner.for_inbound(organization_id: org, token: extract_bearer_token)
    unless partner
      record_federation_auth_failure(org)
      render_oauth_unauthorized("Invalid federation credentials", error_code: "federation_invalid")
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
    "mcp:fed_auth_fail:#{org}"
  end

  def federation_auth_throttled?(org)
    Rails.cache.read(federation_auth_failure_key(org)).to_i >= FEDERATION_AUTH_FAILURE_LIMIT
  end

  # Atomic increment; seed with a TTL on the first failure (cache stores that do
  # not auto-create on increment return nil).
  def record_federation_auth_failure(org)
    key = federation_auth_failure_key(org)
    if Rails.cache.increment(key).nil?
      Rails.cache.write(key, 1, expires_in: FEDERATION_AUTH_FAILURE_WINDOW)
    end
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

    @current_user = user
    @current_account = user.account
    @current_mcp_principal = ::Mcp::Principal.for_user(user)
    @doorkeeper_token = doorkeeper_token

    # Capture OAuth application on the MCP session if present
    link_mcp_session_to_application(doorkeeper_token)
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
        if revoked&.reactivatable?
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
