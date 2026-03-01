# frozen_string_literal: true

module Devops
  module StepHandlers
    # Handles generic command execution steps
    class RunCommandHandler < Base
      BLOCKED_COMMAND_PATTERNS = [
        /sudo/i,
        /rm\s+-rf/i,
        /rm\s+\//i,
        /dd\s+if=/i,
        /mkfs/i,
        /chmod\s+777/i,
        /:\(\)\{:\|:&\}/i,
        /eval\s/i,
        /`[^`]+`/,
        /\$\([^)]+\)/,
        />\s*\/dev\/sd/i,
      ].freeze

      # Execute run command step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting run command step")

        command = config["command"]
        unless command.present?
          raise StandardError, "No command specified"
        end

        # Determine working directory
        workspace = previous_outputs.dig("checkout", :workspace)
        working_dir = config["working_directory"] || workspace || Dir.pwd

        # Interpolate variables in command
        variables = build_variables(context, previous_outputs)
        command = interpolate(command, variables)

        # Validate command against dangerous patterns
        validate_command!(command)

        logs << log_info("Executing command", command: command.truncate(100))

        # Set up environment variables
        env = build_environment(config, context)

        # Execute the command
        timeout = (config["timeout_minutes"]&.to_i || 10) * 60
        result = execute_command_with_env(command, working_dir, env, timeout)

        if result[:success]
          logs << log_info("Command completed successfully", exit_code: result[:exit_code])

          {
            outputs: {
              output: result[:output],
              exit_code: result[:exit_code]
            },
            logs: logs.join("\n") + "\n\n--- Command Output ---\n" + result[:output]
          }
        else
          logs << log_error("Command failed", exit_code: result[:exit_code])

          if config["continue_on_error"]
            log_warn("Continuing despite error (continue_on_error: true)")

            {
              outputs: {
                output: result[:output],
                error: result[:error],
                exit_code: result[:exit_code],
                failed: true
              },
              logs: logs.join("\n") + "\n\n--- Command Output ---\n" + (result[:output] || "") +
                    "\n\n--- Error Output ---\n" + (result[:error] || "")
            }
          else
            raise StandardError, "Command failed with exit code #{result[:exit_code]}: #{result[:error]}"
          end
        end
      end

      private

      def build_variables(context, previous_outputs)
        trigger = context[:trigger_context] || {}

        {
          "workspace" => previous_outputs.dig("checkout", :workspace),
          "repository" => trigger[:repository],
          "branch" => trigger[:head_branch] || trigger[:ref],
          "commit_sha" => trigger[:head_sha] || trigger[:after],
          "pr_number" => trigger[:pr_number],
          "issue_number" => trigger[:issue_number],
          "run_id" => context.dig(:pipeline_run, :id),
          "run_number" => context.dig(:pipeline_run, :run_number)
        }.compact
      end

      def build_environment(config, context)
        env = {}

        # Add config-specified environment variables
        if config["env"].is_a?(Hash)
          env.merge!(config["env"].transform_keys(&:to_s))
        end

        # Add CI/CD environment variables
        env["CI"] = "true"
        env["CI_PIPELINE_ID"] = context.dig(:pipeline_run, :pipeline, :id).to_s
        env["CI_PIPELINE_RUN_ID"] = context.dig(:pipeline_run, :id).to_s
        env["CI_PIPELINE_RUN_NUMBER"] = context.dig(:pipeline_run, :run_number).to_s

        trigger = context[:trigger_context] || {}
        env["CI_REPOSITORY"] = trigger[:repository].to_s if trigger[:repository]
        env["CI_BRANCH"] = (trigger[:head_branch] || trigger[:ref]).to_s if trigger[:head_branch] || trigger[:ref]
        env["CI_COMMIT_SHA"] = (trigger[:head_sha] || trigger[:after]).to_s if trigger[:head_sha] || trigger[:after]

        env.compact
      end

      def validate_command!(command)
        BLOCKED_COMMAND_PATTERNS.each do |pattern|
          if command.match?(pattern)
            raise StandardError, "Command blocked by security policy: matches dangerous pattern"
          end
        end
      end

      def execute_command_with_env(command, working_dir, env, timeout)
        output = nil
        error_output = nil
        exit_status = nil

        # Merge environment variables
        full_env = ENV.to_h.merge(env)

        Open3.popen3(full_env, command, chdir: working_dir) do |stdin, stdout, stderr, wait_thr|
          stdin.close

          begin
            Timeout.timeout(timeout) do
              output = stdout.read
              error_output = stderr.read
              exit_status = wait_thr.value
            end
          rescue Timeout::Error
            Process.kill("TERM", wait_thr.pid) rescue nil
            return {
              success: false,
              output: output,
              error: "Command timed out after #{timeout}s",
              exit_code: -1
            }
          end
        end

        {
          success: exit_status&.success?,
          output: output,
          error: error_output,
          exit_code: exit_status&.exitstatus || 1
        }
      end
    end
  end
end
