# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Sub-workflow node executor - executes nested workflows as nodes
    #
    # Configuration options:
    #   workflow_id: ID of the sub-workflow to execute (required)
    #   input_mapping: Hash mapping parent variables to sub-workflow inputs
    #   output_mapping: Hash mapping sub-workflow outputs to parent variables
    #   execution_mode: "sync" or "async" (default: "sync")
    #   timeout_seconds: Maximum execution time for sync mode (default: 300)
    #   wait_for_completion: Wait for async workflows to complete (default: false)
    #   inherit_context: Pass parent context to sub-workflow (default: true)
    #
    class SubWorkflow < Base
      DEFAULT_TIMEOUT_SECONDS = 300

      protected

      def perform_execution
        log_info "Executing sub_workflow node"

        # Get configuration
        workflow_id = configuration["workflow_id"]
        input_mapping = configuration["input_mapping"] || {}
        output_mapping = configuration["output_mapping"] || {}
        execution_mode = configuration["execution_mode"] || "sync"
        timeout_seconds = (configuration["timeout_seconds"] || DEFAULT_TIMEOUT_SECONDS).to_i
        inherit_context = configuration.fetch("inherit_context", true)
        wait_for_completion = configuration.fetch("wait_for_completion", false)

        # Validate workflow ID
        if workflow_id.blank?
          return error_result("Sub-workflow ID is required")
        end

        # Load the sub-workflow
        sub_workflow = load_workflow(workflow_id)
        return error_result("Sub-workflow not found: #{workflow_id}") unless sub_workflow

        # Validate sub-workflow is active
        unless sub_workflow.is_active?
          return error_result("Sub-workflow is not active: #{workflow_id}")
        end

        log_info "Executing sub-workflow: #{sub_workflow.name} (#{execution_mode})"

        # Build input variables for sub-workflow
        sub_workflow_input = build_sub_workflow_input(input_mapping, inherit_context)

        # Execute based on mode
        result = case execution_mode
        when "async"
                  execute_async(sub_workflow, sub_workflow_input, wait_for_completion, timeout_seconds)
        else
                  execute_sync(sub_workflow, sub_workflow_input, timeout_seconds)
        end

        # Apply output mapping if successful
        if result[:success] && output_mapping.present?
          apply_output_mapping(result[:output], output_mapping)
        end

        result
      end

      private

      def load_workflow(workflow_id)
        # Support both UUID and slug lookup
        if workflow_id =~ /^[0-9a-f-]{36}$/i
          AiWorkflow.find_by(id: workflow_id)
        else
          AiWorkflow.find_by(slug: workflow_id)
        end
      end

      def build_sub_workflow_input(input_mapping, inherit_context)
        input = {}

        # Inherit context from parent if enabled
        if inherit_context
          input = (input_data || {}).deep_dup
        end

        # Apply explicit input mappings
        input_mapping.each do |sub_var, source|
          value = resolve_mapping_source(source)
          input[sub_var.to_s] = value
        end

        input
      end

      def resolve_mapping_source(source)
        case source
        when String
          if source.start_with?("$")
            # Variable reference
            get_variable(source[1..])
          elsif source.start_with?("{{") && source.end_with?("}}")
            # Template variable
            var_name = source[2..-3]
            get_variable(var_name)
          else
            # Literal value
            source
          end
        when Hash
          source.transform_values { |v| resolve_mapping_source(v) }
        when Array
          source.map { |v| resolve_mapping_source(v) }
        else
          source
        end
      end

      def execute_sync(sub_workflow, sub_workflow_input, timeout_seconds)
        start_time = Time.current

        begin
          # Create a new run for the sub-workflow
          sub_run = sub_workflow.ai_workflow_runs.create!(
            status: "pending",
            input_data: sub_workflow_input,
            started_at: Time.current,
            metadata: {
              parent_run_id: @node_execution&.ai_workflow_run_id,
              parent_node_id: @node.node_id,
              triggered_by: "sub_workflow_node"
            }
          )

          # Create orchestrator for sub-workflow
          sub_orchestrator = Mcp::AiWorkflowOrchestrator.new(sub_run)

          # Execute with timeout
          Timeout.timeout(timeout_seconds) do
            sub_orchestrator.execute
          end

          # Reload to get final state
          sub_run.reload
          execution_time_ms = ((Time.current - start_time) * 1000).round

          if sub_run.completed?
            success_result(sub_run, execution_time_ms)
          else
            error_result(
              "Sub-workflow did not complete successfully: #{sub_run.status}",
              sub_workflow_run_id: sub_run.id,
              execution_time_ms: execution_time_ms
            )
          end

        rescue Timeout::Error
          execution_time_ms = ((Time.current - start_time) * 1000).round
          error_result(
            "Sub-workflow execution timed out after #{timeout_seconds}s",
            execution_time_ms: execution_time_ms
          )
        rescue StandardError => e
          execution_time_ms = ((Time.current - start_time) * 1000).round
          log_error "Sub-workflow execution failed: #{e.message}"
          error_result(
            "Sub-workflow execution failed: #{e.message}",
            execution_time_ms: execution_time_ms
          )
        end
      end

      def execute_async(sub_workflow, sub_workflow_input, wait_for_completion, timeout_seconds)
        # Create run for sub-workflow
        sub_run = sub_workflow.ai_workflow_runs.create!(
          status: "pending",
          input_data: sub_workflow_input,
          started_at: Time.current,
          metadata: {
            parent_run_id: @node_execution&.ai_workflow_run_id,
            parent_node_id: @node.node_id,
            triggered_by: "sub_workflow_node",
            async: true
          }
        )

        # Schedule async execution
        if defined?(AiWorkflowExecutionJob)
          AiWorkflowExecutionJob.perform_async(sub_run.id)
        else
          # Fallback: execute in thread
          Thread.new do
            Mcp::AiWorkflowOrchestrator.new(sub_run).execute
          rescue StandardError => e
            Rails.logger.error "[SUB_WORKFLOW] Async execution failed: #{e.message}"
          end
        end

        if wait_for_completion
          # Poll for completion
          wait_for_run_completion(sub_run, timeout_seconds)
        else
          # Return immediately with run reference
          {
            output: { run_id: sub_run.id },
            result: {
              sub_workflow_id: sub_workflow.id,
              sub_workflow_run_id: sub_run.id,
              async: true,
              status: "scheduled"
            },
            metadata: {
              node_id: @node.node_id,
              node_type: "sub_workflow",
              executed_at: Time.current.iso8601,
              sub_workflow_name: sub_workflow.name
            },
            success: true
          }
        end
      end

      def wait_for_run_completion(sub_run, timeout_seconds)
        start_time = Time.current
        poll_interval = 1 # seconds

        loop do
          elapsed = Time.current - start_time

          if elapsed > timeout_seconds
            return error_result(
              "Timed out waiting for sub-workflow completion",
              sub_workflow_run_id: sub_run.id,
              execution_time_ms: (elapsed * 1000).round
            )
          end

          sub_run.reload

          case sub_run.status
          when "completed"
            return success_result(sub_run, (elapsed * 1000).round)
          when "failed", "cancelled"
            return error_result(
              "Sub-workflow #{sub_run.status}",
              sub_workflow_run_id: sub_run.id,
              execution_time_ms: (elapsed * 1000).round
            )
          end

          sleep(poll_interval)
        end
      end

      def apply_output_mapping(output, output_mapping)
        output_mapping.each do |parent_var, source_path|
          value = extract_value(output, source_path)
          set_variable(parent_var.to_s, value) if value.present?
        end
      end

      def extract_value(data, path)
        return data if path.blank? || path == "$"

        parts = path.to_s.split(".")
        result = data

        parts.each do |part|
          if result.is_a?(Hash)
            result = result[part] || result[part.to_sym]
          elsif result.is_a?(Array) && part =~ /^\d+$/
            result = result[part.to_i]
          else
            return nil
          end
          return nil if result.nil?
        end

        result
      end

      def success_result(sub_run, execution_time_ms)
        sub_workflow = sub_run.ai_workflow

        {
          output: sub_run.output_data || {},
          result: {
            sub_workflow_id: sub_workflow.id,
            sub_workflow_run_id: sub_run.id,
            sub_workflow_completed: true,
            status: sub_run.status
          },
          data: {
            sub_workflow_name: sub_workflow.name,
            node_executions_count: sub_run.ai_workflow_node_executions.count,
            total_cost: sub_run.total_cost
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "sub_workflow",
            executed_at: Time.current.iso8601,
            execution_time_ms: execution_time_ms
          },
          success: true
        }
      end

      def error_result(message, sub_workflow_run_id: nil, execution_time_ms: 0)
        {
          output: {},
          result: {
            sub_workflow_completed: false,
            sub_workflow_run_id: sub_workflow_run_id,
            error_message: message
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "sub_workflow",
            executed_at: Time.current.iso8601,
            execution_time_ms: execution_time_ms,
            error: true
          },
          success: false
        }
      end
    end
  end
end
