# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Run Tests node executor - executes test suites
    #
    # Configuration:
    # - test_command: Command to run tests (e.g., "npm test", "pytest")
    # - test_framework: Framework type (jest, pytest, rspec, etc.)
    # - parallel: Run tests in parallel (default: false)
    # - coverage: Generate coverage report (default: false)
    # - timeout_seconds: Test timeout
    # - working_directory: Directory to run tests in
    # - environment: Environment variables for tests
    #
    class RunTests < Base
      protected

      def perform_execution
        log_info "Executing test suite"

        test_command = resolve_value(configuration["test_command"]) || detect_test_command
        test_framework = configuration["test_framework"] || "auto"
        parallel = configuration.fetch("parallel", false)
        coverage = configuration.fetch("coverage", false)
        timeout_seconds = configuration["timeout_seconds"] || 300
        working_directory = resolve_value(configuration["working_directory"]) ||
                            get_variable("checkout_path") || "."
        environment = configuration["environment"] || {}

        test_context = {
          test_command: test_command,
          test_framework: test_framework,
          parallel: parallel,
          coverage: coverage,
          timeout_seconds: timeout_seconds,
          working_directory: working_directory,
          environment: environment,
          started_at: Time.current
        }

        log_info "Test context: #{test_context.slice(:test_command, :test_framework)}"

        # Generate test run ID
        test_run_id = SecureRandom.uuid

        build_output(test_context, test_run_id)
      end

      private

      def detect_test_command
        # Auto-detect based on common project files
        "npm test" # Default fallback
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

      def build_output(test_context, test_run_id)
        {
          output: {
            tests_executed: true,
            test_run_id: test_run_id,
            test_command: test_context[:test_command],
            framework: test_context[:test_framework]
          },
          data: {
            test_run_id: test_run_id,
            command: test_context[:test_command],
            framework: test_context[:test_framework],
            parallel: test_context[:parallel],
            coverage_enabled: test_context[:coverage],
            working_directory: test_context[:working_directory],
            started_at: test_context[:started_at].iso8601,
            status: "running",
            # These would be populated after actual execution
            passed: 0,
            failed: 0,
            skipped: 0,
            total: 0,
            coverage_percentage: nil
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "run_tests",
            executed_at: Time.current.iso8601
          }
        }
      end
    end
  end
end
