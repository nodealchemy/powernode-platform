# frozen_string_literal: true

module CiCd
  module GitProviders
    # Base class for git provider integrations
    # Provides a common interface for Gitea, GitLab, and GitHub
    class BaseProvider
      attr_reader :api_url, :access_token, :logger

      # Commit status states (normalized across providers)
      STATUS_PENDING = "pending"
      STATUS_RUNNING = "running"
      STATUS_SUCCESS = "success"
      STATUS_FAILURE = "failure"
      STATUS_ERROR = "error"
      STATUS_CANCELLED = "cancelled"

      def initialize(api_url:, access_token:, logger: nil)
        @api_url = api_url.chomp("/")
        @access_token = access_token
        @logger = logger || Logger.new($stdout)
      end

      # Provider type identifier
      # @return [Symbol] :gitea, :gitlab, or :github
      def provider_type
        raise NotImplementedError
      end

      # =============================================================================
      # COMMIT STATUS
      # =============================================================================

      # Update commit status
      # @param repo [String] Repository full name (owner/repo)
      # @param sha [String] Commit SHA
      # @param state [String] Status state (pending, running, success, failure, error)
      # @param context [String] Status context/name
      # @param description [String] Status description
      # @param target_url [String, nil] URL to link to
      # @return [Hash] Created status
      def create_commit_status(repo:, sha:, state:, context:, description:, target_url: nil)
        raise NotImplementedError
      end

      # Get commit statuses
      # @param repo [String] Repository full name
      # @param sha [String] Commit SHA
      # @return [Array<Hash>] List of statuses
      def get_commit_statuses(repo:, sha:)
        raise NotImplementedError
      end

      # =============================================================================
      # PULL REQUESTS / MERGE REQUESTS
      # =============================================================================

      # Create a pull/merge request
      # @param repo [String] Repository full name
      # @param title [String] PR title
      # @param head [String] Head branch
      # @param base [String] Base branch
      # @param body [String, nil] PR description
      # @param draft [Boolean] Create as draft
      # @return [Hash] Created PR
      def create_pull_request(repo:, title:, head:, base:, body: nil, draft: false)
        raise NotImplementedError
      end

      # Get pull request details
      # @param repo [String] Repository full name
      # @param number [Integer] PR number
      # @return [Hash] PR details
      def get_pull_request(repo:, number:)
        raise NotImplementedError
      end

      # List pull requests
      # @param repo [String] Repository full name
      # @param state [String] State filter (open, closed, all)
      # @param head [String, nil] Head branch filter
      # @param base [String, nil] Base branch filter
      # @return [Array<Hash>] List of PRs
      def list_pull_requests(repo:, state: "open", head: nil, base: nil)
        raise NotImplementedError
      end

      # Merge a pull request
      # @param repo [String] Repository full name
      # @param number [Integer] PR number
      # @param merge_method [String] Merge method (merge, squash, rebase)
      # @param commit_message [String, nil] Commit message
      # @return [Hash] Merge result
      def merge_pull_request(repo:, number:, merge_method: "merge", commit_message: nil)
        raise NotImplementedError
      end

      # =============================================================================
      # COMMENTS
      # =============================================================================

      # Create a comment on an issue/PR
      # @param repo [String] Repository full name
      # @param number [Integer] Issue/PR number
      # @param body [String] Comment body
      # @return [Hash] Created comment
      def create_issue_comment(repo:, number:, body:)
        raise NotImplementedError
      end

      # Update a comment
      # @param repo [String] Repository full name
      # @param comment_id [Integer] Comment ID
      # @param body [String] New comment body
      # @return [Hash] Updated comment
      def update_issue_comment(repo:, comment_id:, body:)
        raise NotImplementedError
      end

      # List comments on an issue/PR
      # @param repo [String] Repository full name
      # @param number [Integer] Issue/PR number
      # @return [Array<Hash>] List of comments
      def list_issue_comments(repo:, number:)
        raise NotImplementedError
      end

      # =============================================================================
      # REPOSITORY
      # =============================================================================

      # Get repository details
      # @param repo [String] Repository full name
      # @return [Hash] Repository details
      def get_repository(repo:)
        raise NotImplementedError
      end

      # List repository branches
      # @param repo [String] Repository full name
      # @return [Array<Hash>] List of branches
      def list_branches(repo:)
        raise NotImplementedError
      end

      # Get branch details
      # @param repo [String] Repository full name
      # @param branch [String] Branch name
      # @return [Hash] Branch details
      def get_branch(repo:, branch:)
        raise NotImplementedError
      end

      # =============================================================================
      # FILES
      # =============================================================================

      # Get file contents
      # @param repo [String] Repository full name
      # @param path [String] File path
      # @param ref [String, nil] Branch/tag/commit
      # @return [Hash] File contents with :content (decoded), :sha
      def get_file_contents(repo:, path:, ref: nil)
        raise NotImplementedError
      end

      # Create or update a file
      # @param repo [String] Repository full name
      # @param path [String] File path
      # @param content [String] File content (will be base64 encoded)
      # @param message [String] Commit message
      # @param branch [String] Branch name
      # @param sha [String, nil] Current file SHA (for updates)
      # @return [Hash] Commit details
      def create_or_update_file(repo:, path:, content:, message:, branch:, sha: nil)
        raise NotImplementedError
      end

      # =============================================================================
      # WEBHOOKS
      # =============================================================================

      # Create a webhook
      # @param repo [String] Repository full name
      # @param url [String] Webhook URL
      # @param events [Array<String>] Events to subscribe to
      # @param secret [String, nil] Webhook secret
      # @return [Hash] Created webhook
      def create_webhook(repo:, url:, events:, secret: nil)
        raise NotImplementedError
      end

      # List webhooks
      # @param repo [String] Repository full name
      # @return [Array<Hash>] List of webhooks
      def list_webhooks(repo:)
        raise NotImplementedError
      end

      # Delete a webhook
      # @param repo [String] Repository full name
      # @param webhook_id [Integer] Webhook ID
      # @return [Boolean] Success
      def delete_webhook(repo:, webhook_id:)
        raise NotImplementedError
      end

      # =============================================================================
      # USERS
      # =============================================================================

      # Get authenticated user
      # @return [Hash] User details
      def get_current_user
        raise NotImplementedError
      end

      # =============================================================================
      # WORKFLOW DISPATCH (if supported)
      # =============================================================================

      # Trigger a workflow/action
      # @param repo [String] Repository full name
      # @param workflow [String] Workflow file name or ID
      # @param ref [String] Branch/tag to run on
      # @param inputs [Hash] Workflow inputs
      # @return [Hash, nil] Dispatch result (nil if not supported)
      def dispatch_workflow(repo:, workflow:, ref:, inputs: {})
        # Default: not supported
        nil
      end

      # =============================================================================
      # HELPERS
      # =============================================================================

      protected

      # Make HTTP request
      def request(method, path, body: nil, params: nil)
        uri = URI.join(api_url, path)
        uri.query = URI.encode_www_form(params) if params

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 30
        http.open_timeout = 10

        request = build_request(method, uri, body)
        response = http.request(request)

        handle_response(response)
      end

      def build_request(method, uri, body)
        request_class = {
          get: Net::HTTP::Get,
          post: Net::HTTP::Post,
          put: Net::HTTP::Put,
          patch: Net::HTTP::Patch,
          delete: Net::HTTP::Delete
        }[method]

        request = request_class.new(uri)
        apply_headers(request)

        if body && %i[post put patch].include?(method)
          request.body = body.to_json
          request["Content-Type"] = "application/json"
        end

        request
      end

      def apply_headers(request)
        request["Accept"] = "application/json"
        request["Authorization"] = authorization_header
        request["User-Agent"] = "Powernode-CI/1.0"
      end

      def authorization_header
        "token #{access_token}"
      end

      def handle_response(response)
        case response.code.to_i
        when 200..299
          response.body.present? ? JSON.parse(response.body) : {}
        when 401
          raise AuthenticationError, "Authentication failed: #{response.body}"
        when 403
          raise ForbiddenError, "Access forbidden: #{response.body}"
        when 404
          raise NotFoundError, "Resource not found: #{response.body}"
        when 422
          raise ValidationError, "Validation failed: #{response.body}"
        when 429
          raise RateLimitError, "Rate limit exceeded: #{response.body}"
        else
          raise ApiError, "API error (#{response.code}): #{response.body}"
        end
      end

      def log_info(message, **metadata)
        logger.info format_log(message, metadata)
      end

      def log_error(message, **metadata)
        logger.error format_log(message, metadata)
      end

      def format_log(message, metadata)
        if metadata.any?
          "[#{provider_type}] #{message} | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}"
        else
          "[#{provider_type}] #{message}"
        end
      end

      # Map normalized status to provider-specific status
      def map_status(state)
        raise NotImplementedError
      end

      # Normalize provider-specific status to standard status
      def normalize_status(state)
        raise NotImplementedError
      end
    end

    # Error classes
    class ApiError < StandardError; end
    class AuthenticationError < ApiError; end
    class ForbiddenError < ApiError; end
    class NotFoundError < ApiError; end
    class ValidationError < ApiError; end
    class RateLimitError < ApiError; end
  end
end
