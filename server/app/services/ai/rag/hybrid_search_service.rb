# frozen_string_literal: true

module Ai
  module Rag
    class HybridSearchServiceError < StandardError; end

    class HybridSearchService
      RRF_K = 60 # Reciprocal Rank Fusion constant
      DEFAULT_TOP_K = 10

      def initialize(account)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Perform hybrid search across vector, keyword, and graph modes
      def search(query:, mode: :hybrid, top_k: DEFAULT_TOP_K, **opts)
        mode = mode.to_s
        top_k = [top_k.to_i, 50].min
        start_time = Time.current

        knowledge_base_id = opts[:knowledge_base_id]

        vector_results = []
        keyword_results = []
        graph_results = []

        case mode
        when "vector"
          vector_results = vector_search(query, top_k: top_k, knowledge_base_id: knowledge_base_id)
        when "keyword"
          keyword_results = keyword_search(query, top_k: top_k, knowledge_base_id: knowledge_base_id)
        when "graph"
          graph_results = graph_search(query, top_k: top_k)
        when "hybrid"
          vector_results = vector_search(query, top_k: top_k, knowledge_base_id: knowledge_base_id)
          keyword_results = keyword_search(query, top_k: top_k, knowledge_base_id: knowledge_base_id)
          graph_results = graph_search(query, top_k: top_k)
        else
          raise HybridSearchServiceError, "Invalid search mode: #{mode}"
        end

        # Fuse results
        fusion_method = opts[:fusion_method] || "rrf"
        merged = case fusion_method
                 when "rrf"
                   reciprocal_rank_fusion(vector_results, keyword_results, graph_results, top_k: top_k)
                 when "weighted"
                   weighted_fusion(vector_results, keyword_results, graph_results, top_k: top_k, weights: opts[:weights])
                 else
                   reciprocal_rank_fusion(vector_results, keyword_results, graph_results, top_k: top_k)
                 end

        latency_ms = ((Time.current - start_time) * 1000).round

        # Record search result
        record = Ai::HybridSearchResult.create!(
          account: @account,
          query_text: query,
          search_mode: mode,
          vector_results: vector_results.map { |r| r.except(:content) },
          keyword_results: keyword_results.map { |r| r.except(:content) },
          graph_results: graph_results.map { |r| r.except(:content) },
          merged_results: merged.map { |r| r.except(:content) },
          result_count: merged.size,
          vector_score: vector_results.first&.dig(:score),
          keyword_score: keyword_results.first&.dig(:score),
          graph_score: graph_results.first&.dig(:score),
          fusion_method: fusion_method,
          total_latency_ms: latency_ms
        )

        {
          results: merged,
          scores: {
            vector: vector_results.size,
            keyword: keyword_results.size,
            graph: graph_results.size,
            merged: merged.size
          },
          metadata: {
            search_id: record.id,
            mode: mode,
            fusion_method: fusion_method,
            latency_ms: latency_ms
          }
        }
      end

      private

      # Vector search using pgvector nearest_neighbors on document chunks
      def vector_search(query, top_k:, knowledge_base_id: nil)
        query_embedding = @embedding_service.generate(query)
        return [] unless query_embedding

        scope = Ai::DocumentChunk.with_embeddings
        scope = scope.for_knowledge_base(knowledge_base_id) if knowledge_base_id

        # Check if any chunks with embeddings exist
        return [] unless scope.exists?

        candidates = scope
          .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
          .first(top_k * 2)

        # Filter to reasonable similarity and take top_k
        candidates
          .select { |c| c.neighbor_distance <= 0.6 }
          .first(top_k)
          .map do |chunk|
            {
              id: chunk.id,
              type: "document_chunk",
              document_id: chunk.document_id,
              content: chunk.content,
              score: (1.0 - chunk.neighbor_distance).round(4),
              source: "vector",
              metadata: { sequence_number: chunk.sequence_number }
            }
          end
      end

      # Keyword search using PostgreSQL full-text search
      def keyword_search(query, top_k:, knowledge_base_id: nil)
        return [] if query.blank?

        sanitized_query = query.gsub(/[^\w\s]/, " ").split.reject { |w| w.length < 2 }.first(10)
        return [] if sanitized_query.empty?

        tsquery = sanitized_query.map { |w| "#{w}:*" }.join(" & ")

        scope = Ai::DocumentChunk.all
        scope = scope.for_knowledge_base(knowledge_base_id) if knowledge_base_id

        results = scope
          .where("to_tsvector('english', content) @@ to_tsquery('english', ?)", tsquery)
          .select(
            "ai_document_chunks.*",
            Arel.sql("ts_rank(to_tsvector('english', content), to_tsquery('english', #{ActiveRecord::Base.connection.quote(tsquery)})) AS rank")
          )
          .order(Arel.sql("rank DESC"))
          .limit(top_k)

        results.map do |chunk|
          {
            id: chunk.id,
            type: "document_chunk",
            document_id: chunk.document_id,
            content: chunk.content,
            score: chunk.respond_to?(:rank) ? chunk.rank.to_f.round(4) : 0.5,
            source: "keyword",
            metadata: { sequence_number: chunk.sequence_number }
          }
        end
      rescue StandardError => e
        Rails.logger.warn "[HybridSearchService] Keyword search failed: #{e.message}"
        []
      end

      # Graph search: find seed nodes from query, expand, collect associated document chunks
      def graph_search(query, top_k:)
        query_embedding = @embedding_service.generate(query)
        return [] unless query_embedding

        nodes_scope = @account.ai_knowledge_graph_nodes.active.with_embeddings
        return [] unless nodes_scope.exists?

        # Find seed nodes
        seed_nodes = nodes_scope
          .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
          .first(5)
          .select { |n| n.neighbor_distance <= 0.5 }

        return [] if seed_nodes.empty?

        # Collect associated document chunks from seed nodes and their neighbors
        document_ids = seed_nodes.filter_map(&:source_document_id).uniq

        # Also expand to get neighbor nodes' documents
        graph_service = Ai::KnowledgeGraph::GraphService.new(@account)
        seed_nodes.each do |node|
          neighbors = graph_service.find_neighbors(node: node, depth: 2)
          doc_ids = @account.ai_knowledge_graph_nodes
            .where(id: neighbors.map { |n| n[:id] })
            .where.not(source_document_id: nil)
            .pluck(:source_document_id)
          document_ids.concat(doc_ids)
        end

        document_ids = document_ids.uniq.first(20)
        return [] if document_ids.empty?

        chunks = Ai::DocumentChunk
          .where(document_id: document_ids)
          .with_embeddings
          .limit(top_k * 2)

        # Score chunks by their embedding similarity to query
        if query_embedding && chunks.any?
          scored = chunks.map do |chunk|
            sim = chunk.similarity_with(query_embedding)
            {
              id: chunk.id,
              type: "document_chunk",
              document_id: chunk.document_id,
              content: chunk.content,
              score: sim.round(4),
              source: "graph",
              metadata: {
                sequence_number: chunk.sequence_number,
                graph_seed_nodes: seed_nodes.map { |n| { id: n.id, name: n.name } }
              }
            }
          end

          scored.sort_by { |r| -r[:score] }.first(top_k)
        else
          chunks.first(top_k).map do |chunk|
            {
              id: chunk.id,
              type: "document_chunk",
              document_id: chunk.document_id,
              content: chunk.content,
              score: 0.3,
              source: "graph",
              metadata: { sequence_number: chunk.sequence_number }
            }
          end
        end
      rescue StandardError => e
        Rails.logger.warn "[HybridSearchService] Graph search failed: #{e.message}"
        []
      end

      # Reciprocal Rank Fusion - combines multiple ranked lists
      def reciprocal_rank_fusion(*result_lists, top_k:)
        scores = {}

        result_lists.flatten.each_with_index.group_by { |item, _| item[:id] }.each do |id, group|
          # Calculate RRF score across all lists
          rrf_score = 0.0
          best_item = nil

          result_lists.each do |list|
            rank = list.index { |item| item[:id] == id }
            if rank
              rrf_score += 1.0 / (RRF_K + rank + 1)
              best_item ||= list[rank]
            end
          end

          if best_item
            scores[id] = {
              item: best_item.merge(rrf_score: rrf_score.round(6)),
              score: rrf_score
            }
          end
        end

        scores.values
          .sort_by { |v| -v[:score] }
          .first(top_k)
          .map { |v| v[:item] }
      end

      # Weighted fusion - apply weights to each search mode
      def weighted_fusion(vector_results, keyword_results, graph_results, top_k:, weights: nil)
        weights ||= { vector: 0.5, keyword: 0.3, graph: 0.2 }

        scores = {}

        apply_weighted_scores(scores, vector_results, weights[:vector] || 0.5)
        apply_weighted_scores(scores, keyword_results, weights[:keyword] || 0.3)
        apply_weighted_scores(scores, graph_results, weights[:graph] || 0.2)

        scores.values
          .sort_by { |v| -v[:weighted_score] }
          .first(top_k)
          .map { |v| v[:item].merge(score: v[:weighted_score].round(4)) }
      end

      def apply_weighted_scores(scores, results, weight)
        results.each do |result|
          id = result[:id]
          existing = scores[id]

          weighted = (result[:score] || 0.0) * weight

          if existing
            existing[:weighted_score] += weighted
          else
            scores[id] = {
              item: result,
              weighted_score: weighted
            }
          end
        end
      end
    end
  end
end
