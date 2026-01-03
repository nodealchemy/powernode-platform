# frozen_string_literal: true

module Git
  class ScheduledPipelineJob < BaseJob
    sidekiq_options queue: 'schedules', retry: 3

    # Execute scheduled pipelines that are due
    # Runs on a recurring basis (e.g., every minute) to check for due schedules
    def execute(options = {})
      account_id = options[:account_id] || options["account_id"]
      schedule_id = options[:schedule_id] || options["schedule_id"]

      log_info "Starting scheduled pipeline check",
               account_id: account_id,
               schedule_id: schedule_id

      if schedule_id.present?
        # Execute specific schedule
        execute_single_schedule(schedule_id)
      elsif account_id.present?
        # Execute all due schedules for account
        execute_account_schedules(account_id)
      else
        # Execute all due schedules across the system
        execute_all_due_schedules
      end
    rescue BackendApiClient::ApiError => e
      log_error "API error during scheduled pipeline execution", e
      raise
    end

    private

    def execute_all_due_schedules
      log_info "Fetching all due schedules"

      response = api_client.get("/api/v1/internal/git/schedules/due")
      schedules = response["data"] || []

      log_info "Found due schedules", count: schedules.count

      results = {
        total: schedules.count,
        triggered: 0,
        failed: 0,
        skipped: 0,
        errors: []
      }

      schedules.each do |schedule|
        result = execute_schedule(schedule)
        case result[:status]
        when :triggered
          results[:triggered] += 1
        when :failed
          results[:failed] += 1
          results[:errors] << { schedule_id: schedule["id"], error: result[:error] }
        when :skipped
          results[:skipped] += 1
        end
      end

      log_info "Scheduled pipeline execution completed",
               triggered: results[:triggered],
               failed: results[:failed],
               skipped: results[:skipped]

      results
    end

    def execute_account_schedules(account_id)
      log_info "Fetching due schedules for account", account_id: account_id

      response = api_client.get("/api/v1/internal/git/schedules/due", { account_id: account_id })
      schedules = response["data"] || []

      results = {
        total: schedules.count,
        triggered: 0,
        failed: 0
      }

      schedules.each do |schedule|
        result = execute_schedule(schedule)
        results[result[:status] == :triggered ? :triggered : :failed] += 1
      end

      results
    end

    def execute_single_schedule(schedule_id)
      log_info "Executing single schedule", schedule_id: schedule_id

      response = api_client.get("/api/v1/internal/git/schedules/#{schedule_id}")
      schedule = response["data"]

      unless schedule
        log_error "Schedule not found", schedule_id: schedule_id
        return { error: "Schedule not found" }
      end

      execute_schedule(schedule)
    end

    def execute_schedule(schedule)
      schedule_id = schedule["id"]
      schedule_name = schedule["name"]

      # Check idempotency - prevent duplicate executions
      idempotency_key = "schedule_execution:#{schedule_id}:#{Time.current.strftime('%Y%m%d%H%M')}"
      if already_processed?(idempotency_key)
        log_info "Schedule already executed this minute, skipping",
                 schedule_id: schedule_id
        return { status: :skipped, reason: "already_executed" }
      end

      log_info "Executing schedule",
               schedule_id: schedule_id,
               name: schedule_name,
               repository: schedule.dig("repository", "full_name")

      # Get decrypted credentials
      credential_id = schedule["credential_id"] || schedule.dig("repository", "credential_id")
      decrypted_response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      credential = decrypted_response["data"]

      unless credential
        record_schedule_failure(schedule_id, "Credential not found or invalid")
        return { status: :failed, error: "Credential not found" }
      end

      # Trigger the pipeline
      result = trigger_pipeline(schedule, credential)

      if result[:success]
        # Record successful run
        api_client.post("/api/v1/internal/git/schedules/#{schedule_id}/record_run", {
          status: "success",
          pipeline_external_id: result[:run_id],
          triggered_at: Time.current.iso8601
        })

        mark_processed(idempotency_key, ttl: 120) # Prevent re-execution for 2 minutes

        log_info "Pipeline triggered successfully",
                 schedule_id: schedule_id,
                 run_id: result[:run_id]

        { status: :triggered, run_id: result[:run_id] }
      else
        # Record failure
        record_schedule_failure(schedule_id, result[:error])

        { status: :failed, error: result[:error] }
      end
    rescue StandardError => e
      log_error "Error executing schedule", e, schedule_id: schedule["id"]
      record_schedule_failure(schedule["id"], e.message)
      { status: :failed, error: e.message }
    end

    def trigger_pipeline(schedule, credential)
      provider_type = credential["provider_type"]
      repository = schedule["repository"]
      workflow_file = schedule["workflow_file"]
      ref = schedule["ref"] || "main"
      inputs = schedule["inputs"] || {}

      owner = repository["owner"]
      name = repository["name"]

      case provider_type
      when "github"
        trigger_github_workflow(credential, owner, name, workflow_file, ref, inputs)
      when "gitlab"
        trigger_gitlab_pipeline(credential, owner, name, ref, inputs)
      when "gitea"
        trigger_gitea_workflow(credential, owner, name, workflow_file, ref, inputs)
      else
        { success: false, error: "Unsupported provider: #{provider_type}" }
      end
    end

    def trigger_github_workflow(credential, owner, repo, workflow_file, ref, inputs)
      base_url = credential["api_base_url"] || "https://api.github.com"
      path = "/repos/#{owner}/#{repo}/actions/workflows/#{workflow_file}/dispatches"

      body = {
        ref: ref,
        inputs: inputs
      }

      response = make_provider_request(
        base_url: base_url,
        token: credential["access_token"] || credential["token"],
        method: :post,
        path: path,
        body: body,
        provider_type: "github"
      )

      # GitHub returns 204 No Content on success
      if response[:status] == 204 || response[:status] == 200
        # Get the latest run to find the run ID
        runs_response = make_provider_request(
          base_url: base_url,
          token: credential["access_token"] || credential["token"],
          method: :get,
          path: "/repos/#{owner}/#{repo}/actions/runs?per_page=1",
          provider_type: "github"
        )

        run_id = runs_response.dig(:body, "workflow_runs", 0, "id")
        { success: true, run_id: run_id&.to_s }
      else
        { success: false, error: response[:error] || "Failed to trigger workflow" }
      end
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def trigger_gitlab_pipeline(credential, owner, repo, ref, variables)
      base_url = credential["api_base_url"] || "https://gitlab.com/api/v4"
      project_id = CGI.escape("#{owner}/#{repo}")
      path = "/projects/#{project_id}/pipeline"

      body = {
        ref: ref,
        variables: variables.map { |k, v| { key: k, value: v } }
      }

      response = make_provider_request(
        base_url: base_url,
        token: credential["access_token"] || credential["token"],
        method: :post,
        path: path,
        body: body,
        provider_type: "gitlab"
      )

      if response[:status] == 201 || response[:status] == 200
        run_id = response.dig(:body, "id")
        { success: true, run_id: run_id&.to_s }
      else
        { success: false, error: response[:error] || "Failed to trigger pipeline" }
      end
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def trigger_gitea_workflow(credential, owner, repo, workflow_file, ref, inputs)
      base_url = credential["api_base_url"]
      return { success: false, error: "Gitea requires explicit api_base_url" } unless base_url

      path = "/repos/#{owner}/#{repo}/actions/workflows/#{workflow_file}/dispatches"

      body = {
        ref: ref,
        inputs: inputs
      }

      response = make_provider_request(
        base_url: base_url,
        token: credential["access_token"] || credential["token"],
        method: :post,
        path: path,
        body: body,
        provider_type: "gitea"
      )

      if response[:status] == 204 || response[:status] == 200
        { success: true, run_id: nil } # Gitea may not return run ID immediately
      else
        { success: false, error: response[:error] || "Failed to trigger workflow" }
      end
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def make_provider_request(base_url:, token:, method:, path:, body: nil, provider_type:)
      require 'faraday'
      require 'json'

      conn = Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end

      # Set authentication header based on provider
      case provider_type
      when "gitlab"
        conn.headers["PRIVATE-TOKEN"] = token
      else
        conn.headers["Authorization"] = "token #{token}"
      end
      conn.headers["Accept"] = "application/json"
      conn.headers["Content-Type"] = "application/json"

      response = case method
                 when :get
                   conn.get(path)
                 when :post
                   conn.post(path, body)
                 else
                   raise ArgumentError, "Unsupported HTTP method: #{method}"
                 end

      {
        status: response.status,
        body: response.body,
        error: response.success? ? nil : "HTTP #{response.status}: #{response.body}"
      }
    end

    def record_schedule_failure(schedule_id, error_message)
      api_client.post("/api/v1/internal/git/schedules/#{schedule_id}/record_run", {
        status: "failure",
        error_message: error_message,
        triggered_at: Time.current.iso8601
      })
    rescue StandardError => e
      log_error "Failed to record schedule failure", e, schedule_id: schedule_id
    end
  end
end
