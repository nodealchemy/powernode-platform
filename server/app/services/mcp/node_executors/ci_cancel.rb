# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # CI Cancel node executor - cancels running CI/CD pipelines
    #
    # Configuration:
    # - repository_id: UUID of GitRepository
    # - run_id: ID of the workflow run to cancel
    # - reason: Optional reason for cancellation (stored in metadata)
    #
    class CiCancel < Base
      protected

      def perform_execution
        log_info "Cancelling CI/CD pipeline"

        # Extract configuration
        repository_id = resolve_value(configuration["repository_id"])
        run_id = resolve_value(configuration["run_id"])
        reason = resolve_value(configuration["reason"]) || "Cancelled by AI workflow"

        # Validate configuration
        validate_configuration!(repository_id, run_id)

        # Get repository and API client
        repository = find_repository(repository_id)
        api_client = build_api_client(repository)

        # Get current run status first
        run_status = fetch_run_status(api_client, repository, run_id)

        # Check if run can be cancelled
        unless can_cancel?(run_status[:status])
          return build_output(
            {
              success: false,
              error: "Cannot cancel run with status '#{run_status[:status]}' - already terminal",
              already_terminal: true,
              current_status: run_status[:status],
              conclusion: run_status[:conclusion]
            },
            repository,
            run_id,
            reason
          )
        end

        # Execute cancellation
        result = api_client.cancel_workflow_run(repository.owner, repository.name, run_id)

        build_output(
          result.merge(
            previous_status: run_status[:status],
            run_data: run_status
          ),
          repository,
          run_id,
          reason
        )
      end

      private

      def validate_configuration!(repository_id, run_id)
        errors = []
        errors << "repository_id is required" if repository_id.blank?
        errors << "run_id is required" if run_id.blank?

        if errors.any?
          raise ArgumentError, "CI Cancel configuration errors: #{errors.join(', ')}"
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

      def fetch_run_status(api_client, repository, run_id)
        run = api_client.get_workflow_run(repository.owner, repository.name, run_id)

        {
          status: run[:status],
          conclusion: run[:conclusion],
          html_url: run[:html_url],
          created_at: run[:created_at],
          updated_at: run[:updated_at]
        }
      rescue Git::ApiClient::NotFoundError
        raise ArgumentError, "Workflow run not found: #{run_id}"
      end

      def can_cancel?(status)
        # Can only cancel runs that are still in progress
        %w[queued in_progress waiting pending].include?(status)
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

      def build_output(result, repository, run_id, reason)
        if result[:success]
          {
            output: {
              cancelled: true,
              run_id: run_id,
              previous_status: result[:previous_status]
            },
            data: {
              repository_id: repository.id,
              repository_name: "#{repository.owner}/#{repository.name}",
              run_id: run_id,
              reason: reason,
              run_url: result.dig(:run_data, :html_url)
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "ci_cancel",
              executed_at: Time.current.iso8601
            }
          }
        else
          {
            output: {
              cancelled: false,
              already_terminal: result[:already_terminal] || false,
              current_status: result[:current_status],
              conclusion: result[:conclusion],
              error: result[:error]
            },
            data: {
              repository_id: repository.id,
              repository_name: "#{repository.owner}/#{repository.name}",
              run_id: run_id,
              reason: reason
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "ci_cancel",
              executed_at: Time.current.iso8601,
              failed: !result[:already_terminal]
            }
          }
        end
      end
    end
  end
end
