# frozen_string_literal: true

module Ai
  module Autonomy
    class TrustEngineService
      # Trust dimensions with weights
      DIMENSION_WEIGHTS = {
        reliability: 0.25,
        cost_efficiency: 0.15,
        safety: 0.30,
        quality: 0.20,
        speed: 0.10
      }.freeze

      # Tier thresholds
      TIER_THRESHOLDS = Ai::AgentTrustScore::TIER_THRESHOLDS

      # Minimum evaluations before promotion is allowed
      MIN_EVALUATIONS_FOR_PROMOTION = 10
      # Consecutive successful executions needed for promotion consideration
      MIN_CONSECUTIVE_SUCCESSES = 5

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Evaluate an agent after execution and update trust scores
      # @param agent [Ai::Agent] The agent to evaluate
      # @param execution [Ai::AgentExecution] The completed execution
      # @return [Hash] Updated trust assessment
      def evaluate(agent:, execution:)
        trust_score = find_or_create_trust_score(agent)

        # Calculate dimension updates based on execution
        updates = calculate_dimension_updates(trust_score, execution)

        # Apply exponential moving average for smooth updates
        apply_updates!(trust_score, updates)

        # Check for tier changes
        tier_change = check_tier_transition(trust_score)

        Rails.logger.info(
          "[TrustEngine] Evaluated agent #{agent.id}: " \
          "score=#{trust_score.overall_score.round(3)} " \
          "tier=#{trust_score.tier} " \
          "change=#{tier_change[:type] || 'none'}"
        )

        {
          success: true,
          agent_id: agent.id,
          overall_score: trust_score.overall_score,
          tier: trust_score.tier,
          tier_change: tier_change,
          dimensions: dimension_snapshot(trust_score)
        }
      rescue StandardError => e
        Rails.logger.error("[TrustEngine] Evaluation failed for agent #{agent.id}: #{e.message}")
        { success: false, error: e.message }
      end

      # Emergency demotion for critical violations (OWASP ASI10 - Rogue Agents)
      # @param agent [Ai::Agent] The agent to demote
      # @param reason [String] Reason for demotion
      def emergency_demote!(agent:, reason:)
        trust_score = find_or_create_trust_score(agent)
        previous_tier = trust_score.tier

        trust_score.emergency_demote!(reason: reason)

        # Update agent trust_level
        agent.update!(trust_level: "supervised") if agent.respond_to?(:trust_level=)

        Rails.logger.warn(
          "[TrustEngine] EMERGENCY DEMOTION: agent=#{agent.id} " \
          "from=#{previous_tier} to=supervised reason=#{reason}"
        )

        { success: true, previous_tier: previous_tier, new_tier: "supervised", reason: reason }
      end

      # Get trust assessment for an agent
      # @param agent [Ai::Agent] The agent to assess
      # @return [Hash] Trust assessment
      def assess(agent:)
        trust_score = Ai::AgentTrustScore.find_by(agent_id: agent.id)

        return { tier: "supervised", score: 0.0, evaluated: false } unless trust_score

        {
          tier: trust_score.tier,
          score: trust_score.overall_score,
          dimensions: dimension_snapshot(trust_score),
          promotable: trust_score.promotable?,
          demotable: trust_score.demotable?,
          evaluation_count: trust_score.evaluation_count,
          last_evaluated_at: trust_score.last_evaluated_at,
          evaluated: true
        }
      end

      # Bulk evaluate all agents that need re-evaluation
      def evaluate_pending
        scores = Ai::AgentTrustScore.needs_evaluation.includes(:agent)
        results = []

        scores.find_each do |trust_score|
          next unless trust_score.agent

          recent_executions = Ai::AgentExecution
            .where(ai_agent_id: trust_score.agent_id)
            .where("created_at > ?", trust_score.last_evaluated_at || 30.days.ago)
            .order(created_at: :desc)
            .limit(20)

          next if recent_executions.empty?

          aggregate_updates = aggregate_execution_metrics(recent_executions)
          apply_updates!(trust_score, aggregate_updates)
          check_tier_transition(trust_score)

          results << { agent_id: trust_score.agent_id, tier: trust_score.tier, score: trust_score.overall_score }
        end

        Rails.logger.info("[TrustEngine] Bulk evaluated #{results.size} agents")
        results
      end

      private

      def find_or_create_trust_score(agent)
        Ai::AgentTrustScore.find_or_create_by!(agent_id: agent.id) do |ts|
          ts.account = agent.account
          ts.reliability = 0.5
          ts.cost_efficiency = 0.5
          ts.safety = 1.0
          ts.quality = 0.5
          ts.speed = 0.5
          ts.overall_score = 0.5
          ts.tier = "supervised"
          ts.evaluation_count = 0
          ts.evaluation_history = []
        end
      end

      def calculate_dimension_updates(trust_score, execution)
        {
          reliability: calculate_reliability(execution),
          cost_efficiency: calculate_cost_efficiency(execution),
          safety: calculate_safety(execution),
          quality: calculate_quality(execution),
          speed: calculate_speed(execution)
        }
      end

      def calculate_reliability(execution)
        case execution.try(:status)
        when "completed" then 1.0
        when "failed" then 0.0
        when "cancelled" then 0.3
        else 0.5
        end
      end

      def calculate_cost_efficiency(execution)
        tokens = execution.try(:tokens_used) || 0
        return 0.5 if tokens.zero?

        # Lower token usage = higher efficiency (normalize to 0-1)
        # Assuming average execution uses ~2000 tokens
        efficiency = 1.0 - ([tokens, 10_000].min.to_f / 10_000)
        [efficiency, 0.0].max
      end

      def calculate_safety(execution)
        # Check for safety violations in execution
        violations = execution.try(:error_details)&.dig("safety_violations")
        return 0.0 if violations.present? && violations.any?

        guardrail_blocked = execution.try(:error_details)&.dig("guardrail_blocked")
        return 0.2 if guardrail_blocked

        1.0
      end

      def calculate_quality(execution)
        # Use evaluation results if available
        eval_score = execution.try(:performance_metrics)&.dig("quality_score")
        return eval_score if eval_score.present?

        # Fallback to completion status
        execution.try(:status) == "completed" ? 0.7 : 0.3
      end

      def calculate_speed(execution)
        duration_ms = execution.try(:duration_ms) || 0
        return 0.5 if duration_ms.zero?

        # Normalize: faster = higher score (under 5s is excellent)
        speed = 1.0 - ([duration_ms, 30_000].min.to_f / 30_000)
        [speed, 0.0].max
      end

      def apply_updates!(trust_score, updates)
        # Exponential moving average with alpha = 0.3
        alpha = 0.3

        updates.each do |dimension, new_value|
          current = trust_score.send(dimension) || 0.5
          updated = (alpha * new_value) + ((1 - alpha) * current)
          trust_score.send(:"#{dimension}=", updated.round(4))
        end

        trust_score.recalculate!
      end

      def check_tier_transition(trust_score)
        trust_score.with_lock do
          trust_score.reload

          if trust_score.promotable? && trust_score.evaluation_count >= MIN_EVALUATIONS_FOR_PROMOTION
            previous = trust_score.tier
            new_tier = next_tier(trust_score.tier)

            if new_tier && trust_score.overall_score >= TIER_THRESHOLDS[new_tier]
              trust_score.update!(tier: new_tier)

              # Update agent model if it has trust_level
              if trust_score.agent.respond_to?(:trust_level=)
                trust_score.agent.update!(trust_level: new_tier)
              end

              return { type: "promotion", from: previous, to: new_tier }
            end
          elsif trust_score.demotable?
            previous = trust_score.tier
            new_tier = previous_tier(trust_score.tier)

            if new_tier
              trust_score.update!(tier: new_tier)

              if trust_score.agent.respond_to?(:trust_level=)
                trust_score.agent.update!(trust_level: new_tier)
              end

              return { type: "demotion", from: previous, to: new_tier }
            end
          end

          { type: nil }
        end
      end

      def next_tier(current)
        tiers = Ai::AgentTrustScore::TIERS
        idx = tiers.index(current)
        idx && idx < tiers.size - 1 ? tiers[idx + 1] : nil
      end

      def previous_tier(current)
        tiers = Ai::AgentTrustScore::TIERS
        idx = tiers.index(current)
        idx && idx > 0 ? tiers[idx - 1] : nil
      end

      def dimension_snapshot(trust_score)
        Ai::AgentTrustScore::DIMENSIONS.each_with_object({}) do |dim, hash|
          hash[dim] = trust_score.send(dim)&.round(4)
        end
      end

      def aggregate_execution_metrics(executions)
        totals = { reliability: 0.0, cost_efficiency: 0.0, safety: 0.0, quality: 0.0, speed: 0.0 }
        count = executions.size.to_f

        executions.each do |exec|
          totals[:reliability] += calculate_reliability(exec)
          totals[:cost_efficiency] += calculate_cost_efficiency(exec)
          totals[:safety] += calculate_safety(exec)
          totals[:quality] += calculate_quality(exec)
          totals[:speed] += calculate_speed(exec)
        end

        totals.transform_values { |v| v / count }
      end
    end
  end
end
