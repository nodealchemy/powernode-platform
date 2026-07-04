# frozen_string_literal: true

module Ai
  module Learning
    # P1 (learning-to-skill-promotion campaign): groups high-value compound
    # learnings into topic clusters by embedding similarity. Read/analyze
    # only — never mutates a learning or creates a skill. The cluster
    # candidates this returns are the input P2 turns into a proposed skill
    # (operator-review gated) via Ai::SkillGraph::EvolutionProposalService's
    # propose-only pattern.
    #
    # Candidate pool: the same "quality, surfacing-set" bar #promote_cross_team
    # already established — status active/verified (retired/deprecated/
    # superseded/disproven are never candidates, see Ai::CompoundLearning::
    # STATUSES and C1's retire_domain!), confidence/effectiveness gated by
    # Ai::Learning::CompoundLearningService's MIN_PROMOTION_CONFIDENCE /
    # MIN_PROMOTION_EFFECTIVENESS rather than inventing new thresholds.
    # Ranked by #effective_importance (importance blended with observed
    # injection outcomes) so the most-proven learnings seed clusters first.
    #
    # Algorithm: greedy threshold nearest-neighbor grouping over the existing
    # pgvector embeddings (has_neighbors :embedding on Ai::CompoundLearning) —
    # no new clustering gem, no re-embedding. Walk candidates highest
    # effective_importance first; join the nearest existing cluster if its
    # seed is within similarity_threshold, else open a new cluster (bounded by
    # max_clusters) with this learning as its seed. Mirrors the seed-based
    # assignment in Ai::Codebase::ClusteringService, simplified to a single
    # threshold pass (no fixed k, no farthest-first seed selection) since we
    # want "does this belong with something already found," not a fixed
    # partition of the whole corpus.
    class LearningClusterService
      # Config knobs, resolved Account#settings -> constant fallback (matches
      # Ai::ModelRefusalPromotionService's config-driven-config convention —
      # no bare magic numbers per the no-hardcoded-budgets rule).
      DEFAULT_SIMILARITY_THRESHOLD = 0.75
      DEFAULT_MIN_CLUSTER_SIZE = 2
      DEFAULT_MAX_CLUSTERS = 20
      DEFAULT_CANDIDATE_LIMIT = 300

      # Label-generation stopwords for the text-term fallback (used only when
      # cluster members carry no tags to summarize from — natural-language
      # learning content, unlike Codebase::ClusteringService's code
      # identifiers, is full of these).
      LABEL_STOPWORDS = %w[
        this that with from into over under while when then than also each
        other every some more most less least does did has have had was
        were been being always never often about above below there their
        which where what your yours ours because since still until unless
        instead rather across along again against between during without
      ].freeze

      def initialize(account:)
        @account = account
      end

      # @return [Hash] { success:, clusters:, unclustered_learning_ids:,
      #   total_candidates:, config: }
      def cluster(similarity_threshold: nil, min_cluster_size: nil, max_clusters: nil, candidate_limit: nil)
        threshold = resolve_similarity_threshold(similarity_threshold)
        min_size = resolve_min_cluster_size(min_cluster_size)
        cap = resolve_max_clusters(max_clusters)
        limit = resolve_candidate_limit(candidate_limit)

        candidates = load_candidates(limit)
        return empty_result(threshold, min_size, cap, limit) if candidates.empty?

        seeds, unclustered = assign_to_clusters(candidates, threshold, cap)

        clusters = []
        seeds.each_with_index do |seed, idx|
          members = seed[:members]
          if members.size < min_size
            unclustered.concat(members)
            next
          end

          clusters << build_cluster(idx, seed[:learning], members)
        end

        {
          success: true,
          clusters: clusters.sort_by { |c| -c[:member_count] },
          unclustered_learning_ids: unclustered.map(&:id),
          total_candidates: candidates.size,
          config: {
            similarity_threshold: threshold,
            min_cluster_size: min_size,
            max_clusters: cap,
            candidate_limit: limit
          }
        }
      rescue StandardError => e
        Rails.logger.error("[LearningClusterService] cluster failed: #{e.message}")
        { success: false, error: e.message, clusters: [], unclustered_learning_ids: [], total_candidates: 0 }
      end

      private

      # ==================================================
      # Candidate selection
      # ==================================================

      def load_candidates(limit)
        scope = Ai::CompoundLearning
          .for_account(@account.id)
          .where(status: %w[active verified])
          .with_embedding
          .where("confidence_score >= ?", Ai::Learning::CompoundLearningService::MIN_PROMOTION_CONFIDENCE)
          .where("effectiveness_score IS NULL OR effectiveness_score >= ?", Ai::Learning::CompoundLearningService::MIN_PROMOTION_EFFECTIVENESS)

        # SQL-side ordering by importance_score bounds the fetch to the most
        # promising slice before the final effective_importance rank (which
        # blends in injection outcomes and can only be computed per-instance,
        # same reasoning as CompoundLearningService#ranked_learning_candidates).
        scope.order(importance_score: :desc).limit(limit).to_a
          .sort_by { |l| -l.effective_importance }
      end

      # ==================================================
      # Clustering
      # ==================================================

      def assign_to_clusters(candidates, threshold, cap)
        seeds = []
        unclustered = []

        candidates.each do |learning|
          vector = vector_array(learning.embedding)
          next unless vector

          best_idx, best_similarity = nearest_seed(vector, seeds)

          if best_idx && best_similarity >= threshold
            seeds[best_idx][:members] << learning
          elsif seeds.size < cap
            seeds << { learning: learning, vector: vector, members: [learning] }
          else
            unclustered << learning
          end
        end

        [seeds, unclustered]
      end

      def nearest_seed(vector, seeds)
        best_idx = nil
        best_similarity = -1.0

        seeds.each_with_index do |seed, idx|
          similarity = cosine_similarity(vector, seed[:vector])
          if similarity > best_similarity
            best_similarity = similarity
            best_idx = idx
          end
        end

        [best_idx, best_similarity]
      end

      def vector_array(embedding)
        return nil if embedding.nil?

        embedding.is_a?(String) ? JSON.parse(embedding) : embedding.to_a
      end

      def cosine_similarity(a, b)
        dot = 0.0
        mag_a = 0.0
        mag_b = 0.0

        a.each_index do |i|
          x = a[i]
          y = b[i]
          dot += x * y
          mag_a += x * x
          mag_b += y * y
        end

        mag_a = Math.sqrt(mag_a)
        mag_b = Math.sqrt(mag_b)
        return 0.0 if mag_a.zero? || mag_b.zero?

        dot / (mag_a * mag_b)
      end

      # ==================================================
      # Cluster candidate assembly (this is what P2 consumes)
      # ==================================================

      def build_cluster(idx, seed_learning, members)
        effectiveness_values = members.filter_map(&:effectiveness_score)
        majority_category = members.group_by(&:category).max_by { |_, group| group.size }&.first

        {
          cluster_id: idx,
          label: generate_label(members, majority_category),
          category: majority_category,
          tags: top_tags(members),
          member_ids: members.map(&:id),
          member_count: members.size,
          seed_id: seed_learning.id,
          representative_summary: seed_learning.title.presence || seed_learning.content.truncate(160),
          aggregate: {
            total_positive_outcome_count: members.sum(&:positive_outcome_count),
            total_negative_outcome_count: members.sum(&:negative_outcome_count),
            total_injection_count: members.sum(&:injection_count),
            mean_confidence_score: mean(members.map(&:confidence_score)),
            mean_effectiveness_score: effectiveness_values.empty? ? nil : mean(effectiveness_values),
            mean_importance_score: mean(members.map(&:importance_score)),
            mean_effective_importance: mean(members.map(&:effective_importance))
          }
        }
      end

      def top_tags(members, count: 3)
        tags = members.flat_map { |m| Array(m.tags) }
        tags.tally.sort_by { |_, n| -n }.first(count).map(&:first)
      end

      # Tags first (already curated, human-authored labels); falls back to
      # term extraction from title/content (mirrors
      # Ai::Codebase::ClusteringService#generate_label's approach, adapted for
      # natural-language sentences rather than code identifiers); falls back
      # to the majority category.
      def generate_label(members, majority_category)
        tags = top_tags(members)
        return tags.map { |t| humanize_term(t) }.join(" / ") if tags.any?

        terms = members.flat_map do |m|
          [m.title, m.content].compact.join(" ")
            .downcase
            .split(/[^a-z0-9]+/)
            .reject { |t| t.length < 4 || LABEL_STOPWORDS.include?(t) }
        end
        top_terms = terms.tally.sort_by { |_, n| -n }.first(3).map(&:first)
        return top_terms.map { |t| t.capitalize }.join(" / ") if top_terms.any?

        majority_category&.humanize || "Cluster"
      end

      def humanize_term(term)
        term.to_s.tr("_-", "  ").split.map(&:capitalize).join(" ")
      end

      def mean(values)
        return nil if values.empty?

        (values.sum.to_f / values.size).round(4)
      end

      def empty_result(threshold, min_size, cap, limit)
        {
          success: true,
          clusters: [],
          unclustered_learning_ids: [],
          total_candidates: 0,
          config: {
            similarity_threshold: threshold,
            min_cluster_size: min_size,
            max_clusters: cap,
            candidate_limit: limit
          }
        }
      end

      # ==================================================
      # Config resolution (Account#settings -> constant fallback)
      # ==================================================

      def resolve_similarity_threshold(explicit)
        value = explicit.presence || setting("ai_learning_cluster_similarity_threshold").presence || DEFAULT_SIMILARITY_THRESHOLD
        value.to_f.clamp(0.0, 1.0)
      end

      def resolve_min_cluster_size(explicit)
        value = explicit.presence || setting("ai_learning_cluster_min_size").presence || DEFAULT_MIN_CLUSTER_SIZE
        value.to_i.clamp(1, 50)
      end

      def resolve_max_clusters(explicit)
        value = explicit.presence || setting("ai_learning_cluster_max_clusters").presence || DEFAULT_MAX_CLUSTERS
        value.to_i.clamp(1, 100)
      end

      def resolve_candidate_limit(explicit)
        value = explicit.presence || setting("ai_learning_cluster_candidate_limit").presence || DEFAULT_CANDIDATE_LIMIT
        value.to_i.clamp(10, 2_000)
      end

      def setting(key)
        s = @account&.settings
        return nil unless s.is_a?(Hash)

        s[key] || s[key.to_sym]
      end
    end
  end
end
