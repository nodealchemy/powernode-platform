# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Run Tests node executor - dispatches test execution to worker
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
      include Concerns::WorkerDispatch

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

        payload = {
          type: "run_command",
          command: test_command,
          working_directory: working_directory,
          environment: environment,
          timeout_seconds: timeout_seconds,
          test_framework: test_framework,
          parallel: parallel,
          coverage: coverage,
          node_id: @node.node_id
        }

        log_info "Dispatching test command: #{test_command}"

        dispatch_to_worker("Devops::StepExecutionJob", payload, queue: "devops_default")
      end

      private

      def detect_test_command
        "npm test"
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
