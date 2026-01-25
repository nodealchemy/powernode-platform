# frozen_string_literal: true

module Ai
  module Workflows
    # Service for executing workflows and coordinating with worker services
    #
    # Consolidates workflow execution logic from WorkflowsController including:
    # - Validating workflow can execute
    # - Preparing execution context
    # - Enqueuing workflow execution jobs
    # - Coordinating with realtime channels
    #
    # Usage:
    #   service = Ai::Workflows::ExecutionService.new(workflow: @workflow, user: current_user)
    #   result = service.execute(input_variables: { name: "test" })
    #
    class ExecutionService
      attr_reader :workflow, :user, :account

      # Initialize the service
      # @param workflow [Ai::Workflow] The workflow to execute
      # @param user [User] The user initiating execution
      # @param account [Account] Optional account override
      def initialize(workflow:, user:, account: nil)
        @workflow = workflow
        @user = user
        @account = account || workflow.account
      end

      # Execute a workflow
      # @param input_variables [Hash] Input variables for the workflow
      # @param trigger_type [String] Type of trigger
      # @param trigger_context [Hash] Additional trigger context
      # @param realtime [Boolean] Whether to broadcast updates in realtime
      # @return [Result] Result object with run and execution details
      def execute(input_variables: {}, trigger_type: "manual", trigger_context: {}, realtime: true)
        # Validate workflow can execute
        validation = validate_execution
        return validation if validation.failure?

        # Validate required providers are available
        provider_validation = validate_providers
        return provider_validation if provider_validation.failure?

        # Create the workflow run
        run_service = RunManagementService.new(workflow: workflow, user: user, account: account)
        run_result = run_service.create_run(
          input_variables: input_variables,
          trigger_type: trigger_type,
          trigger_context: trigger_context
        )

        return run_result if run_result.failure?

        run = run_result.run

        # Enqueue execution job
        enqueue_result = enqueue_execution(run, realtime: realtime)
        return enqueue_result if enqueue_result.failure?

        Result.success(
          run: run,
          channel_id: "ai_workflow_execution_#{run.run_id}",
          execution_url: "/api/v1/ai/workflows/#{workflow.id}/runs/#{run.run_id}"
        )
      rescue ProviderUnavailableError => e
        Result.failure(error: e.message, error_type: "provider_unavailable")
      rescue ValidationError => e
        Result.failure(error: e.message, error_type: "validation_error")
      rescue StandardError => e
        Rails.logger.error("Workflow execution failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        Result.failure(error: "Failed to start workflow execution: #{e.message}")
      end

      # Execute workflow as dry run (validation only, no actual execution)
      # @param input_variables [Hash] Input variables to validate
      # @return [Result] Result object with validation status
      def dry_run(input_variables: {})
        validation = validate_execution
        return validation if validation.failure?

        # Validate input variables against schema
        input_validation = validate_input_variables(input_variables)
        return input_validation if input_validation.failure?

        # Validate all nodes
        node_validation = validate_all_nodes
        return node_validation if node_validation.failure?

        # Check provider availability
        provider_validation = validate_providers(fail_fast: false)

        Result.success(
          valid: true,
          workflow_status: workflow.status,
          node_count: workflow.nodes.count,
          edge_count: workflow.edges.count,
          estimated_cost: estimate_execution_cost(input_variables),
          provider_status: provider_validation.success? ? "all_available" : "some_unavailable",
          provider_issues: provider_validation.issues || [],
          input_schema: workflow.configuration["input_schema"] || {},
          recommendations: build_execution_recommendations
        )
      end

      # Duplicate and execute a workflow
      # @param input_variables [Hash] Input variables
      # @return [Result] Result object with cloned run
      def duplicate_and_execute(input_variables: {})
        duplicated_workflow = workflow.duplicate(account, user)

        unless duplicated_workflow.persisted?
          return Result.failure(error: duplicated_workflow.errors.full_messages.join(", "))
        end

        # Execute the duplicated workflow
        ExecutionService.new(workflow: duplicated_workflow, user: user, account: account)
                        .execute(input_variables: input_variables)
      end

      private

      # Validate that workflow can be executed
      # @return [Result] Validation result
      def validate_execution
        unless workflow.can_execute?
          return Result.failure(
            error: "Workflow cannot be executed",
            details: build_execution_error_details
          )
        end

        Result.success
      end

      # Validate required providers are available
      # @param fail_fast [Boolean] Whether to fail on first unavailable provider
      # @return [Result] Validation result
      def validate_providers(fail_fast: true)
        issues = []

        # Get all AI agent nodes
        agent_nodes = workflow.nodes.where(node_type: "ai_agent")

        agent_nodes.each do |node|
          provider_id = node.configuration&.dig("provider_id")
          next unless provider_id

          provider = ::Ai::Provider.find_by(id: provider_id)

          if provider.nil?
            issues << { node: node.name, issue: "Provider not found" }
            return Result.failure(error: "Provider not found for node: #{node.name}") if fail_fast
          elsif !provider.active?
            issues << { node: node.name, issue: "Provider not active" }
            return Result.failure(error: "Provider not active for node: #{node.name}") if fail_fast
          end
        end

        if issues.any? && fail_fast
          Result.failure(error: "Provider validation failed", issues: issues)
        else
          Result.success(issues: issues)
        end
      end

      # Validate input variables against workflow schema
      # @param input_variables [Hash] Input variables to validate
      # @return [Result] Validation result
      def validate_input_variables(input_variables)
        input_schema = workflow.configuration["input_schema"] || {}
        required_vars = input_schema["required"] || []
        properties = input_schema["properties"] || {}

        missing_vars = required_vars - input_variables.keys.map(&:to_s)

        if missing_vars.any?
          return Result.failure(
            error: "Missing required input variables: #{missing_vars.join(', ')}",
            missing_variables: missing_vars
          )
        end

        # Type validation for provided variables
        type_errors = []
        input_variables.each do |key, value|
          expected_type = properties.dig(key.to_s, "type")
          next unless expected_type

          unless valid_type?(value, expected_type)
            type_errors << "#{key}: expected #{expected_type}, got #{value.class.name.downcase}"
          end
        end

        if type_errors.any?
          return Result.failure(error: "Input type errors: #{type_errors.join('; ')}", type_errors: type_errors)
        end

        Result.success
      end

      # Validate all workflow nodes
      # @return [Result] Validation result
      def validate_all_nodes
        errors = []

        workflow.nodes.each do |node|
          validator = find_node_validator(node.node_type)
          next unless validator

          node_errors = validator.validate(node)
          errors.concat(node_errors.map { |e| "#{node.name}: #{e}" }) if node_errors.any?
        end

        if errors.any?
          Result.failure(error: "Node validation errors: #{errors.first}", all_errors: errors)
        else
          Result.success
        end
      end

      # Enqueue workflow execution job
      # @param run [Ai::WorkflowRun] The run to execute
      # @param realtime [Boolean] Whether to use realtime updates
      # @return [Result] Enqueue result
      def enqueue_execution(run, realtime: true)
        options = {
          "realtime" => realtime,
          "channel_id" => "ai_workflow_execution_#{run.run_id}"
        }

        WorkerJobService.enqueue_ai_workflow_execution(run.run_id, options)
        Result.success
      rescue WorkerJobService::WorkerServiceError => e
        Result.failure(error: "Failed to enqueue execution: #{e.message}")
      end

      # Estimate cost for workflow execution
      # @param input_variables [Hash] Input variables
      # @return [Hash] Estimated cost breakdown
      def estimate_execution_cost(input_variables)
        total_estimated_cost = 0.0
        cost_breakdown = []

        workflow.nodes.where(node_type: "ai_agent").each do |node|
          provider_id = node.configuration&.dig("provider_id")
          model = node.configuration&.dig("model")

          # Get estimated tokens (rough estimate)
          estimated_input_tokens = 1000
          estimated_output_tokens = 500

          # Calculate cost based on provider pricing
          provider = ::Ai::Provider.find_by(id: provider_id)
          if provider
            pricing = provider.pricing || {}
            input_cost = (estimated_input_tokens / 1000.0) * (pricing["input_cost_per_1k"] || 0.001)
            output_cost = (estimated_output_tokens / 1000.0) * (pricing["output_cost_per_1k"] || 0.002)
            node_cost = input_cost + output_cost

            total_estimated_cost += node_cost
            cost_breakdown << {
              node: node.name,
              model: model,
              estimated_cost: node_cost.round(6)
            }
          end
        end

        {
          total: total_estimated_cost.round(6),
          breakdown: cost_breakdown,
          currency: "USD"
        }
      end

      # Build execution error details
      # @return [Hash] Error details
      def build_execution_error_details
        {
          workflow_status: workflow.status,
          node_count: workflow.nodes.count,
          start_node_count: workflow.start_nodes.count,
          end_node_count: workflow.end_nodes.count,
          can_execute: workflow.can_execute?,
          recommendations: build_execution_recommendations
        }
      end

      # Build execution recommendations
      # @return [Array<String>] Recommendations
      def build_execution_recommendations
        recommendations = []

        recommendations << "Add at least one node to the workflow" if workflow.nodes.count.zero?
        recommendations << "Mark at least one node as a start node" if workflow.start_nodes.count.zero?
        recommendations << "Mark at least one node as an end node" if workflow.end_nodes.count.zero?
        recommendations << "Set the workflow status to 'active' or 'published'" unless workflow.active?

        recommendations
      end

      # Check if value matches expected JSON Schema type
      # @param value [Object] Value to check
      # @param expected_type [String] Expected JSON Schema type
      # @return [Boolean] Whether type matches
      def valid_type?(value, expected_type)
        case expected_type
        when "string" then value.is_a?(String)
        when "number", "integer" then value.is_a?(Numeric)
        when "boolean" then value.is_a?(TrueClass) || value.is_a?(FalseClass)
        when "array" then value.is_a?(Array)
        when "object" then value.is_a?(Hash)
        else true
        end
      end

      # Find appropriate validator for node type
      # @param node_type [String] Node type
      # @return [Object, nil] Validator instance or nil
      def find_node_validator(node_type)
        validator_class = "Ai::WorkflowValidators::#{node_type.camelize}Validator".safe_constantize
        validator_class&.new
      end

      # Result wrapper for service operations
      class Result
        attr_reader :success, :data

        def initialize(success:, data: {})
          @success = success
          @data = data
        end

        def self.success(data = {})
          new(success: true, data: data)
        end

        def self.failure(data = {})
          new(success: false, data: data)
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def method_missing(method, *args, &block)
          if data.key?(method)
            data[method]
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          data.key?(method) || super
        end
      end

      # Custom error classes
      class ProviderUnavailableError < StandardError; end
      class ValidationError < StandardError; end
    end
  end
end
