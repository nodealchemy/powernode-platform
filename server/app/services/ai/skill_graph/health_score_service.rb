# frozen_string_literal: true

module Ai
  module SkillGraph
    class HealthScoreService
      COMPONENT_WEIGHTS = {
        coverage: 0.25,
        connectivity: 0.20,
        freshness: 0.20,
        effectiveness: 0.25,
        conflict_penalty: 0.10
      }.freeze

      GRADES = {
        90..100 => "A",
        80..89  => "B",
        70..79  => "C",
        60..69  => "D",
        0..59   => "F"
      }.freeze

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Calculate the overall health score (0-100) with component breakdown
      def calculate
        active_skills = Ai::Skill.for_account(account.id).active
        total_active = active_skills.count

        return empty_score if total_active.zero?

        components = {
          coverage: calculate_coverage(active_skills, total_active),
          connectivity: calculate_connectivity(total_active),
          freshness: calculate_freshness(active_skills, total_active),
          effectiveness: calculate_effectiveness(active_skills),
          conflict_penalty: calculate_conflict_penalty(active_skills, total_active)
        }

        raw_score = 100 * (
          COMPONENT_WEIGHTS[:coverage] * components[:coverage] +
          COMPONENT_WEIGHTS[:connectivity] * components[:connectivity] +
          COMPONENT_WEIGHTS[:freshness] * components[:freshness] +
          COMPONENT_WEIGHTS[:effectiveness] * components[:effectiveness] -
          COMPONENT_WEIGHTS[:conflict_penalty] * components[:conflict_penalty]
        )

        score = raw_score.clamp(0, 100).round(1)

        {
          score: score,
          grade: score_to_grade(score),
          components: components.transform_values { |v| v.round(4) }
        }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::HealthScore] calculate failed: #{e.message}"
        empty_score
      end

      # Full report with additional context beyond the health score
      def comprehensive_report
        health = calculate

        skills = Ai::Skill.for_account(account.id).active

        {
          health: health,
          kg_stats: graph_service.statistics,
          conflict_summary: build_conflict_summary,
          top_skills: top_skills(skills, 5),
          bottom_skills: bottom_skills(skills, 5),
          stale_skills: stale_skills(skills),
          orphan_skills: orphan_skills(skills)
        }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::HealthScore] comprehensive_report failed: #{e.message}"
        { health: empty_score, error: e.message }
      end

      private

      # Coverage: what fraction of active skills have KG nodes
      def calculate_coverage(active_skills, total_active)
        skill_ids_with_nodes = account.ai_knowledge_graph_nodes
          .skill_nodes.active
          .where(ai_skill_id: active_skills.select(:id))
          .distinct
          .count(:ai_skill_id)

        skill_ids_with_nodes / total_active.to_f
      end

      # Connectivity: average edges per skill node / 3.0 (capped at 1.0)
      def calculate_connectivity(total_active)
        skill_node_ids = account.ai_knowledge_graph_nodes
          .skill_nodes.active
          .pluck(:id)

        return 0.0 if skill_node_ids.empty?

        edge_count = account.ai_knowledge_graph_edges
          .active
          .where(source_node_id: skill_node_ids)
          .or(account.ai_knowledge_graph_edges.active.where(target_node_id: skill_node_ids))
          .count

        avg_edges = edge_count / skill_node_ids.size.to_f
        [avg_edges / 3.0, 1.0].min
      end

      # Freshness: fraction of active skills used in last 30 days
      def calculate_freshness(active_skills, total_active)
        fresh_count = active_skills
          .where("last_used_at >= ?", 30.days.ago)
          .count

        fresh_count / total_active.to_f
      end

      # Effectiveness: average effectiveness_score across all active skills
      def calculate_effectiveness(active_skills)
        avg = active_skills.average(:effectiveness_score)
        avg&.to_f || 0.0
      end

      # Conflict penalty: active_conflicts / total_active_skills (capped at 1.0)
      def calculate_conflict_penalty(active_skills, total_active)
        active_conflict_count = Ai::SkillConflict.where(account: account).active.count
        [active_conflict_count / total_active.to_f, 1.0].min
      end

      def score_to_grade(score)
        GRADES.each do |range, grade|
          return grade if range.include?(score.floor)
        end
        "F"
      end

      def empty_score
        {
          score: 0.0,
          grade: "F",
          components: {
            coverage: 0.0,
            connectivity: 0.0,
            freshness: 0.0,
            effectiveness: 0.0,
            conflict_penalty: 0.0
          }
        }
      end

      def build_conflict_summary
        conflicts = Ai::SkillConflict.where(account: account).active

        {
          total_active: conflicts.count,
          by_type: conflicts.group(:conflict_type).count,
          by_severity: conflicts.group(:severity).count
        }
      end

      def top_skills(skills, limit)
        skills.order(effectiveness_score: :desc).limit(limit).map do |s|
          { id: s.id, name: s.name, effectiveness_score: s.effectiveness_score, category: s.category }
        end
      end

      def bottom_skills(skills, limit)
        skills.order(effectiveness_score: :asc).limit(limit).map do |s|
          { id: s.id, name: s.name, effectiveness_score: s.effectiveness_score, category: s.category }
        end
      end

      def stale_skills(skills)
        skills.where("last_used_at < ? OR last_used_at IS NULL", 30.days.ago).map do |s|
          { id: s.id, name: s.name, last_used_at: s.last_used_at, effectiveness_score: s.effectiveness_score }
        end
      end

      def orphan_skills(skills)
        skills.left_joins(:agent_skills).where(ai_agent_skills: { id: nil }).map do |s|
          { id: s.id, name: s.name, category: s.category, effectiveness_score: s.effectiveness_score }
        end
      end

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end
    end
  end
end
