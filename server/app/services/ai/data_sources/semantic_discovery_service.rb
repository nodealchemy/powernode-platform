# frozen_string_literal: true

module Ai
  module DataSources
    # Semantic discovery of data sources, mirroring Ai::ConciergeRouter's
    # embedding + nearest_neighbors pattern but ranking Ai::DataSource rows
    # instead of skills.
    #
    # Given a natural-language query ("hourly precipitation forecast",
    # "intraday equity prices"), this service:
    #
    #   1. Embeds the query via the same Ai::Memory::EmbeddingService used by
    #      the DataSourceGraph bridge.
    #   2. Pulls the nearest data_source KG nodes via pgvector cosine
    #      nearest_neighbors.
    #   3. Maps each node back to its Ai::DataSource (eager-loaded).
    #   4. Blends a final 0..1 score from four trust signals:
    #        - semantic   : cosine similarity (1 - distance)
    #        - effectiveness : the source's rolled-up effectiveness_score
    #        - health     : 1.0 if healthy?, else 0.0
    #        - recency    : linear decay of last_used_at over a 7-day window
    #
    # Hermetic + nil-safe: when no embedding backend is available (test/CI)
    # the query embedding comes back nil and the service degrades to a
    # keyword-only ranking via KnowledgeGraphNode.search_by_name, with the
    # semantic signal neutralized. The blend never raises on missing data —
    # absent signals fall back to neutral defaults.
    #
    # Optional LLM reranking (opt-in via rerank:) routes the top candidates
    # through Ai::Rag::RerankingService. That service expects each candidate
    # to be a Hash exposing a :content string (it truncates result[:content]
    # and merges back :rerank_score), so we adapt each data source into a
    # content blob (name + description + endpoint names) before handing it
    # over, then fold the returned relevance back into the semantic signal.
    # When no scoring agent is available the reranker returns a heuristic
    # ordering, so this stays safe in hermetic environments — but because it
    # consumes an LLM call when an agent IS present, it defaults to off.
    class SemanticDiscoveryService
      # Final blend weights. Semantic relevance dominates (we are, after all,
      # answering "which source matches this intent"), with effectiveness,
      # health, and recency acting as trust/quality tie-breakers.
      WEIGHTS = {
        semantic: 0.55,
        effectiveness: 0.25,
        health: 0.10,
        recency: 0.10
      }.freeze

      # How many KG nodes to pull from pgvector before mapping + blending.
      # A generous candidate pool (independent of the caller's limit) lets the
      # post-blend re-rank promote a high-effectiveness source that the raw
      # cosine ordering placed a few slots down.
      DEFAULT_CANDIDATE_POOL = 50

      # Neutral semantic score used when there is no embedding to compare
      # against (keyword fallback path). Keeps keyword hits rankable by their
      # effectiveness/health/recency signals without pretending to a
      # similarity we never measured.
      KEYWORD_SEMANTIC_BASELINE = 0.5

      # Recency decay window — last_used_at within this many days decays
      # linearly from 1.0 (just used) to 0.0 (window-old). Mirrors the
      # freshness window in Ai::DataSource#freshness_score.
      RECENCY_WINDOW_DAYS = 7.0

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Returns a ranked Array of:
      #   { data_source:, score:, signals: { semantic:, effectiveness:, health:, recency: } }
      #
      #   query:  natural-language description of the data need (required).
      #   agent:  optional requesting agent (reserved for future per-agent
      #           attribution / permission scoping; not used in ranking yet).
      #   limit:  max results to return after ranking (default 10).
      #   rerank: when true, pass the post-blend top candidates through
      #           Ai::Rag::RerankingService and fold its relevance into the
      #           semantic signal before the final sort. Defaults to false to
      #           keep discovery hermetic and free of LLM calls.
      def discover(query:, agent: nil, limit: 10, rerank: false)
        @agent = agent
        text = query.to_s.strip
        return [] if text.blank?
        return [] if account.nil?

        candidates = semantic_candidates(text)
        candidates = keyword_candidates(text) if candidates.empty?
        return [] if candidates.empty?

        candidates = apply_rerank(text, candidates) if rerank

        candidates
          .sort_by { |c| -c[:score].to_f }
          .first(limit)
      end

      private

      # Embedding-backed candidate set. Returns [] when there is no embedding
      # backend (hermetic) or no data_source nodes carry embeddings yet, so
      # the caller can fall through to the keyword path.
      def semantic_candidates(text)
        embedding = embedding_service.generate(text)
        return [] if embedding.blank?

        nodes = account.ai_knowledge_graph_nodes
                       .data_source_nodes
                       .active
                       .with_embeddings
                       .nearest_neighbors(:embedding, embedding, distance: "cosine")
                       .first(DEFAULT_CANDIDATE_POOL)
        return [] if nodes.blank?

        sources_by_id = sources_for(nodes)

        nodes.filter_map do |node|
          ds = sources_by_id[node.ai_data_source_id]
          next if ds.nil?

          semantic = cosine_similarity(node.neighbor_distance)
          build_candidate(ds, semantic)
        end
      rescue StandardError => e
        ::Rails.logger.warn("[SemanticDiscovery] semantic discovery failed: #{e.class}: #{e.message}")
        []
      end

      # Keyword fallback — used when there is no usable embedding or the
      # semantic path surfaced nothing. Matches the data_source node name and
      # neutralizes the semantic signal (we never measured similarity here).
      def keyword_candidates(text)
        nodes = account.ai_knowledge_graph_nodes
                       .data_source_nodes
                       .active
                       .search_by_name(text)
                       .limit(DEFAULT_CANDIDATE_POOL)
                       .to_a
        return [] if nodes.empty?

        sources_by_id = sources_for(nodes)

        nodes.filter_map do |node|
          ds = sources_by_id[node.ai_data_source_id]
          next if ds.nil?

          build_candidate(ds, KEYWORD_SEMANTIC_BASELINE)
        end
      rescue StandardError => e
        ::Rails.logger.warn("[SemanticDiscovery] keyword discovery failed: #{e.class}: #{e.message}")
        []
      end

      # Eager-load the backing Ai::DataSource rows (with the associations the
      # blend + serialization touch) for a set of KG nodes, indexed by id.
      def sources_for(nodes)
        ids = nodes.map(&:ai_data_source_id).compact.uniq
        return {} if ids.empty?

        ::Ai::DataSource
          .where(account_id: account.id, id: ids)
          .includes(:knowledge_graph_node, :endpoints)
          .index_by(&:id)
      end

      # Builds a ranked candidate hash from a data source + its semantic
      # similarity, blending in effectiveness, health, and recency signals.
      def build_candidate(data_source, semantic)
        signals = {
          semantic: round_signal(semantic),
          effectiveness: round_signal(effectiveness_signal(data_source)),
          health: round_signal(health_signal(data_source)),
          recency: round_signal(recency_signal(data_source))
        }

        {
          data_source: data_source,
          score: blended_score(signals),
          signals: signals
        }
      end

      # Weighted sum of the four signals, clamped to 0..1.
      def blended_score(signals)
        score = WEIGHTS.sum { |key, weight| weight * signals[key].to_f }
        score.clamp(0.0, 1.0).round(4)
      end

      # pgvector cosine distance: 0 == identical, 2 == opposite. Convert to a
      # 0..1 similarity. nil distance (shouldn't happen on the semantic path)
      # degrades to the neutral baseline rather than blowing up the blend.
      def cosine_similarity(distance)
        return KEYWORD_SEMANTIC_BASELINE if distance.nil?

        (1.0 - distance.to_f).clamp(0.0, 1.0)
      end

      def effectiveness_signal(data_source)
        data_source.effectiveness_score.to_f.clamp(0.0, 1.0)
      end

      def health_signal(data_source)
        data_source.healthy? ? 1.0 : 0.0
      end

      # Linear recency decay over RECENCY_WINDOW_DAYS from last_used_at.
      # Never-used sources get a neutral 0.5 so they are not unfairly buried
      # beneath stale-but-recently-touched sources.
      def recency_signal(data_source)
        used_at = data_source.last_used_at
        return 0.5 if used_at.nil?

        age_days = (::Time.current - used_at) / 1.day
        return 1.0 if age_days <= 0

        (1.0 - (age_days / RECENCY_WINDOW_DAYS)).clamp(0.0, 1.0)
      end

      # Optionally refine the top of the candidate list with the RAG reranker.
      # RerankingService#rerank(query:, results:) wants each result to carry a
      # :content string and returns the same hashes merged with :rerank_score
      # (0..1). We adapt each candidate into a content blob, rerank, then fold
      # the relevance back into the semantic signal and re-blend. If the
      # reranker yields nothing usable we leave the original candidates intact.
      def apply_rerank(text, candidates)
        adapted = candidates.map do |candidate|
          candidate.merge(content: rerank_content(candidate[:data_source]))
        end

        reranked = reranking_service.rerank(query: text, results: adapted)
        return candidates if reranked.blank?

        reranked.map do |entry|
          relevance = entry[:rerank_score]
          # No score for this entry → keep its prior blended score untouched.
          next entry.except(:content, :rerank_score) if relevance.nil?

          signals = entry[:signals].merge(semantic: round_signal(relevance.to_f.clamp(0.0, 1.0)))
          {
            data_source: entry[:data_source],
            score: blended_score(signals),
            signals: signals
          }
        end
      rescue StandardError => e
        ::Rails.logger.warn("[SemanticDiscovery] rerank failed, using blended order: #{e.class}: #{e.message}")
        candidates
      end

      # Content blob the reranker scores against: name + description +
      # endpoint names, mirroring the embedding text the bridge builds.
      def rerank_content(data_source)
        parts = [data_source.name]
        parts << data_source.description if data_source.description.present?
        endpoint_names = data_source.endpoints.map(&:name).compact
        parts << "endpoints: #{endpoint_names.join(', ')}" if endpoint_names.any?
        parts.join(" | ")
      end

      def embedding_service
        @embedding_service ||= ::Ai::Memory::EmbeddingService.new(account: account)
      end

      def reranking_service
        @reranking_service ||= ::Ai::Rag::RerankingService.new(account)
      end

      def round_signal(value)
        value.to_f.round(4)
      end
    end
  end
end
