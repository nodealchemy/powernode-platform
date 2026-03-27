# frozen_string_literal: true

module Ai
  module Codebase
    class DeadCodeDetectionService
      INBOUND_RELATION_TYPES = %w[calls imports uses inherits implements].freeze
      STRUCTURAL_RELATION_TYPES = %w[defines contains].freeze
      DEFAULT_ENTITY_TYPES = %w[method function class].freeze

      def initialize(account:, knowledge_base:)
        @account = account
        @knowledge_base = knowledge_base
      end

      # Detect dead code candidates in the knowledge graph.
      # @param entity_types [Array<String>|nil] Filter to specific entity types
      # @param scope_path [String|nil] Limit to files under this path prefix
      # @param min_score [Float] Minimum deadness score (0-1, default 0.5)
      # @param top_k [Integer] Maximum results (default 50)
      # @return [Hash] Candidates with scores and summary
      def detect(entity_types: nil, scope_path: nil, min_score: 0.5, top_k: 50)
        target_types = entity_types || DEFAULT_ENTITY_TYPES

        # Find unreferenced nodes via SQL
        unreferenced = find_unreferenced_nodes(target_types, scope_path)

        # Score each candidate
        candidates = unreferenced.filter_map do |node|
          score = calculate_deadness_score(node)
          next if score < min_score

          {
            id: node.id,
            name: node.name,
            simple_name: node.properties&.dig("simple_name") || node.name,
            entity_type: node.entity_type,
            file_path: node.properties&.dig("file_path"),
            line_start: node.properties&.dig("line_start"),
            line_end: node.properties&.dig("line_end"),
            visibility: node.properties&.dig("visibility"),
            params: node.properties&.dig("params"),
            score: score.round(4),
            reason: deadness_reason(node, score),
            incoming_edges: count_incoming_edges(node),
            outgoing_edges: count_outgoing_edges(node),
            mention_count: node.mention_count,
            confidence: node.confidence,
            last_seen_at: node.last_seen_at&.iso8601
          }
        end

        # Sort by score descending, limit results
        candidates.sort_by! { |c| -c[:score] }
        candidates = candidates.first(top_k)

        # Summary stats
        by_type = candidates.group_by { |c| c[:entity_type] }.transform_values(&:size)
        by_file = candidates.group_by { |c| c[:file_path] }.transform_values(&:size)
        top_files = by_file.sort_by { |_, v| -v }.first(10).to_h

        {
          success: true,
          candidates: candidates,
          summary: {
            total_candidates: candidates.size,
            by_entity_type: by_type,
            top_files: top_files,
            avg_score: candidates.any? ? (candidates.sum { |c| c[:score] } / candidates.size).round(3) : 0,
            scope_path: scope_path
          }
        }
      end

      private

      # Find nodes with zero inbound reference edges.
      # Excludes structural parents (nodes that define/contain other nodes).
      def find_unreferenced_nodes(entity_types, scope_path)
        scope = @knowledge_base.knowledge_graph_nodes
                                .where(account: @account, node_type: "code_entity", status: "active")
                                .where(entity_type: entity_types)

        # Scope by path prefix if provided
        if scope_path.present?
          scope = scope.where("name LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(scope_path)}%")
        end

        # Exclude nodes that have inbound reference edges (calls, imports, uses, inherits)
        scope = scope.where(<<~SQL, INBOUND_RELATION_TYPES)
          NOT EXISTS (
            SELECT 1 FROM ai_knowledge_graph_edges e
            WHERE e.target_node_id = ai_knowledge_graph_nodes.id
              AND e.relation_type IN (?)
              AND e.status = 'active'
          )
        SQL

        # Exclude structural parent nodes (classes/modules that define/contain children)
        # These are "used" by being structural containers, not dead code
        if entity_types.include?("class") || entity_types.include?("module")
          scope = scope.where(<<~SQL, STRUCTURAL_RELATION_TYPES)
            NOT EXISTS (
              SELECT 1 FROM ai_knowledge_graph_edges e2
              WHERE e2.source_node_id = ai_knowledge_graph_nodes.id
                AND e2.relation_type IN (?)
                AND e2.status = 'active'
            )
          SQL
        end

        scope.order(mention_count: :asc, last_seen_at: :asc).limit(200).to_a
      end

      # Calculate composite deadness score (0-1, higher = more likely dead).
      def calculate_deadness_score(node)
        incoming = count_incoming_edges(node)
        outgoing = count_outgoing_edges(node)

        # Component 1: Incoming degree (40%) — zero inbound = high deadness
        # Normalized: 1.0 for 0 incoming, decays with more incoming
        degree_score = 1.0 / (1.0 + incoming)

        # Component 2: Recency (30%) — older = more likely dead
        if node.last_seen_at
          days_old = [(Time.current - node.last_seen_at) / 1.day, 0].max
          recency_score = [days_old / 90.0, 1.0].min # Normalize to 90 days
        else
          recency_score = 1.0
        end

        # Component 3: Mention count (20%) — fewer mentions = more likely dead
        mention_score = 1.0 / (1.0 + Math.log10(node.mention_count + 1))

        # Component 4: Confidence (10%) — lower confidence = more likely dead
        confidence_score = 1.0 - (node.confidence || 0.5)

        # Weighted composite
        (degree_score * 0.4) + (recency_score * 0.3) + (mention_score * 0.2) + (confidence_score * 0.1)
      end

      def deadness_reason(node, score)
        reasons = []
        incoming = count_incoming_edges(node)

        reasons << "zero inbound references" if incoming == 0
        reasons << "private/unused method" if node.properties&.dig("visibility") == "private" && incoming == 0
        reasons << "low mention count (#{node.mention_count})" if node.mention_count <= 1
        reasons << "low confidence (#{node.confidence&.round(2)})" if node.confidence && node.confidence < 0.3

        reasons.any? ? reasons.join(", ") : "low overall activity score"
      end

      def count_incoming_edges(node)
        @incoming_cache ||= {}
        @incoming_cache[node.id] ||= Ai::KnowledgeGraphEdge
          .where(account: @account, target_node_id: node.id, status: "active")
          .where(relation_type: INBOUND_RELATION_TYPES)
          .count
      end

      def count_outgoing_edges(node)
        @outgoing_cache ||= {}
        @outgoing_cache[node.id] ||= Ai::KnowledgeGraphEdge
          .where(account: @account, source_node_id: node.id, status: "active")
          .count
      end
    end
  end
end
