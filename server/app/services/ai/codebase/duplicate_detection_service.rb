# frozen_string_literal: true

module Ai
  module Codebase
    class DuplicateDetectionService
      DEFAULT_THRESHOLD = 0.96
      DEFAULT_ENTITY_TYPES = %w[method function].freeze
      MAX_NODES = 500
      MAX_PAIRS = 100

      def initialize(account:, knowledge_base:)
        @account = account
        @knowledge_base = knowledge_base
      end

      # Detect duplicate code using scoped pgvector nearest-neighbor queries.
      # For each node in scope, finds its closest neighbor within the same scope.
      # @param threshold [Float] Minimum cosine similarity (0-1, default 0.95)
      # @param entity_types [Array<String>|nil] Filter by entity types
      # @param scope_path [String|nil] Limit to files under this path prefix
      # @param top_k [Integer] Maximum duplicate groups (default 30)
      # @return [Hash] Duplicate groups with recommendations
      def detect(threshold: DEFAULT_THRESHOLD, entity_types: nil, scope_path: nil, top_k: 30)
        target_types = entity_types || DEFAULT_ENTITY_TYPES

        scope = build_scope(target_types, scope_path)
        nodes = scope.select(:id, :name, :entity_type, :embedding, :properties, :mention_count)
                     .limit(MAX_NODES).to_a

        return { success: true, duplicate_groups: [], summary: { groups_found: 0, nodes_scanned: 0 } } if nodes.size < 2

        # Find similar pairs using scoped nearest-neighbor queries
        pairs = find_pairs(nodes, scope, threshold)

        # Group transitive pairs
        groups = group_transitive_pairs(pairs)

        # Build results
        duplicate_groups = groups.first(top_k).filter_map.with_index do |group, idx|
          details = group[:node_ids].filter_map { |id| @node_map[id] }
          next if details.size < 2

          sorted = details.sort_by { |n| -n[:mention_count] }
          keep = sorted.first
          merge = sorted[1..]

          {
            group_id: idx,
            similarity: group[:avg_similarity].round(4),
            nodes: details.map { |n| n.except(:mention_count_raw) },
            recommendation: {
              keep: { id: keep[:id], name: keep[:simple_name], file_path: keep[:file_path] },
              merge: merge.map { |m| { id: m[:id], name: m[:simple_name], file_path: m[:file_path] } },
              reason: "most mentions (#{keep[:mention_count]})"
            }
          }
        end

        {
          success: true,
          duplicate_groups: duplicate_groups,
          summary: {
            groups_found: duplicate_groups.size,
            total_duplicates: duplicate_groups.sum { |g| g[:nodes].size },
            unique_files_affected: duplicate_groups.flat_map { |g| g[:nodes].map { |n| n[:file_path] } }.uniq.size,
            threshold: threshold,
            scope_path: scope_path,
            nodes_scanned: nodes.size,
            pairs_found: pairs.size
          }
        }
      end

      private

      def build_scope(entity_types, scope_path)
        scope = @knowledge_base.knowledge_graph_nodes
                                .where(account: @account, node_type: "code_entity", status: "active")
                                .where(entity_type: entity_types)
                                .with_embeddings

        if scope_path.present?
          scope = scope.where("name LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(scope_path)}%")
        end

        scope
      end

      # For each node, find nearest neighbor within the scoped set.
      # Uses pgvector HNSW index via .nearest_neighbors on the filtered scope.
      def find_pairs(nodes, scope, threshold)
        pairs = []
        seen = Set.new
        @node_map = {}

        nodes.each do |node|
          # Cache node details
          @node_map[node.id] = {
            id: node.id,
            name: node.name,
            simple_name: node.properties&.dig("simple_name") || node.name,
            entity_type: node.entity_type,
            file_path: node.properties&.dig("file_path"),
            line_start: node.properties&.dig("line_start"),
            visibility: node.properties&.dig("visibility"),
            params: node.properties&.dig("params"),
            mention_count: node.mention_count
          }

          match = scope.nearest_neighbors(:embedding, node.embedding, distance: "cosine")
                       .where.not(id: node.id)
                       .first

          next unless match
          sim = 1.0 - match.neighbor_distance
          next if sim < threshold

          pair_key = [node.id, match.id].sort
          next if seen.include?(pair_key)
          seen << pair_key

          # Cross-file only
          next if node.properties&.dig("file_path") == match.properties&.dig("file_path")

          # Cache match details too
          @node_map[match.id] ||= {
            id: match.id,
            name: match.name,
            simple_name: match.properties&.dig("simple_name") || match.name,
            entity_type: match.entity_type,
            file_path: match.properties&.dig("file_path"),
            line_start: match.properties&.dig("line_start"),
            visibility: match.properties&.dig("visibility"),
            params: match.properties&.dig("params"),
            mention_count: match.mention_count
          }

          pairs << { node_a_id: node.id, node_b_id: match.id, similarity: sim.round(4) }
          break if pairs.size >= MAX_PAIRS
        end

        pairs.sort_by { |p| -p[:similarity] }
      end

      def group_transitive_pairs(pairs)
        parent = {}
        find = ->(x) { parent[x] ||= x; parent[x] = find.call(parent[x]) while parent[x] != x; parent[x] }
        union = ->(x, y) { rx = find.call(x); ry = find.call(y); parent[rx] = ry if rx != ry }

        pairs.each { |p| union.call(p[:node_a_id], p[:node_b_id]) }

        groups = {}
        pairs.each do |p|
          root = find.call(p[:node_a_id])
          groups[root] ||= { node_ids: Set.new, similarities: [] }
          groups[root][:node_ids] << p[:node_a_id]
          groups[root][:node_ids] << p[:node_b_id]
          groups[root][:similarities] << p[:similarity]
        end

        groups.values.map { |g| { node_ids: g[:node_ids].to_a, avg_similarity: g[:similarities].sum / g[:similarities].size } }
              .sort_by { |g| -g[:avg_similarity] }
      end
    end
  end
end
