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
          # Merge KG nodes if both have them
          winner_node = winner.knowledge_graph_node
          loser_node = loser.knowledge_graph_node

          if winner_node && loser_node
            graph_service.merge_nodes(
              keep: winner_node,
              merge: loser_node,
              reason: "Duplicate skill merge: #{loser.name} → #{winner.name}"
            )
          end

          # Reassign AgentSkills from loser to winner
          loser.agent_skills.find_each do |agent_skill|
            existing = Ai::AgentSkill.find_by(ai_agent_id: agent_skill.ai_agent_id, ai_skill_id: winner.id)
            if existing
              agent_skill.destroy!
            else
              agent_skill.update!(ai_skill_id: winner.id)
            end
          end

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
            title: "Consolidate overlapping skills",
            description: build_overlap_description(conflict),
            conflict_id: conflict.id,
            skill_a_id: conflict.skill_a_id,
            skill_b_id: conflict.skill_b_id,
            similarity_score: conflict.similarity_score
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
              title: "Review orphan skill: #{skill.name}",
              description: "Skill '#{skill.name}' has no agent assignments or knowledge graph connections after #{days_old} days. Consider archiving or connecting to relevant agents.",
              conflict_id: conflict.id,
              days_old: days_old
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
            title: "Resolve version drift between related skills",
            description: build_version_drift_description(conflict),
            conflict_id: conflict.id,
            skill_a_id: conflict.skill_a_id,
            skill_b_id: conflict.skill_b_id,
            skill_a_name: conflict.resolution_details&.dig("skill_a_name"),
            skill_b_name: conflict.resolution_details&.dig("skill_b_name")
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
        "Skills '#{details['skill_a_name']}' and '#{details['skill_b_name']}' share the prefix " \
          "'#{details['shared_prefix']}' and may represent different versions of the same capability. " \
          "Review whether they should be consolidated or versioned properly."
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
