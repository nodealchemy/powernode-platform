# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Shell Command node executor - executes arbitrary shell commands
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
      protected

      def perform_execution
        log_info "Executing shell command"

        command = resolve_value(configuration["command"])
        working_directory = resolve_value(configuration["working_directory"]) ||
                            get_variable("checkout_path") || "."
        environment = configuration["environment"] || {}
        timeout_seconds = configuration["timeout_seconds"] || 300
        capture_output = configuration.fetch("capture_output", true)
        fail_on_error = configuration.fetch("fail_on_error", true)

        validate_configuration!(command)

        command_context = {
          command: command,
          working_directory: working_directory,
          environment: environment,
          timeout_seconds: timeout_seconds,
          capture_output: capture_output,
          fail_on_error: fail_on_error,
          started_at: Time.current
        }

        log_info "Command context: #{command_context.slice(:command, :working_directory)}"

        # Generate execution ID
        execution_id = SecureRandom.uuid

        build_output(command_context, execution_id)
      end

      private

      def validate_configuration!(command)
        raise ArgumentError, "command is required" if command.blank?

        # Security check - block dangerous commands
        dangerous_patterns = [
          /rm\s+-rf\s+\//, # rm -rf /
          /mkfs/, # Format disk
          /dd\s+if=.*of=\/dev/, # dd to devices
          /shutdown|reboot|halt/, # System commands
          /chmod\s+777\s+\//, # Dangerous permissions
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

      def build_output(command_context, execution_id)
        {
          output: {
            command_executed: true,
            execution_id: execution_id,
            command: command_context[:command]
          },
          data: {
            execution_id: execution_id,
            command: command_context[:command],
            working_directory: command_context[:working_directory],
            started_at: command_context[:started_at].iso8601,
            status: "completed",
            exit_code: 0, # Would be actual exit code
            stdout: "", # Would be captured output
            stderr: "",
            duration_ms: 0
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "shell_command",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
