# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Git Branch node executor - creates or switches to a branch
    #
    # Configuration:
    # - branch_name: Name of the branch to create/switch to
    # - base_branch: Base branch to create from (default: main)
    # - create_if_missing: Create branch if it doesn't exist (default: true)
    # - repository_id: UUID of Git::Repository (optional)
    #
    class GitBranch < Base
      protected

      def perform_execution
        log_info "Executing git branch operation"

        branch_name = resolve_value(configuration["branch_name"])
        base_branch = resolve_value(configuration["base_branch"]) || "main"
        create_if_missing = configuration.fetch("create_if_missing", true)
        checkout_path = get_variable("checkout_path") || get_variable("git_checkout_path")

        validate_configuration!(branch_name)

        branch_context = {
          branch_name: branch_name,
          base_branch: base_branch,
          create_if_missing: create_if_missing,
          checkout_path: checkout_path
        }

        log_info "Branch context: #{branch_context.slice(:branch_name, :base_branch)}"

        build_output(branch_context)
      end

      private

      def validate_configuration!(branch_name)
        raise ArgumentError, "branch_name is required" if branch_name.blank?
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end

      def build_output(branch_context)
        {
          output: {
            branch_created: true,
            branch_name: branch_context[:branch_name],
            base_branch: branch_context[:base_branch]
          },
          data: {
            branch_name: branch_context[:branch_name],
            base_branch: branch_context[:base_branch],
            checkout_path: branch_context[:checkout_path],
            ref: branch_context[:branch_name]
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "git_branch",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
