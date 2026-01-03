# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # CI Wait Status node executor - waits for CI/CD pipeline completion
    #
    # This node polls the pipeline status until it reaches the expected state
    # or times out. Used in workflows to wait for CI/CD results.
    #
    # Configuration:
    # - repository_id: UUID of GitRepository
    # - run_id: ID of the workflow run to wait for
    # - expected_status: Status to wait for (success, failure, completed, any)
    # - poll_interval_seconds: How often to check (default: 30)
    # - timeout_seconds: Maximum wait time (default: 3600 / 1 hour)
    #
    class CiWaitStatus < Base
      DEFAULT_POLL_INTERVAL = 30
      DEFAULT_TIMEOUT = 3600
      MAX_POLL_ATTEMPTS = 500

      TERMINAL_STATUSES = %w[completed success failure cancelled timed_out action_required].freeze
      SUCCESS_CONCLUSIONS = %w[success neutral skipped].freeze

      protected

      def perform_execution
        log_info "Waiting for CI/CD pipeline status"

        # Extract configuration
        repository_id = resolve_value(configuration["repository_id"])
        run_id = resolve_value(configuration["run_id"])
        expected_status = configuration["expected_status"] || "completed"
        poll_interval = (configuration["poll_interval_seconds"] || DEFAULT_POLL_INTERVAL).to_i
        timeout_seconds = (configuration["timeout_seconds"] || DEFAULT_TIMEOUT).to_i

        # Validate configuration
        validate_configuration!(repository_id, run_id)

        # Get repository and API client
        repository = find_repository(repository_id)
        api_client = build_api_client(repository)

        # Poll for status
        result = poll_for_status(
          api_client: api_client,
          repository: repository,
          run_id: run_id,
          expected_status: expected_status,
          poll_interval: poll_interval,
          timeout_seconds: timeout_seconds
        )

        build_output(result, repository, run_id, expected_status)
      end

      private

      def validate_configuration!(repository_id, run_id)
        errors = []
        errors << "repository_id is required" if repository_id.blank?
        errors << "run_id is required" if run_id.blank?

        if errors.any?
          raise ArgumentError, "CI Wait Status configuration errors: #{errors.join(', ')}"
        end
      end

      def find_repository(repository_id)
        repository = GitRepository.find_by(id: repository_id)
        raise ArgumentError, "Repository not found: #{repository_id}" unless repository
        repository
      end

      def build_api_client(repository)
        credential = repository.git_provider_credential
        raise ArgumentError, "No credential found for repository" unless credential

        Git::ApiClient.for(credential)
      end

      def poll_for_status(api_client:, repository:, run_id:, expected_status:, poll_interval:, timeout_seconds:)
        start_time = Time.current
        attempts = 0

        loop do
          attempts += 1

          # Check timeout
          elapsed = Time.current - start_time
          if elapsed > timeout_seconds
            return {
              success: false,
              timed_out: true,
              error: "Timeout after #{elapsed.round} seconds",
              final_status: nil,
              elapsed_seconds: elapsed.round
            }
          end

          # Safety check for max attempts
          if attempts > MAX_POLL_ATTEMPTS
            return {
              success: false,
              error: "Maximum poll attempts exceeded",
              final_status: nil,
              elapsed_seconds: elapsed.round
            }
          end

          # Get current status
          run_status = fetch_run_status(api_client, repository, run_id)

          log_debug "Poll attempt #{attempts}: status=#{run_status[:status]}, conclusion=#{run_status[:conclusion]}"

          # Check if status matches expected
          if status_matches?(run_status, expected_status)
            return {
              success: true,
              matched: true,
              final_status: run_status[:status],
              conclusion: run_status[:conclusion],
              elapsed_seconds: elapsed.round,
              poll_attempts: attempts,
              run_data: run_status
            }
          end

          # Check if terminal status reached but doesn't match
          if terminal_status?(run_status[:status]) && !status_matches?(run_status, expected_status)
            return {
              success: false,
              matched: false,
              error: "Pipeline finished with status '#{run_status[:conclusion]}' but expected '#{expected_status}'",
              final_status: run_status[:status],
              conclusion: run_status[:conclusion],
              elapsed_seconds: elapsed.round,
              run_data: run_status
            }
          end

          # Wait before next poll
          sleep(poll_interval)
        end
      end

      def fetch_run_status(api_client, repository, run_id)
        run = api_client.get_workflow_run(repository.owner, repository.name, run_id)

        {
          status: run[:status],
          conclusion: run[:conclusion],
          html_url: run[:html_url],
          created_at: run[:created_at],
          updated_at: run[:updated_at],
          head_sha: run[:head_sha],
          head_branch: run[:head_branch],
          workflow_id: run[:workflow_id]
        }
      rescue Git::ApiClient::NotFoundError
        raise ArgumentError, "Workflow run not found: #{run_id}"
      end

      def status_matches?(run_status, expected_status)
        case expected_status
        when "success"
          run_status[:conclusion] == "success"
        when "failure"
          run_status[:conclusion] == "failure"
        when "completed"
          terminal_status?(run_status[:status])
        when "any"
          terminal_status?(run_status[:status])
        else
          run_status[:conclusion] == expected_status
        end
      end

      def terminal_status?(status)
        TERMINAL_STATUSES.include?(status)
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

      def build_output(result, repository, run_id, expected_status)
        {
          output: {
            matched: result[:matched] || false,
            timed_out: result[:timed_out] || false,
            final_status: result[:final_status],
            conclusion: result[:conclusion],
            expected_status: expected_status
          },
          data: {
            repository_id: repository.id,
            repository_name: "#{repository.owner}/#{repository.name}",
            run_id: run_id,
            elapsed_seconds: result[:elapsed_seconds],
            poll_attempts: result[:poll_attempts],
            run_url: result.dig(:run_data, :html_url),
            head_sha: result.dig(:run_data, :head_sha),
            head_branch: result.dig(:run_data, :head_branch)
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "ci_wait_status",
            executed_at: Time.current.iso8601,
            success: result[:success],
            error: result[:error]
          }
        }
      end
    end
  end
end
