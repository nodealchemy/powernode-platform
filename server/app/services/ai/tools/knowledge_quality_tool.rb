# frozen_string_literal: true

module Ai
  module Tools
    class KnowledgeQualityTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.manage"

      def self.definition
        {
          name: "knowledge_quality",
          description: "Manage knowledge quality: verify/dispute learnings, resolve contradictions, rate shared knowledge, or get a cross-system health report",
          parameters: {
            action: { type: "string", required: true, description: "Action: verify_learning, dispute_learning, resolve_contradiction, rate_knowledge, knowledge_health" },
            learning_id: { type: "string", required: false, description: "CompoundLearning ID (for verify/dispute)" },
            winner_id: { type: "string", required: false, description: "Winning learning ID (for resolve_contradiction)" },
            loser_id: { type: "string", required: false, description: "Losing learning ID (for resolve_contradiction)" },
            entry_id: { type: "string", required: false, description: "SharedKnowledge entry ID (for rate_knowledge)" },
            rating: { type: "integer", required: false, description: "Quality rating 1-5 (for rate_knowledge)" },
            reason: { type: "string", required: false, description: "Reason for dispute or contradiction resolution" }
          }
        }
      end

      def self.action_definitions
        {
          "verify_learning" => {
            description: "Verify a compound learning as accurate, boosting its confidence score",
            parameters: {
              learning_id: { type: "string", required: true, description: "CompoundLearning ID to verify" }
            }
          },
          "dispute_learning" => {
            description: "Dispute a compound learning as inaccurate with a reason",
            parameters: {
              learning_id: { type: "string", required: true, description: "CompoundLearning ID to dispute" },
              reason: { type: "string", required: true, description: "Reason for the dispute" }
            }
          },
          "resolve_contradiction" => {
            description: "Resolve a contradiction between two learnings by picking a winner",
            parameters: {
              winner_id: { type: "string", required: true, description: "Winning learning ID" },
              loser_id: { type: "string", required: true, description: "Losing learning ID (will be superseded)" },
              reason: { type: "string", required: true, description: "Reason for the resolution" }
            }
          },
          "rate_knowledge" => {
            description: "Rate a shared knowledge entry on a 1-5 quality scale",
            parameters: {
              entry_id: { type: "string", required: true, description: "SharedKnowledge entry ID" },
              rating: { type: "integer", required: true, description: "Quality rating (1-5)" }
            }
          },
          "knowledge_health" => {
            description: "Get a cross-system health report for learnings, shared knowledge, and knowledge graph",
            parameters: {}
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "verify_learning" then verify_learning(params)
        when "dispute_learning" then dispute_learning(params)
        when "resolve_contradiction" then resolve_contradiction(params)
        when "rate_knowledge" then rate_knowledge(params)
        when "knowledge_health" then knowledge_health
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid: verify_learning, dispute_learning, resolve_contradiction, rate_knowledge, knowledge_health" }
        end
      end

      private

      def verify_learning(params)
        learning = find_learning!(params[:learning_id])
        return learning unless learning.is_a?(Ai::CompoundLearning)

        return { success: false, error: "Learning is already #{learning.status}" } unless learning.status == "active"
        return { success: false, error: "User context required to verify" } unless user

        learning.verify!(user: user)

        {
          success: true,
          message: "Learning verified successfully",
          learning_id: learning.id,
          new_status: learning.status,
          new_importance: learning.reload.importance_score.to_f.round(4),
          new_confidence: learning.confidence_score.to_f.round(4)
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def dispute_learning(params)
        learning = find_learning!(params[:learning_id])
        return learning unless learning.is_a?(Ai::CompoundLearning)

        return { success: false, error: "Learning is already #{learning.status}" } if learning.status == "disproven"
        return { success: false, error: "User context required to dispute" } unless user
        return { success: false, error: "Reason is required to dispute a learning" } if params[:reason].blank?

        learning.disprove!(user: user, reason: params[:reason])

        {
          success: true,
          message: "Learning marked as disproven",
          learning_id: learning.id,
          new_status: learning.status,
          new_importance: learning.importance_score.to_f.round(4),
          reason: params[:reason]
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def resolve_contradiction(params)
        winner = find_learning!(params[:winner_id])
        return winner unless winner.is_a?(Ai::CompoundLearning)

        loser = find_learning!(params[:loser_id])
        return loser unless loser.is_a?(Ai::CompoundLearning)

        return { success: false, error: "Reason is required to resolve a contradiction" } if params[:reason].blank?

        loser.supersede!(winner)
        loser.resolve_contradiction!(note: params[:reason])
        winner.boost_importance!(0.10)

        {
          success: true,
          message: "Contradiction resolved",
          winner_id: winner.id,
          loser_id: loser.id,
          winner_importance: winner.reload.importance_score.to_f.round(4),
          loser_status: loser.status,
          reason: params[:reason]
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def rate_knowledge(params)
        return { success: false, error: "entry_id is required" } if params[:entry_id].blank?
        return { success: false, error: "rating (1-5) is required" } if params[:rating].blank?

        entry = Ai::SharedKnowledge.find_by(id: params[:entry_id], account: account)
        return { success: false, error: "Knowledge entry not found" } unless entry

        entry.record_rating!(params[:rating].to_i)

        {
          success: true,
          message: "Rating recorded",
          entry_id: entry.id,
          new_quality_score: entry.reload.quality_score.to_f.round(4),
          rating_count: entry.rating_count,
          average_rating: entry.rating_count.positive? ? (entry.rating_sum.to_f / entry.rating_count).round(2) : nil
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def knowledge_health
        learnings = learning_health
        knowledge = shared_knowledge_health
        graph = graph_health

        {
          success: true,
          health: {
            learnings: learnings,
            shared_knowledge: knowledge,
            knowledge_graph: graph,
            generated_at: Time.current.iso8601
          }
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def learning_health
        scope = Ai::CompoundLearning.where(account: account)
        event_processed_24h = scope.where("last_event_processed_at >= ?", 24.hours.ago).count
        batch_only_24h = scope.active.where("updated_at >= ?", 24.hours.ago)
          .where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago).count
        {
          total: scope.count,
          active: scope.active.count,
          verified: scope.verified.count,
          disproven: scope.disproven.count,
          deprecated: scope.where(status: "deprecated").count,
          superseded: scope.where(status: "superseded").count,
          avg_importance: scope.active.average(:importance_score)&.to_f&.round(4) || 0,
          avg_confidence: scope.active.average(:confidence_score)&.to_f&.round(4) || 0,
          avg_effectiveness: scope.active.where("injection_count >= 3").average(:effectiveness_score)&.to_f&.round(4) || 0,
          high_importance_count: scope.active.high_importance.count,
          event_processed_24h: event_processed_24h,
          batch_only_24h: batch_only_24h
        }
      end

      def shared_knowledge_health
        scope = Ai::SharedKnowledge.where(account: account)
        event_processed_24h = scope.where("last_event_processed_at >= ?", 24.hours.ago).count
        {
          total: scope.count,
          avg_quality: scope.average(:quality_score)&.to_f&.round(4) || 0,
          with_ratings: scope.where("rating_count > 0").count,
          avg_rating: scope.where("rating_count > 0").average("rating_sum::float / rating_count")&.to_f&.round(2) || 0,
          total_usage: scope.sum(:usage_count),
          with_embeddings: scope.with_embedding.count,
          stale_count: scope.where("last_quality_recalc_at < ? OR last_quality_recalc_at IS NULL", 24.hours.ago).count,
          event_processed_24h: event_processed_24h
        }
      end

      def graph_health
        scope = Ai::KnowledgeGraphNode.where(account: account)
        event_processed_24h = scope.where("last_event_processed_at >= ?", 24.hours.ago).count
        {
          total_nodes: scope.count,
          active_nodes: scope.active.count,
          avg_confidence: scope.active.where.not(confidence: nil).average(:confidence)&.to_f&.round(4) || 0,
          low_confidence_count: scope.active.where("confidence < ?", 0.3).count,
          with_embeddings: scope.with_embeddings.count,
          total_edges: Ai::KnowledgeGraphEdge.joins(:source_node).where(ai_knowledge_graph_nodes: { account_id: account.id }).count,
          event_processed_24h: event_processed_24h
        }
      end

      def find_learning!(learning_id)
        return { success: false, error: "learning_id is required" } if learning_id.blank?

        learning = Ai::CompoundLearning.find_by(id: learning_id, account: account)
        return { success: false, error: "Learning not found" } unless learning

        learning
      end
    end
  end
end
