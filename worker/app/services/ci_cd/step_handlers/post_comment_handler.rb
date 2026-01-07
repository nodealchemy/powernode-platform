# frozen_string_literal: true

require_relative "../git_operations_service"

module CiCd
  module StepHandlers
    # Handles posting comments to PRs/issues
    # Uses git provider APIs directly for better cross-provider support
    class PostCommentHandler < Base
      # Execute post comment step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting post comment step")

        # Load provider config for direct API access
        fetch_provider_config(context)

        # Get repository and issue/PR number
        repository = context.dig(:trigger_context, :repository)
        issue_number = config["issue_number"] ||
                       context.dig(:trigger_context, :pr_number) ||
                       context.dig(:trigger_context, :issue_number)

        unless repository && issue_number
          raise StandardError, "Repository and issue/PR number are required"
        end

        # Build comment body
        body = build_comment_body(config, context, previous_outputs)

        logs << log_info("Posting comment", repository: repository, issue_number: issue_number)

        # Post the comment via API
        result = post_comment(repository, issue_number, body)

        logs << log_info("Comment posted successfully", comment_id: result["id"])

        {
          outputs: {
            comment_id: result["id"],
            comment_url: result["html_url"]
          },
          logs: logs.join("\n")
        }
      end

      private

      def build_comment_body(config, context, previous_outputs)
        body = nil

        # Get body from file if specified
        if config["body_file"].present?
          workspace = previous_outputs.dig("checkout", :workspace) || Dir.pwd
          file_path = File.join(workspace, config["body_file"])

          if File.exist?(file_path)
            body = File.read(file_path)
          else
            log_warn("Comment body file not found", file: file_path)
          end
        end

        # Get body from previous step output if specified
        if body.nil? && config["body_from"].present?
          step_name, output_key = config["body_from"].split(".")
          body = previous_outputs.dig(step_name, output_key.to_sym) ||
                 previous_outputs.dig(step_name, :raw_output)
        end

        # Fall back to config body
        body ||= config["body"]

        # Interpolate variables
        variables = build_variables(context, previous_outputs)
        body = interpolate(body, variables)

        # Add header/footer if configured
        if config["header"].present?
          body = "#{interpolate(config['header'], variables)}\n\n#{body}"
        end

        if config["footer"].present?
          body = "#{body}\n\n#{interpolate(config['footer'], variables)}"
        end

        # Add default signature
        unless config["no_signature"]
          body = "#{body}\n\n---\n*Powered by Claude Code CI/CD*"
        end

        body
      end

      def build_variables(context, previous_outputs)
        trigger = context[:trigger_context] || {}

        {
          "pr_number" => trigger[:pr_number],
          "issue_number" => trigger[:issue_number],
          "repository" => trigger[:repository],
          "branch" => trigger[:head_branch],
          "commit_sha" => trigger[:head_sha],
          "session_id" => context.dig(:pipeline_run, :id)
        }
      end

      def post_comment(repository, issue_number, body)
        # Try direct provider API first if provider config available
        if @provider_config
          git_ops = GitOperationsService.new(provider_config: @provider_config, logger: logger)
          return git_ops.post_comment(repo: repository, number: issue_number, body: body)
        end

        # Fall back to internal API
        response = api_client.post("/api/v1/internal/ci_cd/comments", {
          comment: {
            repository: repository,
            issue_number: issue_number,
            body: body
          }
        })

        response.dig("data", "comment") || response.dig("data")
      end

      def fetch_provider_config(context)
        @provider_config ||= context.dig(:pipeline_run, :pipeline, :provider) ||
                             context[:provider_config]
      end
    end
  end
end
