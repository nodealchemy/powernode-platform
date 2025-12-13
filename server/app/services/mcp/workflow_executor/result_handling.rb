# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module ResultHandling
      # Handle successful node execution
      #
      # @param node [AiWorkflowNode] Executed node
      # @param node_execution [AiWorkflowNodeExecution] Execution record
      # @param result [Hash] Execution result
      def handle_node_success(node, node_execution, result)
        log_info "Node completed successfully: #{node.node_id}"

        # Store result
        @node_results[node.node_id] = result

        # Update execution context
        if result[:output_data].present?
          update_execution_context(node, result[:output_data])
        end

        # Update execution record using state transition method to trigger broadcasts
        # CRITICAL FIX: Use complete_execution! instead of update! to trigger WebSocket broadcasts
        node_execution.complete_execution!(
          result[:output_data],
          result[:cost] || 0  # Pass cost if present
        )

        # Update additional metadata if present (complete_execution! doesn't handle all fields)
        if result[:execution_time_ms].present? || result[:metadata].present?
          node_execution.update!(
            duration_ms: result[:execution_time_ms],
            metadata: (node_execution.metadata || {}).merge(result[:metadata] || {})
          )
        end

        # Record event
        @event_store.record_node_completed(node, node_execution, result)

        # Broadcast to WebSocket
        broadcast_node_execution(node, "completed", result)

        # Track cost if present
        track_cost("node_execution", result[:cost]) if result[:cost].present?
      end

      # Handle failed node execution
      #
      # @param node [AiWorkflowNode] Failed node
      # @param node_execution [AiWorkflowNodeExecution] Execution record
      # @param error [StandardError] Error that occurred
      def handle_node_failure(node, node_execution, error)
        log_error "Node execution failed: #{node.node_id}", {
          error: error.message,
          node_type: node.node_type
        }

        # Update execution record using state transition method to trigger broadcasts
        # CRITICAL FIX: Use fail_execution! instead of update! to trigger WebSocket broadcasts
        node_execution.fail_execution!(
          error.message,
          {
            exception_class: error.class.name,
            backtrace: error.backtrace&.first(10)
          }
        )

        # Record event
        @event_store.record_node_failed(node, node_execution, error)

        # Broadcast to WebSocket
        broadcast_node_execution(node, "failed", { error: error.message })
      end

      # Handle execution failure
      #
      # @param error [StandardError] Error that occurred
      def handle_execution_failure(error)
        log_error "Workflow execution failed", {
          workflow_id: @workflow.id,
          run_id: @workflow_run.run_id,
          error: error.message
        }

        # Transition to failed state
        @state_manager.transition_to_failed

        # Record event
        @event_store.record_execution_failed(error)

        # Update workflow run
        @workflow_run.update!(
          status: "failed",
          error_details: {
            error_message: error.message,
            exception_class: error.class.name,
            backtrace: error.backtrace&.first(20)
          },
          completed_at: Time.current
        )
      end

      # Generate final execution result
      #
      # @return [Hash] Execution result
      def generate_execution_result
        {
          status: determine_final_status,
          node_count: @node_results.count,
          execution_path: @execution_context[:execution_path],
          variables: @execution_context[:variables],
          node_results: @node_results,
          duration_ms: calculate_execution_duration,
          total_cost: calculate_total_cost
        }
      end

      # Determine final execution status
      #
      # @return [String] Status (completed or failed)
      def determine_final_status
        failed_nodes = @workflow_run.ai_workflow_node_executions.where(status: "failed")
        failed_nodes.any? ? "failed" : "completed"
      end

      # Calculate total execution duration
      #
      # @return [Integer] Duration in milliseconds
      def calculate_execution_duration
        return 0 unless @workflow_run.started_at

        ((Time.current - @workflow_run.started_at) * 1000).round
      end

      # Calculate total cost
      #
      # @return [Float] Total cost in USD
      def calculate_total_cost
        @workflow_run.ai_workflow_node_executions.sum(:cost) || 0.0
      end
    end
  end
end
