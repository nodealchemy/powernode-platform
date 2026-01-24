# frozen_string_literal: true

module Devops
  # Executes Claude Code commands
  # Queue: devops_high (long timeout)
  # Retry: 1
  class ClaudeInvokeJob < BaseJob
    sidekiq_options queue: "devops_high", retry: 1

    # Execute Claude Code command
    # @param invocation_id [String] The invocation tracking ID
    # @param prompt [String] The prompt to execute
    # @param options [Hash] Additional options (model, working_directory, etc.)
    def execute(invocation_id, prompt, options = {})
      log_info "Starting Claude Code invocation", invocation_id: invocation_id

      options = options.deep_symbolize_keys

      # Set up authentication environment
      setup_authentication(options)

      # Execute Claude Code CLI
      result = execute_claude_command(prompt, options)

      # Report results back to backend
      report_invocation_result(invocation_id, result)

      log_info "Claude invocation completed", invocation_id: invocation_id

      result
    rescue StandardError => e
      log_error "Claude invocation failed", e, invocation_id: invocation_id

      report_invocation_error(invocation_id, e)

      raise
    end

    private

    def setup_authentication(options)
      # Authentication is set via environment variables
      # The worker should have these configured or passed in options
      if options[:provider] == "bedrock"
        ENV["CLAUDE_CODE_USE_BEDROCK"] = "1"
        ENV["AWS_REGION"] = options[:aws_region] || "us-east-1"
      elsif options[:provider] == "vertex"
        ENV["CLAUDE_CODE_USE_VERTEX"] = "1"
        ENV["GOOGLE_CLOUD_PROJECT"] = options[:google_project]
      end
      # Default: use ANTHROPIC_API_KEY from environment
    end

    def execute_claude_command(prompt, options)
      # Build the Claude command
      cmd_parts = ["claude"]

      # Add print mode for output
      cmd_parts << "--print"

      # Add model if specified
      if options[:model].present?
        cmd_parts << "--model"
        cmd_parts << options[:model]
      end

      # Add session ID if specified
      if options[:session_id].present?
        cmd_parts << "--session-id"
        cmd_parts << options[:session_id]
      end

      # Add prompt via stdin to handle special characters
      full_command = cmd_parts.join(" ")

      log_info "Executing Claude command", command: full_command.truncate(100)

      # Execute with timeout
      timeout_seconds = options[:timeout_seconds] || 600
      output = nil
      error_output = nil
      exit_status = nil

      Open3.popen3(full_command, chdir: options[:working_directory] || Dir.pwd) do |stdin, stdout, stderr, wait_thr|
        stdin.write(prompt)
        stdin.close

        # Read with timeout
        begin
          Timeout.timeout(timeout_seconds) do
            output = stdout.read
            error_output = stderr.read
            exit_status = wait_thr.value
          end
        rescue Timeout::Error
          Process.kill("TERM", wait_thr.pid)
          raise StandardError, "Claude command timed out after #{timeout_seconds}s"
        end
      end

      if exit_status&.success?
        {
          success: true,
          output: output,
          exit_code: exit_status.exitstatus
        }
      else
        {
          success: false,
          output: output,
          error: error_output,
          exit_code: exit_status&.exitstatus || 1
        }
      end
    end

    def report_invocation_result(invocation_id, result)
      api_client.patch("/api/v1/internal/devops/claude_invocations/#{invocation_id}", {
        claude_invocation: {
          status: result[:success] ? "success" : "failed",
          output: result[:output],
          error: result[:error],
          exit_code: result[:exit_code],
          completed_at: Time.current.iso8601
        }
      })
    rescue StandardError => e
      log_warn "Failed to report invocation result", exception: e.message
    end

    def report_invocation_error(invocation_id, exception)
      api_client.patch("/api/v1/internal/devops/claude_invocations/#{invocation_id}", {
        claude_invocation: {
          status: "failed",
          error: exception.message,
          completed_at: Time.current.iso8601
        }
      })
    rescue StandardError => e
      log_warn "Failed to report invocation error", exception: e.message
    end
  end
end
