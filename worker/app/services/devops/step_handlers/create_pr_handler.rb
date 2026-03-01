# frozen_string_literal: true

require_relative "../git_operations_service"

module Devops
  module StepHandlers
    # Handles creating pull requests
    # Uses git provider APIs directly for cross-provider support
    class CreatePrHandler < Base
      # Execute create PR step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting create PR step")

        # Load provider config for direct API access
        fetch_provider_config(context)

        # Get repository from context
        repository = context.dig(:trigger_context, :repository)
        unless repository
          raise StandardError, "Repository not found in context"
        end

        # Determine workspace
        workspace = previous_outputs.dig("checkout", :workspace) || Dir.pwd

        # Get branch name
        branch = config["branch"] || generate_branch_name(config, context)

        # Create and push branch if needed
        unless config["skip_branch_creation"]
          logs << log_info("Creating branch", branch: branch)
          create_and_push_branch(workspace, branch, config)
        end

        # Build PR details
        title = build_title(config, context, previous_outputs)
        body = build_body(config, context, previous_outputs)
        base = config["base"] || "develop"

        logs << log_info("Creating pull request",
                         repository: repository,
                         head: branch,
                         base: base)

        # Create the PR via API
        result = create_pull_request(
          repository: repository,
          title: title,
          body: body,
          head: branch,
          base: base
        )

        logs << log_info("Pull request created",
                         pr_number: result["number"],
                         url: result["html_url"])

        {
          outputs: {
            pr_number: result["number"],
            pr_url: result["html_url"],
            branch: branch
          },
          logs: logs.join("\n")
        }
      end

      private

      def generate_branch_name(config, context)
        trigger = context[:trigger_context] || {}

        prefix = config["branch_prefix"] || "claude"

        if trigger[:issue_number]
          "#{prefix}/issue-#{trigger[:issue_number]}"
        elsif trigger[:pr_number]
          "#{prefix}/pr-#{trigger[:pr_number]}-changes"
        else
          run_id = context.dig(:pipeline_run, :run_number) || SecureRandom.hex(4)
          "#{prefix}/run-#{run_id}"
        end
      end

      def create_and_push_branch(workspace, branch, config)
        # Check if branch already exists
        result = execute_shell_command(
          "git rev-parse --verify #{branch}",
          working_directory: workspace
        )

        if result[:success]
          # Branch exists, checkout
          execute_shell_command("git checkout #{branch}", working_directory: workspace)
        else
          # Create new branch
          base = config["from_branch"] || "HEAD"
          execute_shell_command("git checkout -b #{branch} #{base}", working_directory: workspace)
        end

        # Stage and commit any changes
        execute_shell_command("git add -A", working_directory: workspace)

        commit_result = execute_shell_command(
          'git diff --cached --quiet || git commit -m "AI-generated changes"',
          working_directory: workspace
        )

        # Push branch
        push_result = execute_shell_command(
          "git push -u origin #{branch}",
          working_directory: workspace
        )

        unless push_result[:success]
          raise StandardError, "Failed to push branch: #{push_result[:error]}"
        end
      end

      def build_title(config, context, previous_outputs)
        title = config["title"]

        # Default title based on trigger type
        if title.blank?
          trigger = context[:trigger_context] || {}

          if trigger[:issue_number]
            title = "feat: Implement solution for ##{trigger[:issue_number]}"
          else
            title = "AI-generated changes"
          end
        end

        # Interpolate variables
        variables = build_variables(context, previous_outputs)
        interpolate(title, variables)
      end

      def build_body(config, context, previous_outputs)
        body = config["body"]

        # Build default body if not specified
        if body.blank?
          trigger = context[:trigger_context] || {}

          body = <<~BODY
            ## Summary

            AI-generated pull request.

            #{issue_reference(trigger)}

            ## Changes

            See commits for details.

            ## Test Plan

            - [ ] Manual testing completed
            - [ ] Automated tests pass

            ---
            *Generated by Claude Code CI/CD*
          BODY
        end

        # Get body from previous step if specified
        if config["body_from"].present?
          step_name, output_key = config["body_from"].split(".")
          body = previous_outputs.dig(step_name, output_key.to_sym) ||
                 previous_outputs.dig(step_name, :raw_output) ||
                 body
        end

        # Interpolate variables
        variables = build_variables(context, previous_outputs)
        interpolate(body, variables)
      end

      def issue_reference(trigger)
        return "" unless trigger[:issue_number]

        "Closes ##{trigger[:issue_number]}"
      end

      def build_variables(context, previous_outputs)
        trigger = context[:trigger_context] || {}

        {
          "issue_number" => trigger[:issue_number],
          "issue_title" => trigger[:issue_title],
          "pr_number" => trigger[:pr_number],
          "repository" => trigger[:repository],
          "run_id" => context.dig(:pipeline_run, :id)
        }
      end

      def create_pull_request(repository:, title:, body:, head:, base:)
        # Try direct provider API first if provider config available
        if @provider_config
          git_ops = GitOperationsService.new(provider_config: @provider_config, logger: logger)

          # Check for existing PR first
          existing = git_ops.find_pull_request(repo: repository, head: head, base: base)
          return normalize_pr_result(existing) if existing

          result = git_ops.create_pull_request(
            repo: repository,
            title: title,
            head: head,
            base: base,
            body: body
          )
          return normalize_pr_result(result)
        end

        # Fall back to internal API
        response = api_client.post("/api/v1/internal/devops/pull_requests", {
          pull_request: {
            repository: repository,
            title: title,
            body: body,
            head: head,
            base: base
          }
        })

        response.dig("data", "pull_request") || response.dig("data")
      end

      def normalize_pr_result(result)
        # Convert git provider response to expected format
        {
          "number" => result[:number],
          "html_url" => result[:html_url],
          "id" => result[:id],
          "state" => result[:state]
        }
      end

      def fetch_provider_config(context)
        @provider_config ||= context.dig(:pipeline_run, :pipeline, :provider) ||
                             context[:provider_config]
      end
    end
  end
end
