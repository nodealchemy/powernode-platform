# frozen_string_literal: true

module Mcp
  module Orchestrator
    module AdvancedExecution
      def execute_conditional_branch(node, visited = Set.new)
        return if visited.include?(node.node_id)
        visited.add(node.node_id)

        @logger.info "[MCP_ORCHESTRATOR] Executing conditional branch: #{node.node_id}"

        node_result = execute_node(node)

        outgoing_edges = @workflow.ai_workflow_edges.where(source_node_id: node.node_id)

        selected_edges = outgoing_edges.select do |edge|
          evaluate_edge_condition(edge, node_result)
        end

        selected_edges = selected_edges.sort_by { |edge| edge.priority || 0 }

        @logger.debug "[MCP_ORCHESTRATOR] Conditional branch selected #{selected_edges.count} path(s)"

        selected_edges.each do |edge|
          target_node = @workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
          next unless target_node && !visited.include?(target_node.node_id)

          if target_node.node_type == "condition"
            execute_conditional_branch(target_node, visited)
          else
            execute_node(target_node)
            next_nodes = find_next_nodes(target_node, @node_results[target_node.node_id])
            next_nodes.each do |next_node|
              execute_sequential_from(next_node, visited) unless visited.include?(next_node.node_id)
            end
          end
        end
      end

      def execute_sequential_from(node, visited = Set.new)
        return if visited.include?(node.node_id)
        return unless prerequisites_complete?(node)

        visited.add(node.node_id)

        if node.node_type == "condition"
          execute_conditional_branch(node, visited)
        else
          node_result = execute_node(node)
          next_nodes = find_next_nodes(node, node_result)

          next_nodes.each do |next_node|
            execute_sequential_from(next_node, visited)
          end
        end
      end

      def build_dag_execution_plan
        dependencies = {}
        reverse_dependencies = {}

        @workflow.ai_workflow_nodes.each do |node|
          dependencies[node.node_id] = []
          reverse_dependencies[node.node_id] = []
        end

        @workflow.ai_workflow_edges.each do |edge|
          dependencies[edge.target_node_id] ||= []
          dependencies[edge.target_node_id] << edge.source_node_id

          reverse_dependencies[edge.source_node_id] ||= []
          reverse_dependencies[edge.source_node_id] << edge.target_node_id
        end

        execution_batches = []
        in_degree = {}

        @workflow.ai_workflow_nodes.each do |node|
          in_degree[node.node_id] = dependencies[node.node_id]&.count || 0
        end

        while in_degree.values.any? { |d| d >= 0 }
          ready_nodes = in_degree.select { |_, degree| degree == 0 }.keys

          break if ready_nodes.empty?

          batch_nodes = @workflow.ai_workflow_nodes.where(node_id: ready_nodes).to_a
          execution_batches << batch_nodes if batch_nodes.any?

          ready_nodes.each do |node_id|
            in_degree[node_id] = -1

            reverse_dependencies[node_id]&.each do |dependent_id|
              in_degree[dependent_id] -= 1 if in_degree[dependent_id] > 0
            end
          end
        end

        @logger.debug "[MCP_ORCHESTRATOR] Built DAG execution plan with #{execution_batches.count} batches"
        execution_batches
      end

      def execute_node_batch_parallel(node_batch)
        return [] if node_batch.empty?

        @logger.info "[MCP_ORCHESTRATOR] Executing batch of #{node_batch.count} nodes in parallel"

        results = {}
        threads = []
        mutex = Mutex.new

        node_batch.each do |node|
          next unless prerequisites_complete?(node)

          threads << Thread.new do
            begin
              result = execute_node(node)
              mutex.synchronize { results[node.node_id] = result }
            rescue StandardError => e
              mutex.synchronize do
                results[node.node_id] = {
                  success: false,
                  error: e.message,
                  output: nil,
                  metadata: { node_id: node.node_id, error_class: e.class.name }
                }
              end
              @logger.error "[MCP_ORCHESTRATOR] Parallel node execution failed: #{node.node_id} - #{e.message}"
            end
          end
        end

        timeout_seconds = @workflow.timeout_seconds || 300
        deadline = Time.current + timeout_seconds

        threads.each do |thread|
          remaining = [ deadline - Time.current, 0 ].max
          thread.join(remaining)

          if thread.alive?
            thread.kill
            @logger.warn "[MCP_ORCHESTRATOR] Thread killed due to timeout"
          end
        end

        @logger.info "[MCP_ORCHESTRATOR] Parallel batch completed with #{results.count} results"
        results
      end
    end
  end
end
