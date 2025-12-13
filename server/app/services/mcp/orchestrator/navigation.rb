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

        source_nodes_with_conditional_incoming = incoming_edges.select do |edge|
          source_node_id = edge.source_node_id
          source_node_incoming = @workflow.ai_workflow_edges.where(target_node_id: source_node_id)
          source_node_incoming.any?(&:is_conditional?)
        end

        is_conditional_convergence = incoming_edges.count > 1 && source_nodes_with_conditional_incoming.any?

        if is_conditional_convergence
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
