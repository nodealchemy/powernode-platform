# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Git Commit Status node executor - updates commit status on Git providers
    #
    # This allows AI workflows to post status updates (checks) to commits,
    # enabling workflow results to appear on pull requests.
    #
    # Configuration:
    # - repository_id: UUID of Devops::GitRepository
    # - sha: Git commit SHA to update status for
    # - state: Status state (pending, success, failure, error)
    # - context: Status context/name (default: "powernode/workflow")
    # - description: Status description text
    # - target_url: URL to link to for more details
    #
    class GitCommitStatus < Base
      VALID_STATES = %w[pending success failure error].freeze
      DEFAULT_CONTEXT = "powernode/workflow"
      MAX_DESCRIPTION_LENGTH = 140

      protected

      def perform_execution
        log_info "Updating git commit status"

        # Extract configuration
        repository_id = resolve_value(configuration["repository_id"])
        sha = resolve_value(configuration["sha"])
        state = resolve_value(configuration["state"]) || "pending"
        context = resolve_value(configuration["context"]) || build_default_context
        description = resolve_value(configuration["description"])
        target_url = resolve_value(configuration["target_url"])

        # Validate configuration
        validate_configuration!(repository_id, sha, state)

        # Truncate description if needed
        description = truncate_description(description)

        # Get repository and API client
        repository = find_repository(repository_id)
        api_client = build_api_client(repository)

        # Create commit status
        result = api_client.create_commit_status(
          repository.owner,
          repository.name,
          sha,
          state,
          {
            context: context,
            description: description,
            target_url: target_url
          }.compact
        )

        build_output(result, repository, sha, state, context, description)
      end

      private

      def validate_configuration!(repository_id, sha, state)
        errors = []
        errors << "repository_id is required" if repository_id.blank?
        errors << "sha is required" if sha.blank?
        errors << "state must be one of: #{VALID_STATES.join(', ')}" unless VALID_STATES.include?(state)

        if errors.any?
          raise ArgumentError, "Git Commit Status configuration errors: #{errors.join(', ')}"
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

      def build_default_context
        workflow_name = @orchestrator&.workflow&.name || "workflow"
        node_name = @node.name || "node"

        "powernode/#{workflow_name}/#{node_name}".gsub(/[^a-zA-Z0-9\/_-]/, "-").truncate(100)
      end

      def truncate_description(description)
        return nil if description.blank?

        description.truncate(MAX_DESCRIPTION_LENGTH)
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

      def build_output(result, repository, sha, state, context, description)
        if result[:success]
          {
            output: {
              updated: true,
              state: state,
              context: context,
              sha: sha
            },
            data: {
              repository_id: repository.id,
              repository_name: "#{repository.owner}/#{repository.name}",
              sha: sha,
              state: state,
              context: context,
              description: description,
              status_id: result[:id],
              status_url: result[:url]
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "git_commit_status",
              executed_at: Time.current.iso8601
            }
          }
        else
          {
            output: {
              updated: false,
              error: result[:error]
            },
            data: {
              repository_id: repository.id,
              sha: sha,
              state: state,
              context: context
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "git_commit_status",
              executed_at: Time.current.iso8601,
              failed: true
            }
          }
        end
      end
    end
  end
end
