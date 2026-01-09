# frozen_string_literal: true

module Orchestration
  module NodeOperations
    def execute_node(node, run, input_data = {})
      @logger.info "Executing node #{node.node_id} for run #{run.run_id}"

      node_execution = run.node_executions.create!(
        node: node,
        node_id: node.node_id,
        node_type: node.node_type,
        status: "pending",
        input_data: input_data,
        started_at: Time.current
      )

      if should_execute_asynchronously?(node.node_type)
        delegate_to_worker(node_execution, input_data)
        return node_execution
      end

      begin
        node_execution.update!(status: "running")

        result = case node.node_type
        when "start"
          { success: true, output_data: input_data, cost: 0, tokens_consumed: 0, tokens_generated: 0 }
        when "end"
          { success: true, output_data: input_data, cost: 0, tokens_consumed: 0, tokens_generated: 0 }
        when "ai_agent"
          execute_ai_agent_node(node, input_data)
        when "api_call"
          execute_api_call_node(node, input_data)
        when "webhook"
          execute_webhook_node(node, input_data)
        when "condition"
          execute_condition_node(node, input_data)
        when "transform"
          execute_transform_node(node, input_data)
        when "human_approval"
          execute_human_approval_node(node, input_data)
        else
          { success: false, error_message: "Unknown node type: #{node.node_type}" }
        end

        if result[:success]
          node_execution.update!(
            status: "completed",
            completed_at: Time.current,
            output_data: result[:output_data] || {},
            cost: result[:cost] || 0,
            duration_ms: ((Time.current - node_execution.started_at) * 1000).to_i
          )
        else
          node_execution.update!(
            status: "failed",
            completed_at: Time.current,
            error_details: {
              error_message: result[:error_message],
              **(result[:error_details] || {})
            }
          )
        end

      rescue StandardError => e
        @logger.error "Node execution failed: #{e.message}"
        node_execution.update!(
          status: "failed",
          completed_at: Time.current,
          error_details: {
            error_message: e.message,
            exception_class: e.class.name,
            backtrace: e.backtrace&.first(5)
          }
        )
      end

      node_execution
    end

    private

    def should_execute_asynchronously?(node_type)
      %w[ai_agent api_call webhook human_approval sub_workflow transform loop].include?(node_type)
    end

    def delegate_to_worker(node_execution, input_data)
      @logger.info "Delegating node execution #{node_execution.execution_id} to background worker"

      begin
        if defined?(Sidekiq) && Rails.env.production?
          require_relative "../../../worker/app/jobs/ai_workflow_node_execution_job"
          AiWorkflowNodeExecutionJob.perform_async(
            node_execution.id,
            {
              "execution_context" => build_worker_execution_context(node_execution, input_data),
              "workflow_run_id" => node_execution.ai_workflow_run_id,
              "account_id" => @account.id,
              "user_id" => @user&.id
            }
          )
          @logger.info "Job queued successfully for node execution #{node_execution.execution_id}"
        else
          @logger.info "Executing node synchronously in test/development environment"
          execute_node_directly(node_execution, input_data)
        end
      rescue StandardError => e
        @logger.error "Failed to delegate to worker: #{e.message}"
        execute_node_directly(node_execution, input_data)
      end
    end

    def execute_node_directly(node_execution, input_data)
      begin
        node_execution.update!(
          status: "running",
          started_at: Time.current,
          input_data: input_data
        )

        executor = @node_executors[node_execution.node_type.to_sym]
        unless executor
          raise Ai::AgentOrchestrationService::ExecutionError, "No executor found for node type: #{node_execution.node_type}"
        end

        result = executor.call(node_execution, input_data, @execution_context)

        node_execution.update!(
          status: "completed",
          completed_at: Time.current,
          output_data: result || {},
          duration_ms: ((Time.current - node_execution.started_at) * 1000).round
        )

        @logger.info "Node execution #{node_execution.execution_id} completed successfully"
        result

      rescue StandardError => e
        @logger.error "Node execution #{node_execution.execution_id} failed: #{e.message}"
        node_execution.update!(
          status: "failed",
          completed_at: Time.current,
          error_message: e.message,
          error_details: { error: e.class.name, message: e.message, backtrace: e.backtrace.first(10) }
        )
        raise
      end
    end

    def build_worker_execution_context(node_execution, input_data)
      {
        "node_id" => node_execution.node_id,
        "node_type" => node_execution.node_type,
        "input_data" => input_data,
        "configuration" => node_execution.node.configuration,
        "workflow_context" => @execution_context,
        "started_at" => Time.current.iso8601
      }
    end
  end
end
