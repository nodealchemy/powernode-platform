# frozen_string_literal: true

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
      raise ArgumentError, "Credential must be a GitProviderCredential" unless credential.is_a?(GitProviderCredential)

      case credential.git_provider.provider_type
      when "github"
        Git::GithubApiClient.new(credential)
      when "gitlab"
        Git::GitlabApiClient.new(credential)
      when "gitea"
        Git::GiteaApiClient.new(credential)
      else
        raise ArgumentError, "Unknown provider type: #{credential.git_provider.provider_type}"
      end
    end

    def initialize(credential)
      @credential = credential
      @provider = credential.git_provider
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
      path.to_s.sub(/\A\//, '')
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

      "#{base}/webhooks/git/#{@provider.provider_type}"
    end
  end
end
