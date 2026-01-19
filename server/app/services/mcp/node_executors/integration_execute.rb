# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Integration Execute node executor - executes external integrations
    #
    # This node type allows workflows to execute configured integration instances,
    # supporting GitHub Actions, webhooks, MCP servers, and REST APIs.
    #
    # Configuration:
    #   integration_instance_id: UUID of the integration instance to execute
    #   input_mapping: Hash mapping workflow variables to integration inputs
    #   output_mapping: Hash mapping integration outputs to workflow variables
    #   timeout_seconds: Override timeout for this execution
    #   wait_for_completion: Whether to wait for async integrations (default: true)
    #
    class IntegrationExecute < Base
      protected

      def perform_execution
        log_info "Executing integration"

        instance = fetch_integration_instance
        input = build_integration_input
        context = build_execution_context

        log_info "Integration: #{instance.name} (#{instance.integration_template.integration_type})"

        result = IntegrationExecutionService.execute(
          instance: instance,
          input: input,
          triggered_by: triggered_by_info,
          context: context
        )

        if result[:success]
          build_success_output(result)
        else
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
                "Integration execution failed: #{result[:error]}"
        end
      end

      private

      def fetch_integration_instance
        instance_id = configuration["integration_instance_id"]
        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "No integration_instance_id configured" unless instance_id.present?

        instance = IntegrationInstance.find_by(
          id: instance_id,
          account_id: @orchestrator.account.id
        )

        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Integration instance not found: #{instance_id}" unless instance.present?

        raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
              "Integration instance is not active" unless instance.status == "active"

        instance
      end

      def build_integration_input
        input_mapping = configuration["input_mapping"] || {}
        static_input = configuration["static_input"] || {}

        # Start with static input
        input = static_input.deep_dup

        # Apply input mapping from workflow variables
        input_mapping.each do |integration_key, workflow_path|
          value = resolve_workflow_value(workflow_path)
          input[integration_key] = value if value.present?
        end

        # Include input_data from previous nodes if configured
        if configuration["include_input_data"]
          input.merge!(input_data) if input_data.is_a?(Hash)
        end

        input.with_indifferent_access
      end

      def resolve_workflow_value(path)
        return nil if path.blank?

        # Check if it's a variable reference
        if path.start_with?("$.")
          var_name = path[2..]
          return get_variable(var_name)
        end

        # Check if it's a previous node result reference
        if path.start_with?("nodes.")
          parts = path.split(".")
          node_id = parts[1]
          remaining_path = parts[2..].join(".")

          node_result = previous_results[node_id]
          return extract_nested_value(node_result, remaining_path) if node_result.present?
        end

        # Return literal value
        path
      end

      def extract_nested_value(data, path)
        return data if path.blank?

        path.split(".").reduce(data) do |current, key|
          break nil unless current.is_a?(Hash) || current.respond_to?(:[])

          current[key.to_s] || current[key.to_sym]
        end
      end

      def build_execution_context
        {
          workflow_run_id: @orchestrator.workflow_run.id,
          workflow_id: @orchestrator.workflow_run.workflow_id,
          node_id: @node.node_id,
          node_name: @node.name,
          account_id: @orchestrator.account.id,
          user_id: @orchestrator.user&.id,
          variables: @node_context.scoped_variables
        }
      end

      def triggered_by_info
        if @orchestrator.user.present?
          { type: "workflow_node", id: @node.node_id, user_id: @orchestrator.user.id }
        else
          { type: "workflow_node", id: @node.node_id }
        end
      end

      def build_success_output(result)
        output = result[:result] || {}

        # Apply output mapping to workflow variables
        output_mapping = configuration["output_mapping"] || {}
        mapped_variables = {}

        output_mapping.each do |workflow_var, integration_path|
          value = extract_nested_value(output, integration_path)
          if value.present?
            mapped_variables[workflow_var] = value
            set_variable(workflow_var, value)
          end
        end

        # Industry-standard output format (v1.0)
        {
          output: {
            execution_id: result[:execution_id],
            integration_result: output,
            mapped_variables: mapped_variables
          },
          data: {
            execution_time_ms: result[:execution_time_ms],
            success: true
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "integration_execute",
            executed_at: Time.current.iso8601,
            integration_execution_id: result[:execution_id]
          }
        }
      end
    end
  end
end
