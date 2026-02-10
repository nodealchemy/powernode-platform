# frozen_string_literal: true

module Devops
  module Git
  class ApiClient
    class ApiError < StandardError
      attr_reader :status, :response

      def initialize(message, status = nil, response = nil)
        super(message)
        @status = status
        @response = response
      end
    end

    class AuthenticationError < ApiError; end
    class RateLimitError < ApiError; end
    class NotFoundError < ApiError; end
    class ValidationError < ApiError; end
    class ServerError < ApiError; end

    # Factory method to create the appropriate client based on provider type
    def self.for(credential)
      raise ArgumentError, "Credential is required" unless credential
      raise ArgumentError, "Credential must be a Devops::GitProviderCredential" unless credential.is_a?(Devops::GitProviderCredential)

      case credential.provider.provider_type
      when "github"
        Devops::Git::GithubApiClient.new(credential)
      when "gitlab"
        Devops::Git::GitlabApiClient.new(credential)
      when "gitea"
        Devops::Git::GiteaApiClient.new(credential)
      else
        raise ArgumentError, "Unknown provider type: #{credential.provider.provider_type}"
      end
    end

    def initialize(credential)
      @credential = credential
      @provider = credential.provider
      @token = credential.access_token
      @base_url = @provider.effective_api_base_url
    end

    # Common interface - to be implemented by subclasses
    def test_connection
      raise NotImplementedError
    end

    def list_repositories(options = {})
      raise NotImplementedError
    end

    def get_repository(owner, repo)
      raise NotImplementedError
    end

    def list_branches(owner, repo)
      raise NotImplementedError
    end

    def list_commits(owner, repo, options = {})
      raise NotImplementedError
    end

    def list_pull_requests(owner, repo, options = {})
      raise NotImplementedError
    end

    def list_issues(owner, repo, options = {})
      raise NotImplementedError
    end

    def create_webhook(repository, secret)
      raise NotImplementedError
    end

    def delete_webhook(repository)
      raise NotImplementedError
    end

    # CI/CD methods - may not be supported by all providers
    def list_workflow_runs(owner, repo, options = {})
      raise NotImplementedError
    end

    def get_workflow_run(owner, repo, run_id)
      raise NotImplementedError
    end

    def get_workflow_run_jobs(owner, repo, run_id)
      raise NotImplementedError
    end

    def get_job_logs(owner, repo, job_id)
      raise NotImplementedError
    end

    def trigger_workflow(owner, repo, workflow_id, ref, inputs = {})
      raise NotImplementedError
    end

    def cancel_workflow_run(owner, repo, run_id)
      raise NotImplementedError
    end

    def rerun_workflow(owner, repo, run_id)
      raise NotImplementedError
    end

    # Commit viewing methods - comprehensive git view capabilities

    def get_commit(owner, repo, sha)
      raise NotImplementedError
    end

    def get_commit_diff(owner, repo, sha)
      raise NotImplementedError
    end

    def compare_commits(owner, repo, base, head)
      raise NotImplementedError
    end

    def get_file_content(owner, repo, path, ref = nil)
      raise NotImplementedError
    end

    def get_tree(owner, repo, sha, recursive: false)
      raise NotImplementedError
    end

    def list_tags(owner, repo, options = {})
      raise NotImplementedError
    end

    protected

    def connection
      @connection ||= build_connection
    end

    def build_connection
      Faraday.new(url: @base_url) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        configure_auth(conn)
        configure_headers(conn)
        conn.options.timeout = 30
        conn.options.open_timeout = 10
        conn.adapter Faraday.default_adapter
      end
    end

    def configure_auth(conn)
      conn.headers["Authorization"] = "Bearer #{@token}"
    end

    def configure_headers(conn)
      conn.headers["Accept"] = "application/json"
      conn.headers["User-Agent"] = "Powernode/1.0"
    end

    def get(path, params = {})
      raw = params.delete(:raw)
      response = connection.get(normalize_path(path), params)
      handle_response(response, raw: raw)
    end

    def post(path, body = {})
      response = connection.post(normalize_path(path), body.to_json)
      handle_response(response)
    end

    def patch(path, body = {})
      response = connection.patch(normalize_path(path), body.to_json)
      handle_response(response)
    end

    def put(path, body = {})
      response = connection.put(normalize_path(path), body.to_json)
      handle_response(response)
    end

    def delete(path)
      response = connection.delete(normalize_path(path))
      handle_response(response)
    end

    # Normalize path to work correctly with base URLs that have a path component
    # Faraday treats paths starting with "/" as absolute, ignoring the base URL's path.
    # By removing the leading slash, the path is appended to the base URL's path.
    def normalize_path(path)
      path.to_s.sub(/\A\//, "")
    end

    def handle_response(response, raw: false)
      case response.status
      when 200..299
        raw ? response.body : response.body
      when 401
        raise AuthenticationError.new("Authentication failed - check your token", response.status, response.body)
      when 403
        if rate_limited?(response)
          raise RateLimitError.new("Rate limit exceeded", response.status, response.body)
        else
          raise ApiError.new("Access forbidden - check permissions/scopes", response.status, response.body)
        end
      when 404
        raise NotFoundError.new("Resource not found", response.status, response.body)
      when 422
        error_message = extract_error_message(response.body)
        raise ValidationError.new("Validation failed: #{error_message}", response.status, response.body)
      when 429
        raise RateLimitError.new("Rate limit exceeded", response.status, response.body)
      when 500..599
        error_message = extract_error_message(response.body)
        raise ServerError.new("Server error (#{response.status}): #{error_message}", response.status, response.body)
      else
        error_message = extract_error_message(response.body)
        raise ApiError.new("API error (#{response.status}): #{error_message}", response.status, response.body)
      end
    end

    def rate_limited?(response)
      # Check headers first
      remaining = response.headers["x-ratelimit-remaining"]
      return true if remaining.present? && remaining.to_i.zero?

      # Check response body for rate limit message
      return true if response.body.is_a?(Hash) &&
                     response.body["message"].to_s.downcase.include?("rate limit")

      false
    end

    def extract_error_message(body)
      return body unless body.is_a?(Hash)

      body["message"] || body["error"] || body.to_json
    end

    def webhook_callback_url
      base = Rails.application.config.respond_to?(:webhook_base_url) ?
        Rails.application.config.webhook_base_url :
        ENV.fetch("WEBHOOK_BASE_URL", "https://app.example.com")

      "#{base}/api/v1/webhooks/git/#{@provider.provider_type}"
    end

    # Standardized error handling wrapper for API operations
    # Usage: with_error_handling { delete("/path"); { success: true } }
    # Usage: with_error_handling(default_on_not_found: { success: true }) { ... }
    #
    # When default_on_not_found is provided, NotFoundError returns that value.
    # Otherwise, NotFoundError (like all ApiErrors) returns { success: false, error: message }
    def with_error_handling(default_on_not_found: nil)
      yield
    rescue NotFoundError => e
      default_on_not_found || { success: false, error: e.message }
    rescue ApiError => e
      { success: false, error: e.message }
    end

    # Extract pagination parameters from options hash
    # Different providers use different parameter names (per_page vs limit)
    def pagination_params(options, limit_key: :per_page, default_limit: 100)
      {
        page: options[:page] || 1,
        limit_key => options[:per_page] || default_limit
      }
    end

    # Parse unified diff patch into structured hunk data
    # This is provider-agnostic - all Git providers use the same patch format
    def parse_patch_hunks(patch)
      return [] if patch.blank?

      hunks = []
      current_hunk = nil
      old_line = 0
      new_line = 0

      patch.lines.each do |line|
        if line.start_with?("@@")
          # Parse hunk header: @@ -old_start,old_lines +new_start,new_lines @@
          match = line.match(/@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
          if match
            current_hunk = {
              header: line.chomp,
              old_start: match[1].to_i,
              old_lines: match[2]&.to_i || 1,
              new_start: match[3].to_i,
              new_lines: match[4]&.to_i || 1,
              lines: []
            }
            hunks << current_hunk
            old_line = current_hunk[:old_start]
            new_line = current_hunk[:new_start]
          end
        elsif current_hunk
          line_type = case line[0]
          when "+" then "addition"
          when "-" then "deletion"
          when " " then "context"
          else "context"
          end

          diff_line = {
            type: line_type,
            content: line[1..].to_s.chomp
          }

          case line_type
          when "deletion"
            diff_line[:old_line_number] = old_line
            old_line += 1
          when "addition"
            diff_line[:new_line_number] = new_line
            new_line += 1
          when "context"
            diff_line[:old_line_number] = old_line
            diff_line[:new_line_number] = new_line
            old_line += 1
            new_line += 1
          end

          current_hunk[:lines] << diff_line
        end
      end

      hunks
    end
  end
  end
end
