# frozen_string_literal: true

module Ai
  module SkillGraph
    class EvolutionService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Record an outcome against the active version (or A/B variant) and the skill itself
      def record_outcome(skill_id:, successful:)
        skill = find_skill!(skill_id)
        active_version = skill.versions.active.first
        ab_variant = skill.versions.ab_variants.first

        # Route traffic to A/B variant based on traffic percentage
        target_version = if ab_variant && active_version
                           rand < (ab_variant.ab_traffic_pct || 0.2) ? ab_variant : active_version
                         else
                           active_version
                         end

        target_version&.record_outcome!(successful: successful)

        outcome = successful ? "success" : "failure"
        skill.record_usage!(outcome: outcome)

        Rails.logger.info "[SkillGraph::Evolution] Recorded #{outcome} for skill #{skill_id}, version #{target_version&.version}"
        { skill_id: skill.id, version_id: target_version&.id, outcome: outcome }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] record_outcome failed: #{e.message}"
        { error: e.message }
      end

      # Compute comprehensive metrics for a skill
      def skill_metrics(skill_id:)
        skill = find_skill!(skill_id)

        recent_7d = skill.usage_records.where("created_at >= ?", 7.days.ago)
        prior_7d = skill.usage_records.where(created_at: 14.days.ago..7.days.ago)

        recent_rate = calculate_success_rate(recent_7d)
        prior_rate = calculate_success_rate(prior_7d)

        trend = if recent_rate > prior_rate + 0.05
                  "up"
                elsif recent_rate < prior_rate - 0.05
                  "down"
                else
                  "stable"
                end

        {
          skill_id: skill.id,
          name: skill.name,
          effectiveness_score: skill.effectiveness_score,
          usage_success_rate: skill.usage_success_rate,
          total_usage: skill.positive_usage_count.to_i + skill.negative_usage_count.to_i,
          positive_count: skill.positive_usage_count.to_i,
          negative_count: skill.negative_usage_count.to_i,
          version_count: skill.versions.count,
          active_conflicts_count: skill.active_conflicts.count,
          last_used_at: skill.last_used_at,
          trend: trend
        }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] skill_metrics failed: #{e.message}"
        { error: e.message }
      end

      # Create an evolved version with an improved system_prompt informed by compound learnings
      def propose_evolution(skill_id:)
        skill = find_skill!(skill_id)
        current_version = skill.versions.active.first

        # Gather compound learnings relevant to this skill
        embedding = skill.knowledge_graph_node&.embedding
        learning_context = ""

        if embedding
          learnings = Ai::CompoundLearning.active
            .for_account(account.id)
            .nearest_neighbors(:embedding, embedding, distance: "cosine")
            .first(5)
            .select { |l| l.neighbor_distance <= 0.5 }

          if learnings.any?
            learning_context = learnings.map { |l| "- #{l.content.truncate(200)}" }.join("\n")
          end
        end

        # Build an evolved system_prompt based on learnings
        base_prompt = current_version&.system_prompt || skill.system_prompt || ""
        evolved_prompt = build_evolved_prompt(base_prompt, learning_context, skill)

        next_version_number = (skill.versions.count + 1).to_s

        version = Ai::SkillVersion.create!(
          account: account,
          ai_skill: skill,
          version: next_version_number,
          change_type: "evolution",
          system_prompt: evolved_prompt,
          is_active: false,
          is_ab_variant: false,
          effectiveness_score: 0.0,
          usage_count: 0,
          success_count: 0,
          failure_count: 0,
          change_reason: "Evolved from v#{current_version&.version || 0} with #{learning_context.present? ? 'compound learning insights' : 'baseline improvement'}",
          metadata: {
            source_version_id: current_version&.id,
            learning_count: learning_context.present? ? learning_context.lines.count : 0,
            evolved_at: Time.current.iso8601
          }
        )

        Rails.logger.info "[SkillGraph::Evolution] Proposed evolution v#{next_version_number} for skill #{skill_id}"
        version
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] propose_evolution failed: #{e.message}"
        nil
      end

      # Activate a specific version (deactivates all others for that skill)
      def activate_version(version_id:)
        version = Ai::SkillVersion.find_by!(id: version_id, account: account)
        version.activate!

        Rails.logger.info "[SkillGraph::Evolution] Activated version #{version.version} for skill #{version.ai_skill_id}"
        version
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "[SkillGraph::Evolution] activate_version: version not found: #{version_id}"
        nil
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] activate_version failed: #{e.message}"
        nil
      end

      # Return all versions for a skill, newest first
      def version_history(skill_id:)
        skill = find_skill!(skill_id)
        skill.versions.order(created_at: :desc).map(&:version_summary)
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] version_history failed: #{e.message}"
        []
      end

      # Start an A/B test between the active version and a variant
      def start_ab_test(skill_id:, variant_version_id:, traffic_pct: 0.2)
        skill = find_skill!(skill_id)
        variant = skill.versions.find_by!(id: variant_version_id)

        # Clear any existing A/B variants for this skill
        skill.versions.ab_variants.update_all(is_ab_variant: false, ab_traffic_pct: nil)

        variant.update!(
          is_ab_variant: true,
          ab_traffic_pct: traffic_pct.clamp(0.01, 0.99)
        )

        Rails.logger.info "[SkillGraph::Evolution] Started A/B test for skill #{skill_id}: variant v#{variant.version} at #{(traffic_pct * 100).round}% traffic"
        { skill_id: skill.id, variant_version_id: variant.id, traffic_pct: variant.ab_traffic_pct }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] start_ab_test failed: #{e.message}"
        { error: e.message }
      end

      # End A/B test: compare effectiveness, activate winner, deactivate loser
      def end_ab_test(skill_id:)
        skill = find_skill!(skill_id)
        active_version = skill.versions.active.first
        variant = skill.versions.ab_variants.first

        unless active_version && variant
          Rails.logger.warn "[SkillGraph::Evolution] No active A/B test found for skill #{skill_id}"
          return { error: "No active A/B test" }
        end

        # Compare effectiveness
        active_eff = active_version.effectiveness_score || 0.0
        variant_eff = variant.effectiveness_score || 0.0

        winner = variant_eff > active_eff ? variant : active_version
        loser = winner == variant ? active_version : variant

        winner.activate!
        loser.update!(is_active: false, is_ab_variant: false, ab_traffic_pct: nil)

        # Reset A/B flags on winner too
        winner.update!(is_ab_variant: false, ab_traffic_pct: nil)

        Rails.logger.info "[SkillGraph::Evolution] A/B test ended for skill #{skill_id}: winner v#{winner.version} (#{winner.effectiveness_score})"
        {
          skill_id: skill.id,
          winner_version_id: winner.id,
          winner_version: winner.version,
          winner_effectiveness: winner.effectiveness_score,
          loser_version_id: loser.id,
          loser_effectiveness: loser.effectiveness_score
        }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] end_ab_test failed: #{e.message}"
        { error: e.message }
      end

      # Decay effectiveness of skills not used recently
      def decay_stale_skills(days_threshold: 30)
        cutoff = days_threshold.days.ago
        stale_skills = Ai::Skill.for_account(account.id).active
          .where("last_used_at < ? OR last_used_at IS NULL", cutoff)
          .where("effectiveness_score > ?", 0.0)

        decayed = 0
        stale_skills.find_each do |skill|
          new_score = [(skill.effectiveness_score - 0.05), 0.0].max
          skill.update_column(:effectiveness_score, new_score)
          decayed += 1
        end

        Rails.logger.info "[SkillGraph::Evolution] Decayed #{decayed} stale skills (threshold: #{days_threshold} days)"
        decayed
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::Evolution] decay_stale_skills failed: #{e.message}"
        0
      end

      private

      def find_skill!(skill_id)
        Ai::Skill.for_account(account.id).find(skill_id)
      end

      def calculate_success_rate(records)
        total = records.count
        return 0.5 if total.zero?

        records.successful.count / total.to_f
      end

      def build_evolved_prompt(base_prompt, learning_context, skill)
        parts = []
        parts << base_prompt if base_prompt.present?

        if learning_context.present?
          parts << "\n\n# Improvements from learned patterns\n#{learning_context}"
        end

        parts << "\n\n# Skill context: #{skill.category} | Effectiveness: #{skill.effectiveness_score}" if skill.category.present?

        parts.join.strip
      end
    end
  end
end
