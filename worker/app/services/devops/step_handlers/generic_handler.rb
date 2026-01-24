# frozen_string_literal: true

module Devops
  module StepHandlers
    # Generic handler for custom step types
    class GenericHandler < Base
      # Execute generic step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting generic step")

        # Determine execution mode
        if config["uses"].present?
          # GitHub Actions-style action reference
          execute_action(config, context, previous_outputs, logs)
        elsif config["run"].present?
          # Shell command execution
          execute_shell(config, context, previous_outputs, logs)
        elsif config["script"].present?
          # Multi-line script execution
          execute_script(config, context, previous_outputs, logs)
        else
          # No-op step (might be used for placeholder or conditional steps)
          logs << log_info("No-op step - nothing to execute")

          {
            outputs: {},
            logs: logs.join("\n")
          }
        end
      end

      private

      def execute_action(config, context, previous_outputs, logs)
        action = config["uses"]
        inputs = config["with"] || {}

        logs << log_info("Executing action", action: action)

        # For now, we'll skip actual action execution
        # This would require implementing action runners for various action types
        logs << log_warn("Action execution not fully implemented", action: action)

        {
          outputs: {
            action: action,
            skipped: true,
            reason: "Action execution not yet implemented"
          },
          logs: logs.join("\n")
        }
      end

      def execute_shell(config, context, previous_outputs, logs)
        command = config["run"]
        workspace = previous_outputs.dig("checkout", :workspace) ||
                    config["working_directory"] ||
                    Dir.pwd

        # Interpolate variables
        variables = build_variables(context, previous_outputs)
        command = interpolate(command, variables)

        logs << log_info("Executing shell command")

        result = execute_shell_command(
          command,
          working_directory: workspace,
          timeout: (config["timeout_minutes"]&.to_i || 10) * 60
        )

        if result[:success]
          logs << log_info("Shell command completed")

          {
            outputs: {
              output: result[:output],
              exit_code: result[:exit_code]
            },
            logs: logs.join("\n") + "\n\n--- Output ---\n" + result[:output]
          }
        else
          raise StandardError, "Shell command failed: #{result[:error]}"
        end
      end

      def execute_script(config, context, previous_outputs, logs)
        script = config["script"]
        workspace = previous_outputs.dig("checkout", :workspace) ||
                    config["working_directory"] ||
                    Dir.pwd

        # Interpolate variables
        variables = build_variables(context, previous_outputs)
        script = interpolate(script, variables)

        logs << log_info("Executing script")

        # Determine shell
        shell = config["shell"] || "bash"

        # Create temp script file
        script_file = File.join(Dir.tmpdir, "devops_script_#{SecureRandom.hex(8)}.sh")
        File.write(script_file, "#!/usr/bin/env #{shell}\n#{script}")
        File.chmod(0o755, script_file)

        begin
          result = execute_shell_command(
            script_file,
            working_directory: workspace,
            timeout: (config["timeout_minutes"]&.to_i || 10) * 60
          )

          if result[:success]
            logs << log_info("Script completed")

            {
              outputs: {
                output: result[:output],
                exit_code: result[:exit_code]
              },
              logs: logs.join("\n") + "\n\n--- Output ---\n" + result[:output]
            }
          else
            raise StandardError, "Script failed: #{result[:error]}"
          end
        ensure
          FileUtils.rm_f(script_file)
        end
      end

      def build_variables(context, previous_outputs)
        trigger = context[:trigger_context] || {}

        {
          "workspace" => previous_outputs.dig("checkout", :workspace),
          "repository" => trigger[:repository],
          "branch" => trigger[:head_branch] || trigger[:ref],
          "commit_sha" => trigger[:head_sha] || trigger[:after],
          "pr_number" => trigger[:pr_number],
          "issue_number" => trigger[:issue_number]
        }.compact
      end
    end
  end
end
