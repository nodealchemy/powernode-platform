# frozen_string_literal: true

module Ai
  module SkillGraph
    # F5 capstone: closes the self-improvement loop by turning skill-health
    # findings into OPERATOR-REVIEW proposals on a schedule. Never mutates a
    # skill, a version, or a conflict itself — it only ever files an
    # Ai::ImprovementRecommendation ("offer") for a human to approve or
    # dismiss via the existing recommendations queue
    # (Api::V1::Ai::LearningController#apply_recommendation /
    # #dismiss_recommendation). Gated behind :skill_scheduled_evolution
    # (default OFF) — independent of :skill_optimization and
    # :skill_conflict_auto_resolve, which stay off per F4 until validated;
    # this proposer is safe to enable even while those stay off since
    # proposing never mutates.
    class EvolutionProposalService
      # Mirrors Ai::Learning::TrajectoryAnalyzer::MIN_SAMPLE_SIZE /
      # #analyze_skill_health's 0.4 cutoff so "low effectiveness" means the
      # same thing everywhere a skill-health signal is judged.
      MIN_USAGE_SAMPLE = 10
      LOW_EFFECTIVENESS_THRESHOLD = 0.4

      attr_reader :account

      def initialize(account)
        @account = account
      end

      def run
        return skipped_result unless Shared::FeatureFlagService.enabled?(:skill_scheduled_evolution, account)

        evolution_ids = propose_low_effectiveness_evolutions
        conflict_ids = propose_conflict_reviews

        result = {
          evolution_proposals: evolution_ids.size,
          conflict_review_proposals: conflict_ids.size,
          ran_at: Time.current.iso8601
        }
        Rails.logger.info "[SkillGraph::EvolutionProposal] #{result.inspect}"
        result
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::EvolutionProposal] run failed: #{e.message}"
        { error: e.message }
      end

      private

      # Low-effectiveness active skills with a real usage sample: draft an
      # evolved version via EvolutionService#propose_evolution (clone-on-write
      # safe — F5) and file a "skill_health" recommendation pointing at the
      # draft for operator review. The version stays inactive (never served)
      # until an operator approves the recommendation, which activates it
      # (Ai::Learning::ImprovementRecommender#apply_recommendation!).
      def propose_low_effectiveness_evolutions
        proposed = []

        candidates = Ai::Skill.for_account(account.id).active.enabled
          .where("positive_usage_count + negative_usage_count >= ?", MIN_USAGE_SAMPLE)
          .where("effectiveness_score < ?", LOW_EFFECTIVENESS_THRESHOLD)

        candidates.find_each do |skill|
          next if pending_skill_health_recommendation?(skill)

          version = evolution_service.propose_evolution(skill_id: skill.id)
          next unless version

          create_evolution_recommendation!(skill: skill, version: version)
          proposed << skill.id
        end

        proposed
      end

      # Every ACTIVE skill conflict — regardless of type or auto_resolvable —
      # gets a reviewable recommendation if one isn't already pending. This is
      # the single push surface for "resolvable conflicts, stale skills, merge
      # candidates" (duplicate/overlapping = merge candidates; stale/orphan/
      # version_drift/circular_dependency = the rest): it never resolves the
      # conflict itself (that stays AutoRepairService#resolve_conflict via the
      # conflicts UI, or the flag-gated auto-resolve sweep) — it only surfaces
      # the finding into the same recommendations queue an operator already
      # reviews for every other proposal type.
      def propose_conflict_reviews
        proposed = []

        Ai::SkillConflict.where(account: account).active.find_each do |conflict|
          next if pending_conflict_recommendation?(conflict)

          create_conflict_recommendation!(conflict)
          proposed << conflict.id
        end

        proposed
      end

      def pending_skill_health_recommendation?(skill)
        Ai::ImprovementRecommendation.where(
          account: account, recommendation_type: "skill_health",
          target_type: "Ai::Skill", target_id: skill.id, status: "pending"
        ).exists?
      end

      def pending_conflict_recommendation?(conflict)
        Ai::ImprovementRecommendation.where(
          account: account, recommendation_type: "skill_consolidation",
          target_type: "Ai::SkillConflict", target_id: conflict.id, status: "pending"
        ).exists?
      end

      def create_evolution_recommendation!(skill:, version:)
        total_usage = skill.positive_usage_count.to_i + skill.negative_usage_count.to_i
        effectiveness_pct = (skill.effectiveness_score.to_f * 100).round(1)

        Ai::ImprovementRecommendation.create!(
          account: account,
          recommendation_type: "skill_health",
          target_type: "Ai::Skill",
          target_id: version.ai_skill_id, # the editable clone when skill was global (F5 clone-on-evolve)
          confidence_score: evolution_confidence(skill),
          status: "pending",
          recommended_config: { "proposed_version_id" => version.id },
          evidence: {
            "title" => "Review proposed evolution for low-effectiveness skill '#{skill.name}'",
            "description" => "Skill '#{skill.name}' succeeds only #{effectiveness_pct}% (effectiveness) over " \
                              "#{total_usage} uses. A draft evolution (v#{version.version}) has been generated " \
                              "from recent compound learnings — approve to activate it, or dismiss to keep the " \
                              "current prompt.",
            "skill_name" => skill.name,
            "effectiveness_score" => skill.effectiveness_score,
            "usage_count" => total_usage,
            "proposed_version" => version.version,
            "proposed_version_id" => version.id
          }
        )
      end

      def create_conflict_recommendation!(conflict)
        Ai::ImprovementRecommendation.create!(
          account: account,
          recommendation_type: "skill_consolidation",
          target_type: "Ai::SkillConflict",
          target_id: conflict.id,
          confidence_score: conflict_confidence(conflict),
          status: "pending",
          evidence: {
            "title" => "Review #{conflict.conflict_type.humanize.downcase} conflict: #{conflict_skill_names(conflict)}",
            "description" => conflict_description(conflict),
            "conflict_id" => conflict.id,
            "conflict_type" => conflict.conflict_type,
            "severity" => conflict.severity,
            "skill_a_id" => conflict.skill_a_id,
            "skill_b_id" => conflict.skill_b_id
          }
        )
      end

      def conflict_skill_names(conflict)
        names = [conflict.skill_a&.name]
        names << conflict.skill_b.name if conflict.skill_b
        names.compact.join(" & ")
      end

      def conflict_description(conflict)
        base = "#{conflict.conflict_type.humanize} conflict detected for '#{conflict_skill_names(conflict)}' " \
               "(severity: #{conflict.severity})."
        strategy = conflict.resolution_strategy.presence
        base += " Suggested resolution: #{strategy.humanize}." if strategy
        "#{base} Review via the skill conflicts queue to resolve or dismiss."
      end

      def evolution_confidence(skill)
        gap = LOW_EFFECTIVENESS_THRESHOLD - skill.effectiveness_score.to_f
        (0.5 + gap).clamp(0.0, 0.9).round(4)
      end

      def conflict_confidence(conflict)
        (conflict.similarity_score || Ai::SkillConflict::SEVERITY_WEIGHTS.fetch(conflict.severity, 2) / 4.0)
          .to_f.clamp(0.0, 1.0).round(4)
      end

      def skipped_result
        { skipped: true, reason: "skill_scheduled_evolution feature flag disabled" }
      end

      def evolution_service
        @evolution_service ||= Ai::SkillGraph::EvolutionService.new(account)
      end
    end
  end
end
