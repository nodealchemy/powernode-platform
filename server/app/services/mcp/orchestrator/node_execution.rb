# frozen_string_literal: true

module Mcp
  module Orchestrator
    module NodeExecution
      def execute_node(node)
        @logger.info "[MCP_ORCHESTRATOR] Executing node: #{node.node_id} (#{node.name})"

        node_context = Mcp::NodeExecutionContext.new(
          node: node,
          workflow_run: @workflow_run,
          execution_context: @execution_context,
          previous_results: @node_results
        )

        node_execution = create_node_execution_record(node, node_context)

        begin
          @state_machine.execute_node(node.node_id)
          node_execution.start_execution!

          @event_store.record_event(
            event_type: "node.execution.started",
            event_data: {
              node_id: node.node_id,
              node_type: node.node_type,
              node_name: node.name
            }
          )

          executor = get_mcp_node_executor(node, node_execution, node_context)
          result = executor.execute

          handle_node_success(node, node_execution, result, node_context)

          result

        rescue StandardError => e
          handle_node_failure(node, node_execution, e, node_context)
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "Node #{node.node_id} failed: #{e.message}"
        end
      end

      def get_mcp_node_executor(node, node_execution, node_context)
        executor_class = resolve_executor_class(node.node_type)

        executor_class.new(
          node: node,
          node_execution: node_execution,
          node_context: node_context,
          orchestrator: self
        )
      end

      def handle_node_success(node, node_execution, result, node_context)
        @logger.info "[MCP_ORCHESTRATOR] Node execution successful: #{node.node_id}"

        @node_results[node.node_id] = result

        output_for_context = build_output_for_context(result)
        if output_for_context.present?
          update_execution_context(node, output_for_context)
        end

        if result[:compensation_handler].present?
          @compensation_stack << {
            node_id: node.node_id,
            handler: result[:compensation_handler],
            context: {
              node_id: node.node_id,
              node_type: node.node_type,
              variables: node_context.scoped_variables.deep_dup
            }
          }
        end

        node_execution.complete_execution!(
          output_for_context,
          result.dig(:metadata, :cost) || result[:cost] || 0.0
        )

        node_execution.update_run_progress
        cost = result.dig(:metadata, :cost) || result[:cost] || 0.0
        node_execution.add_cost_to_run_explicit(cost) if cost > 0

        if result.dig(:metadata, :duration_ms).present?
          node_execution.update_column(:duration_ms, result.dig(:metadata, :duration_ms))
        end
        if result[:metadata].present?
          serializable_metadata = result[:metadata].deep_dup.except(:compensation_handler)
          node_execution.update_column(:metadata, node_execution.metadata.merge(serializable_metadata))
        end

        @event_store.record_event(
          event_type: "node.execution.completed",
          event_data: {
            node_id: node.node_id,
            node_type: node.node_type,
            duration_ms: result.dig(:metadata, :duration_ms) || result[:execution_time_ms],
            cost: result.dig(:metadata, :cost) || result[:cost]
          }
        )

        @execution_tracer.trace_node_completion(node, result)
        @monitor.node_completed(node, result)
      end

      def handle_node_failure(node, node_execution, error, node_context)
        @logger.error "[MCP_ORCHESTRATOR] Node execution failed: #{node.node_id} - #{error.message}"

        node_execution.fail_execution!(
          error.message,
          {
            "exception_class" => error.class.name,
            "backtrace" => error.backtrace&.first(10)
          }
        )

        @event_store.record_event(
          event_type: "node.execution.failed",
          event_data: {
            node_id: node.node_id,
            node_type: node.node_type,
            error_message: error.message,
            error_class: error.class.name
          }
        )

        @execution_tracer.trace_node_failure(node, error)
        @monitor.node_failed(node, error)

        if should_compensate_on_failure?
          trigger_compensation(error)
        end
      end

      private

      def resolve_executor_class(node_type)
        case node_type
        when "ai_agent"
          Mcp::NodeExecutors::AiAgent
        when "api_call"
          Mcp::NodeExecutors::ApiCall
        when "transform"
          Mcp::NodeExecutors::Transform
        when "condition"
          Mcp::NodeExecutors::Condition
        when "webhook"
          Mcp::NodeExecutors::Webhook
        when "delay"
          Mcp::NodeExecutors::Delay
        when "loop"
          Mcp::NodeExecutors::Loop
        when "merge"
          Mcp::NodeExecutors::Merge
        when "split"
          Mcp::NodeExecutors::Split
        when "sub_workflow"
          Mcp::NodeExecutors::SubWorkflow
        when "human_approval"
          Mcp::NodeExecutors::HumanApproval
        when "trigger", "start"
          Mcp::NodeExecutors::Start
        when "end"
          Mcp::NodeExecutors::End
        when "kb_article_create"
          Mcp::NodeExecutors::KbArticleCreate
        when "kb_article_read"
          Mcp::NodeExecutors::KbArticleRead
        when "kb_article_update"
          Mcp::NodeExecutors::KbArticleUpdate
        when "kb_article_search"
          Mcp::NodeExecutors::KbArticleSearch
        when "kb_article_publish"
          Mcp::NodeExecutors::KbArticlePublish
        when "page_create"
          Mcp::NodeExecutors::PageCreate
        when "page_read"
          Mcp::NodeExecutors::PageRead
        when "page_update"
          Mcp::NodeExecutors::PageUpdate
        when "page_publish"
          Mcp::NodeExecutors::PagePublish
        when "mcp_tool"
          Mcp::NodeExecutors::McpTool
        when "mcp_resource"
          Mcp::NodeExecutors::McpResource
        when "mcp_prompt"
          Mcp::NodeExecutors::McpPrompt
        else
          raise Mcp::AiWorkflowOrchestrator::NodeExecutionError, "Unknown node type: #{node_type}"
        end
      end

      def create_node_execution_record(node, node_context)
        @workflow_run.ai_workflow_node_executions.create!(
          ai_workflow_node_id: node.id,
          node_id: node.node_id,
          node_type: node.node_type,
          status: "pending",
          started_at: Time.current,
          input_data: node_context.input_data,
          metadata: {
            mcp_execution: true,
            mcp_tool_id: node.mcp_tool_id,
            execution_context_snapshot: {
              variables: node_context.scoped_variables.deep_dup,
              has_previous_results: node_context.previous_results.any?
            }
          }
        )
      end
    end
  end
end
