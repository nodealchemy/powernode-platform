# frozen_string_literal: true

module Ai
  class FeedbackLoopService
    TRUST_BATCH_SIZE = 20

    # Closed contract with Api::V1::Internal::Ai::AutonomyController
    # #analyze_policy_patterns (the only consumer), which switches on
    # suggestion[:type] via `==` comparisons rather than an exhaustive case
    # and always files the result as recommendation_type "agent_reliability"
    # regardless of type. A suggestion type outside this set would silently
    # fall through those comparisons' `else` branches instead of raising —
    # #build_suggestion below is the guard that keeps that from happening.
    KNOWN_SUGGESTION_TYPES = %w[auto_approve_suggestion quality_concern].freeze

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

    # Batch apply accumulated feedback to trust score.
    #
    # Atomic + deterministic: a stable, ordered batch of feedback ids is pinned
    # up front, then the average, trust update, and applied-flag write all run
    # against EXACTLY that id set inside a single transaction with row locks.
    # This prevents (a) averaging a different set of rows than are marked
    # applied (the lazy-relation re-query hazard) and (b) a crash between the
    # trust update and the flag write leaving rows unapplied → re-applied.
    def apply_feedback_to_trust(agent)
      Ai::AgentFeedback.transaction do
        batch_ids = Ai::AgentFeedback.for_agent(agent.id)
                                     .unapplied
                                     .order(:created_at, :id)
                                     .limit(TRUST_BATCH_SIZE)
                                     .lock("FOR UPDATE SKIP LOCKED")
                                     .pluck(:id)
        next if batch_ids.empty?

        batch = Ai::AgentFeedback.where(id: batch_ids)

        # Calculate quality delta over exactly the pinned batch
        avg_rating = batch.average(:rating).to_f
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

        # Mark exactly the pinned batch as applied
        batch.update_all(applied_to_trust: true)

        { feedbacks_applied: batch_ids.size, quality_delta: quality_delta }
      end
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
        suggestions << build_suggestion(
          type: "auto_approve_suggestion",
          message: "#{(approval_rate * 100).round(1)}% approval rate over 30 days — consider enabling auto-approve policy",
          agent_id: agent&.id,
          approval_rate: approval_rate
        )
      end

      if approval_rate < 0.3
        suggestions << build_suggestion(
          type: "quality_concern",
          message: "Only #{(approval_rate * 100).round(1)}% approval rate — agent may need retraining or trust demotion",
          agent_id: agent&.id,
          approval_rate: approval_rate
        )
      end

      {
        total_proposals: total,
        approval_rate: approval_rate,
        suggestions: suggestions.compact
      }
    end

    private

    # Guard clause, not an exhaustive-case raise: analyze_patterns runs across
    # every active agent for every active account in a single sweep
    # (Api::V1::Internal::Ai::AutonomyController#analyze_policy_patterns), and
    # that caller already rescues per-agent to keep one failure from aborting
    # the batch. Raising here would just bounce off that rescue anyway, so
    # logging and dropping the single bad suggestion in place is cheaper and
    # keeps the safety net at the point of truth instead of relying on every
    # future caller to wrap this in its own rescue.
    def build_suggestion(type:, message:, agent_id:, approval_rate:)
      unless KNOWN_SUGGESTION_TYPES.include?(type)
        Rails.logger.warn "[FeedbackLoop] Dropping suggestion with unrecognized type: #{type.inspect}"
        return nil
      end

      { type: type, message: message, agent_id: agent_id, approval_rate: approval_rate }
    end
  end
end
