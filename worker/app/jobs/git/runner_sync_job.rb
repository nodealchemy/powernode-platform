# frozen_string_literal: true

module Git
  class RunnerSyncJob < BaseJob
    sidekiq_options queue: 'services', retry: 3

    # Sync CI/CD runners from Git provider
    # Can sync for specific credential, repository, or all credentials in account
    def execute(options = {})
      credential_id = options[:credential_id] || options["credential_id"]
      repository_id = options[:repository_id] || options["repository_id"]
      account_id = options[:account_id] || options["account_id"]

      log_info "Starting runner sync",
               credential_id: credential_id,
               repository_id: repository_id,
               account_id: account_id

      if credential_id.present?
        sync_credential_runners(credential_id, repository_id)
      elsif account_id.present?
        sync_account_runners(account_id)
      else
        log_error "No credential_id or account_id provided"
        return { error: "credential_id or account_id required" }
      end
    rescue BackendApiClient::ApiError => e
      log_error "API error during runner sync", e
      raise
    end

    private

    def sync_account_runners(account_id)
      log_info "Syncing all runners for account", account_id: account_id

      # Fetch all active credentials for the account
      response = api_client.get("/api/v1/internal/git/credentials", { account_id: account_id })
      credentials = response["data"] || []

      total_synced = 0
      credentials.each do |credential|
        next unless credential["status"] == "active"

        result = sync_credential_runners(credential["id"])
        total_synced += result[:synced_count] || 0
      end

      log_info "Account runner sync completed",
               account_id: account_id,
               total_synced: total_synced

      { success: true, synced_count: total_synced }
    end

    def sync_credential_runners(credential_id, repository_id = nil)
      log_info "Syncing runners for credential",
               credential_id: credential_id,
               repository_id: repository_id

      # Get decrypted credentials
      decrypted_response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      credential = decrypted_response["data"]

      unless credential
        log_error "Credential not found", credential_id: credential_id
        return { error: "Credential not found" }
      end

      client_config = {
        provider_type: credential["provider_type"],
        api_base_url: credential["api_base_url"],
        token: credential["access_token"] || credential["token"]
      }

      synced_count = 0

      if repository_id.present?
        # Sync runners for specific repository
        synced_count = sync_repository_runners(credential_id, repository_id, client_config)
      else
        # Sync all repository runners for this credential
        repos_response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/repositories")
        repositories = repos_response["data"] || []

        repositories.each do |repo|
          synced_count += sync_repository_runners(credential_id, repo["id"], client_config, repo)
        end
      end

      log_info "Credential runner sync completed",
               credential_id: credential_id,
               synced_count: synced_count

      { success: true, synced_count: synced_count }
    end

    def sync_repository_runners(credential_id, repository_id, config, repo_data = nil)
      # Fetch repository data if not provided
      unless repo_data
        response = api_client.get("/api/v1/internal/git/repositories/#{repository_id}")
        repo_data = response["data"]
      end

      return 0 unless repo_data

      owner = repo_data["owner"]
      name = repo_data["name"]

      log_info "Syncing repository runners",
               repository_id: repository_id,
               owner: owner,
               name: name

      # Fetch runners from provider
      runners = fetch_runners_from_provider(owner, name, config)

      return 0 if runners.empty?

      # Normalize and send to backend
      normalized_runners = runners.map { |r| normalize_runner(r, config[:provider_type]) }

      api_client.post("/api/v1/internal/git/runners/sync", {
        credential_id: credential_id,
        repository_id: repository_id,
        runners: normalized_runners
      })

      log_info "Repository runners synced",
               repository_id: repository_id,
               count: runners.count

      runners.count
    rescue StandardError => e
      log_warn "Failed to sync repository runners",
               repository_id: repository_id,
               error: e.message
      0
    end

    def fetch_runners_from_provider(owner, name, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/runners"
             when "gitea"
               "/repos/#{owner}/#{name}/actions/runners"
             else
               # GitHub
               "/repos/#{owner}/#{name}/actions/runners"
             end

      result = make_provider_request(config, "GET", path)

      # GitHub returns { runners: [...] }, Gitea returns array
      if result.is_a?(Hash) && result["runners"]
        result["runners"]
      elsif result.is_a?(Array)
        result
      else
        []
      end
    rescue StandardError => e
      log_error "Failed to fetch runners from provider", e, owner: owner, name: name
      []
    end

    def make_provider_request(config, method, path, params = {})
      require 'faraday'
      require 'json'

      base_url = config[:api_base_url] || default_base_url(config[:provider_type])

      conn = Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end

      case config[:provider_type]
      when "gitlab"
        conn.headers["PRIVATE-TOKEN"] = config[:token]
      else
        conn.headers["Authorization"] = "token #{config[:token]}"
      end
      conn.headers["Accept"] = "application/json"

      response = conn.get(path, params)

      unless response.success?
        raise StandardError, "Provider API error: #{response.status}"
      end

      response.body
    end

    def default_base_url(provider_type)
      case provider_type
      when "github"
        "https://api.github.com"
      when "gitlab"
        "https://gitlab.com/api/v4"
      when "gitea"
        raise ArgumentError, "Gitea requires explicit api_base_url"
      else
        raise ArgumentError, "Unknown provider type: #{provider_type}"
      end
    end

    def normalize_runner(runner, provider_type)
      case provider_type
      when "gitlab"
        normalize_gitlab_runner(runner)
      when "gitea"
        normalize_gitea_runner(runner)
      else
        normalize_github_runner(runner)
      end
    end

    def normalize_github_runner(runner)
      status = if runner["busy"]
                 "busy"
               elsif runner["status"] == "online"
                 "online"
               else
                 "offline"
               end

      {
        external_id: runner["id"].to_s,
        name: runner["name"],
        status: status,
        busy: runner["busy"] || false,
        labels: (runner["labels"] || []).map { |l| l.is_a?(Hash) ? l["name"] : l },
        os: runner["os"],
        architecture: runner["arch"] || runner["architecture"]
      }
    end

    def normalize_gitea_runner(runner)
      status = case runner["status"]
               when "active", "idle"
                 "online"
               when "offline"
                 "offline"
               else
                 runner["busy"] ? "busy" : "offline"
               end

      {
        external_id: runner["id"].to_s,
        name: runner["name"],
        status: status,
        busy: runner["busy"] || false,
        labels: runner["labels"] || [],
        os: runner["os"],
        architecture: runner["arch"] || runner["architecture"],
        version: runner["version"]
      }
    end

    def normalize_gitlab_runner(runner)
      status = case runner["status"]
               when "online", "active"
                 runner["is_shared"] ? "online" : "online"
               when "paused"
                 "offline"
               else
                 "offline"
               end

      {
        external_id: runner["id"].to_s,
        name: runner["description"] || runner["name"] || "Runner ##{runner['id']}",
        status: status,
        busy: runner["active"] == false,
        labels: runner["tag_list"] || [],
        os: runner["platform"],
        architecture: runner["architecture"],
        version: runner["version"]
      }
    end
  end
end
