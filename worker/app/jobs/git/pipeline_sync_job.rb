# frozen_string_literal: true

module Git
  class PipelineSyncJob < BaseJob
    sidekiq_options queue: 'services', retry: 3

    # Sync CI/CD pipeline status from Git provider
    # Fetches workflow runs, jobs, and their statuses
    def execute(repository_id, external_pipeline_id = nil)
      log_info "Starting pipeline sync",
               repository_id: repository_id,
               external_pipeline_id: external_pipeline_id

      # Fetch repository with credential from backend
      response = api_client.get("/api/v1/internal/git/repositories/#{repository_id}")
      repository = response["data"]

      unless repository
        log_error "Repository not found", repository_id: repository_id
        return { error: "Repository not found" }
      end

      credential_id = repository["credential_id"]

      # Get decrypted credentials
      decrypted_response = api_client.get("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
      credential = decrypted_response["data"]

      client_config = {
        provider_type: repository.dig("provider", "provider_type") || credential["provider_type"],
        api_base_url: repository.dig("provider", "api_base_url") || credential["api_base_url"],
        token: credential["access_token"] || credential["token"]
      }

      owner = repository["owner"]
      name = repository["name"]

      if external_pipeline_id
        # Sync specific pipeline
        sync_single_pipeline(repository_id, owner, name, external_pipeline_id, client_config)
      else
        # Sync recent pipelines
        sync_recent_pipelines(repository_id, owner, name, client_config)
      end
    rescue BackendApiClient::ApiError => e
      log_error "API error during pipeline sync", e, repository_id: repository_id
      raise
    end

    private

    def sync_single_pipeline(repository_id, owner, name, external_id, config)
      log_info "Syncing single pipeline",
               repository_id: repository_id,
               external_id: external_id

      # Fetch pipeline details from provider
      pipeline = fetch_pipeline_from_provider(owner, name, external_id, config)

      unless pipeline
        log_warn "Pipeline not found on provider",
                 repository_id: repository_id,
                 external_id: external_id
        return { error: "Pipeline not found" }
      end

      # Fetch jobs for the pipeline
      jobs = fetch_pipeline_jobs_from_provider(owner, name, external_id, config)

      # Upsert pipeline in backend
      api_client.post("/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines", {
        pipelines: [normalize_pipeline(pipeline, jobs)]
      })

      # Sync jobs
      if jobs.any?
        sync_pipeline_jobs(repository_id, external_id, jobs, config, owner, name)
      end

      log_info "Pipeline sync completed",
               repository_id: repository_id,
               external_id: external_id,
               jobs_count: jobs.count

      {
        success: true,
        pipeline_id: external_id,
        status: pipeline["status"] || pipeline["state"],
        conclusion: pipeline["conclusion"],
        jobs_count: jobs.count
      }
    end

    def sync_recent_pipelines(repository_id, owner, name, config)
      log_info "Syncing recent pipelines", repository_id: repository_id

      # Fetch recent pipelines from provider
      pipelines = fetch_pipelines_from_provider(owner, name, config)

      log_info "Fetched pipelines from provider",
               repository_id: repository_id,
               count: pipelines.count

      # Normalize and send to backend
      normalized_pipelines = pipelines.map do |p|
        jobs = fetch_pipeline_jobs_from_provider(owner, name, p["id"], config)
        normalize_pipeline(p, jobs)
      end

      api_client.post("/api/v1/internal/git/repositories/#{repository_id}/sync_pipelines", {
        pipelines: normalized_pipelines
      })

      {
        success: true,
        synced_count: pipelines.count
      }
    end

    def sync_pipeline_jobs(repository_id, pipeline_external_id, jobs, config, owner, name)
      normalized_jobs = jobs.map do |job|
        normalize_job(job, owner, name, config)
      end

      # Find internal pipeline ID first
      begin
        api_client.post("/api/v1/internal/git/pipelines/sync_jobs", {
          repository_id: repository_id,
          pipeline_external_id: pipeline_external_id,
          jobs: normalized_jobs
        })
      rescue BackendApiClient::ApiError => e
        log_warn "Failed to sync pipeline jobs",
                 pipeline_external_id: pipeline_external_id,
                 error: e.message
      end
    end

    # Provider API calls
    def fetch_pipeline_from_provider(owner, name, external_id, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/pipelines/#{external_id}"
             when "gitea"
               "/repos/#{owner}/#{name}/actions/runs/#{external_id}"
             else
               "/repos/#{owner}/#{name}/actions/runs/#{external_id}"
             end

      make_provider_request(config, "GET", path)
    rescue StandardError => e
      log_error "Failed to fetch pipeline", e, external_id: external_id
      nil
    end

    def fetch_pipelines_from_provider(owner, name, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/pipelines"
             when "gitea"
               "/repos/#{owner}/#{name}/actions/runs"
             else
               "/repos/#{owner}/#{name}/actions/runs"
             end

      result = make_provider_request(config, "GET", path, { per_page: 30 })

      # GitHub/Gitea return { workflow_runs: [...] }
      if result.is_a?(Hash) && result["workflow_runs"]
        result["workflow_runs"]
      elsif result.is_a?(Array)
        result
      else
        []
      end
    end

    def fetch_pipeline_jobs_from_provider(owner, name, pipeline_id, config)
      path = case config[:provider_type]
             when "gitlab"
               "/projects/#{CGI.escape("#{owner}/#{name}")}/pipelines/#{pipeline_id}/jobs"
             when "gitea"
               "/repos/#{owner}/#{name}/actions/runs/#{pipeline_id}/jobs"
             else
               "/repos/#{owner}/#{name}/actions/runs/#{pipeline_id}/jobs"
             end

      result = make_provider_request(config, "GET", path)

      # GitHub/Gitea return { jobs: [...] }
      if result.is_a?(Hash) && result["jobs"]
        result["jobs"]
      elsif result.is_a?(Array)
        result
      else
        []
      end
    rescue StandardError => e
      log_warn "Failed to fetch pipeline jobs", pipeline_id: pipeline_id, error: e.message
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
      else
        raise ArgumentError, "Unknown provider type: #{provider_type}"
      end
    end

    def normalize_pipeline(pipeline, jobs = [])
      # Handle different provider formats
      status = normalize_status(pipeline["status"] || pipeline["state"])
      conclusion = pipeline["conclusion"]

      # GitLab uses status for both state and conclusion
      if pipeline["status"].in?(%w[success failed canceled skipped])
        conclusion ||= normalize_conclusion(pipeline["status"])
        status = "completed"
      end

      {
        external_id: pipeline["id"].to_s,
        name: pipeline["name"] || pipeline["display_title"] || "Pipeline ##{pipeline['id']}",
        status: status,
        conclusion: conclusion,
        trigger_event: pipeline["event"] || pipeline["source"],
        ref: pipeline["head_branch"] || pipeline["ref"],
        sha: pipeline["head_sha"] || pipeline["sha"],
        actor_username: pipeline.dig("actor", "login") || pipeline.dig("user", "username"),
        web_url: pipeline["html_url"] || pipeline["web_url"],
        run_number: pipeline["run_number"] || pipeline["id"],
        run_attempt: pipeline["run_attempt"] || 1,
        total_jobs: jobs.count,
        completed_jobs: jobs.count { |j| completed_status?(j["status"] || j["conclusion"]) },
        failed_jobs: jobs.count { |j| (j["conclusion"] || j["status"]) == "failure" },
        started_at: pipeline["run_started_at"] || pipeline["started_at"],
        completed_at: pipeline["completed_at"] || pipeline["finished_at"]
      }
    end

    def normalize_job(job, owner, name, config)
      {
        external_id: job["id"].to_s,
        name: job["name"],
        status: normalize_status(job["status"]),
        conclusion: job["conclusion"],
        step_number: job["run_attempt"] || 1,
        runner_name: job["runner_name"] || job.dig("runner", "name"),
        runner_id: (job["runner_id"] || job.dig("runner", "id"))&.to_s,
        runner_os: job.dig("runner", "os"),
        steps: job["steps"] || [],
        started_at: job["started_at"],
        completed_at: job["completed_at"]
      }
    end

    def normalize_status(status)
      case status&.to_s&.downcase
      when "queued", "waiting", "pending"
        "queued"
      when "in_progress", "running"
        "in_progress"
      when "completed", "success", "failed", "failure", "cancelled", "canceled", "skipped"
        "completed"
      else
        status || "pending"
      end
    end

    def normalize_conclusion(status)
      case status&.to_s&.downcase
      when "success"
        "success"
      when "failed", "failure"
        "failure"
      when "cancelled", "canceled"
        "cancelled"
      when "skipped"
        "skipped"
      else
        nil
      end
    end

    def completed_status?(status)
      %w[completed success failed failure cancelled canceled skipped].include?(status&.to_s&.downcase)
    end
  end
end
