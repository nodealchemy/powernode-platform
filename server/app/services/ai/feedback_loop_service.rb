# frozen_string_literal: true

module Ai
  class FeedbackLoopService
    TRUST_BATCH_SIZE = 20

    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Record a piece of feedback and check if trust should be updated
    def record_feedback(agent:, user:, feedback_type:, rating:, comment: nil, context_type: nil, context_id: nil)
      feedback = Ai::AgentFeedback.create!(
        account: account,
        user: user,
        ai_agent_id: agent.id,
        feedback_type: feedback_type,
        rating: rating,
        comment: comment,
        context_type: context_type,
        context_id: context_id
      )

      # Check if enough feedback has accumulated to update trust
      unapplied_count = Ai::AgentFeedback.for_agent(agent.id).unapplied.count
      apply_feedback_to_trust(agent) if unapplied_count >= TRUST_BATCH_SIZE

      feedback
    end

    # Batch apply accumulated feedback to trust score
    def apply_feedback_to_trust(agent)
      feedbacks = Ai::AgentFeedback.for_agent(agent.id).unapplied.limit(TRUST_BATCH_SIZE)
      return if feedbacks.empty?

      # Calculate quality delta
      avg_rating = feedbacks.average(:rating).to_f
      quality_delta = (avg_rating - 3.0) / 2.0  # Normalize: 1→-1.0, 3→0.0, 5→+1.0

      # Apply to trust score
      trust_score = Ai::AgentTrustScore.find_by(agent_id: agent.id)
      if trust_score
        current = trust_score.overall_score || 0.5
        adjusted = (current + quality_delta * 0.1).clamp(0.0, 1.0)
        trust_score.update!(
          overall_score: adjusted,
          last_evaluated_at: Time.current
        )
      end

      # Mark feedbacks as applied
      feedbacks.update_all(applied_to_trust: true)

      { feedbacks_applied: feedbacks.size, quality_delta: quality_delta }
    end

    # Analyze approval/rejection patterns for policy tuning suggestions
    def analyze_patterns(agent: nil)
      scope = account.ai_agent_proposals
      scope = scope.where(ai_agent_id: agent.id) if agent

      total = scope.where("created_at >= ?", 30.days.ago).count
      return nil if total < 10

      approved = scope.where(status: "approved").where("created_at >= ?", 30.days.ago).count
      approval_rate = approved.to_f / total

      suggestions = []

      if approval_rate > 0.95
        suggestions << {
          type: "auto_approve_suggestion",
          message: "#{(approval_rate * 100).round(1)}% approval rate over 30 days — consider enabling auto-approve policy",
          agent_id: agent&.id,
          approval_rate: approval_rate
        }
      end

      if approval_rate < 0.3
        suggestions << {
          type: "quality_concern",
          message: "Only #{(approval_rate * 100).round(1)}% approval rate — agent may need retraining or trust demotion",
          agent_id: agent&.id,
          approval_rate: approval_rate
        }
      end

      {
        total_proposals: total,
        approval_rate: approval_rate,
        suggestions: suggestions
      }
    end
  end
end
