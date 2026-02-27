# frozen_string_literal: true

require "shellwords"
require_relative "../git_operations_service"

module Devops
  module StepHandlers
    # Handles checkout step - clones repository to workspace
    # Supports multiple git providers (Gitea, GitLab, GitHub) via API
    class CheckoutHandler < Base
      # Execute checkout step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting checkout step")

        # Load provider config for API-driven operations
        fetch_provider_config(context)

        # Get repository info from context
        repository = context.dig(:trigger_context, :repository) ||
                     context.dig(:pipeline_run, :repository)

        unless repository
          raise StandardError, "No repository specified in context"
        end

        # Fetch repository details (via provider API or internal API)
        repo_data = fetch_repository_data(repository, context)

        # Set up workspace directory
        workspace_dir = config["workspace"] || create_workspace_dir(context)

        logs << log_info("Cloning repository",
                         repository: repository,
                         workspace: workspace_dir,
                         provider: @provider_config&.dig(:type) || "internal")

        # Clone the repository
        clone_result = clone_repository(repo_data, workspace_dir, config)

        unless clone_result[:success]
          raise StandardError, "Failed to clone repository: #{clone_result[:error]}"
        end

        logs << log_info("Repository cloned successfully")

        # Checkout specific ref if provided
        ref = determine_ref(config, context)
        if ref.present?
          logs << log_info("Checking out ref", ref: ref)
          checkout_ref(workspace_dir, ref)
        end

        logs << log_info("Checkout completed")

        {
          outputs: {
            workspace: workspace_dir,
            repository: repository,
            ref: ref,
            commit_sha: get_current_sha(workspace_dir),
            provider_type: @provider_config&.dig(:type)
          },
          logs: logs.join("\n")
        }
      end

      private

      def fetch_provider_config(context)
        @provider_config ||= context.dig(:pipeline_run, :pipeline, :provider) ||
                             context[:provider_config]
      end

      def fetch_repository_data(repository, context)
        # Try to get from pipeline context first
        if context.dig(:pipeline_run, :pipeline, :repository_data)
          return context.dig(:pipeline_run, :pipeline, :repository_data)
        end

        # If provider config available, fetch via git provider API
        if @provider_config
          git_ops = GitOperationsService.new(provider_config: @provider_config, logger: logger)
          provider_repo = git_ops.get_repository(repo: repository)

          if provider_repo
            return {
              "clone_url" => provider_repo[:clone_url],
              "ssh_url" => provider_repo[:ssh_url],
              "default_branch" => provider_repo[:default_branch],
              "provider" => {
                "type" => @provider_config[:type],
                "api_token" => @provider_config[:api_token],
                "api_url" => @provider_config[:api_url]
              }
            }
          end
        end

        # Fall back to internal API
        response = api_client.get("/api/v1/internal/git/repositories/lookup", {
          full_name: repository
        })
        response.dig("data")
      end

      def create_workspace_dir(context)
        run_id = context.dig(:pipeline_run, :id) || SecureRandom.hex(8)
        dir = File.join(Dir.tmpdir, "devops_workspace_#{run_id}")
        FileUtils.mkdir_p(dir)
        dir
      end

      def clone_repository(repo_data, workspace_dir, config)
        clone_url = build_clone_url(repo_data)
        depth = config["fetch_depth"] || 0

        cmd_parts = ["git", "clone"]
        cmd_parts += ["--depth", depth.to_s] if depth > 0
        cmd_parts << clone_url
        cmd_parts << workspace_dir

        execute_shell_command(cmd_parts.join(" "), timeout: 300)
      end

      def build_clone_url(repo_data)
        # Clone URL should include authentication
        clone_url = repo_data["clone_url"]
        api_token = repo_data.dig("provider", "api_token")

        if api_token && clone_url.start_with?("https://")
          uri = URI.parse(clone_url)
          uri.user = "git"
          uri.password = api_token
          uri.to_s
        else
          clone_url
        end
      end

      def determine_ref(config, context)
        # Priority: config > trigger context > default branch
        config["ref"] ||
          context.dig(:trigger_context, :head_sha) ||
          context.dig(:trigger_context, :after) ||
          context.dig(:trigger_context, :head_branch)
      end

      def checkout_ref(workspace_dir, ref)
        validate_git_ref!(ref)

        escaped_ref = Shellwords.shellescape(ref)
        result = execute_shell_command("git checkout #{escaped_ref}", working_directory: workspace_dir)

        unless result[:success]
          # Try fetching and checking out
          execute_shell_command("git fetch origin #{escaped_ref}", working_directory: workspace_dir)
          result = execute_shell_command("git checkout #{escaped_ref}", working_directory: workspace_dir)

          unless result[:success]
            raise StandardError, "Failed to checkout ref #{ref}: #{result[:error]}"
          end
        end
      end

      def validate_git_ref!(ref)
        unless ref.match?(/\A[\w.\-\/]+\z/)
          raise StandardError, "Invalid git ref format: #{ref}. Only alphanumeric, dots, hyphens, and slashes allowed."
        end
      end

      def get_current_sha(workspace_dir)
        result = execute_shell_command("git rev-parse HEAD", working_directory: workspace_dir)
        result[:output]&.strip
      end
    end
  end
end
