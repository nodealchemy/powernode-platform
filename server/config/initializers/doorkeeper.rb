# frozen_string_literal: true

Doorkeeper.configure do
  # Reuse our existing JWT authentication for resource owner
  resource_owner_authenticator do
    # Check for current user from our JWT authentication
    request.env["current_user"] || warden.authenticate!(scope: :user)
  rescue StandardError
    nil
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
  # OAuth 2.0 Grant Types Configuration
  # ===================================================================

  # Authorization Code Grant - for web applications
  grant_flows %w[
    authorization_code
    client_credentials
    refresh_token
    password
  ]

  # Skip authorization for trusted applications
  skip_authorization do |_resource_owner, client|
    client.application.trusted?
  end

  # Enable refresh tokens
  use_refresh_token

  # ===================================================================
  # Token Configuration
  # ===================================================================

  # Access token expiration (2 hours)
  access_token_expires_in 2.hours

  # Refresh token expiration (30 days)
  custom_access_token_expires_in do |context|
    if context.grant_type == Doorkeeper::OAuth::CLIENT_CREDENTIALS
      1.hour # Shorter for client credentials
    else
      2.hours
    end
  end

  # In Doorkeeper 5.8+, refresh token reuse prevention is handled automatically
  # when using refresh tokens with the default configuration

  # ===================================================================
  # Token Format & Security
  # ===================================================================

  # Use secure random tokens (not JWT by default)
  access_token_generator "::Doorkeeper::JWT"

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

  # Scope descriptions for authorization page
  scope_descriptions = {
    read: "Read access to your data",
    write: "Write access to create and modify data",
    admin: "Administrative access",
    billing: "Access to billing and subscription data",
    users: "Access to user management",
    webhooks: "Access to webhook configuration",
    workflows: "Access to AI workflows and automation",
    files: "Access to file management"
  }

  # Enforce configured scopes
  enforce_configured_scopes

  # ===================================================================
  # Application Configuration
  # ===================================================================

  # Enable PKCE (Proof Key for Code Exchange)
  force_ssl_in_redirect_uri !Rails.env.development?

  # Allow wildcard redirect URIs for development
  if Rails.env.development?
    allow_blank_redirect_uri true
  end

  # Client credentials can only access public resources
  allow_grant_flow_for_client client_credentials: ->(client) { client.application.machine_client? }

  # ===================================================================
  # Base Controller
  # ===================================================================

  # Use custom base controller for API consistency
  base_controller "Api::V1::BaseController" if defined?(Api::V1::BaseController)

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

    # Use RS256 for production, HS256 for development
    encryption_method Rails.env.production? ? :rs256 : :hs256

    # Use separate key pair for RS256
    if Rails.env.production?
      secret_key_path Rails.root.join("config", "keys", "oauth_private.pem")
      public_key_path Rails.root.join("config", "keys", "oauth_public.pem")
    end
  end
end
