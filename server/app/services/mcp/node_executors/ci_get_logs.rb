# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # CI Get Logs node executor - fetches logs from CI/CD pipeline jobs
    #
    # Configuration:
    # - repository_id: UUID of Devops::GitRepository
    # - run_id: ID of the workflow run
    # - job_id: ID of specific job (optional - if not provided, fetches all jobs)
    # - include_steps: Whether to include step-level details (default: true)
    # - max_log_size: Maximum log size in bytes to return (default: 1MB)
    #
    class CiGetLogs < Base
      DEFAULT_MAX_LOG_SIZE = 1_048_576 # 1MB

      protected

      def perform_execution
        log_info "Fetching CI/CD pipeline logs"

        # Extract configuration
        repository_id = resolve_value(configuration["repository_id"])
        run_id = resolve_value(configuration["run_id"])
        job_id = resolve_value(configuration["job_id"])
        include_steps = configuration["include_steps"] != false
        max_log_size = (configuration["max_log_size"] || DEFAULT_MAX_LOG_SIZE).to_i

        # Validate configuration
        validate_configuration!(repository_id, run_id)

        # Get repository and API client
        repository = find_repository(repository_id)
        api_client = build_api_client(repository)

        # Fetch logs
        result = if job_id.present?
          fetch_job_logs(api_client, repository, run_id, job_id, max_log_size)
        else
          fetch_all_job_logs(api_client, repository, run_id, include_steps, max_log_size)
        end

        build_output(result, repository, run_id, job_id)
      end

      private

      def validate_configuration!(repository_id, run_id)
        errors = []
        errors << "repository_id is required" if repository_id.blank?
        errors << "run_id is required" if run_id.blank?

        if errors.any?
          raise ArgumentError, "CI Get Logs configuration errors: #{errors.join(', ')}"
        end
      end

      def find_repository(repository_id)
        repository = Devops::GitRepository.find_by(id: repository_id)
        raise ArgumentError, "Repository not found: #{repository_id}" unless repository
        repository
      end

      def build_api_client(repository)
        credential = repository.git_provider_credential
        raise ArgumentError, "No credential found for repository" unless credential

        Devops::Git::ApiClient.for(credential)
      end

      def fetch_job_logs(api_client, repository, run_id, job_id, max_log_size)
        log_info "Fetching logs for job #{job_id}"

        logs = api_client.get_job_logs(repository.owner, repository.name, job_id)
        truncated = false

        if logs.is_a?(String) && logs.bytesize > max_log_size
          logs = logs.byteslice(0, max_log_size)
          truncated = true
        end

        {
          success: true,
          jobs: [
            {
              job_id: job_id,
              logs: logs,
              truncated: truncated
            }
          ],
          total_jobs: 1
        }
      rescue Devops::Git::ApiClient::NotFoundError
        { success: false, error: "Job logs not found: #{job_id}" }
      rescue StandardError => e
        { success: false, error: "Failed to fetch job logs: #{e.message}" }
      end

      def fetch_all_job_logs(api_client, repository, run_id, include_steps, max_log_size)
        log_info "Fetching logs for all jobs in run #{run_id}"

        # Get list of jobs for this run
        jobs_response = api_client.get_workflow_run_jobs(repository.owner, repository.name, run_id)
        jobs = jobs_response.is_a?(Hash) ? (jobs_response[:jobs] || jobs_response["jobs"] || []) : jobs_response

        if jobs.empty?
          return { success: true, jobs: [], total_jobs: 0 }
        end

        # Fetch logs for each job
        job_logs = jobs.map do |job|
          job_id = job[:id] || job["id"]
          job_name = job[:name] || job["name"]
          job_status = job[:status] || job["status"]
          job_conclusion = job[:conclusion] || job["conclusion"]

          logs = nil
          truncated = false
          error = nil

          begin
            if job_status == "completed"
              logs = api_client.get_job_logs(repository.owner, repository.name, job_id)
              if logs.is_a?(String) && logs.bytesize > max_log_size
                logs = logs.byteslice(0, max_log_size)
                truncated = true
              end
            end
          rescue StandardError => e
            error = e.message
            log_debug "Failed to fetch logs for job #{job_id}: #{e.message}"
          end

          result = {
            job_id: job_id.to_s,
            name: job_name,
            status: job_status,
            conclusion: job_conclusion,
            logs: logs,
            truncated: truncated,
            error: error
          }

          # Include step details if requested
          if include_steps
            steps = job[:steps] || job["steps"] || []
            result[:steps] = steps.map do |step|
              {
                number: step[:number] || step["number"],
                name: step[:name] || step["name"],
                status: step[:status] || step["status"],
                conclusion: step[:conclusion] || step["conclusion"],
                started_at: step[:started_at] || step["started_at"],
                completed_at: step[:completed_at] || step["completed_at"]
              }
            end
          end

          result
        end

        {
          success: true,
          jobs: job_logs,
          total_jobs: jobs.size
        }
      rescue Devops::Git::ApiClient::NotFoundError
        { success: false, error: "Workflow run not found: #{run_id}" }
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\{\{(.+?)\}\}/)
          variable_name = value.match(/\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def build_output(result, repository, run_id, job_id)
        if result[:success]
          {
            output: {
              found: result[:jobs].any?,
              total_jobs: result[:total_jobs],
              jobs_with_logs: result[:jobs].count { |j| j[:logs].present? },
              jobs_with_errors: result[:jobs].count { |j| j[:error].present? }
            },
            data: {
              repository_id: repository.id,
              repository_name: "#{repository.owner}/#{repository.name}",
              run_id: run_id,
              job_id: job_id,
              jobs: result[:jobs]
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "ci_get_logs",
              executed_at: Time.current.iso8601
            }
          }
        else
          {
            output: {
              found: false,
              error: result[:error]
            },
            data: {
              repository_id: repository.id,
              run_id: run_id,
              job_id: job_id
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "ci_get_logs",
              executed_at: Time.current.iso8601,
              failed: true
            }
          }
        end
      end
    end
  end
end
