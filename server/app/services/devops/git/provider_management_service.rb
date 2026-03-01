# frozen_string_literal: true

module Devops
  module Git
  class ProviderManagementService
    class ValidationError < StandardError; end
    class CredentialError < StandardError; end
    class ProviderError < StandardError; end

    class << self
      # Create a new credential for a provider
      def create_credential(provider, account, user, params)
        validate_credential_params(provider, params)

        credential = account.git_provider_credentials.build(
          git_provider_id: provider.id,
          user: user,
          name: params[:name] || generate_credential_name(provider, params[:auth_type]),
          auth_type: params[:auth_type],
          is_active: params[:is_active] != false,
          is_default: params[:is_default] == true,
          expires_at: params[:expires_at]
        )

        # Encrypt and set credentials
        credential.credentials = normalize_credentials(params[:credentials])

        if credential.save
          # Test the credential
          test_and_update_credential(credential)
        end

        credential
      end

      # Update an existing credential
      def update_credential(credential, params)
        if params[:credentials].present?
          credential.credentials = normalize_credentials(params[:credentials])
        end

        credential.assign_attributes(params.except(:credentials))

        if credential.save && params[:credentials].present?
          test_and_update_credential(credential)
        end

        credential
      end

      # List available repositories from provider without importing
      # Returns raw repository data for user to select from
      def list_available_repositories(credential, options = {})
        raise CredentialError, "Credential cannot be used" unless credential.can_be_used?

        client = Devops::Git::ApiClient.for(credential)
        page = options[:page] || 1
        per_page = options[:per_page] || 100
        search = options[:search]

        repos_data = client.list_repositories(
          page: page,
          per_page: per_page
        )

        # Filter by search if provided
        if search.present?
          search_lower = search.downcase
          repos_data = repos_data.select do |repo|
            (repo["name"]&.downcase&.include?(search_lower) ||
             repo["full_name"]&.downcase&.include?(search_lower) ||
             repo["description"]&.downcase&.include?(search_lower))
          end
        end

        # Filter archived/forks if not explicitly included
        unless options[:include_archived]
          repos_data = repos_data.reject { |r| r["archived"] }
        end
        unless options[:include_forks]
          repos_data = repos_data.reject { |r| r["fork"] }
        end

        # Get already imported external_ids for this account
        account = credential.account
        imported_ids = account.git_repositories
                        .where(credential: credential)
                        .pluck(:external_id)
                        .map(&:to_s)

        # Map to simplified format with import status
        repositories = repos_data.map do |repo|
          {
            external_id: repo["id"].to_s,
            name: repo["name"],
            full_name: repo["full_name"],
            owner: extract_owner(repo),
            description: repo["description"],
            default_branch: repo["default_branch"] || "main",
            web_url: repo["html_url"] || repo["web_url"],
            is_private: repo["private"],
            is_fork: repo["fork"],
            is_archived: repo["archived"],
            stars_count: repo["stargazers_count"] || repo["stars_count"] || 0,
            primary_language: repo["language"],
            already_imported: imported_ids.include?(repo["id"].to_s)
          }
        end

        credential.record_success!
        {
          success: true,
          repositories: repositories,
          pagination: {
            current_page: page,
            per_page: per_page,
            total_count: repos_data.count
          }
        }
      rescue Devops::Git::ApiClient::ApiError => e
        credential.record_failure!(e.message)
        { success: false, error: e.message }
      end

      # Import specific repositories by external_id
      def import_specific_repositories(credential, external_ids, options = {})
        raise CredentialError, "Credential cannot be used" unless credential.can_be_used?
        raise ValidationError, "No external_ids provided" if external_ids.blank?

        client = Devops::Git::ApiClient.for(credential)
        account = credential.account

        imported = []
        errors = []

        # Fetch all repos to find the ones we need
        # Note: For large accounts, this could be optimized with individual repo fetches
        all_repos = client.list_repositories(page: 1, per_page: 100)

        # Build a map of external_id -> repo_data
        repos_by_id = all_repos.each_with_object({}) do |repo, hash|
          hash[repo["id"].to_s] = repo
        end

        external_ids.each do |external_id|
          repo_data = repos_by_id[external_id.to_s]

          if repo_data.nil?
            errors << { external_id: external_id, error: "Repository not found" }
            next
          end

          result = sync_single_repository(credential, repo_data, options)
          if result[:success]
            imported << result[:repository]
          elsif result[:skipped]
            errors << { external_id: external_id, error: "Skipped: #{result[:reason]}" }
          else
            errors << { external_id: external_id, error: result[:error] }
          end
        end

        credential.record_success!
        {
          success: true,
          imported_count: imported.count,
          error_count: errors.count,
          repositories: imported,
          errors: errors
        }
      rescue Devops::Git::ApiClient::ApiError => e
        credential.record_failure!(e.message)
        { success: false, error: e.message }
      end

      # Sync repositories from the provider
      # @deprecated Use import_specific_repositories for individual imports
      def sync_repositories(credential, options = {})
        raise CredentialError, "Credential cannot be used" unless credential.can_be_used?

        client = Devops::Git::ApiClient.for(credential)
        repos_data = client.list_repositories(
          page: options[:page] || 1,
          per_page: options[:per_page] || 100
        )

        synced = []
        errors = []

        repos_data.each do |repo_data|
          result = sync_single_repository(credential, repo_data, options)
          if result[:success]
            synced << result[:repository]
          else
            errors << { repo: repo_data["full_name"], error: result[:error] }
          end
        end

        credential.record_success!
        {
          success: true,
          synced_count: synced.count,
          error_count: errors.count,
          repositories: synced,
          errors: errors
        }
      rescue Devops::Git::ApiClient::ApiError => e
        credential.record_failure!(e.message)
        { success: false, error: e.message }
      end

      # Sync a single repository
      def sync_single_repository(credential, repo_data, options = {})
        account = credential.account

        # Skip archived repos unless explicitly included
        if repo_data["archived"] && !options[:include_archived]
          return { success: false, skipped: true, reason: "archived" }
        end

        # Skip forks unless explicitly included
        if repo_data["fork"] && !options[:include_forks]
          return { success: false, skipped: true, reason: "fork" }
        end

        repo = credential.repositories.find_or_initialize_by(
          external_id: repo_data["id"].to_s,
          account: account
        )

        repo.assign_attributes(
          name: repo_data["name"],
          full_name: repo_data["full_name"],
          owner: extract_owner(repo_data),
          description: repo_data["description"],
          default_branch: repo_data["default_branch"] || "main",
          clone_url: repo_data["clone_url"],
          ssh_url: repo_data["ssh_url"],
          web_url: repo_data["html_url"] || repo_data["web_url"],
          is_private: repo_data["private"],
          is_fork: repo_data["fork"],
          is_archived: repo_data["archived"],
          stars_count: repo_data["stargazers_count"] || repo_data["stars_count"] || 0,
          forks_count: repo_data["forks_count"] || 0,
          open_issues_count: repo_data["open_issues_count"] || 0,
          languages: extract_languages(repo_data),
          topics: repo_data["topics"] || [],
          last_synced_at: Time.current,
          provider_updated_at: parse_timestamp(repo_data["updated_at"])
        )

        if repo.save
          { success: true, repository: repo }
        else
          { success: false, error: repo.errors.full_messages.join(", ") }
        end
      end

      # Configure webhooks for a repository
      def configure_webhook(repository, events = nil)
        credential = repository.credential
        raise CredentialError, "Credential cannot be used" unless credential.can_be_used?

        repository.configure_webhook!
      end

      # Sync pipeline data for a repository
      def sync_pipelines(repository, options = {})
        credential = repository.credential
        raise CredentialError, "Credential cannot be used" unless credential.can_be_used?

        client = Devops::Git::ApiClient.for(credential)

        begin
          runs_data = client.list_workflow_runs(
            repository.owner,
            repository.name,
            page: options[:page] || 1,
            per_page: options[:per_page] || 30
          )

          synced = []
          runs_data.each do |run_data|
            pipeline = sync_pipeline(repository, run_data)
            synced << pipeline if pipeline
          end

          { success: true, synced_count: synced.count, pipelines: synced }
        rescue Devops::Git::ApiClient::NotFoundError
          { success: true, synced_count: 0, pipelines: [], message: "CI/CD not enabled" }
        rescue Devops::Git::ApiClient::ApiError => e
          { success: false, error: e.message }
        end
      end

      # Sync a single pipeline
      def sync_pipeline(repository, run_data)
        pipeline = repository.pipelines.find_or_initialize_by(
          external_id: run_data["id"].to_s
        )

        pipeline.assign_attributes(
          account: repository.account,
          name: run_data["name"] || "Pipeline ##{run_data['id']}",
          status: normalize_pipeline_status(run_data["status"]),
          conclusion: run_data["conclusion"],
          trigger_event: run_data["event"],
          ref: run_data["head_branch"],
          sha: run_data["head_sha"],
          actor_username: run_data.dig("actor", "login"),
          web_url: run_data["html_url"],
          run_number: run_data["run_number"],
          started_at: parse_timestamp(run_data["started_at"]),
          completed_at: parse_timestamp(run_data["completed_at"])
        )

        pipeline.save ? pipeline : nil
      end

      # Setup default providers (seed data)
      def setup_default_providers
        providers_config.each do |config|
          Devops::GitProvider.find_or_create_by!(slug: config[:slug]) do |provider|
            provider.assign_attributes(config)
          end
        end
      end

      private

      def validate_credential_params(provider, params)
        raise ValidationError, "auth_type is required" unless params[:auth_type].present?
        raise ValidationError, "credentials are required" unless params[:credentials].present?

        unless Devops::GitProviderCredential::AUTH_TYPES.include?(params[:auth_type])
          raise ValidationError, "Invalid auth_type: #{params[:auth_type]}"
        end

        case params[:auth_type]
        when "oauth"
          unless params.dig(:credentials, :access_token).present?
            raise ValidationError, "access_token is required for OAuth authentication"
          end
        when "personal_access_token"
          token = params.dig(:credentials, :token) || params.dig(:credentials, :access_token)
          unless token.present?
            raise ValidationError, "token is required for personal access token authentication"
          end
        end
      end

      def normalize_credentials(credentials)
        creds = credentials.to_h.with_indifferent_access

        # Normalize token field names
        if creds[:token].present? && creds[:access_token].blank?
          creds[:access_token] = creds[:token]
        end

        creds.to_h
      end

      def test_and_update_credential(credential)
        result = Devops::Git::ProviderTestService.new(credential).test_connection

        if result[:success]
          credential.update!(
            external_username: result[:username],
            external_user_id: result[:user_id],
            external_avatar_url: result[:avatar_url],
            scopes: result[:scopes] || []
          )
          credential.record_success!
        else
          credential.record_failure!(result[:error])
        end
      end

      def generate_credential_name(provider, auth_type)
        type_label = auth_type == "oauth" ? "OAuth" : "Personal Token"
        "#{provider.name} - #{type_label}"
      end

      def extract_owner(repo_data)
        repo_data.dig("owner", "login") ||
          repo_data.dig("namespace", "path") ||
          repo_data["full_name"]&.split("/")&.first
      end

      def extract_languages(repo_data)
        if repo_data["language"].present?
          { repo_data["language"] => 100 }
        else
          {}
        end
      end

      def parse_timestamp(timestamp)
        Time.parse(timestamp) if timestamp.present?
      rescue ArgumentError
        nil
      end

      def normalize_pipeline_status(status)
        case status&.downcase
        when "queued", "waiting"
          "queued"
        when "pending", "requested"
          "pending"
        when "in_progress", "running"
          "in_progress"
        when "completed", "success"
          "completed"
        when "failure", "failed"
          "failed"
        when "cancelled", "canceled"
          "cancelled"
        when "skipped"
          "skipped"
        else
          status || "pending"
        end
      end

      def providers_config
        [
          {
            name: "GitHub",
            slug: "github",
            provider_type: "github",
            description: "GitHub - The world's leading software development platform",
            api_base_url: "https://api.github.com",
            web_base_url: "https://github.com",
            capabilities: %w[repos branches commits pull_requests issues webhooks ci_cd],
            supports_oauth: true,
            supports_pat: true,
            supports_webhooks: true,
            supports_devops: true,
            priority_order: 1,
            oauth_config: {
              authorization_url: "https://github.com/login/oauth/authorize",
              token_url: "https://github.com/login/oauth/access_token",
              scopes: %w[repo read:org admin:repo_hook workflow]
            }
          },
          {
            name: "GitLab",
            slug: "gitlab",
            provider_type: "gitlab",
            description: "GitLab - DevOps lifecycle tool with built-in CI/CD",
            api_base_url: "https://gitlab.com/api/v4",
            web_base_url: "https://gitlab.com",
            capabilities: %w[repos branches commits merge_requests issues webhooks ci_cd],
            supports_oauth: true,
            supports_pat: true,
            supports_webhooks: true,
            supports_devops: true,
            priority_order: 2,
            oauth_config: {
              authorization_url: "https://gitlab.com/oauth/authorize",
              token_url: "https://gitlab.com/oauth/token",
              scopes: %w[api read_api read_repository write_repository]
            }
          },
          {
            name: "Gitea",
            slug: "gitea",
            provider_type: "gitea",
            description: "Gitea - Self-hosted Git service with act runner CI/CD support",
            api_base_url: nil, # User provides during setup
            web_base_url: nil,
            capabilities: %w[repos branches commits pull_requests issues webhooks ci_cd act_runner],
            supports_oauth: true,
            supports_pat: true,
            supports_webhooks: true,
            supports_devops: true,
            priority_order: 3,
            devops_config: {
              runner_type: "act_runner",
              supports_workflow_dispatch: true,
              supports_job_logs: true
            }
          }
        ]
      end
    end
  end
  end

# Backwards compatibility alias
GitProviderManagementService = Devops::Git::ProviderManagementService unless defined?(GitProviderManagementService)
end
