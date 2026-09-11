# frozen_string_literal: true

module Ai
  module SkillGraph
    class EvolutionService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Record an outcome against the active version (or A/B variant) and the skill itself
      # D5 — THE A/B routing decision, made where the prompt is SERVED.
      #
      # Returns { skill_id => { version_id:, prompt: } } for every id given.
      # `prompt` is the variant's own text when the variant was drawn, and nil
      # when the skill's text serves (which is the active version's text, since
      # SkillVersion#activate! writes it there). `version_id` names what served,
      # or nil for a skill with no versions at all.
      #
      # A variant whose share is outside (0, 1] is never served: create_variant
      # wrote 20.0 — a percent — before D5, and clamping that would serve such
      # a variant on every call. An out-of-range share is not a routing
      # instruction, so it fails closed. One draw per skill per build; `random`
      # is injectable so specs can pin the draw.
      def self.route_served_versions(skill_ids, random: Random)
        ids = Array(skill_ids).compact.uniq
        return {} if ids.empty?

        rows = Ai::SkillVersion.where(ai_skill_id: ids)
                               .where("is_active = TRUE OR is_ab_variant = TRUE")
                               .order(:created_at)
                               .group_by(&:ai_skill_id)

        ids.index_with do |skill_id|
          versions = rows[skill_id] || []
          active = versions.find(&:is_active)
          variant = versions.find { |v| v.is_ab_variant && !v.is_active }
          share = variant&.ab_traffic_pct.to_f

          if variant && variant.system_prompt.present? && share.positive? && share <= 1.0 && random.rand < share
            { version_id: variant.id, prompt: variant.system_prompt }
          else
            { version_id: active&.id, prompt: nil }
          end
        end
      end

      # D5 — credit the version that SERVED, never a coin flip.
      #
      # This used to choose a version at RECORD time (`rand < ab_traffic_pct`
      # between the active version and the variant) while the serving path read
      # ai_skills.system_prompt and never served the variant at all — so the
      # variant was credited with outcomes of text it never produced. Routing
      # now happens at serve time (.route_served_versions) and the served
      # version travels with the execution; this credits the one named.
      #
      # With no version named: outside an A/B the active version is the only
      # one serving, so it is credited. During an A/B the served one is not
      # knowable here, so NO version is credited — the skill-level usage still
      # records, and `attributed: false` says why the version counters did not
      # move.
      def record_outcome(skill_id:, successful:, version_id: nil)
        skill = find_skill!(skill_id)
        target_version = served_version_for(skill, version_id)

        target_version&.record_outcome!(successful: successful)

        outcome = successful ? "success" : "failure"
        skill.record_usage!(outcome: outcome)

        Rails.logger.info "[SkillGraph::Evolution] Recorded #{outcome} for skill #{skill_id}, version #{target_version&.version || 'unattributed'}"
        { skill_id: skill.id, version_id: target_version&.id, attributed: target_version.present?, outcome: outcome }
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
        # F5 clone-on-evolve: a GLOBAL (is_system) skill is never versioned in
        # place — that would attach the new version to the shared baseline
        # every account resolves to. Redirect onto this account's editable
        # clone first (reusing F2/F3's idempotent resolve-or-clone), the same
        # guarantee SkillService#update_skill already gives manual edits.
        skill = editable_skill(skill)
        current_version = skill.versions.active.first

        # Gather compound learnings relevant to this skill
        # Account-scoped: a global skill carries one node PER ACCOUNT, so the bare
        # has_one would seed this account's learning context from another
        # tenant's embedding (IMP-019fedd4).
        embedding = skill.knowledge_graph_node_for(account.id)&.embedding
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

      # Decay effectiveness of skills not used recently. Only skills that HAVE
      # a last_used_at (i.e. were actually used at some point, then went
      # stale) decay — a skill that has NEVER been used (last_used_at nil) is
      # a no-signal seed, not a bad skill, and previously rotted to 0.0 daily
      # for no reason other than not yet being attached/discovered (F4).
      def decay_stale_skills(days_threshold: 30)
        cutoff = days_threshold.days.ago
        stale_skills = Ai::Skill.for_account(account.id).active
          .where.not(last_used_at: nil)
          .where("last_used_at < ?", cutoff)
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

      # The version an outcome belongs to (see #record_outcome). A named id is
      # looked up WITHIN the skill, so another skill's version is never credited.
      def served_version_for(skill, version_id)
        return skill.versions.find_by(id: version_id) if version_id.present?
        return nil if skill.versions.ab_variants.exists?

        skill.versions.active.first
      end

      # Override-aware (F2/F3 clone-on-evolve): resolves by id first, then falls
      # back to Ai::Skill.resolve_for so a slug shared by a global skill and the
      # account's own clone/override deterministically resolves to the account's
      # row — mirrors Ai::SkillService#find_skill / SkillTool#resolve_skill.
      # Bang semantics preserved (raises, not nil) since every caller here
      # already relies on the exception being caught by its own rescue block.
      def find_skill!(skill_id)
        Ai::Skill.for_account(account.id).find_by(id: skill_id) ||
          Ai::Skill.resolve_for(account.id, slug: skill_id) ||
          raise(ActiveRecord::RecordNotFound, "Couldn't find Ai::Skill with id or slug=#{skill_id}")
      end

      # Resolve the account-editable target for a (possibly global) skill,
      # mirroring SkillService#resolve_editable_target: an already
      # account-owned skill is returned as-is; a global one is redirected to
      # the account's existing override (if this account already cloned it)
      # or a fresh clone via SkillService#clone_skill — idempotent either way.
      def editable_skill(skill)
        return skill unless skill.global?

        skill_service.clone_skill(skill_id: skill.id)
      end

      def skill_service
        @skill_service ||= Ai::SkillService.new(account: account)
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
