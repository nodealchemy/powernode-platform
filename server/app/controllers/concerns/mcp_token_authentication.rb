# frozen_string_literal: true

# MCP OAuth 2.1 authentication for Streamable HTTP endpoints.
# Accepts Doorkeeper OAuth access tokens only (Bearer tokens from the OAuth 2.1 flow).
# Returns HTTP 401 with WWW-Authenticate header on auth failure to trigger
# the MCP client's OAuth discovery and token refresh flow (RFC 9728).
module McpTokenAuthentication
  extend ActiveSupport::Concern

  PROTECTED_RESOURCE_PATH = "/.well-known/oauth-protected-resource"

  private

  def authenticate_mcp_request
    token_string = extract_bearer_token

    unless token_string.present?
      render_oauth_unauthorized("No access token provided")
      return
    end

    doorkeeper_token = Doorkeeper::AccessToken.by_token(token_string)

    if doorkeeper_token&.accessible?
      authenticate_via_doorkeeper_token(doorkeeper_token)
    else
      render_oauth_unauthorized("Invalid or expired access token")
    end
  end

  def authenticate_via_doorkeeper_token(doorkeeper_token)
    user = User.find_by(id: doorkeeper_token.resource_owner_id)

    unless user&.active? && user&.account&.active?
      render_oauth_unauthorized("User or account inactive")
      return
    end

    @current_user = user
    @current_account = user.account
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

  def render_oauth_unauthorized(message)
    resource_url = "#{request.base_url}#{PROTECTED_RESOURCE_PATH}"
    response.set_header(
      "WWW-Authenticate",
      %(Bearer resource_metadata="#{resource_url}")
    )
    render json: { error: message }, status: :unauthorized
  end

  def extract_bearer_token
    header = request.headers["Authorization"]
    return nil unless header&.start_with?("Bearer ")

    header.split(" ", 2).last
  end
end
