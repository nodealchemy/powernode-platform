# frozen_string_literal: true

# Service for handling OAuth 2.1 authentication flow for MCP servers
# Implements PKCE (S256) for enhanced security per OAuth 2.1 spec
class McpOauthService
  PKCE_CODE_VERIFIER_LENGTH = 64
  STATE_LENGTH = 32
  DEFAULT_TIMEOUT = 30

  class OAuthError < StandardError; end
  class TokenRefreshError < OAuthError; end
  class AuthorizationError < OAuthError; end
  class ConfigurationError < OAuthError; end

  def initialize(mcp_server)
    @server = mcp_server
    @logger = Rails.logger
  end

  # Generate PKCE code verifier and challenge (S256)
  def generate_pkce_challenge
    code_verifier = SecureRandom.urlsafe_base64(PKCE_CODE_VERIFIER_LENGTH)
    code_challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier),
      padding: false
    )
    { code_verifier: code_verifier, code_challenge: code_challenge }
  end

  # Generate authorization URL for OAuth flow
  def generate_authorization_url(redirect_uri:)
    validate_oauth_configuration!

    state = SecureRandom.urlsafe_base64(STATE_LENGTH)
    pkce = generate_pkce_challenge

    # Store state and PKCE verifier for callback validation
    @server.update!(
      oauth_state: state,
      oauth_pkce_code_verifier: pkce[:code_verifier],
      oauth_error: nil
    )

    params = {
      response_type: 'code',
      client_id: @server.oauth_client_id,
      redirect_uri: redirect_uri,
      scope: @server.oauth_scopes,
      state: state,
      code_challenge: pkce[:code_challenge],
      code_challenge_method: 'S256'
    }.compact

    uri = URI.parse(@server.oauth_authorization_url)
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  # Exchange authorization code for tokens
  def exchange_code_for_tokens(code:, redirect_uri:, state:)
    # Validate state parameter (CSRF protection)
    unless ActiveSupport::SecurityUtils.secure_compare(state.to_s, @server.oauth_state.to_s)
      raise AuthorizationError, 'Invalid state parameter - possible CSRF attack'
    end

    params = {
      grant_type: 'authorization_code',
      code: code,
      redirect_uri: redirect_uri,
      client_id: @server.oauth_client_id,
      code_verifier: @server.oauth_pkce_code_verifier
    }

    # Include client_secret if configured (some OAuth servers require it)
    client_secret = @server.oauth_client_secret
    params[:client_secret] = client_secret if client_secret.present?

    response = make_token_request(params)
    store_tokens(response)

    @logger.info "[McpOauthService] OAuth tokens obtained for MCP server #{@server.name} (#{@server.id})"
    response
  rescue StandardError => e
    @server.update!(oauth_error: e.message)
    raise OAuthError, "Token exchange failed: #{e.message}"
  end

  # Refresh access token using refresh token
  def refresh_token!
    refresh_token = @server.oauth_refresh_token
    raise TokenRefreshError, 'No refresh token available' if refresh_token.blank?

    params = {
      grant_type: 'refresh_token',
      refresh_token: refresh_token,
      client_id: @server.oauth_client_id
    }

    client_secret = @server.oauth_client_secret
    params[:client_secret] = client_secret if client_secret.present?

    response = make_token_request(params)
    store_tokens(response)

    @logger.info "[McpOauthService] Refreshed OAuth token for MCP server #{@server.name} (#{@server.id})"
    response
  rescue StandardError => e
    @server.update!(oauth_error: "Token refresh failed: #{e.message}")
    raise TokenRefreshError, "Token refresh failed: #{e.message}"
  end

  # Get valid access token (auto-refresh if needed)
  def get_valid_access_token
    return @server.oauth_access_token unless @server.oauth_token_expiring_soon?

    if @server.oauth_refresh_token.present?
      refresh_token!
      @server.reload.oauth_access_token
    else
      raise TokenRefreshError, 'Token expired and no refresh token available'
    end
  end

  # Check if OAuth tokens are valid
  def tokens_valid?
    @server.oauth_connected?
  end

  # Revoke OAuth tokens
  def revoke_tokens!
    @server.clear_oauth_tokens!
    @logger.info "[McpOauthService] Revoked OAuth tokens for MCP server #{@server.name}"
  end

  private

  def validate_oauth_configuration!
    raise ConfigurationError, 'OAuth client ID is required' if @server.oauth_client_id.blank?
    raise ConfigurationError, 'OAuth authorization URL is required' if @server.oauth_authorization_url.blank?
    raise ConfigurationError, 'OAuth token URL is required' if @server.oauth_token_url.blank?
  end

  def make_token_request(params)
    uri = URI.parse(@server.oauth_token_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = DEFAULT_TIMEOUT
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.path.presence || '/')
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request['Accept'] = 'application/json'
    request.body = URI.encode_www_form(params)

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      error_body = JSON.parse(response.body) rescue {}
      error_message = error_body['error_description'] || error_body['error'] || response.body.truncate(500)
      raise OAuthError, "OAuth request failed (#{response.code}): #{error_message}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise OAuthError, "Invalid OAuth response: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise OAuthError, "OAuth request timed out: #{e.message}"
  rescue SocketError, Errno::ECONNREFUSED => e
    raise OAuthError, "Cannot connect to OAuth server: #{e.message}"
  end

  def store_tokens(token_response)
    expires_at = if token_response['expires_in']
                   Time.current + token_response['expires_in'].to_i.seconds
                 end

    @server.update!(
      oauth_access_token: token_response['access_token'],
      oauth_refresh_token: token_response['refresh_token'] || @server.oauth_refresh_token,
      oauth_token_expires_at: expires_at,
      oauth_token_type: token_response['token_type'] || 'Bearer',
      oauth_last_refreshed_at: Time.current,
      oauth_state: nil,
      oauth_pkce_code_verifier: nil,
      oauth_error: nil
    )
  end
end
