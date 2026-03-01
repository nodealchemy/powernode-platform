# frozen_string_literal: true

module Devops
  module StepHandlers
    # Base class for pipeline step handlers
    class Base
      attr_reader :api_client, :logger

      def initialize(api_client:, logger:)
        @api_client = api_client
        @logger = logger
      end

      # Execute the step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context (pipeline run info, trigger context)
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        raise NotImplementedError, "Subclasses must implement the execute method"
      end

      protected

      # Log info message
      def log_info(message, **metadata)
        formatted = format_log_message(message, **metadata)
        logger.info formatted
        formatted
      end

      # Log error message
      def log_error(message, exception = nil, **metadata)
        error_metadata = {
          exception: exception&.class&.name,
          exception_message: exception&.message
        }.merge(metadata).compact

        formatted = format_log_message(message, **error_metadata)
        logger.error formatted
        formatted
      end

      # Log warning message
      def log_warn(message, **metadata)
        formatted = format_log_message(message, **metadata)
        logger.warn formatted
        formatted
      end

      # Format log message with metadata
      def format_log_message(message, **metadata)
        if metadata.any?
          "#{message} | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}"
        else
          message
        end
      end

      # Execute a shell command
      # @param command [String] Command to execute
      # @param working_directory [String, nil] Working directory
      # @param timeout [Integer] Timeout in seconds
      # @return [Hash] Result with :success, :output, :error, :exit_code
      def execute_shell_command(command, working_directory: nil, timeout: 300)
        output = nil
        error_output = nil
        exit_status = nil

        Open3.popen3(command, chdir: working_directory || Dir.pwd) do |stdin, stdout, stderr, wait_thr|
          stdin.close

          Timeout.timeout(timeout) do
            output = stdout.read
            error_output = stderr.read
            exit_status = wait_thr.value
          end
        end

        {
          success: exit_status&.success?,
          output: output,
          error: error_output,
          exit_code: exit_status&.exitstatus || 1
        }
      rescue Timeout::Error
        {
          success: false,
          output: output,
          error: "Command timed out after #{timeout}s",
          exit_code: -1
        }
      end

      # Interpolate variables in a string
      # @param template [String] Template with {{ variable }} placeholders
      # @param variables [Hash] Variables to interpolate
      # @return [String] Interpolated string
      def interpolate(template, variables)
        return template unless template.is_a?(String)

        result = template.dup

        # Replace {{ variable }} patterns
        result.gsub!(/\{\{\s*(\w+(?:\.\w+)*)\s*\}\}/) do |match|
          keys = ::Regexp.last_match(1).split(".")
          value = dig_value(variables, keys)
          value.nil? ? match : value.to_s
        end

        # Replace ${{ variable }} patterns (GitHub Actions style)
        result.gsub!(/\$\{\{\s*(\w+(?:\.\w+)*)\s*\}\}/) do |match|
          keys = ::Regexp.last_match(1).split(".")
          value = dig_value(variables, keys)
          value.nil? ? match : value.to_s
        end

        result
      end

      private

      def dig_value(hash, keys)
        keys.reduce(hash) do |h, key|
          return nil unless h.is_a?(Hash)

          h[key] || h[key.to_sym]
        end
      end
    end
  end
end
