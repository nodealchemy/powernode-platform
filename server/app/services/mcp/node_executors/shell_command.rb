# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Shell Command node executor - dispatches shell commands to worker
    #
    # Configuration:
    # - command: The shell command to execute
    # - working_directory: Directory to run command in
    # - environment: Environment variables
    # - timeout_seconds: Command timeout
    # - capture_output: Capture stdout/stderr (default: true)
    # - fail_on_error: Fail node if command fails (default: true)
    #
    class ShellCommand < Base
      include Concerns::WorkerDispatch

      protected

      def perform_execution
        log_info "Executing shell command"

        command = resolve_value(configuration["command"])
        working_directory = resolve_value(configuration["working_directory"]) ||
                            get_variable("checkout_path") || "."
        environment = configuration["environment"] || {}
        timeout_seconds = configuration["timeout_seconds"] || 300
        fail_on_error = configuration.fetch("fail_on_error", true)

        validate_configuration!(command)

        payload = {
          type: "run_command",
          command: command,
          working_directory: working_directory,
          environment: environment,
          timeout_seconds: timeout_seconds,
          fail_on_error: fail_on_error,
          node_id: @node.node_id
        }

        log_info "Dispatching command: #{command}"

        dispatch_to_worker("Devops::StepExecutionJob", payload, queue: "devops_default")
      end

      private

      def validate_configuration!(command)
        raise ArgumentError, "command is required" if command.blank?

        dangerous_patterns = [
          /rm\s+-rf\s+\//,
          /mkfs/,
          /dd\s+if=.*of=\/dev/,
          /shutdown|reboot|halt/,
          /chmod\s+777\s+\//
        ]

        dangerous_patterns.each do |pattern|
          if command.match?(pattern)
            raise ArgumentError, "Command contains potentially dangerous pattern"
          end
        end
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
    end
  end
end
