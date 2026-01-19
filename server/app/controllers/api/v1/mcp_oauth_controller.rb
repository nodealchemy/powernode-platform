# frozen_string_literal: true

class Api::V1::McpOauthController < ApplicationController
  include AuditLogging

  before_action :authenticate_request
  before_action :require_write_permission
  before_action :set_mcp_server, only: [ :authorize, :status, :disconnect, :refresh ]

  # POST /api/v1/mcp_servers/:id/oauth/authorize
  # Initiates the OAuth 2.1 authorization flow
  def authorize
    unless @mcp_server.auth_type == "oauth2"
      return render_error("Server is not configured for OAuth authentication", status: :unprocessable_content)
    end

    redirect_uri = params[:redirect_uri] || default_redirect_uri
    oauth_service = Mcp::OauthService.new(@mcp_server)

    begin
      authorization_url = oauth_service.generate_authorization_url(redirect_uri: redirect_uri)

      render_success({
        authorization_url: authorization_url,
        state: @mcp_server.oauth_state,
        message: "OAuth authorization URL generated"
      })

      log_audit_event("mcp.oauth.authorize_initiated", @mcp_server)
    rescue Mcp::OauthService::ConfigurationError => e
      Rails.logger.error "OAuth configuration error for MCP server #{@mcp_server.id}: #{e.message}"
      render_error("OAuth configuration error: #{e.message}", status: :unprocessable_content)
    rescue StandardError => e
      Rails.logger.error "Failed to generate OAuth authorization URL: #{e.message}"
      render_error("Failed to initiate OAuth: #{e.message}", status: :internal_server_error)
    end
  end

  # GET /api/v1/mcp/oauth/callback
  # Handles the OAuth callback from the authorization server
  def callback
    state = params[:state]
    code = params[:code]
    error = params[:error]
    error_description = params[:error_description]

    # Handle OAuth errors from the provider
    if error.present?
      Rails.logger.error "OAuth error from provider: #{error} - #{error_description}"
      return render_error("OAuth authorization failed: #{error_description || error}", status: :unprocessable_content)
    end

    unless code.present? && state.present?
      return render_error("Missing required OAuth parameters (code and state)", status: :bad_request)
    end

    # Find the MCP server by state (CSRF protection)
    mcp_server = find_server_by_state(state)
    unless mcp_server
      Rails.logger.warn "OAuth callback with invalid state: #{state}"
      return render_error("Invalid or expired OAuth state", status: :bad_request)
    end

    oauth_service = Mcp::OauthService.new(mcp_server)
    redirect_uri = params[:redirect_uri] || default_redirect_uri

    begin
      token_response = oauth_service.exchange_code_for_tokens(
        code: code,
        redirect_uri: redirect_uri,
        state: state
      )

      render_success({
        mcp_server_id: mcp_server.id,
        mcp_server_name: mcp_server.name,
        oauth_connected: mcp_server.reload.oauth_connected?,
        token_expires_at: mcp_server.oauth_token_expires_at,
        message: "OAuth authentication successful"
      })

      log_audit_event("mcp.oauth.callback_success", mcp_server)
    rescue Mcp::OauthService::AuthorizationError => e
      Rails.logger.error "OAuth authorization error for MCP server #{mcp_server.id}: #{e.message}"
      render_error("OAuth authorization failed: #{e.message}", status: :unprocessable_content)
    rescue Mcp::OauthService::OAuthError => e
      Rails.logger.error "OAuth token exchange error for MCP server #{mcp_server.id}: #{e.message}"
      render_error("OAuth token exchange failed: #{e.message}", status: :unprocessable_content)
    rescue StandardError => e
      Rails.logger.error "OAuth callback error: #{e.message}"
      render_error("OAuth callback failed: #{e.message}", status: :internal_server_error)
    end
  end

  # GET /api/v1/mcp_servers/:id/oauth/status
  # Returns the current OAuth status for the MCP server
  def status
    render_success({
      mcp_server_id: @mcp_server.id,
      mcp_server_name: @mcp_server.name,
      oauth_status: @mcp_server.oauth_status
    })

    log_audit_event("mcp.oauth.status_read", @mcp_server)
  rescue StandardError => e
    Rails.logger.error "Failed to get OAuth status: #{e.message}"
    render_error("Failed to get OAuth status: #{e.message}", status: :internal_server_error)
  end

  # DELETE /api/v1/mcp_servers/:id/oauth/disconnect
  # Revokes OAuth tokens and disconnects
  def disconnect
    unless @mcp_server.oauth_configured?
      return render_error("Server does not have OAuth configured", status: :unprocessable_content)
    end

    oauth_service = Mcp::OauthService.new(@mcp_server)

    begin
      oauth_service.revoke_tokens!

      render_success({
        mcp_server_id: @mcp_server.id,
        oauth_connected: false,
        message: "OAuth disconnected successfully"
      })

      log_audit_event("mcp.oauth.disconnect", @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Failed to disconnect OAuth: #{e.message}"
      render_error("Failed to disconnect OAuth: #{e.message}", status: :internal_server_error)
    end
  end

  # POST /api/v1/mcp_servers/:id/oauth/refresh
  # Manually refreshes the OAuth access token
  def refresh
    unless @mcp_server.oauth_configured?
      return render_error("Server does not have OAuth configured", status: :unprocessable_content)
    end

    unless @mcp_server.oauth_refresh_token.present?
      return render_error("No refresh token available", status: :unprocessable_content)
    end

    oauth_service = Mcp::OauthService.new(@mcp_server)

    begin
      oauth_service.refresh_token!

      render_success({
        mcp_server_id: @mcp_server.id,
        oauth_connected: @mcp_server.reload.oauth_connected?,
        token_expires_at: @mcp_server.oauth_token_expires_at,
        message: "OAuth token refreshed successfully"
      })

      log_audit_event("mcp.oauth.token_refreshed", @mcp_server)
    rescue Mcp::OauthService::TokenRefreshError => e
      Rails.logger.error "OAuth token refresh failed for MCP server #{@mcp_server.id}: #{e.message}"
      render_error("Token refresh failed: #{e.message}", status: :unprocessable_content)
    rescue StandardError => e
      Rails.logger.error "Failed to refresh OAuth token: #{e.message}"
      render_error("Failed to refresh token: #{e.message}", status: :internal_server_error)
    end
  end

  private

  def set_mcp_server
    @mcp_server = current_user.account.mcp_servers.find(params[:id] || params[:mcp_server_id])
  rescue ActiveRecord::RecordNotFound
    render_error("MCP server not found", status: :not_found)
  end

  def require_write_permission
    unless current_user.has_permission?("mcp.servers.write")
      render_error("Insufficient permissions to manage MCP server OAuth", status: :forbidden)
    end
  end

  def find_server_by_state(state)
    McpServer.where(account: current_user.account)
             .where.not(oauth_state: nil)
             .find_by(oauth_state: state)
  end

  def default_redirect_uri
    # Generate default redirect URI based on the request
    "#{request.protocol}#{request.host_with_port}/oauth/mcp/callback"
  end
end
