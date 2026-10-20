# frozen_string_literal: true

module Ai
  module Skills
    # Runs every capability skill's evals through discovery-style ranking with
    # a chosen embedding space and the PRODUCTION seed cut-off, and reports
    # hit@1, hit@3 and false-firsts per eval. Read-only apart from the
    # embeddings it must compute (cached per account by the embedding service):
    # it reads the authored YAML batches of every loaded owner plus the legacy
    # skill rows already in the database, and writes nothing.
    #
    # It ranks the way TraversalService picks its SEEDS — cosine over the same
    # embedding text, distance <= SEED_DISTANCE_THRESHOLD, top-N, then the
    # project-kind facet — without graph expansion, so the result reflects
    # whether each skill's own triggers reach its tasks.
    class DiscoveryEvalRunner
      SEED_LIMIT = 10

      Row = Struct.new(:slug, :task, :expected, :project_kind, :rank, :top, keyword_init: true) do
        def hit1 = expected && rank == 1
        def hit3 = expected && rank.present? && rank <= 3
        def false_first = !expected && rank == 1
        def false_top3 = !expected && rank.present? && rank <= 3
      end

      attr_reader :rows, :embedder

      # @param legacy [Boolean] include the legacy (pre-contract) rows as
      #   competition — true for today's picture, false for the post-retirement one
      def initialize(embedder: :provider, account: nil, threshold: ::Ai::SkillGraph::TraversalService::SEED_DISTANCE_THRESHOLD, legacy: true)
        @embedder = SkillEmbedder.new(embedder, account: account)
        @threshold = threshold
        @legacy = legacy
      end

      def run
        candidates = capability_candidates + (@legacy ? legacy_candidates : [])
        evals = capability_candidates.flat_map do |c|
          Array(c[:metadata]["evals"]).map { |ev| { slug: c[:slug], task: ev["task"], expected: ev["expect_selected"], project_kind: ev["project_kind"] } }
        end

        texts = candidates.to_h { |c| [ [ :skill, c[:slug] ], c[:text] ] }
        evals.each_with_index { |ev, i| texts[[ :task, i ]] = ev[:task] }
        vectors = embedder.embed_all(texts)

        @rows = evals.each_with_index.map do |ev, i|
          ranked = rank(vectors[[ :task, i ]], candidates, vectors, ev[:project_kind])
          Row.new(slug: ev[:slug], task: ev[:task], expected: ev[:expected], project_kind: ev[:project_kind],
                  rank: ranked.index(ev[:slug])&.+(1), top: ranked.first(3))
        end
        self
      end

      def totals
        positives = rows.select(&:expected)
        negatives = rows.reject(&:expected)
        {
          embedder: embedder.mode_used,
          threshold: @threshold,
          legacy: @legacy,
          evals: rows.size,
          positives: positives.size,
          hit1: positives.count(&:hit1),
          hit3: positives.count(&:hit3),
          negatives: negatives.size,
          false_first: negatives.count(&:false_first),
          false_top3: negatives.count(&:false_top3),
          empty: rows.count { |r| r.top.empty? }
        }
      end

      private

      def rank(task_vector, candidates, vectors, project_kind)
        scored = candidates.filter_map do |c|
          similarity = LexicalEmbedder.cosine(task_vector, vectors[[ :skill, c[:slug] ]])
          next if (1.0 - similarity) > @threshold

          [ c, similarity ]
        end
        seeds = scored.sort_by { |_, s| -s }.first(SEED_LIMIT).map(&:first)
                      .select { |c| SelectionFacets.applies?(c[:metadata], project_kind) }
        SelectionFacets.resolve_refinements(seeds, project_kind) { |c| [ c[:slug], c[:metadata] ] }.map { |c| c[:slug] }
      end

      def capability_candidates
        @capability_candidates ||= CapabilitySeeder.data_sources.flat_map do |owner, dir|
          CapabilitySeeder.load_entries(dir).map do |raw|
            entry = CapabilitySeeder.normalize(raw, owner)
            skill = ::Ai::Skill.new(entry.slice("name", "description", "category", "tags", "metadata"))
            { slug: entry["slug"], metadata: entry["metadata"], text: ::Ai::SkillGraph::BridgeService.embedding_text_for(skill) }
          end
        end
      end

      # Legacy (pre-contract) global rows still selectable today.
      def legacy_candidates
        authored = capability_candidates.map { |c| c[:slug] }
        ::Ai::Skill.global.active.enabled.where.not("ai_skills.metadata ? 'capability'").where.not(slug: authored).map do |skill|
          { slug: skill.slug, metadata: skill.metadata.is_a?(Hash) ? skill.metadata : {}, text: ::Ai::SkillGraph::BridgeService.embedding_text_for(skill) }
        end
      end
    end
  end
end
