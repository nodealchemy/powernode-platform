# frozen_string_literal: true

module Git
  class RepositorySyncJob < BaseJob
    sidekiq_options queue: 'services', retry: 3

    # Sync Git repositories from provider API
    # Can sync all repositories for a credential, or specific data for one repository
    def execute(credential_id, repository_id = nil, sync_type = nil)
      log_info "Starting Git repository sync",
               credential_id: credential_id,
               repository_id: repository_id,
               sync_type: sync_type

      # Fetch credential from backend
      response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}")
      credential = response["data"]

      unless credential
        log_error "Credential not found", credential_id: credential_id
        return { error: "Credential not found" }
      end

      # Get decrypted credentials for API access
      decrypted_response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      decrypted = decrypted_response["data"]

      # Build API client configuration
      client_config = build_client_config(credential, decrypted)

      if repository_id
        # Sync specific repository
        sync_repository(credential_id, repository_id, sync_type, client_config)
      else
        # Sync all repositories for credential
        sync_all_repositories(credential_id, client_config)
      end
    rescue BackendApiClient::ApiError => e
      log_error "API error during repository sync", e,
                credential_id: credential_id,
                repository_id: repository_id
      raise
    end

    private

    def build_client_config(credential, decrypted)
      # Credentials are nested inside "credentials" key from decrypted response
      creds = decrypted["credentials"] || {}
      token = creds["access_token"] || creds["token"] || decrypted["access_token"] || decrypted["token"]
      api_url = credential.dig("provider", "api_base_url") || decrypted.dig("provider", "api_base_url")

      log_info "Building client config",
               provider_type: credential.dig("provider", "provider_type"),
               api_base_url: api_url,
               has_token: token.present?,
               token_length: token&.length

      {
        provider_type: credential.dig("provider", "provider_type"),
        api_base_url: api_url,
        token: token,
        auth_type: credential["auth_type"]
      }
    end

    def sync_all_repositories(credential_id, client_config)
      log_info "Syncing all repositories for credential", credential_id: credential_id

      # Fetch repositories from Git provider
      repositories = fetch_repositories_from_provider(client_config)

      log_info "Fetched repositories from provider",
               count: repositories.count,
               credential_id: credential_id

      synced_count = 0
      error_count = 0

      repositories.each do |repo_data|
        begin
          # Upsert repository in backend
          api_client.post("/api/v1/internal/git/repositories", {
            credential_id: credential_id,
            repository: normalize_repository(repo_data)
          })
          synced_count += 1
        rescue BackendApiClient::ApiError => e
          log_error "Failed to sync repository", e,
                    repository: repo_data["full_name"]
          error_count += 1
        end
      end

      log_info "Repository sync completed",
               credential_id: credential_id,
               synced_count: synced_count,
               error_count: error_count

      {
        success: true,
        synced_count: synced_count,
        error_count: error_count,
        total_count: repositories.count
      }
    end

    def sync_repository(credential_id, repository_id, sync_type, client_config)
      # Fetch repository details from backend
      response = api_client.get("/api/v1/internal/git/repositories/#{repository_id}")
      repository = response["data"]

      unless repository
        log_error "Repository not found", repository_id: repository_id
        return { error: "Repository not found" }
      end

      owner = repository["owner"]
      name = repository["name"]

      case sync_type
      when "branches"
        sync_branches(repository_id, owner, name, client_config)
      when "commits"
        sync_commits(repository_id, owner, name, repository["default_branch"], client_config)
      when "pipelines"
        sync_pipelines(repository_id, owner, name, client_config)
      when "metadata"
        sync_metadata(repository_id, owner, name, client_config)
      else
        # Full sync
        sync_metadata(repository_id, owner, name, client_config)
        sync_branches(repository_id, owner, name, client_config)
        {
          success: true,
          sync_type: "full",
          repository_id: repository_id
        }
      end
    end

    def sync_branches(repository_id, owner, name, client_config)
      log_info "Syncing branches", repository_id: repository_id

      branches = fetch_branches_from_provider(owner, name, client_config)

      api_client.post("/api/v1/internal/git/repositories/#{repository_id}/sync_branches", {
        branches: branches
      })

      {
        success: true,
        sync_type: "branches",
        count: branches.count
      }
    end

    def sync_commits(repository_id, owner, name, branch, client_config)
      log_info "Syncing commits", repository_id: repository_id, branch: branch

      commits = fetch_commits_from_provider(owner, name, branch, client_config)

      api_client.post("/api/v1/internal/git/repositories/#{repository_id}/sync_commits", {
        commits: commits,
        branch: branch
      })

      {
        success: true,
        sync_type: "commits",
        count: commits.count
      }
    end

    def sync_pipelines(repository_id, owner, name, client_config)
      log_info "Syncing pipelines", repository_id: repository_id

      pipelines = fetch_pipelines_from_provider(owner, name, client_config)

      api_client.post("/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines", {
        pipelines: pipelines
      })

      {
        success: true,
        sync_type: "pipelines",
        count: pipelines.count
      }
    end

    def sync_metadata(repository_id, owner, name, client_config)
      log_info "Syncing repository metadata", repository_id: repository_id

      repo_data = fetch_repository_from_provider(owner, name, client_config)

      api_client.patch("/api/v1/internal/git/repositories/#{repository_id}", {
        repository: normalize_repository(repo_data)
      })

      {
        success: true,
        sync_type: "metadata"
      }
    end

    # Provider API calls using HTTP client
    def fetch_repositories_from_provider(config)
      make_provider_request(config, "GET", "/user/repos", { per_page: 100 })
    end

    def fetch_repository_from_provider(owner, name, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}"
             else
               "/repos/#{owner}/#{name}"
             end
      make_provider_request(config, "GET", path)
    end

    def fetch_branches_from_provider(owner, name, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/repository/branches"
             else
               "/repos/#{owner}/#{name}/branches"
             end
      make_provider_request(config, "GET", path, { per_page: 100 })
    end

    def fetch_commits_from_provider(owner, name, branch, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/repository/commits"
             else
               "/repos/#{owner}/#{name}/commits"
             end
      make_provider_request(config, "GET", path, { sha: branch, per_page: 30 })
    end

    def fetch_pipelines_from_provider(owner, name, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/pipelines"
             when "gitea"
               "/repos/#{owner}/#{name}/actions/runs"
             else
               "/repos/#{owner}/#{name}/actions/runs"
             end

      result = make_provider_request(config, "GET", path, { per_page: 30 })

      # GitHub/Gitea return { workflow_runs: [...] }
      result.is_a?(Hash) && result["workflow_runs"] ? result["workflow_runs"] : result
    end

    def make_provider_request(config, method, path, params = {})
      require 'faraday'
      require 'json'

      base_url = config[:api_base_url] || default_base_url(config[:provider_type])

      # IMPORTANT: Remove leading slash from path to make it relative
      # When using Faraday with a base URL that includes a path (like /api/v1),
      # absolute paths (starting with /) replace the entire path instead of appending
      relative_path = path.sub(%r{^/}, '')

      log_info "Making provider request",
               base_url: base_url,
               path: relative_path,
               method: method,
               has_token: config[:token].present?

      conn = Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end

      # Set auth header based on provider
      case config[:provider_type]
      when "gitlab"
        conn.headers["PRIVATE-TOKEN"] = config[:token]
      else
        conn.headers["Authorization"] = "token #{config[:token]}"
      end
      conn.headers["Accept"] = "application/json"

      response = case method.upcase
                 when "GET"
                   conn.get(relative_path, params)
                 when "POST"
                   conn.post(relative_path, params)
                 else
                   raise ArgumentError, "Unsupported method: #{method}"
                 end

      unless response.success?
        raise StandardError, "Provider API error: #{response.status} - #{response.body}"
      end

      response.body
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

    def normalize_repository(repo)
      {
        external_id: repo["id"].to_s,
        name: repo["name"],
        full_name: repo["full_name"] || repo["path_with_namespace"],
        owner: repo.dig("owner", "login") || repo.dig("namespace", "path"),
        description: repo["description"],
        default_branch: repo["default_branch"],
        clone_url: repo["clone_url"] || repo["http_url_to_repo"],
        ssh_url: repo["ssh_url"] || repo["ssh_url_to_repo"],
        web_url: repo["html_url"] || repo["web_url"],
        is_private: repo["private"] || repo["visibility"] == "private",
        is_fork: repo["fork"] || repo["forked_from_project"].present?,
        is_archived: repo["archived"],
        stars_count: repo["stargazers_count"] || repo["star_count"] || 0,
        forks_count: repo["forks_count"] || repo["forks_count"] || 0,
        open_issues_count: repo["open_issues_count"] || 0,
        primary_language: repo["language"],
        topics: repo["topics"] || repo["tag_list"] || [],
        last_synced_at: Time.current.iso8601
      }
    end
  end
end
