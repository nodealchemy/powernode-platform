# frozen_string_literal: true

module Ai
  class Workflow
    module StructureValidation
      extend ActiveSupport::Concern

      # Workflow structure methods
      def has_valid_structure?
        # Only require at least one start node
        # End nodes are optional - workflows can terminate naturally
        start_nodes.any? && !has_circular_dependencies?
      end

      # Public validation method for API endpoint
      # Returns validation result hash with errors and warnings
      def validate_structure
        validation_errors = []
        validation_warnings = []

        # Check for at least one start node
        if start_nodes.empty?
          validation_errors << "Workflow must have at least one node marked as a start node"
        end

        # Check for circular dependencies (excluding intentional loops)
        if has_circular_dependencies?
          validation_errors << "Workflow contains circular dependencies"
        end

        # Check if workflow has any nodes
        if workflow_nodes.empty?
          validation_errors << "Workflow must contain at least one node"
        end

        # Warnings for best practices
        if end_nodes.empty? && workflow_nodes.any?
          validation_warnings << "Workflow has no end nodes - execution will terminate when no next nodes are available"
        end

        # Check for orphaned nodes (nodes not connected to anything)
        if workflow_nodes.any? && workflow_edges.any?
          connected_node_ids = Set.new
          workflow_edges.each do |edge|
            connected_node_ids.add(edge.source_node_id)
            connected_node_ids.add(edge.target_node_id)
          end

          orphaned_nodes = workflow_nodes.reject { |node| connected_node_ids.include?(node.node_id) }
          if orphaned_nodes.any? && orphaned_nodes.size < workflow_nodes.size
            orphaned_names = orphaned_nodes.map(&:name).join(", ")
            validation_warnings << "Orphaned nodes detected (not connected to workflow): #{orphaned_names}"
          end
        end

        # Check for unreachable nodes from start nodes
        if start_nodes.any? && workflow_edges.any?
          reachable_nodes = find_reachable_nodes
          unreachable_nodes = workflow_nodes.reject { |node| reachable_nodes.include?(node.node_id) }

          if unreachable_nodes.any?
            unreachable_names = unreachable_nodes.map(&:name).join(", ")
            validation_warnings << "Unreachable nodes detected (cannot be reached from start nodes): #{unreachable_names}"
          end
        end

        {
          valid: validation_errors.empty?,
          errors: validation_errors,
          warnings: validation_warnings
        }
      end

      def start_nodes
        workflow_nodes.where(is_start_node: true)
      end

      def end_nodes
        workflow_nodes.where(is_end_node: true)
      end

      def node_count
        workflow_nodes.count
      end

      def edge_count
        workflow_edges.count
      end

      def has_circular_dependencies?
        # Cycle detection that allows intentional loops and branching/merging patterns
        # Uses Kahn's algorithm (topological sort)

        # Build adjacency list and in-degree count
        in_degree = Hash.new(0)
        adjacency = Hash.new { |h, k| h[k] = [] }

        # Get all node IDs and build node info map
        all_node_ids = workflow_nodes.pluck(:node_id).to_set
        node_types = workflow_nodes.pluck(:node_id, :node_type).to_h

        # Initialize in_degree for all nodes
        all_node_ids.each { |id| in_degree[id] = 0 }

        # Identify nodes that can have intentional feedback loops
        feedback_source_types = %w[condition loop split].freeze

        # Build the graph, excluding intentional loop edges
        workflow_edges.each do |edge|
          next unless all_node_ids.include?(edge.source_node_id) && all_node_ids.include?(edge.target_node_id)

          # Skip edges explicitly marked as intentional loops
          next if %w[retry loop compensation feedback revision].include?(edge.edge_type)

          # Skip "false" branch edges from condition nodes
          source_type = node_types[edge.source_node_id]
          if feedback_source_types.include?(source_type)
            next if edge.source_handle.to_s.match?(/false|retry|loop|back|revision/i)
          end

          adjacency[edge.source_node_id] << edge.target_node_id
          in_degree[edge.target_node_id] += 1
        end

        # Kahn's algorithm: start with nodes that have no incoming edges
        queue = all_node_ids.select { |id| in_degree[id] == 0 }
        processed_count = 0

        while queue.any?
          node_id = queue.shift
          processed_count += 1

          adjacency[node_id].each do |neighbor|
            in_degree[neighbor] -= 1
            queue << neighbor if in_degree[neighbor] == 0
          end
        end

        # If we couldn't process all nodes, there's a real cycle
        processed_count < all_node_ids.size
      end

      # Find all nodes reachable from start nodes
      def find_reachable_nodes
        reachable = Set.new
        queue = start_nodes.map(&:node_id)

        while queue.any?
          current_node_id = queue.shift
          next if reachable.include?(current_node_id)

          reachable.add(current_node_id)

          # Find all outgoing edges from this node
          outgoing_edges = workflow_edges.where(source_node_id: current_node_id)
          outgoing_edges.each do |edge|
            queue << edge.target_node_id unless reachable.include?(edge.target_node_id)
          end
        end

        reachable
      end
    end
  end
end
