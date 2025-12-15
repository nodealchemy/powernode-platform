# frozen_string_literal: true

module Mcp
  module Orchestrator
    module Navigation
      def find_start_nodes
        start_nodes = @workflow.ai_workflow_nodes.where(is_start_node: true)

        if start_nodes.empty?
          all_target_node_ids = @workflow.ai_workflow_edges.pluck(:target_node_id)
          start_nodes = @workflow.ai_workflow_nodes.where.not(node_id: all_target_node_ids)
        end

        start_nodes
      end

      def find_next_nodes(current_node, node_result)
        outgoing_edges = @workflow.ai_workflow_edges.where(source_node_id: current_node.node_id)

        valid_edges = outgoing_edges.select do |edge|
          evaluate_edge_condition(edge, node_result)
        end

        valid_edges = valid_edges.sort_by { |edge| edge.priority || 0 }

        target_node_ids = valid_edges.map(&:target_node_id)
        @workflow.ai_workflow_nodes.where(node_id: target_node_ids)
      end

      def evaluate_edge_condition(edge, node_result)
        return false if node_result.nil?
        return true if edge.edge_type == "default"

        if edge.edge_type == "success"
          return node_result[:success] == true
        end

        if edge.edge_type == "error"
          return node_result[:success] == false
        end

        if edge.is_conditional? && edge.condition.present?
          return evaluate_conditional_expression(edge.condition, node_result)
        end

        true
      end

      def evaluate_conditional_expression(condition, node_result)
        evaluator = Mcp::ConditionalEvaluator.new(
          condition: condition,
          context: @execution_context,
          node_result: node_result
        )

        evaluator.evaluate
      rescue StandardError => e
        @logger.error "[MCP_ORCHESTRATOR] Conditional evaluation failed: #{e.message}"
        false
      end

      def prerequisites_complete?(node)
        incoming_edges = @workflow.ai_workflow_edges.where(target_node_id: node.node_id)

        return true if incoming_edges.empty?

        # Check which source nodes have results
        edges_with_results = incoming_edges.select { |e| @node_results.key?(e.source_node_id) }
        edges_without_results = incoming_edges.reject { |e| @node_results.key?(e.source_node_id) }

        # Detect feedback loops: edges from nodes that are downstream (no result yet)
        # For feedback loops, we use ANY logic - allow execution if any forward path is complete
        has_feedback_loop = edges_without_results.any? && edges_with_results.any?

        # Check for conditional convergence
        source_nodes_with_conditional_incoming = incoming_edges.select do |edge|
          source_node_id = edge.source_node_id
          source_node_incoming = @workflow.ai_workflow_edges.where(target_node_id: source_node_id)
          source_node_incoming.any?(&:is_conditional?)
        end
        is_conditional_convergence = incoming_edges.count > 1 && source_nodes_with_conditional_incoming.any?

        # Use ANY logic for: conditional convergence OR feedback loops
        # This allows a node to execute as soon as one valid path is complete
        if is_conditional_convergence || has_feedback_loop
          incoming_edges.any? do |edge|
            source_node_id = edge.source_node_id

            if @node_results.key?(source_node_id)
              source_result = @node_results[source_node_id]
              evaluate_edge_condition(edge, source_result)
            else
              false
            end
          end
        else
          # Standard case: all incoming edges must be satisfied
          incoming_edges.all? do |edge|
            source_node_id = edge.source_node_id

            if @node_results.key?(source_node_id)
              source_result = @node_results[source_node_id]
              evaluate_edge_condition(edge, source_result)
            else
              false
            end
          end
        end
      end
    end
  end
end
