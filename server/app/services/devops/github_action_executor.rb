# frozen_string_literal: true

module Devops
  class GithubActionExecutor < BaseExecutor
    GITHUB_API_BASE = "https://api.github.com"

    # Execute a GitHub Action workflow
    def perform_execution(input)
      workflow_id = effective_configuration[:workflow_id] || input[:workflow_id]
      ref = input[:ref] || effective_configuration[:default_ref] || "main"
      inputs = input[:inputs] || {}

      raise ConfigurationError, "workflow_id is required" unless workflow_id.present?

      with_retry(max_attempts: 3) do
        response = trigger_workflow(workflow_id, ref, inputs)

        if response.status.success?
          workflow_run = wait_for_workflow_run(workflow_id, ref) if effective_configuration[:wait_for_completion]

          {
            success: true,
            status_code: response.status.code,
            workflow_id: workflow_id,
            ref: ref,
            run_id: workflow_run&.dig("id"),
            run_url: workflow_run&.dig("html_url"),
            triggered_at: Time.current.iso8601
          }
        else
          handle_github_error(response)
        end
      end
    end

    def perform_connection_test
      response = github_client.get(
        "#{GITHUB_API_BASE}/repos/#{owner}/#{repo}"
      )

      if response.status.success?
        { success: true, message: "Successfully connected to #{owner}/#{repo}" }
      else
        { success: false, error: "Failed to access repository: #{response.status}" }
      end
    rescue HTTP::Error => e
      { success: false, error: "Connection failed: #{e.message}" }
    end

    private

    def owner
      effective_configuration[:owner] || decrypted_credentials[:owner]
    end

    def repo
      effective_configuration[:repo] || decrypted_credentials[:repo]
    end

    def trigger_workflow(workflow_id, ref, inputs)
      github_client.post(
        "#{GITHUB_API_BASE}/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/dispatches",
        json: { ref: ref, inputs: inputs }
      )
    end

    def wait_for_workflow_run(workflow_id, ref)
      max_wait = effective_configuration.fetch(:max_wait_seconds, 300)
      poll_interval = effective_configuration.fetch(:poll_interval_seconds, 10)
      start_time = Time.current

      loop do
        runs = fetch_recent_runs(workflow_id)
        matching_run = runs.find { |run| run["head_branch"] == ref && run["status"] != "completed" }

        if matching_run
          return matching_run if matching_run["status"] == "completed"

          if effective_configuration[:wait_for_completion]
            return wait_for_run_completion(matching_run["id"], max_wait - (Time.current - start_time).to_i)
          end

          return matching_run
        end

        break if Time.current - start_time > max_wait

        sleep(poll_interval)
      end

      nil
    end

    def wait_for_run_completion(run_id, remaining_time)
      poll_interval = effective_configuration.fetch(:poll_interval_seconds, 10)
      start_time = Time.current

      loop do
        run = fetch_run(run_id)
        return run if run["status"] == "completed"

        break if Time.current - start_time > remaining_time

        sleep(poll_interval)
      end

      fetch_run(run_id)
    end

    def fetch_recent_runs(workflow_id)
      response = github_client.get(
        "#{GITHUB_API_BASE}/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/runs",
        params: { per_page: 5 }
      )

      return [] unless response.status.success?

      JSON.parse(response.body.to_s)["workflow_runs"] || []
    end

    def fetch_run(run_id)
      response = github_client.get(
        "#{GITHUB_API_BASE}/repos/#{owner}/#{repo}/actions/runs/#{run_id}"
      )

      return nil unless response.status.success?

      JSON.parse(response.body.to_s)
    end

    def github_client
      @github_client ||= HTTP
        .timeout(connect: connect_timeout, read: read_timeout)
        .headers(github_headers)
    end

    def github_headers
      token = decrypted_credentials[:token] || decrypted_credentials[:access_token]

      {
        "Accept" => "application/vnd.github+json",
        "Authorization" => "Bearer #{token}",
        "X-GitHub-Api-Version" => "2022-11-28",
        "User-Agent" => "Powernode-Integration/1.0"
      }
    end

    def handle_github_error(response)
      body = JSON.parse(response.body.to_s) rescue {}
      message = body["message"] || "GitHub API error"

      case response.status.code
      when 401
        raise CredentialError, "Authentication failed: #{message}"
      when 403
        if response.headers["X-RateLimit-Remaining"] == "0"
          raise RateLimitError, "GitHub rate limit exceeded"
        end
        raise ExecutionError, "Access forbidden: #{message}"
      when 404
        raise ConfigurationError, "Resource not found: #{message}"
      when 422
        raise ExecutionError, "Validation failed: #{message}"
      else
        raise ExecutionError, "GitHub API error (#{response.status.code}): #{message}"
      end
    end
  end
end
