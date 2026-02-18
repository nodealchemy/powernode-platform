# frozen_string_literal: true

module Ai
  module Rag
    class GraphRagService
      MAX_SEED_NODES = 5
      MAX_COMMUNITY_DEPTH = 3
      MAX_COMMUNITIES = 5
      SEED_DISTANCE_THRESHOLD = 0.5
      COMMUNITY_MIN_SIZE = 2

      def initialize(account:)
        @account = account
        @graph_service = Ai::KnowledgeGraph::GraphService.new(account)
        @hybrid_search = Ai::Rag::HybridSearchService.new(account)
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Full GraphRAG pipeline: query → entities → graph traversal → context enrichment
      def retrieve(query:, top_k: 10, include_summaries: true, max_hops: 2)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Step 1: Find seed nodes via embedding similarity
        seed_nodes = find_seed_nodes(query)
        return empty_result(query) if seed_nodes.empty?

        # Step 2: Detect communities around seed nodes
        communities = detect_communities(seed_nodes, max_depth: max_hops)

        # Step 3: Collect document chunks from community nodes
        chunks = collect_community_chunks(communities)

        # Step 4: Score and rank results
        ranked = score_results(query, chunks, communities)

        # Step 5: Build community summaries if requested
        summaries = include_summaries ? build_community_summaries(communities) : []

        # Step 6: Merge with hybrid search for comprehensive coverage
        hybrid_results = @hybrid_search.search(query: query, mode: :hybrid, top_k: top_k)
        merged = merge_results(ranked, hybrid_results[:results], top_k: top_k)

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

        {
          results: merged,
          communities: communities.map { |c| community_summary_data(c) },
          summaries: summaries,
          seed_nodes: seed_nodes.map { |sn| { id: sn[:node].id, name: sn[:node].name, similarity: sn[:similarity] } },
          metadata: {
            query: query,
            seed_nodes_found: seed_nodes.size,
            communities_detected: communities.size,
            total_chunks: chunks.size,
            results_count: merged.size,
            latency_ms: elapsed_ms
          }
        }
      end

      # Build context string for injection into LLM prompt
      def build_context(query:, token_budget: 2000, max_hops: 2)
        result = retrieve(query: query, top_k: 8, include_summaries: true, max_hops: max_hops)

        context_parts = []
        chars_budget = token_budget * 4
        chars_used = 0

        # Add community summaries first (high-level understanding)
        if result[:summaries].any?
          context_parts << "## Graph Knowledge Summaries"
          result[:summaries].each do |summary|
            entry = "- **#{summary[:community_label]}**: #{summary[:summary]}"
            break if chars_used + entry.length > chars_budget

            context_parts << entry
            chars_used += entry.length
          end
        end

        # Add specific retrieved passages
        if result[:results].any?
          context_parts << "\n## Retrieved Context"
          result[:results].each do |r|
            content = r[:content].to_s.truncate(500)
            entry = "- #{content}"
            break if chars_used + entry.length > chars_budget

            context_parts << entry
            chars_used += entry.length
          end
        end

        {
          context: context_parts.join("\n"),
          token_estimate: chars_used / 4,
          source: "graph_rag",
          metadata: result[:metadata]
        }
      end

      private

      def find_seed_nodes(query)
        query_embedding = @embedding_service.generate(query)
        return keyword_seed_fallback(query) unless query_embedding

        nodes = Ai::KnowledgeGraphNode
          .where(account_id: @account.id, status: "active")
          .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
          .first(MAX_SEED_NODES * 2)

        nodes.filter_map do |node|
          distance = node.neighbor_distance
          similarity = 1.0 - distance
          next if similarity < (1.0 - SEED_DISTANCE_THRESHOLD)

          { node: node, similarity: similarity }
        end.first(MAX_SEED_NODES)
      rescue StandardError => e
        Rails.logger.warn "[GraphRAG] Seed node search failed: #{e.message}"
        keyword_seed_fallback(query)
      end

      def keyword_seed_fallback(query)
        terms = query.downcase.split(/\s+/).reject { |t| t.length < 3 }
        return [] if terms.empty?

        nodes = Ai::KnowledgeGraphNode
          .where(account_id: @account.id, status: "active")
          .where("LOWER(name) SIMILAR TO ?", "%(#{terms.join('|')})%")
          .order(mention_count: :desc)
          .limit(MAX_SEED_NODES)

        nodes.map { |node| { node: node, similarity: 0.5 } }
      end

      def detect_communities(seed_nodes, max_depth: MAX_COMMUNITY_DEPTH)
        communities = []
        visited_node_ids = Set.new

        seed_nodes.each do |seed_entry|
          seed = seed_entry[:node]
          next if visited_node_ids.include?(seed.id)

          # Expand from seed node using graph traversal
          neighbors = @graph_service.find_neighbors(node: seed, depth: max_depth)
          community_node_ids = [seed.id] + neighbors.map { |n| n[:id] }
          community_node_ids.uniq!

          # Skip if heavily overlapping with existing community
          new_ids = community_node_ids.reject { |id| visited_node_ids.include?(id) }
          next if new_ids.size < COMMUNITY_MIN_SIZE

          visited_node_ids.merge(community_node_ids)

          community_nodes = Ai::KnowledgeGraphNode.where(id: community_node_ids, status: "active")
          community_edges = Ai::KnowledgeGraphEdge.where(
            "source_node_id IN (?) OR target_node_id IN (?)",
            community_node_ids, community_node_ids
          )

          communities << {
            seed: seed,
            seed_similarity: seed_entry[:similarity],
            nodes: community_nodes.to_a,
            edges: community_edges.to_a,
            node_ids: community_node_ids
          }

          break if communities.size >= MAX_COMMUNITIES
        end

        communities
      end

      def collect_community_chunks(communities)
        all_node_ids = communities.flat_map { |c| c[:node_ids] }.uniq
        return [] if all_node_ids.empty?

        # Find document chunks associated with community nodes
        Ai::DocumentChunk
          .joins("INNER JOIN ai_knowledge_graph_nodes ON ai_knowledge_graph_nodes.source_document_id = ai_document_chunks.document_id")
          .where(ai_knowledge_graph_nodes: { id: all_node_ids })
          .distinct
          .limit(50)
          .map do |chunk|
            {
              id: chunk.id,
              content: chunk.content,
              document_id: chunk.ai_document_id,
              source: "graph_rag",
              metadata: { sequence_number: chunk.sequence_number }
            }
          end
      rescue StandardError => e
        Rails.logger.warn "[GraphRAG] Chunk collection failed: #{e.message}"
        []
      end

      def score_results(query, chunks, communities)
        return chunks if chunks.empty?

        query_embedding = @embedding_service.generate(query)
        community_node_ids = communities.flat_map { |c| c[:node_ids] }.to_set

        chunks.map do |chunk|
          base_score = 0.5

          # Embedding similarity boost
          if query_embedding && chunk[:content].present?
            chunk_embedding = @embedding_service.generate(chunk[:content])
            if chunk_embedding
              sim = @embedding_service.similarity(query_embedding, chunk_embedding)
              base_score = [sim, base_score].max
            end
          end

          # Community centrality boost (chunks from highly connected nodes score higher)
          centrality_boost = communities.any? { |c| c[:nodes].size > 3 } ? 0.1 : 0.0

          chunk.merge(score: (base_score + centrality_boost).clamp(0.0, 1.0))
        end.sort_by { |c| -c[:score] }
      end

      def build_community_summaries(communities)
        communities.filter_map do |community|
          node_names = community[:nodes].map(&:name).first(10)
          edge_types = community[:edges].map(&:relation_type).tally.sort_by { |_, v| -v }.first(3)

          label = "#{community[:seed].name} cluster (#{community[:nodes].size} nodes)"
          relations = edge_types.map { |type, count| "#{type} (#{count})" }.join(", ")

          summary = "Centered on '#{community[:seed].name}', includes: #{node_names.join(', ')}. " \
                    "Key relationships: #{relations}."

          {
            community_label: label,
            summary: summary,
            seed_node: community[:seed].name,
            node_count: community[:nodes].size,
            edge_count: community[:edges].size,
            seed_similarity: community[:seed_similarity]
          }
        end
      end

      def merge_results(graph_results, hybrid_results, top_k:)
        seen_ids = Set.new
        merged = []

        # Graph results get priority (higher base relevance)
        graph_results.each do |r|
          next if seen_ids.include?(r[:id])

          seen_ids.add(r[:id])
          merged << r.merge(source: "graph_rag")
        end

        # Fill with hybrid results
        (hybrid_results || []).each do |r|
          next if seen_ids.include?(r[:id])

          seen_ids.add(r[:id])
          merged << r
        end

        merged.sort_by { |r| -(r[:score] || 0) }.first(top_k)
      end

      def community_summary_data(community)
        {
          seed: community[:seed].name,
          node_count: community[:nodes].size,
          edge_count: community[:edges].size,
          node_types: community[:nodes].map(&:node_type).tally
        }
      end

      def empty_result(query)
        {
          results: [],
          communities: [],
          summaries: [],
          seed_nodes: [],
          metadata: {
            query: query,
            seed_nodes_found: 0,
            communities_detected: 0,
            total_chunks: 0,
            results_count: 0,
            latency_ms: 0
          }
        }
      end
    end
  end
end
