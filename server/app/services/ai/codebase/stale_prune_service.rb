# frozen_string_literal: true

module Ai
  module Codebase
    # Detects (and optionally archives) knowledge-graph nodes/edges for code
    # files that no longer exist on disk. Extracted verbatim from
    # CodeMemoryTool#prune_stale so the long-running scan can run on the worker
    # via the internal /codebase/analyze endpoint.
    class StalePruneService
      attr_reader :account, :knowledge_base, :base_path

      def initialize(account:, knowledge_base:, base_path:)
        @account = account
        @knowledge_base = knowledge_base
        @base_path = base_path
      end

      # @param dry_run [Boolean] preview without archiving (default true)
      # @return [Hash] success / dry_run / pruned_nodes / pruned_edges / summary
      def prune(dry_run: true)
        file_nodes = knowledge_base.knowledge_graph_nodes
                                   .where(account: account, node_type: "code_entity", entity_type: "file", status: "active")

        stale_nodes = []
        stale_edges = []

        file_nodes.find_each(batch_size: 100) do |node|
          full_path = File.join(base_path, node.name)
          next if File.exist?(full_path)

          stale_nodes << { id: node.id, name: node.name, entity_type: node.entity_type }

          # Child nodes (symbols defined in this file)
          children = knowledge_base.knowledge_graph_nodes
                                   .where(account: account, node_type: "code_entity", status: "active")
                                   .where("properties->>'file_path' = ?", node.name)
          children.each do |child|
            stale_nodes << { id: child.id, name: child.name, entity_type: child.entity_type }
          end

          # Edges touching this file node
          edges = Ai::KnowledgeGraphEdge.where(account: account, status: "active")
                                        .where("source_node_id = :id OR target_node_id = :id", id: node.id)
          edges.each do |edge|
            stale_edges << { id: edge.id, relation_type: edge.relation_type }
          end
        end

        unless dry_run
          stale_node_ids = stale_nodes.map { |n| n[:id] }.uniq
          stale_edge_ids = stale_edges.map { |e| e[:id] }.uniq

          Ai::KnowledgeGraphEdge.where(id: stale_edge_ids).update_all(status: "archived") if stale_edge_ids.any?
          Ai::KnowledgeGraphNode.where(id: stale_node_ids).update_all(status: "archived") if stale_node_ids.any?
        end

        {
          success: true,
          dry_run: dry_run,
          pruned_nodes: stale_nodes.uniq { |n| n[:id] },
          pruned_edges: stale_edges.uniq { |e| e[:id] },
          summary: {
            nodes_affected: stale_nodes.uniq { |n| n[:id] }.size,
            edges_affected: stale_edges.uniq { |e| e[:id] }.size
          }
        }
      end
    end
  end
end
