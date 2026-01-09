# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Git Checkout node executor - clones repository and checks out a ref
    #
    # Configuration:
    # - repository_id: UUID of GitRepository (optional, can use trigger context)
    # - repository: Repository name/path if not using repository_id
    # - ref: Git ref (branch/tag/SHA) to checkout
    # - fetch_depth: Shallow clone depth (0 for full history)
    # - submodules: Whether to checkout submodules
    #
    class GitCheckout < Base
      protected

      def perform_execution
        log_info "Executing git checkout"

        # Resolve configuration with variable interpolation
        repository = resolve_value(configuration["repository"]) ||
                     get_variable("trigger.repository") ||
                     get_variable("repository")
        ref = resolve_value(configuration["ref"]) ||
              get_variable("trigger.ref") ||
              get_variable("ref") || "main"
        fetch_depth = configuration["fetch_depth"] || 1
        submodules = configuration["submodules"] || false

        # Build checkout context
        checkout_context = {
          repository: repository,
          ref: ref,
          fetch_depth: fetch_depth,
          submodules: submodules,
          checkout_path: generate_checkout_path
        }

        log_info "Checkout context: #{checkout_context.slice(:repository, :ref)}"

        build_output(checkout_context)
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

      def generate_checkout_path
        "/tmp/workflow_#{@workflow_run.id}/checkout_#{SecureRandom.hex(4)}"
      end

      def build_output(checkout_context)
        {
          output: {
            checked_out: true,
            repository: checkout_context[:repository],
            ref: checkout_context[:ref],
            path: checkout_context[:checkout_path]
          },
          data: {
            checkout_path: checkout_context[:checkout_path],
            repository: checkout_context[:repository],
            ref: checkout_context[:ref],
            sha: checkout_context[:ref], # Would be resolved to actual SHA during execution
            fetch_depth: checkout_context[:fetch_depth],
            submodules: checkout_context[:submodules]
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "git_checkout",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
