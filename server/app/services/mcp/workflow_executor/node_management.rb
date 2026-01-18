# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module NodeManagement
      # Execute a single node
      #
      # @param node [Ai::WorkflowNode] Node to execute
      # @return [Hash] Node execution result
      def execute_node(node)
        with_monitoring("node_execution", node_id: node.node_id, node_type: node.node_type) do
          log_info "Executing node: #{node.name} (#{node.node_type})"

          # Create execution record
          node_execution = create_node_execution_record(node)

          begin
            # Transition state
            @state_manager.execute_node(node.node_id)

            # Update status using state transition method to trigger broadcasts
            # CRITICAL FIX: Use start_execution! instead of update! to trigger WebSocket broadcasts
            node_execution.start_execution!

            # Record event
            @event_store.record_node_started(node, node_execution)

            # Get node executor
            executor = get_node_executor(node, node_execution)

            # Execute node
            result = executor.execute

            # Handle success
            handle_node_success(node, node_execution, result)

            result

          rescue StandardError => e
            # Handle failure
            handle_node_failure(node, node_execution, e)
            raise Mcp::WorkflowExecutor::NodeExecutionError, "Node #{node.node_id} failed: #{e.message}"
          end
        end
      end

      # Execute multiple nodes in parallel
      #
      # @param nodes [Array<Ai::WorkflowNode>] Nodes to execute
      def execute_batch_parallel(nodes)
        # Note: This is a simplified implementation
        # In production, you'd use Sidekiq or similar for true parallelism
        results = nodes.map do |node|
          Thread.new { execute_node(node) }
        end.map(&:value)

        results
      rescue StandardError => e
        log_error "Parallel batch execution failed", { error: e.message }
        raise
      end

      # Get appropriate executor for node type
      #
      # @param node [Ai::WorkflowNode] Node to execute
      # @param node_execution [Ai::WorkflowNodeExecution] Execution record
      # @return [Mcp::NodeExecutors::Base] Node executor instance
      def get_node_executor(node, node_execution)
        executor_class = case node.node_type
        when "ai_agent"
                          Mcp::NodeExecutors::Ai::Agent
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
        when "start"
                          Mcp::NodeExecutors::Start
        when "end"
                          Mcp::NodeExecutors::End
        # CI/CD node types
        when "ci_trigger"
                          Mcp::NodeExecutors::CiTrigger
        when "ci_wait_status"
                          Mcp::NodeExecutors::CiWaitStatus
        when "ci_get_logs"
                          Mcp::NodeExecutors::CiGetLogs
        when "ci_cancel"
                          Mcp::NodeExecutors::CiCancel
        when "git_commit_status"
                          Mcp::NodeExecutors::GitCommitStatus
        when "git_create_check"
                          Mcp::NodeExecutors::GitCreateCheck
        when "integration_execute"
                          Mcp::NodeExecutors::IntegrationExecute
        when "git_checkout"
                          Mcp::NodeExecutors::GitCheckout
        when "git_branch"
                          Mcp::NodeExecutors::GitBranch
        when "git_pull_request"
                          Mcp::NodeExecutors::GitPullRequest
        when "git_comment"
                          Mcp::NodeExecutors::GitComment
        when "deploy"
                          Mcp::NodeExecutors::Deploy
        when "run_tests"
                          Mcp::NodeExecutors::RunTests
        when "shell_command"
                          Mcp::NodeExecutors::ShellCommand
        else
                          raise Mcp::WorkflowExecutor::NodeExecutionError, "Unknown node type: #{node.node_type}"
        end

        node_context = Mcp::NodeExecutionContext.new(
          node: node,
          workflow_run: @workflow_run,
          execution_context: @execution_context,
          previous_results: @node_results
        )

        executor_class.new(
          node: node,
          node_execution: node_execution,
          node_context: node_context,
          orchestrator: self
        )
      end

      # Create node execution record
      #
      # @param node [Ai::WorkflowNode] Node to create record for
      # @return [Ai::WorkflowNodeExecution] Created record
      def create_node_execution_record(node)
        @workflow_run.node_executions.create!(
          node: node,
          node_id: node.node_id,
          node_type: node.node_type,
          status: "pending",
          started_at: Time.current,
          input_data: build_node_input_data(node),
          metadata: {
            mcp_execution: true,
            mcp_tool_id: node.mcp_tool_id,
            executor: self.class.name
          }
        )
      end
    end
  end
end
