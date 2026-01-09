# frozen_string_literal: true

module Git
  class ProviderTestService
    def initialize(credential)
      @credential = credential
      @provider = credential.provider
    end

    def test_connection
      return error_result("Credential is not active") unless @credential.is_active?
      return error_result("Credential has expired") if @credential.expired?

      start_time = Time.current
      client = Git::ApiClient.for(@credential)
      result = client.test_connection
      response_time_ms = ((Time.current - start_time) * 1000).to_i

      if result[:success]
        success_result(result, response_time_ms)
      else
        error_result(result[:error], response_time_ms)
      end
    rescue Git::ApiClient::AuthenticationError => e
      error_result("Authentication failed: #{e.message}", 0, "authentication_error")
    rescue Git::ApiClient::RateLimitError => e
      error_result("Rate limit exceeded: #{e.message}", 0, "rate_limit_error")
    rescue Git::ApiClient::ApiError => e
      error_result("API error: #{e.message}", 0, "api_error")
    rescue Faraday::ConnectionFailed => e
      error_result("Connection failed: #{e.message}", 0, "connection_error")
    rescue Faraday::TimeoutError => e
      error_result("Connection timed out", 0, "timeout_error")
    rescue StandardError => e
      Rails.logger.error "Git::ProviderTestService error: #{e.message}"
      error_result("Unexpected error: #{e.message}", 0, "unexpected_error")
    end

    def test_with_rate_limit
      result = test_connection
      return result unless result[:success]

      # Try to get rate limit info
      begin
        client = Git::ApiClient.for(@credential)
        if client.respond_to?(:rate_limit)
          rate_limit = client.rate_limit
          result[:rate_limit] = {
            limit: rate_limit.dig("rate", "limit") || rate_limit.dig("resources", "core", "limit"),
            remaining: rate_limit.dig("rate", "remaining") || rate_limit.dig("resources", "core", "remaining"),
            resets_at: parse_reset_time(rate_limit)
          }
        end
      rescue StandardError => e
        Rails.logger.debug "Could not fetch rate limit: #{e.message}"
      end

      result
    end

    def test_repository_access(owner, repo)
      return error_result("Credential cannot be used") unless @credential.can_be_used?

      start_time = Time.current
      client = Git::ApiClient.for(@credential)
      repo_data = client.get_repository(owner, repo)
      response_time_ms = ((Time.current - start_time) * 1000).to_i

      {
        success: true,
        repository: {
          name: repo_data["name"],
          full_name: repo_data["full_name"],
          private: repo_data["private"],
          default_branch: repo_data["default_branch"]
        },
        response_time_ms: response_time_ms
      }
    rescue Git::ApiClient::NotFoundError
      error_result("Repository not found or access denied", 0, "not_found")
    rescue Git::ApiClient::ApiError => e
      error_result(e.message, 0, "api_error")
    end

    def test_webhook_access(owner, repo)
      return error_result("Credential cannot be used") unless @credential.can_be_used?

      client = Git::ApiClient.for(@credential)
      webhooks = client.list_webhooks(owner, repo)

      {
        success: true,
        webhook_count: webhooks.count,
        can_manage_webhooks: true
      }
    rescue Git::ApiClient::ApiError => e
      if e.status == 404
        { success: true, webhook_count: 0, can_manage_webhooks: false, error: "No webhook access" }
      else
        error_result(e.message, 0, "api_error")
      end
    end

    def test_ci_cd_access(owner, repo)
      return error_result("Credential cannot be used") unless @credential.can_be_used?
      return error_result("Provider does not support CI/CD") unless @provider.supports_ci_cd?

      client = Git::ApiClient.for(@credential)

      begin
        runs = client.list_workflow_runs(owner, repo, per_page: 1)
        {
          success: true,
          ci_cd_enabled: true,
          recent_runs: runs.count
        }
      rescue Git::ApiClient::NotFoundError
        { success: true, ci_cd_enabled: false, message: "CI/CD not enabled for this repository" }
      end
    rescue Git::ApiClient::ApiError => e
      error_result(e.message, 0, "api_error")
    end

    private

    def success_result(result, response_time_ms)
      {
        success: true,
        username: result[:username],
        user_id: result[:user_id],
        avatar_url: result[:avatar_url],
        email: result[:email],
        scopes: result[:scopes] || [],
        provider_type: @provider.provider_type,
        response_time_ms: response_time_ms,
        message: "Connection successful"
      }
    end

    def error_result(message, response_time_ms = 0, error_code = nil)
      {
        success: false,
        error: message,
        error_code: error_code,
        provider_type: @provider.provider_type,
        response_time_ms: response_time_ms
      }
    end

    def parse_reset_time(rate_limit)
      reset = rate_limit.dig("rate", "reset") || rate_limit.dig("resources", "core", "reset")
      return nil unless reset

      Time.at(reset).iso8601
    rescue StandardError
      nil
    end
  end
end

# Backwards compatibility alias
GitProviderTestService = Git::ProviderTestService unless defined?(GitProviderTestService)
