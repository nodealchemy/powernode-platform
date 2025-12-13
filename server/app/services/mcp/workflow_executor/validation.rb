# frozen_string_literal: true

module Mcp
  class WorkflowExecutor
    module Validation
      # Validate workflow is ready for execution
      #
      # Checks:
      # - Workflow has at least one start node
      # - Workflow has at least one end node
      # - All non-start nodes have incoming edges
      # - Warns if nodes lack data mapping configuration
      # - Validates no disconnected subgraphs
      #
      # @raise [ExecutionError] If workflow is not executable
      def validate_workflow_executable!
        log_info "Validating workflow structure"

        nodes = @workflow.ai_workflow_nodes.to_a
        edges = @workflow.ai_workflow_edges.to_a

        # Check for start and end nodes
        start_nodes = nodes.select { |n| n.node_type == "start" }
        end_nodes = nodes.select { |n| n.node_type == "end" }

        if start_nodes.empty?
          raise Mcp::WorkflowExecutor::ExecutionError, "Workflow must have at least one start node"
        end

        if end_nodes.empty?
          raise Mcp::WorkflowExecutor::ExecutionError, "Workflow must have at least one end node"
        end

        # Check each node has required connections
        validation_warnings = []
        validation_errors = []

        nodes.each do |node|
          # Skip start nodes (they don't need incoming edges)
          next if node.node_type == "start"

          # Get incoming edges
          incoming = edges.select { |e| e.target_node_id == node.node_id }

          # Check for incoming connections
          if incoming.empty?
            validation_errors << "Node '#{node.name}' (#{node.node_id}) has no incoming edges"
            next
          end

          # NEW STANDARD: All nodes with incoming edges will receive previous outputs automatically
          # No configuration required - data flow is mandatory and automatic
          log_debug "Node '#{node.name}' will receive #{incoming.count} predecessor outputs automatically"

          # Check for explicit data mapping (optional enhancement)
          has_data_mapping = incoming.any? { |e| e.configuration&.dig("data_mapping").present? }

          if has_data_mapping
            log_debug "Node '#{node.name}' has explicit data mapping configured"
          end
        end

        # Check for disconnected subgraphs
        reachable_nodes = find_reachable_nodes(start_nodes, edges)
        unreachable_nodes = nodes.reject { |n| reachable_nodes.include?(n.node_id) }

        if unreachable_nodes.any?
          unreachable_names = unreachable_nodes.map { |n| "'#{n.name}'" }.join(", ")
          validation_errors << "Disconnected nodes (not reachable from start): #{unreachable_names}"
        end

        # Check if all nodes can reach an end node
        nodes_without_path_to_end = find_nodes_without_path_to_end(nodes, edges, end_nodes)

        if nodes_without_path_to_end.any?
          dead_end_names = nodes_without_path_to_end.map { |n| "'#{n.name}'" }.join(", ")
          validation_warnings << "Dead-end nodes (no path to end node): #{dead_end_names}"
        end

        # Log warnings
        if validation_warnings.any?
          log_warn "Workflow validation warnings:", {
            count: validation_warnings.size,
            warnings: validation_warnings
          }
        end

        # Fail if errors found
        if validation_errors.any?
          error_message = "Workflow validation failed:\n" + validation_errors.join("\n")
          raise Mcp::WorkflowExecutor::ExecutionError, error_message
        end

        log_info "Workflow validation passed", {
          nodes: nodes.size,
          edges: edges.size,
          start_nodes: start_nodes.size,
          end_nodes: end_nodes.size,
          warnings: validation_warnings.size
        }
      end

      # Find all nodes reachable from start nodes
      #
      # @param start_nodes [Array<AiWorkflowNode>] Starting nodes
      # @param edges [Array<AiWorkflowEdge>] All edges
      # @return [Set<String>] Set of reachable node IDs
      def find_reachable_nodes(start_nodes, edges)
        reachable = Set.new
        queue = start_nodes.map(&:node_id)

        while queue.any?
          current_id = queue.shift
          next if reachable.include?(current_id)

          reachable << current_id

          # Find outgoing edges from current node
          outgoing = edges.select { |e| e.source_node_id == current_id }
          outgoing.each do |edge|
            queue << edge.target_node_id unless reachable.include?(edge.target_node_id)
          end
        end

        reachable
      end

      # Find nodes that cannot reach any end node
      #
      # @param nodes [Array<AiWorkflowNode>] All nodes
      # @param edges [Array<AiWorkflowEdge>] All edges
      # @param end_nodes [Array<AiWorkflowNode>] End nodes
      # @return [Array<AiWorkflowNode>] Nodes without path to end
      def find_nodes_without_path_to_end(nodes, edges, end_nodes)
        # Build reverse edge map (target -> sources)
        reverse_edges = {}
        edges.each do |edge|
          reverse_edges[edge.target_node_id] ||= []
          reverse_edges[edge.target_node_id] << edge.source_node_id
        end

        # Find all nodes that can reach an end node (working backwards)
        can_reach_end = Set.new
        queue = end_nodes.map(&:node_id)

        while queue.any?
          current_id = queue.shift
          next if can_reach_end.include?(current_id)

          can_reach_end << current_id

          # Find incoming edges to current node
          incoming = reverse_edges[current_id] || []
          incoming.each do |source_id|
            queue << source_id unless can_reach_end.include?(source_id)
          end
        end

        # Return nodes that can't reach end
        nodes.reject { |n| can_reach_end.include?(n.node_id) || n.node_type == "end" }
      end
    end
  end
end
