# frozen_string_literal: true

module Ai
  module Learning
    # P2 (learning-to-skill-promotion campaign): promotes a P1 cluster
    # candidate (Ai::Learning::LearningClusterService#cluster's clusters[i]
    # hash) into a skill. Two-phase, operator-review gated the whole way —
    # never auto-creates or activates anything:
    #
    #   1. #propose_from_cluster drafts an Ai::SkillProposal from the cluster
    #      (REUSING Ai::SkillGraph::LifecycleService's existing draft ->
    #      proposed pipeline — no new skill-authoring path) and files an
    #      Ai::ImprovementRecommendation ("skill_creation", already a valid
    #      RECOMMENDATION_TYPE) pointing at it. Mirrors F5's
    #      EvolutionProposalService: draft via the existing seam, surface via
    #      the existing recommendations review queue. Never creates or
    #      activates a skill.
    #
    #   2. #apply_approved_proposal! runs only once an operator has approved
    #      the underlying SkillProposal (status "approved") — its single
    #      trigger is Ai::Learning::ImprovementRecommender#apply_recommendation!'s
    #      "skill_creation" case. It creates the skill (or clone-on-evolves a
    #      matching existing one), wires KG provenance edges to the source
    #      learnings, seeds effectiveness_score from the cluster's observed
    #      outcome aggregate (never the bare 0.5 schema default), and
    #      supersedes the source learnings (P3) so the corpus stops
    #      resurfacing content that's now embodied in the approved skill.
    #
    # Structural never-auto-approve guarantee: propose_from_cluster never sets
    # trust_tier_at_proposal, so Ai::SkillProposal#can_auto_approve? (which
    # requires "trusted"/"autonomous") is always false here —
    # LifecycleService#submit_proposal's auto-approve branch is unreachable
    # for cluster-sourced proposals regardless of the
    # :skill_lifecycle_auto_create flag.
    class LearningToSkillPromoter
      # Cosine similarity between a cluster's seed-learning embedding and the
      # nearest existing skill KG node above which the cluster is treated as
      # reinforcing that EXISTING skill (clone-on-evolve refresh) rather than
      # a brand-new one. Mirrors the "has a match" side of
      # SelfLearningService#detect_capability_gaps's 0.5 gap-detection
      # cutoff, but stricter — an actual skill mapping should read as a
      # closer match than "merely worth flagging as a possible gap."
      EXISTING_SKILL_MATCH_THRESHOLD = 0.75

      # Cap on source learnings that get a system_prompt bullet / a KG
      # provenance edge per promotion — clusters can have many members; bound
      # both the prompt size and the edge-creation fan-out.
      MAX_SOURCE_LEARNINGS = 10

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Draft + submit a SkillProposal from a cluster, then file the
      # operator-facing recommendation. Idempotent per cluster seed learning
      # — returns the existing proposal/recommendation instead of filing a
      # duplicate.
      def propose_from_cluster(cluster)
        existing = pending_proposal_for(cluster)
        if existing
          return { proposal: existing, recommendation: pending_recommendation_for(existing), reused: true }
        end

        proposal = lifecycle_service.create_proposal(attributes: proposal_attributes(cluster))
        proposal = lifecycle_service.submit_proposal(proposal_id: proposal.id)
        recommendation = create_recommendation!(cluster, proposal)

        { proposal: proposal, recommendation: recommendation, reused: false }
      end

      # Apply an operator-approved cluster proposal: create/refresh the
      # skill, wire provenance, inherit effectiveness. Raises unless the
      # proposal is already "approved" — i.e. an operator said yes via the
      # existing SkillProposal approve gate.
      def apply_approved_proposal!(proposal_id)
        proposal = find_proposal!(proposal_id)
        unless proposal.status == "approved"
          raise ArgumentError, "SkillProposal #{proposal_id} must be approved before applying (status: #{proposal.status})"
        end

        matched_skill = matching_existing_skill(proposal)
        skill = matched_skill ? refresh_existing_skill!(matched_skill, proposal) : create_new_skill!(proposal)

        create_provenance_edges!(skill, proposal)
        supersede_source_learnings!(skill, proposal)

        { skill: skill, proposal: proposal.reload, matched_existing: matched_skill.present? }
      end

      private

      # ==================================================
      # Propose phase
      # ==================================================

      def pending_proposal_for(cluster)
        Ai::SkillProposal.for_account(account.id)
          .where.not(status: "rejected")
          .where("metadata @> ?", { "cluster_seed_learning_id" => cluster[:seed_id] }.to_json)
          .order(created_at: :desc)
          .first
      end

      def pending_recommendation_for(proposal)
        Ai::ImprovementRecommendation.where(
          account: account, recommendation_type: "skill_creation",
          target_type: "Ai::SkillProposal", target_id: proposal.id
        ).order(created_at: :desc).first
      end

      def proposal_attributes(cluster)
        learnings = source_learnings(cluster)

        {
          name: cluster_name(cluster),
          description: build_description(cluster),
          category: normalize_category(cluster),
          tags: Array(cluster[:tags]),
          system_prompt: build_system_prompt(cluster, learnings),
          confidence_score: cluster_confidence(cluster),
          metadata: {
            "source" => "learning_cluster_promotion",
            "cluster_seed_learning_id" => cluster[:seed_id],
            "source_learning_ids" => cluster[:member_ids],
            "cluster_aggregate" => (cluster[:aggregate] || {}).stringify_keys,
            "cluster_label" => cluster[:label]
          }
        }
      end

      def create_recommendation!(cluster, proposal)
        Ai::ImprovementRecommendation.create!(
          account: account,
          recommendation_type: "skill_creation",
          target_type: "Ai::SkillProposal",
          target_id: proposal.id,
          confidence_score: cluster_confidence(cluster),
          status: "pending",
          recommended_config: { "skill_proposal_id" => proposal.id },
          evidence: {
            "title" => "Promote learning cluster '#{cluster[:label]}' to a skill",
            "description" => "#{cluster[:member_count]} related learnings (seed ##{cluster[:seed_id]}) suggest a " \
                              "reusable skill. A draft proposal ('#{proposal.name}') has been generated — approve " \
                              "to create/refresh the skill, or dismiss to keep these as standalone learnings.",
            "cluster_label" => cluster[:label],
            "cluster_category" => cluster[:category],
            "member_count" => cluster[:member_count],
            "source_learning_ids" => cluster[:member_ids],
            "skill_proposal_id" => proposal.id,
            "skill_proposal_name" => proposal.name
          }
        )
      end

      def source_learnings(cluster)
        Ai::CompoundLearning.where(id: cluster[:member_ids], account_id: account.id)
          .order(importance_score: :desc)
          .limit(MAX_SOURCE_LEARNINGS)
      end

      def cluster_name(cluster)
        label = cluster[:label].presence || "Learning cluster #{cluster[:seed_id]}"
        "#{label} (learning cluster)"
      end

      def build_description(cluster)
        "Auto-drafted from #{cluster[:member_count]} related compound learnings — seed: " \
          "#{cluster[:representative_summary].to_s.truncate(200)}"
      end

      def build_system_prompt(cluster, learnings)
        bullets = learnings.map { |l| "- #{l.content.truncate(240)}" }.join("\n")
        <<~PROMPT.strip
          # #{cluster[:label]}

          Drafted from a cluster of #{cluster[:member_count]} related compound learnings. Apply these proven patterns:

          #{bullets}
        PROMPT
      end

      # Learning categories (pattern/anti_pattern/best_practice/...) aren't
      # valid Ai::Skill categories (productivity/devops/security/...) — the
      # two taxonomies don't overlap. Only promote a tag straight into the
      # category slot when it happens to BE a valid skill category (e.g. a
      # cluster tagged "devops"); otherwise fall back to "productivity", the
      # same uncategorized default Ai::SkillGraph::LifecycleService#infer_category
      # already uses.
      def normalize_category(cluster)
        candidate = Array(cluster[:tags]).find { |t| Ai::Skill.all_categories.include?(t.to_s) }
        candidate || "productivity"
      end

      def cluster_confidence(cluster)
        agg = (cluster[:aggregate] || {}).with_indifferent_access
        (agg[:mean_effective_importance] || agg[:mean_confidence_score] || 0.5).to_f.clamp(0.0, 1.0).round(4)
      end

      # ==================================================
      # Apply phase
      # ==================================================

      def find_proposal!(proposal_id)
        Ai::SkillProposal.find_by!(id: proposal_id, account_id: account.id)
      end

      # Mirrors SelfLearningService#detect_capability_gaps's "does an existing
      # skill already cover this" check: nearest active skill KG node to the
      # cluster's seed learning embedding, by cosine similarity.
      def matching_existing_skill(proposal)
        seed_id = proposal.metadata["cluster_seed_learning_id"]
        return nil if seed_id.blank?

        seed_learning = Ai::CompoundLearning.find_by(id: seed_id, account_id: account.id)
        return nil unless seed_learning&.embedding

        candidate = account.ai_knowledge_graph_nodes
          .skill_nodes.active.with_embeddings
          .nearest_neighbors(:embedding, seed_learning.embedding, distance: "cosine")
          .first
        return nil unless candidate

        similarity = 1.0 - candidate.neighbor_distance
        return nil if similarity < EXISTING_SKILL_MATCH_THRESHOLD

        Ai::Skill.for_account(account.id).find_by(id: candidate.ai_skill_id)
      end

      def create_new_skill!(proposal)
        result = lifecycle_service.create_skill_from_proposal(proposal_id: proposal.id)
        skill = result[:skill]

        inherited = effectiveness_from_metadata(proposal.metadata)
        skill.update!(effectiveness_score: inherited) if inherited

        skill
      end

      # Clone-on-evolve (F2/F3 pattern): a GLOBAL match is never edited in
      # place — fork the account's editable copy (idempotent — reuses an
      # existing fork). effectiveness_score is deliberately left untouched
      # here: the matched skill already carries REAL accrued usage signal,
      # which a cluster-derived estimate must never overwrite.
      def refresh_existing_skill!(matched_skill, proposal)
        editable = matched_skill.global? ? skill_service.clone_skill(skill_id: matched_skill.id) : matched_skill

        editable.update!(
          tags: (Array(editable.tags) + Array(proposal.tags)).uniq,
          metadata: editable.metadata.merge(
            "reinforced_by_cluster_proposals" => (Array(editable.metadata["reinforced_by_cluster_proposals"]) | [proposal.id])
          )
        )

        proposal.mark_created!(editable)
        editable
      end

      # Blended positive/(positive+negative) outcome rate when the cluster
      # has real outcome signal; falls back to the cluster's mean
      # effectiveness/importance; nil (caller skips the update, leaving the
      # schema default) only when the cluster carried no signal whatsoever.
      def effectiveness_from_metadata(metadata)
        agg = (metadata["cluster_aggregate"] || {}).with_indifferent_access
        pos = agg[:total_positive_outcome_count].to_i
        neg = agg[:total_negative_outcome_count].to_i
        return (pos.to_f / (pos + neg)).round(4) if (pos + neg).positive?

        mean_eff = agg[:mean_effectiveness_score]
        return mean_eff.to_f.round(4) if mean_eff.present?

        mean_importance = agg[:mean_effective_importance] || agg[:mean_importance_score]
        mean_importance.present? ? mean_importance.to_f.round(4) : nil
      end

      # P3: once a cluster is folded into an approved skill, its source
      # learnings are superseded so the corpus stops resurfacing content
      # that's now embodied in the skill (semantic_search/find_similar/
      # promote_cross_team all scope to active/verified — see
      # Ai::CompoundLearning::STATUSES). Only reached here, on
      # approval/apply — #propose_from_cluster stays read-only per the class
      # comment above. Walks the FULL source_learning_ids list (unlike
      # #create_provenance_edges!'s MAX_SOURCE_LEARNINGS-bounded edge/prompt
      # budget) since every cluster member contributed to the promotion, not
      # just the ones that made the prompt/edge cut. #supersede_by_skill! is
      # itself a no-op on an already-superseded learning (e.g. one shared by
      # two clusters that both got approved) — never re-points an earlier
      # supersession.
      def supersede_source_learnings!(skill, proposal)
        learning_ids = Array(proposal.metadata["source_learning_ids"])
        return if learning_ids.empty?

        Ai::CompoundLearning.where(id: learning_ids, account_id: account.id).find_each do |learning|
          learning.supersede_by_skill!(skill)
        rescue StandardError => e
          Rails.logger.warn "[LearningToSkillPromoter] supersede failed for learning #{learning.id}: #{e.message}"
        end
      end

      def create_provenance_edges!(skill, proposal)
        learning_ids = Array(proposal.metadata["source_learning_ids"]).first(MAX_SOURCE_LEARNINGS)
        return if learning_ids.empty?

        skill_node = find_skill_node(skill)
        return unless skill_node

        Ai::CompoundLearning.where(id: learning_ids, account_id: account.id).find_each do |learning|
          learning_node = find_or_create_learning_node(learning)
          next unless learning_node
          next if provenance_edge_exists?(skill_node, learning_node)

          graph_service.create_edge(
            source: skill_node,
            target: learning_node,
            relation_type: "composes",
            weight: 1.0,
            confidence: (learning.confidence_score || 1.0),
            metadata: { "provenance" => "learning_cluster_promotion", "skill_proposal_id" => proposal.id }
          )
        rescue StandardError => e
          Rails.logger.warn "[LearningToSkillPromoter] provenance edge failed for learning #{learning.id}: #{e.message}"
        end
      end

      # Fresh direct query, never the skill object's `knowledge_graph_node`
      # association — that association may already be cached (correctly)
      # nil from an EARLIER call in this same request (e.g.
      # LifecycleService#create_skill_from_proposal's own internal
      # bridge_service.sync_skill(skill), which primes the has_one cache
      # before the node exists). Trusting the stale cache here would make
      # this fallback try to create a SECOND node for the same skill and
      # collide with the "one active node per skill" unique index. Mirrors
      # BridgeService's own private #find_skill_node! query.
      def find_skill_node(skill)
        account.ai_knowledge_graph_nodes.skill_nodes.active.find_by(ai_skill_id: skill.id) ||
          bridge_service.sync_skill(skill)
      end

      # Find-or-create a lightweight KG node representing a compound
      # learning, keyed on properties->>'source_learning_id' — the SAME key
      # Ai::CompoundLearning#enqueue_graph_update_on_status_change already
      # looks up (previously dormant: nothing wrote this key until now), so
      # a verify!/disprove! on the source learning after promotion now also
      # triggers this node's graph-quality recalculation for free.
      def find_or_create_learning_node(learning)
        account.ai_knowledge_graph_nodes
          .where(entity_type: "custom")
          .where("properties->>'source_learning_id' = ?", learning.id.to_s)
          .first ||
          graph_service.create_node(
            name: learning.title.presence || learning.content.truncate(80),
            node_type: "concept",
            entity_type: "custom",
            description: learning.content.truncate(500),
            properties: { "source_learning_id" => learning.id, "compound_learning" => true, "category" => learning.category },
            confidence: learning.confidence_score
          )
      end

      def provenance_edge_exists?(skill_node, learning_node)
        Ai::KnowledgeGraphEdge.where(
          account: account, source_node: skill_node, target_node: learning_node, relation_type: "composes"
        ).exists?
      end

      def lifecycle_service
        @lifecycle_service ||= Ai::SkillGraph::LifecycleService.new(account)
      end

      def skill_service
        @skill_service ||= Ai::SkillService.new(account: account)
      end

      def bridge_service
        @bridge_service ||= Ai::SkillGraph::BridgeService.new(account)
      end

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end
    end
  end
end
