# frozen_string_literal: true

require_relative "git_providers/provider_factory"

module CiCd
  # Service for performing git operations through provider APIs
  # This is the primary interface for pipeline handlers to interact with git providers
  class GitOperationsService
    attr_reader :provider, :logger

    def initialize(provider_config:, logger: nil)
      @logger = logger || Logger.new($stdout)
      @provider = create_provider(provider_config)
    end

    # =============================================================================
    # STATUS OPERATIONS
    # =============================================================================

    # Update build status for a commit
    def update_status(repo:, sha:, state:, context:, description:, target_url: nil)
      log_info("Updating commit status", repo: repo, sha: sha[0..7], state: state)

      provider.create_commit_status(
        repo: repo,
        sha: sha,
        state: state,
        context: context,
        description: description,
        target_url: target_url
      )
    end

    # =============================================================================
    # PULL REQUEST OPERATIONS
    # =============================================================================

    # Create a pull request
    def create_pull_request(repo:, title:, head:, base:, body: nil, draft: false)
      log_info("Creating pull request", repo: repo, head: head, base: base)

      provider.create_pull_request(
        repo: repo,
        title: title,
        head: head,
        base: base,
        body: body,
        draft: draft
      )
    end

    # Get pull request details
    def get_pull_request(repo:, number:)
      provider.get_pull_request(repo: repo, number: number)
    end

    # Find existing pull request
    def find_pull_request(repo:, head:, base:)
      prs = provider.list_pull_requests(repo: repo, state: "open", head: head, base: base)
      prs.first
    end

    # Merge a pull request
    def merge_pull_request(repo:, number:, method: "merge", message: nil)
      log_info("Merging pull request", repo: repo, number: number)

      provider.merge_pull_request(
        repo: repo,
        number: number,
        merge_method: method,
        commit_message: message
      )
    end

    # =============================================================================
    # COMMENT OPERATIONS
    # =============================================================================

    # Post a comment on an issue/PR
    def post_comment(repo:, number:, body:)
      log_info("Posting comment", repo: repo, number: number)

      provider.create_issue_comment(
        repo: repo,
        number: number,
        body: body
      )
    end

    # Update an existing comment
    def update_comment(repo:, comment_id:, body:)
      log_info("Updating comment", repo: repo, comment_id: comment_id)

      provider.update_issue_comment(
        repo: repo,
        comment_id: comment_id,
        body: body
      )
    end

    # Find or create a comment with a marker
    def upsert_comment(repo:, number:, body:, marker:)
      full_body = "<!-- #{marker} -->\n#{body}"

      # Search for existing comment with marker
      comments = provider.list_issue_comments(repo: repo, number: number)
      existing = comments.find { |c| c[:body]&.include?("<!-- #{marker} -->") }

      if existing
        update_comment(repo: repo, comment_id: existing[:id], body: full_body)
      else
        post_comment(repo: repo, number: number, body: full_body)
      end
    end

    # =============================================================================
    # FILE OPERATIONS
    # =============================================================================

    # Get file contents
    def get_file(repo:, path:, ref: nil)
      provider.get_file_contents(repo: repo, path: path, ref: ref)
    end

    # Create or update a file
    def write_file(repo:, path:, content:, message:, branch:, sha: nil)
      log_info("Writing file", repo: repo, path: path, branch: branch)

      # Try to get existing file SHA for update
      unless sha
        begin
          existing = provider.get_file_contents(repo: repo, path: path, ref: branch)
          sha = existing[:sha]
        rescue GitProviders::NotFoundError
          # File doesn't exist, will create new
        end
      end

      provider.create_or_update_file(
        repo: repo,
        path: path,
        content: content,
        message: message,
        branch: branch,
        sha: sha
      )
    end

    # =============================================================================
    # REPOSITORY OPERATIONS
    # =============================================================================

    # Get repository info
    def get_repository(repo:)
      provider.get_repository(repo: repo)
    end

    # List branches
    def list_branches(repo:)
      provider.list_branches(repo: repo)
    end

    # Get branch info
    def get_branch(repo:, branch:)
      provider.get_branch(repo: repo, branch: branch)
    end

    # =============================================================================
    # WORKFLOW OPERATIONS
    # =============================================================================

    # Trigger a workflow/action
    def trigger_workflow(repo:, workflow:, ref:, inputs: {})
      log_info("Triggering workflow", repo: repo, workflow: workflow, ref: ref)

      provider.dispatch_workflow(
        repo: repo,
        workflow: workflow,
        ref: ref,
        inputs: inputs
      )
    end

    # =============================================================================
    # WEBHOOK OPERATIONS
    # =============================================================================

    # Set up a webhook for the repository
    def setup_webhook(repo:, url:, events:, secret: nil)
      log_info("Setting up webhook", repo: repo, url: url)

      # Check for existing webhook with same URL
      existing = provider.list_webhooks(repo: repo)
      webhook = existing.find { |w| w["url"] == url || w.dig("config", "url") == url }

      if webhook
        log_info("Webhook already exists", webhook_id: webhook["id"])
        return webhook
      end

      provider.create_webhook(
        repo: repo,
        url: url,
        events: events,
        secret: secret
      )
    end

    # =============================================================================
    # UTILITY METHODS
    # =============================================================================

    # Get provider type
    def provider_type
      provider.provider_type
    end

    # Test connection
    def test_connection
      user = provider.get_current_user
      {
        success: true,
        user: user,
        provider_type: provider_type
      }
    rescue StandardError => e
      {
        success: false,
        error: e.message,
        provider_type: provider_type
      }
    end

    private

    def create_provider(config)
      if config.is_a?(Hash)
        GitProviders::ProviderFactory.from_api_data(config, logger: logger)
      else
        GitProviders::ProviderFactory.from_record(config, logger: logger)
      end
    end

    def log_info(message, **metadata)
      formatted = "[GitOps:#{provider_type}] #{message}"
      formatted += " | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}" if metadata.any?
      logger.info formatted
    end
  end
end
