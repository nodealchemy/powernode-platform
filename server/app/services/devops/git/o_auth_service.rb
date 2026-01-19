# frozen_string_literal: true

module Devops
  module Git
  # Handles OAuth authentication flows for Git providers
  class OAuthService
    class OAuthError < StandardError; end

    GITHUB_OAUTH_URL = "https://github.com/login/oauth/authorize"
    GITLAB_OAUTH_URL = "https://gitlab.com/oauth/authorize"

    attr_reader :provider, :account

    def initialize(provider, account)
      @provider = provider
      @account = account
    end

    # Generate OAuth authorization URL for the provider
    def authorization_url(redirect_uri: nil, state: nil)
      case provider.provider_type
      when "github"
        github_authorization_url(redirect_uri, state)
      when "gitlab"
        gitlab_authorization_url(redirect_uri, state)
      when "gitea"
        gitea_authorization_url(redirect_uri, state)
      else
        raise OAuthError, "OAuth not supported for provider type: #{provider.provider_type}"
      end
    end

    # Generate a secure state token for OAuth
    def generate_state(user)
      payload = {
        user_id: user.id,
        account_id: account.id,
        provider_id: provider.id,
        timestamp: Time.current.to_i,
        nonce: SecureRandom.hex(16)
      }

      Base64.urlsafe_encode64(payload.to_json)
    end

    # Handle OAuth callback and create credential
    def handle_callback(code:, state:)
      validate_state!(state)
      token_response = exchange_code_for_token(code)

      if token_response[:success]
        credential = create_credential_from_token(token_response)
        { success: true, credential: credential }
      else
        { success: false, error: token_response[:error] }
      end
    rescue OAuthError => e
      { success: false, error: e.message }
    end

    private

    def github_authorization_url(redirect_uri, state)
      oauth_config = provider.oauth_config
      params = {
        client_id: oauth_config["client_id"],
        redirect_uri: redirect_uri || oauth_config["redirect_uri"],
        scope: oauth_config["scopes"]&.join(" ") || "repo user",
        state: state,
        allow_signup: false
      }.compact

      "#{GITHUB_OAUTH_URL}?#{params.to_query}"
    end

    def gitlab_authorization_url(redirect_uri, state)
      oauth_config = provider.oauth_config
      base_url = provider.web_base_url || "https://gitlab.com"

      params = {
        client_id: oauth_config["client_id"],
        redirect_uri: redirect_uri || oauth_config["redirect_uri"],
        response_type: "code",
        scope: oauth_config["scopes"]&.join(" ") || "api read_user",
        state: state
      }.compact

      "#{base_url}/oauth/authorize?#{params.to_query}"
    end

    def gitea_authorization_url(redirect_uri, state)
      oauth_config = provider.oauth_config
      base_url = provider.web_base_url

      raise OAuthError, "Gitea provider requires web_base_url to be configured" if base_url.blank?

      params = {
        client_id: oauth_config["client_id"],
        redirect_uri: redirect_uri || oauth_config["redirect_uri"],
        response_type: "code",
        scope: oauth_config["scopes"]&.join(" ") || "read:user",
        state: state
      }.compact

      "#{base_url}/login/oauth/authorize?#{params.to_query}"
    end

    def validate_state!(state)
      return if state.blank?

      begin
        payload = JSON.parse(Base64.urlsafe_decode64(state))
        timestamp = payload["timestamp"].to_i

        # State expires after 10 minutes
        if Time.current.to_i - timestamp > 600
          raise OAuthError, "OAuth state has expired"
        end

        # Verify provider matches
        if payload["provider_id"] != provider.id
          raise OAuthError, "OAuth state provider mismatch"
        end
      rescue JSON::ParserError, ArgumentError
        raise OAuthError, "Invalid OAuth state"
      end
    end

    def exchange_code_for_token(code)
      case provider.provider_type
      when "github"
        exchange_github_code(code)
      when "gitlab"
        exchange_gitlab_code(code)
      when "gitea"
        exchange_gitea_code(code)
      else
        { success: false, error: "Unsupported provider type" }
      end
    end

    def exchange_github_code(code)
      oauth_config = provider.oauth_config
      uri = URI("https://github.com/login/oauth/access_token")

      response = Net::HTTP.post_form(uri, {
        client_id: oauth_config["client_id"],
        client_secret: oauth_config["client_secret"],
        code: code
      })

      params = CGI.parse(response.body)

      if params["access_token"].present?
        {
          success: true,
          access_token: params["access_token"].first,
          token_type: params["token_type"]&.first || "bearer",
          scope: params["scope"]&.first&.split(",")
        }
      else
        { success: false, error: params["error_description"]&.first || "Failed to exchange code" }
      end
    rescue StandardError => e
      { success: false, error: "OAuth token exchange failed: #{e.message}" }
    end

    def exchange_gitlab_code(code)
      oauth_config = provider.oauth_config
      base_url = provider.web_base_url || "https://gitlab.com"
      uri = URI("#{base_url}/oauth/token")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri)
      request.set_form_data({
        client_id: oauth_config["client_id"],
        client_secret: oauth_config["client_secret"],
        code: code,
        grant_type: "authorization_code",
        redirect_uri: oauth_config["redirect_uri"]
      })

      response = http.request(request)
      data = JSON.parse(response.body)

      if data["access_token"].present?
        {
          success: true,
          access_token: data["access_token"],
          refresh_token: data["refresh_token"],
          token_type: data["token_type"] || "bearer",
          expires_in: data["expires_in"],
          scope: data["scope"]&.split(" ")
        }
      else
        { success: false, error: data["error_description"] || "Failed to exchange code" }
      end
    rescue StandardError => e
      { success: false, error: "OAuth token exchange failed: #{e.message}" }
    end

    def exchange_gitea_code(code)
      oauth_config = provider.oauth_config
      base_url = provider.web_base_url

      raise OAuthError, "Gitea provider requires web_base_url to be configured" if base_url.blank?

      uri = URI("#{base_url}/login/oauth/access_token")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri)
      request.set_form_data({
        client_id: oauth_config["client_id"],
        client_secret: oauth_config["client_secret"],
        code: code,
        grant_type: "authorization_code",
        redirect_uri: oauth_config["redirect_uri"]
      })

      response = http.request(request)
      data = JSON.parse(response.body)

      if data["access_token"].present?
        {
          success: true,
          access_token: data["access_token"],
          refresh_token: data["refresh_token"],
          token_type: data["token_type"] || "bearer",
          expires_in: data["expires_in"]
        }
      else
        { success: false, error: data["error"] || "Failed to exchange code" }
      end
    rescue StandardError => e
      { success: false, error: "OAuth token exchange failed: #{e.message}" }
    end

    def create_credential_from_token(token_response)
      # Fetch user info from provider
      user_info = fetch_user_info(token_response[:access_token])

      credential = Devops::GitProviderCredential.new(
        git_provider_id: provider.id,
        account: account,
        name: "#{provider.name} - #{user_info[:username] || 'OAuth'}",
        auth_type: "oauth",
        external_username: user_info[:username],
        external_user_id: user_info[:id],
        external_avatar_url: user_info[:avatar_url],
        scopes: token_response[:scope] || [],
        is_active: true
      )

      # Set credentials using the setter (handles encryption internally)
      credential.credentials = {
        "access_token" => token_response[:access_token],
        "refresh_token" => token_response[:refresh_token],
        "token_type" => token_response[:token_type],
        "expires_in" => token_response[:expires_in]
      }.compact

      if token_response[:expires_in].present?
        credential.expires_at = Time.current + token_response[:expires_in].to_i.seconds
      end

      credential.save!
      credential
    end

    def fetch_user_info(access_token)
      case provider.provider_type
      when "github"
        fetch_github_user(access_token)
      when "gitlab"
        fetch_gitlab_user(access_token)
      when "gitea"
        fetch_gitea_user(access_token)
      else
        { username: nil, id: nil, avatar_url: nil }
      end
    end

    def fetch_github_user(access_token)
      uri = URI("https://api.github.com/user")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Accept"] = "application/vnd.github.v3+json"

      response = http.request(request)
      data = JSON.parse(response.body)

      {
        username: data["login"],
        id: data["id"].to_s,
        avatar_url: data["avatar_url"]
      }
    rescue StandardError
      { username: nil, id: nil, avatar_url: nil }
    end

    def fetch_gitlab_user(access_token)
      base_url = provider.api_base_url || "https://gitlab.com/api/v4"
      uri = URI("#{base_url}/user")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"

      response = http.request(request)
      data = JSON.parse(response.body)

      {
        username: data["username"],
        id: data["id"].to_s,
        avatar_url: data["avatar_url"]
      }
    rescue StandardError
      { username: nil, id: nil, avatar_url: nil }
    end

    def fetch_gitea_user(access_token)
      base_url = provider.api_base_url
      # api_base_url may or may not include /api/v1, so we use /user endpoint
      # The base URL should be like https://git.example.com/api/v1
      uri = URI("#{base_url}/user")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "token #{access_token}"

      response = http.request(request)
      data = JSON.parse(response.body)

      {
        username: data["login"] || data["username"],
        id: data["id"].to_s,
        avatar_url: data["avatar_url"]
      }
    rescue StandardError
      { username: nil, id: nil, avatar_url: nil }
    end
  end
end

# Backwards compatibility alias
end
