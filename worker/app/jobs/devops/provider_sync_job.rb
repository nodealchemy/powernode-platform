# frozen_string_literal: true

module Devops
  # Syncs repositories from Git providers
  # Queue: devops_default
  # Retry: 2
  class ProviderSyncJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    # Sync repositories from a provider
    # @param provider_id [String] The provider ID
    # @param options [Hash] Additional options
    def execute(provider_id, options = {})
      log_info "Starting provider sync", provider_id: provider_id

      options = options.deep_symbolize_keys

      # Fetch provider config
      provider = fetch_provider(provider_id)

      # Update sync status
      update_provider(provider_id, sync_status: "syncing", last_sync_started_at: Time.current.iso8601)

      # Initialize provider client
      client = build_provider_client(provider)

      # Sync repositories
      synced_count = 0
      created_count = 0
      updated_count = 0
      error_count = 0

      page = 1
      per_page = 100

      loop do
        repositories = client.list_repositories(page: page, per_page: per_page)
        break if repositories.empty?

        repositories.each do |repo_data|
          result = sync_repository(provider_id, repo_data)
          synced_count += 1
          created_count += 1 if result[:created]
          updated_count += 1 if result[:updated]
        rescue StandardError => e
          log_warn "Failed to sync repository",
                   repository: repo_data["full_name"],
                   exception: e.message
          error_count += 1
        end

        page += 1
      end

      # Update sync status
      update_provider(
        provider_id,
        sync_status: "completed",
        last_sync_at: Time.current.iso8601,
        sync_stats: {
          synced: synced_count,
          created: created_count,
          updated: updated_count,
          errors: error_count
        }
      )

      log_info "Provider sync completed",
               provider_id: provider_id,
               synced: synced_count,
               created: created_count,
               updated: updated_count,
               errors: error_count
    rescue StandardError => e
      log_error "Provider sync failed", e, provider_id: provider_id

      update_provider(
        provider_id,
        sync_status: "failed",
        sync_error: e.message
      )

      raise
    end

    private

    def fetch_provider(provider_id)
      response = api_client.get("/api/v1/internal/devops/providers/#{provider_id}")
      response.dig("data", "provider")
    end

    def update_provider(provider_id, **attributes)
      api_client.patch("/api/v1/internal/devops/providers/#{provider_id}", {
        provider: attributes
      })
    end

    def build_provider_client(provider)
      GitProviderClient.new(
        provider_type: provider["provider_type"],
        base_url: provider["base_url"],
        api_token: provider["api_token"]
      )
    end

    def sync_repository(provider_id, repo_data)
      # Normalize repository data
      normalized = normalize_repository_data(repo_data)

      # Check if repository exists
      existing = find_existing_repository(provider_id, normalized[:external_id])

      if existing
        # Update existing repository
        update_repository(existing["id"], normalized)
        { updated: true, created: false }
      else
        # Create new repository
        create_repository(provider_id, normalized)
        { updated: false, created: true }
      end
    end

    def normalize_repository_data(repo_data)
      # Different providers have different response formats
      {
        external_id: repo_data["id"].to_s,
        name: repo_data["name"],
        full_name: repo_data["full_name"] || repo_data["path_with_namespace"],
        default_branch: repo_data["default_branch"] || "main",
        clone_url: repo_data["clone_url"] || repo_data["http_url_to_repo"],
        web_url: repo_data["html_url"] || repo_data["web_url"],
        settings: {
          private: repo_data["private"],
          description: repo_data["description"],
          language: repo_data["language"],
          archived: repo_data["archived"]
        }
      }
    end

    def find_existing_repository(provider_id, external_id)
      response = api_client.get("/api/v1/internal/devops/repositories", {
        provider_id: provider_id,
        external_id: external_id
      })
      repositories = response.dig("data", "repositories") || []
      repositories.first
    rescue StandardError
      nil
    end

    def create_repository(provider_id, data)
      api_client.post("/api/v1/internal/devops/repositories", {
        repository: data.merge(
          provider_id: provider_id,
          is_active: true,
          last_synced_at: Time.current.iso8601
        )
      })
    end

    def update_repository(repository_id, data)
      api_client.patch("/api/v1/internal/devops/repositories/#{repository_id}", {
        repository: data.merge(last_synced_at: Time.current.iso8601)
      })
    end
  end

  # Client for interacting with Git providers (worker-side)
  class GitProviderClient
    attr_reader :provider_type, :base_url, :api_token

    def initialize(provider_type:, base_url:, api_token:)
      @provider_type = provider_type
      @base_url = base_url&.chomp("/")
      @api_token = api_token
    end

    def list_repositories(page: 1, per_page: 100)
      case provider_type
      when "gitea"
        get("#{base_url}/api/v1/user/repos", page: page, limit: per_page)
      when "github"
        get("https://api.github.com/user/repos", page: page, per_page: per_page)
      when "gitlab"
        get("#{base_url}/api/v4/projects", page: page, per_page: per_page, membership: true)
      else
        []
      end
    end

    def create_issue(repository:, title:, body:, labels: [])
      case provider_type
      when "gitea"
        owner, repo = repository.split("/")
        post("#{base_url}/api/v1/repos/#{owner}/#{repo}/issues",
             title: title, body: body, labels: labels)
      when "github"
        post("https://api.github.com/repos/#{repository}/issues",
             title: title, body: body, labels: labels)
      when "gitlab"
        encoded = CGI.escape(repository)
        post("#{base_url}/api/v4/projects/#{encoded}/issues",
             title: title, description: body, labels: labels.join(","))
      end
    end

    private

    def get(url, params = {})
      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = auth_header
      request["Accept"] = "application/json"

      execute_request(uri, request)
    end

    def post(url, data)
      uri = URI(url)

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = auth_header
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = data.to_json

      execute_request(uri, request)
    end

    def auth_header
      case provider_type
      when "gitlab"
        "Bearer #{api_token}"
      else
        "token #{api_token}"
      end
    end

    def execute_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(request)

      case response.code.to_i
      when 200, 201
        JSON.parse(response.body)
      else
        raise "API error: #{response.code} - #{response.body}"
      end
    end
  end
end
