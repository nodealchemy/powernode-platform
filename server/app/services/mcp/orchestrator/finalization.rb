# frozen_string_literal: true

module Mcp
  module Orchestrator
    module Finalization
      def finalize_execution
        @logger.info "[MCP_ORCHESTRATOR] Finalizing workflow execution"

        failed_nodes = @workflow_run.node_executions.where(status: "failed")
        final_status = failed_nodes.any? ? "failed" : "completed"

        transition_state!(:running, final_status.to_sym)

        final_output = generate_final_output

        @workflow_run.update_progress!

        @workflow_run.update!(
          status: final_status,
          completed_at: Time.current,
          output_variables: final_output,
          duration_ms: calculate_total_duration,
          total_cost: calculate_total_cost
        )

        AiOrchestrationChannel.broadcast_workflow_run_event(
          "workflow.execution.completed",
          @workflow_run,
          {
            workflow_run: {
              id: @workflow_run.id,
              run_id: @workflow_run.run_id,
              status: final_status,
              completed_at: @workflow_run.completed_at&.iso8601,
              duration_seconds: (@workflow_run.duration_ms || 0) / 1000.0,
              cost_usd: @workflow_run.total_cost,
              output: final_output,
              outputVariables: final_output,
              output_variables: final_output,
              progress_percentage: 100,
              completed_nodes: @workflow_run.completed_nodes,
              failed_nodes: @workflow_run.failed_nodes,
              total_nodes: @workflow_run.total_nodes
            }
          }
        )

        @event_store.record_event(
          event_type: "workflow.execution.completed",
          event_data: {
            status: final_status,
            duration_ms: calculate_total_duration,
            total_cost: calculate_total_cost,
            nodes_executed: @node_results.count
          }
        )

        @execution_tracer.trace_completion(final_status, final_output)
        broadcast_completion(final_status, final_output)
      end

      def generate_final_output
        end_node = @workflow.workflow_nodes.find_by(node_type: "end")
        end_node_result = end_node ? @node_results[end_node.node_id] : nil

        if end_node_result.present?
          @logger.info "[MCP_ORCHESTRATOR] Using End node output as final workflow output"
          end_node_result
        else
          @logger.warn "[MCP_ORCHESTRATOR] No End node found, generating fallback output"
          {
            workflow_id: @workflow.id,
            run_id: @workflow_run.run_id,
            status: @workflow_run.status,
            execution_summary: {
              total_nodes: @node_results.count,
              execution_path: @execution_context[:execution_path],
              duration_ms: calculate_total_duration,
              total_cost: calculate_total_cost
            },
            variables: @execution_context[:variables],
            node_results: @node_results,
            mcp_metadata: {
              protocol_version: McpProtocolService::MCP_VERSION,
              orchestrator_version: "2.0.0",
              execution_mode: @workflow.mcp_orchestration_config&.dig("execution_mode") || "sequential"
            }
          }
        end
      end

      def handle_execution_failure(error)
        @logger.error "[MCP_ORCHESTRATOR] Workflow execution failed: #{error.message}"

        begin
          transition_state!(@state_machine.current_state, :failed)
        rescue Mcp::AiWorkflowOrchestrator::StateTransitionError
          # State may already be failed
        end

        cleanup_active_nodes(error)

        @workflow_run.update!(
          status: "failed",
          error_details: {
            error_message: error.message,
            exception_class: error.class.name,
            backtrace: error.backtrace&.first(20)
          },
          completed_at: Time.current
        )

        @event_store.record_event(
          event_type: "workflow.execution.failed",
          event_data: {
            error_message: error.message,
            error_class: error.class.name
          }
        )

        @execution_tracer.trace_failure(error)
        broadcast_failure(error)
      end

      def cleanup_active_nodes(error)
        active_nodes = @workflow_run.node_executions.active

        if active_nodes.any?
          @logger.warn "[MCP_ORCHESTRATOR] Cleaning up #{active_nodes.count} active node(s) due to workflow failure"

          active_nodes.each do |node_execution|
            begin
              node_execution.cancel_execution!("Workflow failed: #{error.message}")
              @logger.info "[MCP_ORCHESTRATOR] Cancelled node: #{node_execution.node_id} (#{node_execution.workflow_node.name})"
            rescue StandardError => cleanup_error
              @logger.error "[MCP_ORCHESTRATOR] Failed to cancel node #{node_execution.node_id}: #{cleanup_error.message}"
            end
          end

          @event_store.record_event(
            event_type: "workflow.nodes.cleanup",
            event_data: {
              nodes_cancelled: active_nodes.count,
              reason: "workflow_failure"
            }
          )
        end
      end

      def calculate_total_duration
        return 0 unless @workflow_run.started_at

        ((Time.current - @workflow_run.started_at) * 1000).round
      end

      def calculate_total_cost
        @workflow_run.node_executions.sum(:cost) || 0.0
      end

      def broadcast_completion(status, output)
        McpBroadcastService.broadcast_workflow_event(
          "workflow_execution_completed",
          @workflow.id,
          {
            workflow_run_id: @workflow_run.id,
            run_id: @workflow_run.run_id,
            status: status,
            output: output,
            timestamp: Time.current.iso8601
          },
          @account
        )
      end

      def broadcast_failure(error)
        McpBroadcastService.broadcast_workflow_event(
          "workflow_execution_failed",
          @workflow.id,
          {
            workflow_run_id: @workflow_run.id,
            run_id: @workflow_run.run_id,
            error: error.message,
            timestamp: Time.current.iso8601
          },
          @account
        )
      end
    end
  end
end
