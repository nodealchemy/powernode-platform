# frozen_string_literal: true

module Ai
  module KnowledgeGraph
    class MultiHopReasoningService
      DEFAULT_MAX_HOPS = 3
      DEFAULT_TOP_K = 5
      SEED_NODE_LIMIT = 10

      def initialize(account)
        @account = account
        @graph_service = GraphService.new(account)
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Multi-hop reasoning from a natural language query
      def reason(query:, max_hops: DEFAULT_MAX_HOPS, top_k: DEFAULT_TOP_K)
        max_hops = [max_hops.to_i, 5].min
        top_k = [top_k.to_i, 20].min

        # Step 1: Find seed nodes via embedding similarity
        seed_nodes = find_seed_nodes(query)
        return empty_result(query) if seed_nodes.empty?

        # Step 2: Expand seed nodes via graph traversal
        expanded_paths = expand_nodes(seed_nodes, max_hops: max_hops)

        # Step 3: Score and rank paths
        scored_paths = score_paths(expanded_paths, query)

        # Step 4: Build reasoning chain from top-k paths
        top_paths = scored_paths.first(top_k)
        answer_nodes = collect_answer_nodes(top_paths)
        reasoning_chain = build_reasoning_chain(top_paths)

        confidence = if scored_paths.any?
          scored_paths.first(top_k).sum { |p| p[:score] } / top_k.to_f
        else
          0.0
        end

        {
          query: query,
          answer_nodes: answer_nodes,
          paths: top_paths.map { |p| serialize_path(p) },
          reasoning_chain: reasoning_chain,
          confidence: confidence.round(4),
          seed_nodes_found: seed_nodes.size,
          total_paths_explored: expanded_paths.size
        }
      end

      private

      def find_seed_nodes(query)
        query_embedding = @embedding_service.generate(query)
        return keyword_seed_nodes(query) unless query_embedding

        nodes_scope = @account.ai_knowledge_graph_nodes.active.with_embeddings

        return keyword_seed_nodes(query) unless nodes_scope.exists?

        candidates = nodes_scope
          .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
          .first(SEED_NODE_LIMIT)

        # Filter to reasonable similarity (distance <= 0.5 means similarity >= 0.5)
        relevant = candidates.select { |c| c.neighbor_distance <= 0.5 }

        return keyword_seed_nodes(query) if relevant.empty?

        relevant.map do |node|
          {
            node: node,
            similarity: (1.0 - node.neighbor_distance).round(4)
          }
        end
      end

      def keyword_seed_nodes(query)
        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
        return [] if keywords.empty?

        nodes = @account.ai_knowledge_graph_nodes.active

        where_clauses = keywords.map do |kw|
          sanitized = Ai::KnowledgeGraphNode.sanitize_sql_like(kw)
          "LOWER(name) LIKE '%#{sanitized}%' OR LOWER(description) LIKE '%#{sanitized}%'"
        end

        results = nodes.where(where_clauses.join(" OR ")).limit(SEED_NODE_LIMIT)

        results.map do |node|
          { node: node, similarity: 0.5 }
        end
      end

      def expand_nodes(seed_nodes, max_hops:)
        paths = []

        seed_nodes.each do |seed|
          node = seed[:node]

          # Get neighbors at each depth
          neighbors = @graph_service.find_neighbors(
            node: node,
            depth: max_hops
          )

          # Build paths from seed to each neighbor
          neighbors.each do |neighbor|
            # Get edges connecting seed to this neighbor path
            edge_path = find_connecting_edges(node.id, neighbor[:id])
            next if edge_path.empty?

            paths << {
              seed: seed,
              target: neighbor,
              edges: edge_path,
              depth: neighbor[:depth]
            }
          end
        end

        paths
      end

      def find_connecting_edges(source_id, target_id)
        # For direct connections, just find the edge
        edge = Ai::KnowledgeGraphEdge.active.find_by(
          source_node_id: source_id,
          target_node_id: target_id
        )

        return [edge] if edge

        # Check reverse direction
        edge = Ai::KnowledgeGraphEdge.active.find_by(
          source_node_id: target_id,
          target_node_id: source_id
        )

        return [edge] if edge

        # For multi-hop, use shortest path
        path = @graph_service.shortest_path(
          source: source_id,
          target: target_id,
          max_depth: 5
        )

        path || []
      end

      def score_paths(paths, query)
        paths.map do |path|
          # Score based on seed similarity, edge weights, and path length
          seed_score = path[:seed][:similarity]
          edge_scores = path[:edges].map { |e| e.respond_to?(:combined_score) ? e.combined_score : 1.0 }
          edge_avg = edge_scores.any? ? edge_scores.sum / edge_scores.size : 0.0

          # Shorter paths get higher scores (depth penalty)
          depth_penalty = 1.0 / (1.0 + (path[:depth] - 1) * 0.2)

          score = seed_score * edge_avg * depth_penalty

          path.merge(score: score.round(4))
        end.sort_by { |p| -p[:score] }
      end

      def collect_answer_nodes(paths)
        node_ids = []

        paths.each do |path|
          node_ids << path[:seed][:node].id
          node_ids << path[:target][:id] if path[:target][:id]
        end

        Ai::KnowledgeGraphNode.where(id: node_ids.uniq).map do |node|
          {
            id: node.id,
            name: node.name,
            node_type: node.node_type,
            entity_type: node.entity_type,
            description: node.description,
            confidence: node.confidence
          }
        end
      end

      def build_reasoning_chain(paths)
        paths.map do |path|
          seed_name = path[:seed][:node].name
          target_name = path[:target][:name]
          relations = path[:edges].map do |e|
            e.respond_to?(:relation_type) ? e.relation_type : "related_to"
          end

          {
            from: seed_name,
            to: target_name,
            via: relations,
            score: path[:score],
            depth: path[:depth]
          }
        end
      end

      def serialize_path(path)
        {
          seed_node: {
            id: path[:seed][:node].id,
            name: path[:seed][:node].name,
            similarity: path[:seed][:similarity]
          },
          target_node: {
            id: path[:target][:id],
            name: path[:target][:name],
            node_type: path[:target][:node_type]
          },
          edges: path[:edges].map do |e|
            if e.respond_to?(:id)
              {
                id: e.id,
                relation_type: e.relation_type,
                weight: e.weight,
                confidence: e.confidence
              }
            else
              { relation_type: "unknown" }
            end
          end,
          depth: path[:depth],
          score: path[:score]
        }
      end

      def empty_result(query)
        {
          query: query,
          answer_nodes: [],
          paths: [],
          reasoning_chain: [],
          confidence: 0.0,
          seed_nodes_found: 0,
          total_paths_explored: 0
        }
      end
    end
  end
end
