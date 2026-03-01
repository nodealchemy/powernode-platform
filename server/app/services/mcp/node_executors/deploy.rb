# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Deploy node executor - dispatches deployment to worker
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
      include Concerns::WorkerDispatch

      protected

      def perform_execution
        log_info "Executing deployment"

        environment = resolve_value(configuration["environment"]) || "staging"
        strategy = configuration["strategy"] || "rolling"
        version = resolve_value(configuration["version"]) ||
                  get_variable("ref") ||
                  get_variable("sha")
        timeout_seconds = configuration["timeout_seconds"] || 600
        rollback_on_failure = configuration.fetch("rollback_on_failure", true)

        payload = {
          environment: environment,
          strategy: strategy,
          version: version,
          timeout_seconds: timeout_seconds,
          rollback_on_failure: rollback_on_failure,
          node_id: @node.node_id
        }

        log_info "Dispatching deployment: #{environment} (#{strategy})"

        dispatch_to_worker("Devops::DeploymentJob", payload, queue: "devops_high")
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
    end
  end
end
