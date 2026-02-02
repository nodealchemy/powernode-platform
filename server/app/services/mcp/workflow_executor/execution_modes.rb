# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module ExecutionModes
      # Execute workflow based on configured mode
      def execute_by_mode
        execution_mode = @workflow.configuration&.dig("execution_mode") ||
                         @workflow.mcp_orchestration_config&.dig("execution_mode") ||
                         "sequential"

        log_info "Executing in #{execution_mode} mode"

        case execution_mode
        when "sequential"
          execute_sequential
        when "parallel"
          execute_parallel
        when "conditional"
          execute_conditional
        when "dag"
          execute_dag
        else
          log_warn "Unknown execution mode: #{execution_mode}, defaulting to sequential"
          execute_sequential
        end
      end

      # Execute nodes sequentially
      def execute_sequential
        queue = find_start_nodes.to_a
        visited = Set.new

        while queue.any?
          current_node = queue.shift

          # Skip if already executed (convergent flows)
          next if @node_results.key?(current_node.node_id)

          # Check prerequisites
          unless prerequisites_complete?(current_node)
            # Re-queue if prerequisites not ready
            queue << current_node unless visited.include?(current_node.node_id)
            visited << current_node.node_id
            next
          end

          # Execute node
          result = execute_node(current_node)

          # Find and queue next nodes
          next_nodes = find_next_nodes(current_node, result)
          queue.concat(next_nodes)

          # Clear visited for this node (allow re-evaluation)
          visited.delete(current_node.node_id)
        end
      end

      # Execute nodes in parallel where possible
      def execute_parallel
        # Group nodes into batches that can run in parallel
        batches = build_parallel_batches

        batches.each_with_index do |batch, index|
          log_info "Executing batch #{index + 1}/#{batches.count}", {
            nodes: batch.map(&:node_id)
          }

          if batch.count > 1
            execute_batch_parallel(batch)
          else
            execute_node(batch.first)
          end
        end
      end

      # Execute conditional branches
      def execute_conditional
        start_nodes = find_start_nodes

        start_nodes.each do |node|
          execute_conditional_branch(node)
        end
      end

      # Execute in DAG optimization mode
      def execute_dag
        # Build optimal execution plan
        execution_plan = build_dag_execution_plan

        execution_plan.each_with_index do |batch, index|
          log_debug "Executing DAG batch #{index + 1}/#{execution_plan.count}"

          if batch.count > 1
            execute_batch_parallel(batch)
          else
            execute_node(batch.first)
          end
        end
      end

      # Execute conditional branch
      #
      # @param node [Ai::WorkflowNode] Starting node
      # @param visited [Set] Set of visited node IDs
      def execute_conditional_branch(node, visited = Set.new)
        return if visited.include?(node.node_id)

        visited << node.node_id

        # Execute current node
        result = execute_node(node)

        # Find next nodes based on result
        next_nodes = find_next_nodes(node, result)

        # Recursively execute each branch
        next_nodes.each do |next_node|
          execute_conditional_branch(next_node, visited)
        end
      end
    end
  end
end
