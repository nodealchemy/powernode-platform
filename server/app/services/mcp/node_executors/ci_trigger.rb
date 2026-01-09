# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # CI Trigger node executor - triggers CI/CD pipelines on Git providers
    #
    # Supported trigger actions:
    # - workflow_dispatch: Trigger a GitHub Actions workflow dispatch event
    # - repository_dispatch: Trigger a custom repository dispatch event
    # - create_run: Directly create a workflow run (GitLab CI)
    #
    # Configuration:
    # - repository_id: UUID of Git::Repository to trigger on
    # - workflow_id: ID/path of the workflow to trigger
    # - ref: Git ref (branch/tag) to trigger on
    # - trigger_action: Type of trigger (workflow_dispatch, repository_dispatch, create_run)
    # - inputs: Key-value pairs to pass to the workflow
    #
    class CiTrigger < Base
      protected

      def perform_execution
        log_info "Triggering CI/CD pipeline"

        # Extract configuration
        repository_id = resolve_value(configuration["repository_id"])
        workflow_id = resolve_value(configuration["workflow_id"])
        ref = resolve_value(configuration["ref"]) || "main"
        trigger_action = configuration["trigger_action"] || "workflow_dispatch"
        inputs = resolve_inputs(configuration["inputs"] || {})

        # Validate required configuration
        validate_configuration!(repository_id, workflow_id)

        # Get repository and API client
        repository = find_repository(repository_id)
        api_client = build_api_client(repository)

        # Execute trigger based on action type
        result = execute_trigger(
          api_client: api_client,
          repository: repository,
          workflow_id: workflow_id,
          ref: ref,
          trigger_action: trigger_action,
          inputs: inputs
        )

        build_output(result, repository, workflow_id, ref, trigger_action)
      end

      private

      def validate_configuration!(repository_id, workflow_id)
        errors = []
        errors << "repository_id is required" if repository_id.blank?
        errors << "workflow_id is required" if workflow_id.blank?

        if errors.any?
          raise ArgumentError, "CI Trigger configuration errors: #{errors.join(', ')}"
        end
      end

      def find_repository(repository_id)
        repository = Git::Repository.find_by(id: repository_id)
        raise ArgumentError, "Repository not found: #{repository_id}" unless repository
        repository
      end

      def build_api_client(repository)
        credential = repository.git_provider_credential
        raise ArgumentError, "No credential found for repository" unless credential

        Git::ApiClient.for(credential)
      end

      def execute_trigger(api_client:, repository:, workflow_id:, ref:, trigger_action:, inputs:)
        case trigger_action
        when "workflow_dispatch"
          api_client.trigger_workflow(
            repository.owner,
            repository.name,
            workflow_id,
            ref,
            inputs
          )
        when "repository_dispatch"
          execute_repository_dispatch(api_client, repository, inputs)
        when "create_run"
          execute_create_run(api_client, repository, workflow_id, ref, inputs)
        else
          raise ArgumentError, "Unknown trigger action: #{trigger_action}"
        end
      end

      def execute_repository_dispatch(api_client, repository, inputs)
        # Repository dispatch uses custom event type
        event_type = inputs.delete("event_type") || "workflow_trigger"

        if api_client.respond_to?(:create_repository_dispatch)
          api_client.create_repository_dispatch(
            repository.owner,
            repository.name,
            event_type,
            inputs
          )
        else
          { success: false, error: "Repository dispatch not supported by this provider" }
        end
      end

      def execute_create_run(api_client, repository, workflow_id, ref, inputs)
        # GitLab-style direct run creation
        if api_client.respond_to?(:create_pipeline)
          api_client.create_pipeline(
            repository.owner,
            repository.name,
            ref: ref,
            variables: inputs.map { |k, v| { key: k, value: v } }
          )
        else
          # Fall back to workflow dispatch for GitHub
          api_client.trigger_workflow(
            repository.owner,
            repository.name,
            workflow_id,
            ref,
            inputs
          )
        end
      end

      def resolve_value(value)
        return nil if value.nil?

        # Check if value is a variable reference like {{variable_name}}
        if value.is_a?(String) && value.match?(/\{\{(.+?)\}\}/)
          variable_name = value.match(/\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def resolve_inputs(inputs)
        return {} unless inputs.is_a?(Hash)

        inputs.transform_values do |value|
          resolve_value(value)
        end
      end

      def build_output(result, repository, workflow_id, ref, trigger_action)
        if result[:success]
          {
            output: {
              triggered: true,
              workflow_id: workflow_id,
              ref: ref,
              trigger_action: trigger_action
            },
            data: {
              repository_id: repository.id,
              repository_name: "#{repository.owner}/#{repository.name}",
              provider: repository.git_provider_credential&.git_provider&.provider_type,
              run_id: result[:run_id],
              run_url: result[:url]
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "ci_trigger",
              executed_at: Time.current.iso8601
            }
          }
        else
          {
            output: {
              triggered: false,
              error: result[:error]
            },
            data: {
              repository_id: repository.id,
              workflow_id: workflow_id
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "ci_trigger",
              executed_at: Time.current.iso8601,
              failed: true
            }
          }
        end
      end
    end
  end
end
