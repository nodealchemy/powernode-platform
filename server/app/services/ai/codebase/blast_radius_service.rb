# frozen_string_literal: true

module Ai
  module Codebase
    class BlastRadiusService
      MAX_DEPTH = 5
      TRAVERSAL_RELATIONS = %w[imports calls uses depends_on inherits implements].freeze

      def initialize(account:, knowledge_base:)
        @account = account
        @knowledge_base = knowledge_base
        @graph_service = Ai::KnowledgeGraph::GraphService.new(account)
      end

      # Trace every file and symbol that depends on or uses a given symbol.
      # @param node_id [String|nil] Knowledge graph node ID
      # @param symbol_name [String|nil] Symbol name (qualified or simple)
      # @param max_depth [Integer] Maximum traversal depth
      # @return [Hash] Affected files, references, and summary
      def trace(node_id: nil, symbol_name: nil, max_depth: 3)
        max_depth = [max_depth.to_i, MAX_DEPTH].min

        node = resolve_node(node_id, symbol_name)
        return { success: false, error: "Symbol not found" } unless node

        # Traverse outward: find all nodes that import/call/use this symbol
        # We need REVERSE traversal — who depends on THIS node
        dependents = find_reverse_dependents(node, max_depth)

        # Group by file
        affected_files = {}
        dependents.each do |dep|
          file_path = dep[:properties]&.dig("file_path") || extract_file_from_name(dep[:name])
          next unless file_path

          affected_files[file_path] ||= { path: file_path, references: [], relations: Set.new }
          affected_files[file_path][:references] << {
            symbol: dep[:name],
            entity_type: dep[:entity_type],
            line_start: dep[:properties]&.dig("line_start"),
            depth: dep[:depth]
          }
          affected_files[file_path][:relations].merge(dep[:relations] || [])
        end

        # Also find file-level imports of this symbol's file
        file_node = find_file_for_symbol(node)
        if file_node
          file_importers = find_file_importers(file_node, max_depth)
          file_importers.each do |imp|
            path = imp[:name]
            affected_files[path] ||= { path: path, references: [], relations: Set.new }
            affected_files[path][:relations] << "imports"
          end
        end

        # Convert sets to arrays for JSON serialization
        results = affected_files.values.map do |f|
          f[:relations] = f[:relations].to_a
          f
        end.sort_by { |f| f[:references].map { |r| r[:depth] }.min || 999 }

        {
          success: true,
          symbol: { id: node.id, name: node.name, entity_type: node.entity_type },
          affected_files: results,
          total_files: results.size,
          total_references: results.sum { |f| f[:references].size }
        }
      end

      private

      def resolve_node(node_id, symbol_name)
        if node_id.present?
          @knowledge_base.knowledge_graph_nodes
                         .where(account: @account, status: "active")
                         .find_by(id: node_id)
        elsif symbol_name.present?
          # Try exact match first, then fuzzy
          scope = @knowledge_base.knowledge_graph_nodes
                                  .where(account: @account, node_type: "code_entity", status: "active")

          scope.find_by(name: symbol_name) ||
            scope.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(symbol_name)}").first
        end
      end

      # Find nodes that depend on the target via reverse edge traversal.
      # Uses a BFS approach following incoming edges of specified relation types.
      def find_reverse_dependents(target_node, max_depth)
        visited = Set.new([target_node.id])
        results = []
        queue = [{ node_id: target_node.id, depth: 0 }]

        while queue.any?
          current = queue.shift
          next if current[:depth] >= max_depth

          # Find all nodes that have edges pointing TO the current node
          incoming = Ai::KnowledgeGraphEdge
                       .where(account: @account, target_node_id: current[:node_id], status: "active")
                       .where(relation_type: TRAVERSAL_RELATIONS)
                       .includes(:source_node)

          incoming.each do |edge|
            source = edge.source_node
            next unless source && source.status == "active"
            next if visited.include?(source.id)

            visited << source.id
            depth = current[:depth] + 1

            results << {
              id: source.id,
              name: source.name,
              node_type: source.node_type,
              entity_type: source.entity_type,
              properties: source.properties,
              depth: depth,
              relations: [edge.relation_type]
            }

            queue << { node_id: source.id, depth: depth }
          end
        end

        results
      end

      def find_file_for_symbol(node)
        # Find the file node that contains this symbol
        file_edge = Ai::KnowledgeGraphEdge
                      .where(account: @account, target_node: node, relation_type: "contains", status: "active")
                      .includes(:source_node)
                      .first

        file_edge&.source_node
      end

      def find_file_importers(file_node, max_depth)
        results = []
        visited = Set.new([file_node.id])
        queue = [{ node_id: file_node.id, depth: 0 }]

        while queue.any?
          current = queue.shift
          next if current[:depth] >= max_depth

          incoming = Ai::KnowledgeGraphEdge
                       .where(account: @account, target_node_id: current[:node_id], status: "active")
                       .where(relation_type: "imports")
                       .includes(:source_node)

          incoming.each do |edge|
            source = edge.source_node
            next unless source&.entity_type == "file" && source.status == "active"
            next if visited.include?(source.id)

            visited << source.id
            results << { id: source.id, name: source.name, depth: current[:depth] + 1 }
            queue << { node_id: source.id, depth: current[:depth] + 1 }
          end
        end

        results
      end

      def extract_file_from_name(qualified_name)
        # Extract file path from qualified name like "app/models/user.rb::User#method"
        qualified_name&.split("::")&.first
      end
    end
  end
end
