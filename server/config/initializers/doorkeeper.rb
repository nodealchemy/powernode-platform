# frozen_string_literal: true

Doorkeeper.configure do
  # API-only mode: no CSRF, no sessions, JSON responses instead of 302 redirects
  api_only

  # Resource owner authenticator for the OAuth authorization endpoint.
  # Supports two flows:
  # 1. Frontend consent page POSTs with JWT in Authorization header
  # 2. Direct browser hit redirects to frontend consent page
  resource_owner_authenticator do
    # Try JWT from Authorization header first (frontend consent approval)
    if request.env["current_user"]
      request.env["current_user"]
    elsif request.headers["Authorization"]&.start_with?("Bearer ")
      token = request.headers["Authorization"].split(" ", 2).last
      begin
        decoded = Security::JwtService.decode(token)
        if decoded
          user = User.find_by(id: decoded["sub"] || decoded["user_id"])
          Rails.logger.warn("[Doorkeeper] JWT valid but user not found: sub=#{decoded['sub']}") unless user
          user
        end
      rescue StandardError => e
        Rails.logger.warn("[Doorkeeper] JWT decode failed: #{e.message}")
        nil
      end
    else
      # Browser-based flow: redirect to frontend consent page with OAuth params
      # Derive the frontend URL from the request origin the client is connected through
      frontend = AdminSetting.frontend_url_for_request(request)

      query = request.query_string.present? ? "?#{request.query_string}" : ""
      redirect_to("#{frontend}/app/oauth/authorize#{query}", allow_other_host: true)
      nil
    end
  end

  # Resource owner from bearer token
  resource_owner_from_credentials do |_routes|
    user = User.find_by(email: params[:username])
    if user&.authenticate(params[:password])
      user
    end
  end

  # Admin authenticator for Doorkeeper admin panel
  admin_authenticator do
    current_user = request.env["current_user"]
    unless current_user&.has_permission?("admin.oauth.manage")
      redirect_to("/unauthorized", allow_other_host: true)
    end
  end

  # ===================================================================
  # OAuth 2.1 Grant Types Configuration
  # ===================================================================

  # Authorization Code Grant + Refresh Token (OAuth 2.1 drops password & implicit)
  grant_flows %w[
    authorization_code
    client_credentials
    refresh_token
  ]

  # PKCE is mandatory for all authorization code grants (OAuth 2.1)
  force_pkce

  # Only allow S256 challenge method (plain is insecure)
  pkce_code_challenge_methods %w[S256]

  # Skip authorization for trusted applications
  skip_authorization do |_resource_owner, client|
    client.application.trusted?
  end

  # Enable refresh tokens
  use_refresh_token

  # ===================================================================
  # Token Configuration
  # ===================================================================

  # Access token expiration (24h in dev for long Claude Code sessions, 2h otherwise)
  access_token_expires_in Rails.env.development? ? 24.hours : 2.hours

  # Refresh token expiration (30 days)
  custom_access_token_expires_in do |context|
    if context.grant_type == Doorkeeper::OAuth::CLIENT_CREDENTIALS
      Rails.env.development? ? 24.hours : 1.hour
    else
      2.hours
    end
  end

  # In Doorkeeper 5.8+, refresh token reuse prevention is handled automatically
  # when using refresh tokens with the default configuration

  # ===================================================================
  # Token Format & Security
  # ===================================================================

  # Use secure random tokens (default generator)
  # access_token_generator "::Doorkeeper::JWT"  # Requires doorkeeper-jwt gem

  # Hash tokens before storing in database
  hash_token_secrets fallback: :plain

  # Hash application secrets
  hash_application_secrets fallback: :plain, using: "::Doorkeeper::SecretStoring::BCrypt"

  # ===================================================================
  # Scopes Configuration
  # ===================================================================

  # Default scope
  default_scopes :read

  # Optional scopes
  optional_scopes :read, :write, :admin, :billing, :users, :webhooks, :workflows, :files

  # Scope descriptions are maintained in the OAuth consent UI (frontend)

  # Enforce configured scopes
  enforce_configured_scopes

  # ===================================================================
  # Application Configuration
  # ===================================================================

  # SSL enforcement for redirect URIs — allow http:// for loopback addresses (RFC 8252 §7.3)
  force_ssl_in_redirect_uri do |uri|
    next false if uri.blank?

    parsed = URI.parse(uri) rescue nil
    next true unless parsed

    loopback_hosts = %w[127.0.0.1 localhost ::1 [::1]]
    if loopback_hosts.include?(parsed.host)
      false # Loopback addresses are exempt from SSL requirement
    else
      !Rails.env.development?
    end
  end

  # Allow wildcard redirect URIs for development
  if Rails.env.development?
    allow_blank_redirect_uri true
  end

  # Client credentials grant is restricted to machine clients only.
  # Lambda syntax avoids Doorkeeper Option DSL &block capture ambiguity.
  # Doorkeeper passes the OauthApplication directly (not a client wrapper).
  allow_grant_flow_for_client ->(grant_flow, application) {
    if grant_flow == "client_credentials"
      application.machine_client?
    else
      true
    end
  }

  # ===================================================================
  # Base Controller
  # ===================================================================

  # base_controller is not needed with api_only — Doorkeeper uses ActionController::API

  # ===================================================================
  # OpenID Connect (optional, for future enhancement)
  # ===================================================================

  # Uncomment to enable OpenID Connect
  # enable_application_owner confirmation: true

  # ===================================================================
  # Custom Access Token Assertion
  # ===================================================================

  # Validate access tokens
  access_token_methods :from_bearer_authorization, :from_access_token_param

  # Custom token claims for JWT
  # Uncomment to use JWT tokens with custom claims
  # access_token_custom_claims do |token|
  #   {
  #     user_id: token.resource_owner_id,
  #     scopes: token.scopes.to_a,
  #     application_id: token.application_id
  #   }
  # end
end

# Configure Doorkeeper JWT if using JWT tokens
if defined?(Doorkeeper::JWT)
  Doorkeeper::JWT.configure do
    # Use the same secret as our main JWT service
    secret_key Rails.application.config.jwt_secret_key

    # Token expiration (in seconds)
    token_payload do |opts|
      user = User.find(opts[:resource_owner_id]) if opts[:resource_owner_id]
      application = Doorkeeper::Application.find(opts[:application_id]) if opts[:application_id]

      {
        iss: Rails.application.class.module_parent_name.downcase,
        iat: Time.current.to_i,
        exp: (Time.current + opts[:expires_in]).to_i,
        jti: SecureRandom.uuid,
        sub: opts[:resource_owner_id],
        scopes: opts[:scopes],
        client_id: application&.uid,
        user: user ? {
          id: user.id,
          email: user.email,
          account_id: user.account_id
        } : nil
      }.compact
    end

    # Use RS256 for production, HS256 for development (env override for containerized dev deployments)
    dk_encryption = (ENV["DOORKEEPER_ENCRYPTION_METHOD"] || (Rails.env.production? ? "rs256" : "hs256")).to_sym
    encryption_method dk_encryption

    # Use separate key pair for RS256
    if dk_encryption == :rs256
      secret_key_path Rails.root.join("config", "keys", "oauth_private.pem")
      public_key_path Rails.root.join("config", "keys", "oauth_public.pem")
    end
  end
end
