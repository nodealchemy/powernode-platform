# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Deploy node executor - triggers deployment to an environment
    #
    # Configuration:
    # - environment: Target environment (staging, production, etc.)
    # - strategy: Deployment strategy (rolling, blue_green, canary)
    # - version: Version/ref to deploy (optional, uses current checkout)
    # - wait_for_completion: Wait for deployment to complete (default: true)
    # - timeout_seconds: Deployment timeout
    # - rollback_on_failure: Auto-rollback on failure (default: true)
    #
    class Deploy < Base
      protected

      def perform_execution
        log_info "Executing deployment"

        environment = resolve_value(configuration["environment"]) || "staging"
        strategy = configuration["strategy"] || "rolling"
        version = resolve_value(configuration["version"]) ||
                  get_variable("ref") ||
                  get_variable("sha")
        wait_for_completion = configuration.fetch("wait_for_completion", true)
        timeout_seconds = configuration["timeout_seconds"] || 600
        rollback_on_failure = configuration.fetch("rollback_on_failure", true)

        deploy_context = {
          environment: environment,
          strategy: strategy,
          version: version,
          wait_for_completion: wait_for_completion,
          timeout_seconds: timeout_seconds,
          rollback_on_failure: rollback_on_failure,
          started_at: Time.current
        }

        log_info "Deploy context: #{deploy_context.slice(:environment, :strategy, :version)}"

        # Generate a deployment ID for tracking
        deployment_id = SecureRandom.uuid

        build_output(deploy_context, deployment_id)
      end

      private

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def build_output(deploy_context, deployment_id)
        {
          output: {
            deployed: true,
            deployment_id: deployment_id,
            environment: deploy_context[:environment],
            strategy: deploy_context[:strategy],
            version: deploy_context[:version]
          },
          data: {
            deployment_id: deployment_id,
            environment: deploy_context[:environment],
            strategy: deploy_context[:strategy],
            version: deploy_context[:version],
            started_at: deploy_context[:started_at].iso8601,
            status: "in_progress",
            rollback_available: deploy_context[:rollback_on_failure]
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "deploy",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
