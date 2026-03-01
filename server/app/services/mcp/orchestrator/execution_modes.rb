# frozen_string_literal: true

module Mcp
  module Orchestrator
    module ExecutionModes
      def execute_workflow_by_mode
        execution_mode = @workflow.configuration&.dig("execution_mode") ||
                         @workflow.mcp_orchestration_config&.dig("execution_mode") ||
                         "sequential"

        @logger.info "[MCP_ORCHESTRATOR] Executing in #{execution_mode} mode"

        case execution_mode
        when "sequential"
          execute_sequential_mode
        when "parallel"
          execute_parallel_mode
        when "conditional"
          execute_conditional_mode
        when "dag"
          execute_dag_mode
        else
          execute_sequential_mode
        end
      end

      def execute_from_resume_point(resume_node)
        @logger.info "[MCP_ORCHESTRATOR] Executing from resume point: #{resume_node.node_id}"

        execution_queue = [ resume_node ]

        while execution_queue.any?
          current_node = execution_queue.shift

          next if @node_results.key?(current_node.node_id)

          unless prerequisites_complete?(current_node)
            execution_queue << current_node
            next
          end

          node_result = execute_node(current_node)

          next_nodes = find_next_nodes(current_node, node_result)
          execution_queue.concat(next_nodes)

          @execution_context[:execution_path] << current_node.node_id
        end
      end

      def execute_sequential_mode
        @logger.info "[MCP_ORCHESTRATOR] Executing workflow sequentially"

        start_nodes = find_start_nodes
        execution_queue = start_nodes.to_a

        while execution_queue.any?
          current_node = execution_queue.shift

          next if @node_results.key?(current_node.node_id)

          unless prerequisites_complete?(current_node)
            # Use loop prevention module for requeue limit checking
            check_requeue_limit(current_node)

            execution_queue << current_node
            next
          end

          node_result = execute_node(current_node)

          next_nodes = find_next_nodes(current_node, node_result)
          execution_queue.concat(next_nodes)

          @execution_context[:execution_path] << current_node.node_id
        end
      end

      def execute_parallel_mode
        @logger.info "[MCP_ORCHESTRATOR] Executing workflow in parallel mode"

        execution_batches = build_dag_execution_plan

        execution_batches.each_with_index do |batch, index|
          @logger.debug "[MCP_ORCHESTRATOR] Executing parallel batch #{index + 1}/#{execution_batches.count} (#{batch.size} nodes)"

          batch.each do |node|
            next unless prerequisites_complete?(node)

            execute_node(node)
            @execution_context[:execution_path] << node.node_id
          end

          @workflow_run.reload
          if @workflow_run.status == "cancelled"
            @logger.info "[MCP_ORCHESTRATOR] Workflow cancelled during parallel execution"
            break
          end
        end
      end

      def execute_conditional_mode
        @logger.info "[MCP_ORCHESTRATOR] Executing workflow with conditional branching"

        start_nodes = find_start_nodes

        start_nodes.each do |start_node|
          execute_conditional_branch(start_node)
        end
      end

      def execute_dag_mode
        @logger.info "[MCP_ORCHESTRATOR] Executing workflow in DAG optimization mode"

        execution_plan = build_dag_execution_plan

        execution_plan.each_with_index do |node_batch, batch_index|
          @logger.debug "[MCP_ORCHESTRATOR] Executing batch #{batch_index + 1}/#{execution_plan.count}"

          if node_batch.count > 1
            execute_node_batch_parallel(node_batch)
          else
            execute_node(node_batch.first)
          end
        end
      end

      def execute_parallel_workflow
        @logger.info "[MCP_ORCHESTRATOR] Starting parallel workflow execution"

        execution_batches = build_dag_execution_plan

        execution_batches.each_with_index do |batch, index|
          @logger.debug "[MCP_ORCHESTRATOR] Executing batch #{index + 1}/#{execution_batches.count}"

          if batch.size == 1
            execute_node(batch.first)
          else
            execute_node_batch_parallel(batch)
          end

          @workflow_run.reload
          if @workflow_run.status == "cancelled"
            @logger.info "[MCP_ORCHESTRATOR] Workflow cancelled during parallel execution"
            break
          end
        end
      end
    end
  end
end
