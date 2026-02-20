# frozen_string_literal: true

module Ai
  module SkillGraph
    class SelfLearningService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Record skill outcomes from an execution
      def record_skill_outcomes(execution:, agent:, outcome:)
        return unless Shared::FeatureFlagService.enabled?(:skill_self_learning, account)
        return unless agent && execution

        skills = agent.skills.active
        return if skills.empty?

        recorded = 0
        skills.find_each do |skill|
          # Create usage record with full execution context
          skill.usage_records.create!(
            account: account,
            ai_agent: agent,
            execution_id: execution.id,
            execution_type: execution.class.name,
            outcome: outcome,
            duration_ms: execution.respond_to?(:duration_ms) ? execution.duration_ms : nil,
            context_summary: execution.respond_to?(:task_description) ? execution.task_description&.truncate(500) : nil
          )

          # Update skill counters (mirrors Skill#record_usage! logic without double-creating records)
          case outcome
          when "success"
            skill.increment!(:positive_usage_count)
          when "failure"
            skill.increment!(:negative_usage_count)
          end
          skill.update_column(:last_used_at, Time.current)

          recorded += 1
        end

        Rails.logger.info "[SkillGraph::SelfLearning] Recorded #{recorded} skill outcomes for agent #{agent.id}"
        recorded
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::SelfLearning] record_skill_outcomes failed: #{e.message}"
        0
      end

      # Strengthen/weaken KG edges based on co-usage outcomes
      def optimize_dependencies(execution:, agent:, outcome:)
        return unless Shared::FeatureFlagService.enabled?(:skill_self_learning, account)

        skills = agent&.skills&.active
        return if skills.blank? || skills.size < 2

        skill_ids = skills.pluck(:id)
        node_ids = account.ai_knowledge_graph_nodes
          .skill_nodes.active
          .where(ai_skill_id: skill_ids)
          .pluck(:id)

        return if node_ids.size < 2

        edges = account.ai_knowledge_graph_edges
          .where(source_node_id: node_ids, target_node_id: node_ids)
          .active

        adjustment = outcome == "success" ? 0.05 : -0.05

        edges.find_each do |edge|
          new_weight = (edge.weight + adjustment).clamp(0.1, 1.0)
          edge.update!(weight: new_weight)
        end

        Rails.logger.info "[SkillGraph::SelfLearning] Adjusted #{edges.count} edge weights by #{adjustment} for outcome: #{outcome}"
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::SelfLearning] optimize_dependencies failed: #{e.message}"
      end

      # Propose prompt refinements based on compound learnings
      def propose_prompt_refinements
        return [] unless Shared::FeatureFlagService.enabled?(:skill_self_learning, account)

        proposals = []
        Ai::Skill.for_account(account.id).active.find_each do |skill|
          # Find compound learnings relevant to this skill
          embedding = skill.knowledge_graph_node&.embedding
          next unless embedding

          learnings = Ai::CompoundLearning.active
            .for_account(account.id)
            .nearest_neighbors(:embedding, embedding, distance: "cosine")
            .first(5)
            .select { |l| l.neighbor_distance <= 0.5 }

          next if learnings.empty?

          # Check if recommendation already exists
          existing = Ai::ImprovementRecommendation
            .where(account: account, target_type: "Ai::Skill", target_id: skill.id, recommendation_type: "prompt_refinement")
            .pending
            .exists?
          next if existing

          learning_summaries = learnings.map { |l| l.content.truncate(100) }.join("; ")

          Ai::ImprovementRecommendation.create!(
            account: account,
            recommendation_type: "prompt_refinement",
            target_type: "Ai::Skill",
            target_id: skill.id,
            title: "Refine prompt for '#{skill.name}' based on #{learnings.size} compound learnings",
            description: "Relevant learnings: #{learning_summaries}",
            confidence_score: learnings.first.respond_to?(:neighbor_distance) ? (1.0 - learnings.first.neighbor_distance).round(4) : 0.7,
            status: "pending",
            metadata: { learning_ids: learnings.map(&:id), skill_effectiveness: skill.effectiveness_score }
          )
          proposals << skill.id
        end

        Rails.logger.info "[SkillGraph::SelfLearning] Proposed #{proposals.size} prompt refinements"
        proposals
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::SelfLearning] propose_prompt_refinements failed: #{e.message}"
        []
      end

      # Detect capability gaps where learnings suggest skills that don't exist
      def detect_capability_gaps
        return { gaps: [], proposed_categories: [] } unless Shared::FeatureFlagService.enabled?(:skill_self_learning, account)

        # Find high-importance learnings with no close skill match
        gaps = []
        high_learnings = Ai::CompoundLearning.active
          .for_account(account.id)
          .where("importance_score >= ?", 0.7)
          .where.not(embedding: nil)
          .order(importance_score: :desc)
          .limit(50)

        high_learnings.each do |learning|
          # Check if any skill closely matches
          closest_skills = account.ai_knowledge_graph_nodes
            .skill_nodes.active.with_embeddings
            .nearest_neighbors(:embedding, learning.embedding, distance: "cosine")
            .first(3)

          best_match = closest_skills.first
          best_similarity = best_match ? (1.0 - best_match.neighbor_distance) : 0.0

          if best_similarity < 0.5
            gaps << {
              learning_id: learning.id,
              learning_content: learning.content.truncate(200),
              category: learning.category,
              importance: learning.importance_score,
              best_match_similarity: best_similarity.round(4)
            }
          end
        end

        # Cluster gaps by category — propose new skills when >= 3 gaps in same category
        by_category = gaps.group_by { |g| g[:category] }
        proposals = []

        by_category.each do |category, category_gaps|
          next if category_gaps.size < 3

          existing = Ai::ImprovementRecommendation
            .where(account: account, recommendation_type: "skill_creation")
            .pending
            .where("metadata @> ?", { gap_category: category }.to_json)
            .exists?
          next if existing

          Ai::ImprovementRecommendation.create!(
            account: account,
            recommendation_type: "skill_creation",
            target_type: "Account",
            target_id: account.id,
            title: "Create skill for '#{category}' capability gap (#{category_gaps.size} learnings)",
            description: "#{category_gaps.size} high-importance learnings suggest a missing #{category} skill. Top gaps: #{category_gaps.first(3).map { |g| g[:learning_content] }.join('; ')}",
            confidence_score: category_gaps.map { |g| g[:importance] }.sum / category_gaps.size,
            status: "pending",
            metadata: { gap_category: category, gap_count: category_gaps.size, learning_ids: category_gaps.map { |g| g[:learning_id] } }
          )
          proposals << category
        end

        Rails.logger.info "[SkillGraph::SelfLearning] Detected #{gaps.size} gaps, proposed #{proposals.size} new skills"
        { gaps: gaps, proposed_categories: proposals }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::SelfLearning] detect_capability_gaps failed: #{e.message}"
        { gaps: [], proposed_categories: [] }
      end

      # Batch recalculate all skill effectiveness scores
      def recalculate_all_effectiveness
        updated = 0
        Ai::Skill.for_account(account.id).active.find_each do |skill|
          skill.recalculate_effectiveness!
          updated += 1
        end

        Rails.logger.info "[SkillGraph::SelfLearning] Recalculated effectiveness for #{updated} skills"
        updated
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::SelfLearning] recalculate_all_effectiveness failed: #{e.message}"
        0
      end
    end
  end
end
