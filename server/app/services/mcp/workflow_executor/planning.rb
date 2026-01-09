# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module Planning
      # Build parallel execution batches
      #
      # @return [Array<Array<Ai::WorkflowNode>>] Batches of nodes
      def build_parallel_batches
        batches = []
        remaining_nodes = @workflow.workflow_nodes.to_a
        executed_node_ids = Set.new

        while remaining_nodes.any?
          # Find nodes that can execute now
          ready_nodes = remaining_nodes.select do |node|
            prerequisites_satisfied?(node, executed_node_ids)
          end

          break if ready_nodes.empty?

          # Add to batch
          batches << ready_nodes

          # Mark as executed
          ready_nodes.each { |node| executed_node_ids << node.node_id }

          # Remove from remaining
          remaining_nodes -= ready_nodes
        end

        batches
      end

      # Build DAG execution plan
      #
      # @return [Array<Array<Ai::WorkflowNode>>] Optimal execution order
      def build_dag_execution_plan
        # Use topological sort to determine optimal order
        # This is a simplified implementation
        build_parallel_batches
      end

      # Check if node prerequisites are satisfied
      #
      # @param node [Ai::WorkflowNode] Node to check
      # @param executed_node_ids [Set] Set of executed node IDs
      # @return [Boolean] Whether prerequisites are satisfied
      def prerequisites_satisfied?(node, executed_node_ids)
        incoming_edges = @workflow.workflow_edges.where(target_node_id: node.node_id)

        # No incoming edges means node is ready
        return true if incoming_edges.empty?

        # All source nodes must be executed
        incoming_edges.all? do |edge|
          executed_node_ids.include?(edge.source_node_id)
        end
      end

      # Check if prerequisites are complete for sequential execution
      #
      # @param node [Ai::WorkflowNode] Node to check
      # @return [Boolean] Whether prerequisites are complete
      def prerequisites_complete?(node)
        incoming_edges = @workflow.workflow_edges.where(target_node_id: node.node_id)

        # No incoming edges means ready
        return true if incoming_edges.empty?

        # Check all source nodes have results
        incoming_edges.all? do |edge|
          @node_results.key?(edge.source_node_id)
        end
      end
    end
  end
end
