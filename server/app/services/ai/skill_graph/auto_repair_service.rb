# frozen_string_literal: true

module Ai
  module SkillGraph
    class AutoRepairService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Process all auto-resolvable conflicts (feature-flagged)
      def auto_resolve_all
        unless Shared::FeatureFlagService.enabled?(:skill_conflict_auto_resolve, account)
          Rails.logger.info "[SkillGraph::AutoRepair] Auto-resolve disabled by feature flag"
          return { resolved: 0, failed: 0, skipped: "feature_flag_disabled" }
        end

        conflicts = Ai::SkillConflict.where(account: account)
          .active
          .auto_resolvable
          .by_priority

        resolved = 0
        failed = 0

        conflicts.find_each do |conflict|
          result = resolve_conflict(conflict)
          if result[:success]
            resolved += 1
          else
            failed += 1
          end
        end

        Rails.logger.info "[SkillGraph::AutoRepair] Auto-resolve complete: resolved=#{resolved} failed=#{failed}"
        { resolved: resolved, failed: failed }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] auto_resolve_all failed: #{e.message}"
        { resolved: 0, failed: 0, error: e.message }
      end

      # Dispatch to type-specific resolver
      def resolve_conflict(conflict, user: nil)
        Rails.logger.info "[SkillGraph::AutoRepair] Resolving conflict #{conflict.id} (#{conflict.conflict_type})"

        result = case conflict.conflict_type
                 when "duplicate" then resolve_duplicate(conflict)
                 when "overlapping" then resolve_overlapping(conflict)
                 when "circular_dependency" then resolve_circular_dependency(conflict)
                 when "stale" then resolve_stale(conflict)
                 when "orphan" then resolve_orphan(conflict)
                 when "version_drift" then resolve_version_drift(conflict)
                 else
                   { success: false, error: "Unknown conflict type: #{conflict.conflict_type}" }
                 end

        if result[:success]
          conflict.resolve!(user: user)
          Rails.logger.info "[SkillGraph::AutoRepair] Conflict #{conflict.id} resolved"
        else
          Rails.logger.warn "[SkillGraph::AutoRepair] Conflict #{conflict.id} resolution failed: #{result[:error]}"
        end

        result
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_conflict #{conflict.id} failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Reassign real associations (agent bindings, MCP server links,
      # knowledge-graph node) from `loser` to `winner` — the "keep the data,
      # drop the duplicate" step. Shared by two callers: resolve_duplicate
      # below (conflict-driven repair, which then archives the loser) and the
      # one-off data migration reconciling seed-globalization duplicates
      # (db/migrate/*_dedupe_skill_seed_globals.rb), which deletes the loser
      # outright once its associations are safely moved. Idempotent — safe to
      # call on a loser that no longer holds any of these associations.
      def merge_associations(winner:, loser:)
        merge_knowledge_graph_node(winner, loser)
        reassign_agent_skills(winner, loser)
        reassign_mcp_servers(winner, loser)
      end

      private

      # Merge duplicate: higher usage_count wins, reassign AgentSkills, archive loser
      def resolve_duplicate(conflict)
        skill_a = Ai::Skill.find_by(id: conflict.skill_a_id)
        skill_b = Ai::Skill.find_by(id: conflict.skill_b_id)
        return { success: false, error: "One or both skills not found" } unless skill_a && skill_b

        # Higher usage_count wins
        winner, loser = if skill_a.usage_count >= skill_b.usage_count
                          [skill_a, skill_b]
                        else
                          [skill_b, skill_a]
                        end

        ActiveRecord::Base.transaction do
          merge_associations(winner: winner, loser: loser)

          # Archive loser skill
          loser.update!(status: "inactive", is_enabled: false)

          # Update conflict resolution details
          conflict.update!(resolution_details: (conflict.resolution_details || {}).merge(
            "winner_skill_id" => winner.id,
            "loser_skill_id" => loser.id,
            "winner_usage_count" => winner.usage_count,
            "loser_usage_count" => loser.usage_count
          ))
        end

        { success: true, winner_id: winner.id, loser_id: loser.id }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_duplicate failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Overlapping: create ImprovementRecommendation for human review
      def resolve_overlapping(conflict)
        Ai::ImprovementRecommendation.create!(
          account: account,
          recommendation_type: "skill_consolidation",
          target_type: "Ai::Skill",
          target_id: conflict.skill_a_id,
          confidence_score: conflict.similarity_score || 0.7,
          status: "pending",
          evidence: {
            "title" => "Consolidate overlapping skills",
            "description" => build_overlap_description(conflict),
            "conflict_id" => conflict.id,
            "skill_a_id" => conflict.skill_a_id,
            "skill_b_id" => conflict.skill_b_id,
            "similarity_score" => conflict.similarity_score
          }
        )

        { success: true, action: "recommendation_created" }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_overlapping failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Circular dependency: find weakest edge (lowest weight × confidence) and archive it
      def resolve_circular_dependency(conflict)
        edge_id = conflict.edge_id || conflict.resolution_details&.dig("cycle_edge_id")

        if edge_id
          edge = account.ai_knowledge_graph_edges.find_by(id: edge_id)
          if edge
            edge.update!(status: "archived")
            return { success: true, action: "edge_archived", edge_id: edge.id }
          end
        end

        # Fallback: find the weakest edge between the two skill nodes
        node_a = account.ai_knowledge_graph_nodes.skill_nodes.active.find_by(ai_skill_id: conflict.skill_a_id)
        node_b = account.ai_knowledge_graph_nodes.skill_nodes.active.find_by(ai_skill_id: conflict.skill_b_id)
        return { success: false, error: "Skill nodes not found" } unless node_a && node_b

        weakest = account.ai_knowledge_graph_edges.active
          .where(
            "(source_node_id = :a AND target_node_id = :b) OR (source_node_id = :b AND target_node_id = :a)",
            a: node_a.id, b: node_b.id
          )
          .order(Arel.sql("weight * confidence ASC"))
          .first

        return { success: false, error: "No edge found between nodes" } unless weakest

        weakest.update!(status: "archived")
        { success: true, action: "weakest_edge_archived", edge_id: weakest.id }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_circular_dependency failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Stale: decrease effectiveness; if already < 0.2, mark as auto_resolved
      #
      # F4 note: unlike EvolutionService#decay_stale_skills (a blanket daily
      # sweep over every skill), this only ever runs against a "stale"
      # SkillConflict, which ConflictDetectionService#detect_stale_skills only
      # creates for skills already `created_at < STALE_MIN_AGE.days.ago` — a
      # brand-new never-used seed can't reach this method in the first place,
      # so it doesn't need the same never-used floor/skip. The <0.2 branch
      # below already acts as a soft floor (stops mutating instead of driving
      # to 0.0).
      def resolve_stale(conflict)
        skill = Ai::Skill.find_by(id: conflict.skill_a_id)
        return { success: false, error: "Skill not found" } unless skill

        current_effectiveness = skill.effectiveness_score.to_f

        if current_effectiveness < 0.2
          # Already very low — auto-resolve without further action
          return { success: true, action: "already_low_effectiveness", effectiveness: current_effectiveness }
        end

        new_effectiveness = [current_effectiveness - 0.1, 0.0].max
        skill.update!(effectiveness_score: new_effectiveness)

        { success: true, action: "effectiveness_decayed", old: current_effectiveness, new: new_effectiveness }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_stale failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Orphan: try auto_detect_relationships; if none found after 60 days, recommend consolidation
      def resolve_orphan(conflict)
        skill = Ai::Skill.find_by(id: conflict.skill_a_id)
        return { success: false, error: "Skill not found" } unless skill

        # Try auto-detecting relationships
        detected = bridge_service.auto_detect_relationships(skill, similarity_threshold: 0.5)

        if detected.any?
          # Create edges for detected relationships
          detected.first(5).each do |suggestion|
            bridge_service.create_skill_edge(
              source_skill_id: skill.id,
              target_skill_id: suggestion[:skill_id],
              relation_type: suggestion[:suggested_relation] || "composes",
              weight: suggestion[:similarity] || 0.7,
              confidence: suggestion[:confidence] || 0.7
            )
          rescue StandardError => e
            Rails.logger.warn "[SkillGraph::AutoRepair] Edge creation failed: #{e.message}"
          end

          return { success: true, action: "relationships_created", count: [detected.size, 5].min }
        end

        # No relationships found — check age
        days_old = ((Time.current - skill.created_at) / 1.day).to_i
        if days_old > 60
          Ai::ImprovementRecommendation.create!(
            account: account,
            recommendation_type: "skill_consolidation",
            target_type: "Ai::Skill",
            target_id: skill.id,
            confidence_score: 0.6,
            status: "pending",
            evidence: {
              "title" => "Review orphan skill: #{skill.name}",
              "description" => "Skill '#{skill.name}' has no agent assignments or knowledge graph connections after #{days_old} days. Consider archiving or connecting to relevant agents.",
              "conflict_id" => conflict.id,
              "days_old" => days_old
            }
          )

          return { success: true, action: "recommendation_created" }
        end

        # Too young to decide — resolve silently
        { success: true, action: "deferred_too_young", days_old: days_old }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_orphan failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Version drift: create ImprovementRecommendation for human review
      def resolve_version_drift(conflict)
        Ai::ImprovementRecommendation.create!(
          account: account,
          recommendation_type: "skill_consolidation",
          target_type: "Ai::Skill",
          target_id: conflict.skill_a_id,
          confidence_score: 0.6,
          status: "pending",
          evidence: {
            "title" => "Resolve version drift between related skills",
            "description" => build_version_drift_description(conflict),
            "conflict_id" => conflict.id,
            "skill_a_id" => conflict.skill_a_id,
            "skill_b_id" => conflict.skill_b_id,
            "skill_a_name" => conflict.resolution_details&.dig("skill_a_name"),
            "skill_b_name" => conflict.resolution_details&.dig("skill_b_name")
          }
        )

        { success: true, action: "recommendation_created" }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::AutoRepair] resolve_version_drift failed: #{e.message}"
        { success: false, error: e.message }
      end

      def build_overlap_description(conflict)
        skill_a = Ai::Skill.find_by(id: conflict.skill_a_id)
        skill_b = Ai::Skill.find_by(id: conflict.skill_b_id)

        "Skills '#{skill_a&.name}' and '#{skill_b&.name}' have #{((conflict.similarity_score || 0) * 100).round(1)}% " \
          "semantic overlap in the same category '#{skill_a&.category}'. Consider merging or clarifying their boundaries."
      end

      def build_version_drift_description(conflict)
        details = conflict.resolution_details || {}
        fields = Array(details["diverged_fields"])
        field_note = fields.any? ? " Diverged fields: #{fields.join(', ')}." : ""

        "Skills '#{details['skill_a_name']}' and '#{details['skill_b_name']}' share lineage " \
          "(source_key '#{details['source_key']}') and have unresolved differences from a 3-way merge " \
          "against their common origin.#{field_note} Review whether they should be reconciled or kept " \
          "as intentionally separate overrides."
      end

      def merge_knowledge_graph_node(winner, loser)
        # Scope to the LOSER's account, not the service's. That is where the
        # duplicate node actually lives, and the two are identical on the
        # ordinary same-account repair path (`resolve_duplicate` picks both
        # skills out of this account), so this is a no-op there.
        #
        # It is NOT a no-op for `DedupeSkillSeedGlobals`, which constructs this
        # service as `.new(nil)` on purpose: it merges an account-scoped
        # duplicate into a GLOBAL survivor, so there is no single account for
        # the service to carry. Reading `account.id` unconditionally raised
        # NoMethodError there and aborted the migration inside its transaction
        # — a `rails db:migrate` failure, not just a red spec.
        #
        # `account&.id` rather than `account.id` because a global-vs-global
        # merge would leave both sides blank; `knowledge_graph_node_for`
        # already returns nil for a blank account_id, so that case falls
        # through to the `return unless loser_node` guard below.
        scope_account_id = loser.account_id || account&.id

        winner_node = winner.knowledge_graph_node_for(scope_account_id)
        loser_node = loser.knowledge_graph_node_for(scope_account_id)
        return unless loser_node

        if winner_node
          graph_service.merge_nodes(
            keep: winner_node,
            merge: loser_node,
            reason: "Duplicate skill merge: #{loser.name} → #{winner.name}"
          )
        else
          # Winner has no node of its own yet — just move the loser's node
          # over rather than merging (nothing to merge into).
          loser_node.update!(ai_skill_id: winner.id)
        end
      end

      def reassign_agent_skills(winner, loser)
        loser.agent_skills.find_each do |agent_skill|
          existing = Ai::AgentSkill.find_by(ai_agent_id: agent_skill.ai_agent_id, ai_skill_id: winner.id)
          if existing
            agent_skill.destroy!
          else
            agent_skill.update!(ai_skill_id: winner.id)
          end
        end
      end

      # MCP server links are a HABTM join table — AR's dependent: option
      # doesn't reassign those, it just clears the join rows on destroy — so
      # without this the loser's server links would silently vanish.
      def reassign_mcp_servers(winner, loser)
        extra_ids = loser.mcp_server_ids - winner.mcp_server_ids
        winner.mcp_server_ids += extra_ids if extra_ids.any?
      end

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end

      def bridge_service
        @bridge_service ||= BridgeService.new(account)
      end
    end
  end
end
