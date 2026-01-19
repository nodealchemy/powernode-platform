# frozen_string_literal: true

module Git
  class CredentialSetupJob < BaseJob
    sidekiq_options queue: 'services', retry: 2

    # Initial setup after a Git credential is created
    # Tests connection, fetches user info, and syncs repositories
    def execute(credential_id, options = {})
      log_info "Starting credential setup", credential_id: credential_id

      skip_repo_sync = options["skip_repo_sync"] || options[:skip_repo_sync]

      # Fetch credential from backend
      response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}")
      credential = response["data"]

      unless credential
        log_error "Credential not found", credential_id: credential_id
        return { error: "Credential not found" }
      end

      # Get decrypted credentials
      decrypted_response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      decrypted = decrypted_response["data"]

      provider = credential["provider"] || {}
      client_config = {
        provider_type: provider["provider_type"],
        api_base_url: provider["api_base_url"],
        token: decrypted["access_token"] || decrypted["token"]
      }

      # Step 1: Test connection and fetch user info
      user_info = test_and_fetch_user(client_config)

      unless user_info[:success]
        log_error "Connection test failed", credential_id: credential_id, error: user_info[:error]

        # Update credential with failure
        api_client.patch("/api/v1/internal/git/credentials/#{credential_id}", {
          credential: {
            last_test_at: Time.current.iso8601,
            last_test_status: "failed",
            last_error: user_info[:error]
          }
        })

        return { success: false, error: user_info[:error] }
      end

      # Step 2: Update credential with user info
      api_client.patch("/api/v1/internal/git/credentials/#{credential_id}", {
        credential: {
          external_username: user_info[:username],
          external_user_id: user_info[:user_id],
          external_avatar_url: user_info[:avatar_url],
          scopes: user_info[:scopes] || [],
          last_test_at: Time.current.iso8601,
          last_test_status: "success",
          last_error: nil
        }
      })

      log_info "Credential validated successfully",
               credential_id: credential_id,
               username: user_info[:username]

      # Step 3: Sync repositories (unless skipped)
      unless skip_repo_sync
        log_info "Starting repository sync", credential_id: credential_id

        # Queue repository sync job
        RepositorySyncJob.perform_async(credential_id)
      end

      {
        success: true,
        username: user_info[:username],
        user_id: user_info[:user_id],
        avatar_url: user_info[:avatar_url],
        scopes: user_info[:scopes],
        repo_sync_queued: !skip_repo_sync
      }
    rescue BackendApiClient::ApiError => e
      log_error "API error during credential setup", e, credential_id: credential_id
      raise
    end

    private

    def test_and_fetch_user(config)
      require 'faraday'

      base_url = config[:api_base_url] || default_base_url(config[:provider_type])

      conn = Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end

      # Set auth headers based on provider
      case config[:provider_type]
      when "gitlab"
        conn.headers["PRIVATE-TOKEN"] = config[:token]
      else
        conn.headers["Authorization"] = "token #{config[:token]}"
      end
      conn.headers["Accept"] = "application/json"

      # Fetch current user
      user_path = config[:provider_type] == "gitlab" ? "/user" : "/user"
      response = conn.get(user_path)

      unless response.success?
        error_message = parse_error_message(response)
        return { success: false, error: error_message }
      end

      user = response.body

      # Extract user info based on provider
      case config[:provider_type]
      when "gitlab"
        {
          success: true,
          username: user["username"],
          user_id: user["id"].to_s,
          avatar_url: user["avatar_url"],
          email: user["email"],
          scopes: extract_gitlab_scopes(conn)
        }
      when "gitea"
        {
          success: true,
          username: user["login"] || user["username"],
          user_id: user["id"].to_s,
          avatar_url: user["avatar_url"],
          email: user["email"],
          scopes: []
        }
      else # GitHub
        scopes = extract_github_scopes(response)
        {
          success: true,
          username: user["login"],
          user_id: user["id"].to_s,
          avatar_url: user["avatar_url"],
          email: user["email"],
          scopes: scopes
        }
      end
    rescue Faraday::ConnectionFailed => e
      { success: false, error: "Connection failed: #{e.message}" }
    rescue Faraday::TimeoutError => e
      { success: false, error: "Connection timeout: #{e.message}" }
    rescue StandardError => e
      { success: false, error: "Unexpected error: #{e.message}" }
    end

    def extract_github_scopes(response)
      # GitHub returns scopes in X-OAuth-Scopes header
      scopes_header = response.headers["x-oauth-scopes"]
      return [] unless scopes_header

      scopes_header.split(",").map(&:strip)
    end

    def extract_gitlab_scopes(conn)
      # GitLab doesn't have a direct scope endpoint for PAT
      # Try to infer from accessible endpoints
      scopes = []

      # Test read_api scope
      begin
        response = conn.get("/projects", { per_page: 1 })
        scopes << "read_api" if response.success?
      rescue StandardError
        # Scope not available
      end

      # Test read_user scope
      begin
        response = conn.get("/user")
        scopes << "read_user" if response.success?
      rescue StandardError
        # Scope not available
      end

      scopes
    end

    def parse_error_message(response)
      body = response.body

      if body.is_a?(Hash)
        body["message"] || body["error"] || body["error_description"] || "Unknown error"
      elsif body.is_a?(String)
        body.truncate(200)
      else
        "API error: #{response.status}"
      end
    end

    def default_base_url(provider_type)
      case provider_type
      when "github"
        "https://api.github.com"
      when "gitlab"
        "https://gitlab.com/api/v4"
      else
        raise ArgumentError, "Unknown provider type: #{provider_type}"
      end
    end
  end
end
