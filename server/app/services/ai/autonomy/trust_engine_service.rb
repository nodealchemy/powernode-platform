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
      # Cooling-off period after demotion before promotion is allowed
      PROMOTION_COOLDOWN_HOURS = 24
      # Minimum hours at current tier before promotion is considered
      MIN_HOURS_AT_CURRENT_TIER = 12

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

        # Cancel all running executions for this agent
        cancel_running_executions(agent, reason)

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

      # Evaluate a specific agent's pending executions
      # @param agent [Ai::Agent] The agent to evaluate
      # @return [Hash] Evaluation result
      def evaluate_pending_for(agent:)
        trust_score = find_or_create_trust_score(agent)

        recent_executions = Ai::AgentExecution
          .where(ai_agent_id: agent.id)
          .where("created_at > ?", trust_score.last_evaluated_at || 30.days.ago)
          .order(created_at: :desc)
          .limit(20)

        if recent_executions.empty?
          return {
            success: true,
            agent_id: agent.id,
            overall_score: trust_score.overall_score,
            tier: trust_score.tier,
            message: "No new executions to evaluate"
          }
        end

        aggregate_updates = aggregate_execution_metrics(recent_executions)
        apply_updates!(trust_score, aggregate_updates)
        tier_change = check_tier_transition(trust_score)

        {
          success: true,
          agent_id: agent.id,
          overall_score: trust_score.overall_score,
          tier: trust_score.tier,
          tier_change: tier_change,
          executions_evaluated: recent_executions.size
        }
      end

      # Apply temporal decay to all trust scores
      # 7-day grace period, 2%/week toward 0.5 baseline, 30% max decay
      # @return [Array<Hash>] List of agents affected
      def apply_decay!
        scores = Ai::AgentTrustScore.where(account_id: account.id)
          .where("last_evaluated_at < ?", 7.days.ago)
          .includes(:agent)

        results = []
        scores.find_each do |trust_score|
          next unless trust_score.agent

          days_since = (Time.current - trust_score.last_evaluated_at).to_f / 1.day
          weeks_since = (days_since - 7) / 7.0 # Grace period subtracted
          next if weeks_since <= 0

          decay_rate = 0.02 # 2% per week
          baseline = 0.5
          max_decay = 0.30

          Ai::AgentTrustScore::DIMENSIONS.each do |dim|
            current = trust_score.send(dim) || 0.5
            diff = current - baseline
            next if diff.abs < 0.01

            magnitude = [diff.abs * decay_rate * weeks_since, diff.abs * max_decay].min
            decay = diff.positive? ? magnitude : -magnitude
            trust_score.send(:"#{dim}=", (current - decay).clamp(0.0, 1.0).round(4))
          end

          trust_score.recalculate!(count_evaluation: false)
          results << { agent_id: trust_score.agent_id, tier: trust_score.tier, overall_score: trust_score.overall_score }
        end

        Rails.logger.info("[TrustEngine] Decay applied to #{results.size} agents")
        results
      end

      # Inherit trust from parent to child with configurable policy
      # @param parent [Ai::Agent] The parent agent
      # @param child [Ai::Agent] The child agent
      # @param policy [String] 'conservative', 'moderate', or 'permissive'
      # @return [Ai::AgentTrustScore] The child's trust score
      def inherit_trust(parent, child, policy: "conservative")
        parent_trust = Ai::AgentTrustScore.find_by(agent_id: parent.id)
        return find_or_create_trust_score(child) unless parent_trust

        multiplier = case policy
                     when "conservative" then 0.3
                     when "moderate" then 0.5
                     when "permissive" then 0.7
                     else 0.3
                     end

        initial_tier = case policy
                       when "conservative" then "supervised"
                       when "moderate" then "monitored"
                       when "permissive" then "trusted"
                       else "supervised"
                       end

        child_trust = find_or_create_trust_score(child)
        Ai::AgentTrustScore::DIMENSIONS.each do |dim|
          parent_val = parent_trust.send(dim) || 0.5
          inherited = [parent_val * multiplier, 0.2].max
          child_trust.send(:"#{dim}=", inherited.round(4))
        end

        child_trust.evaluation_history = (child_trust.evaluation_history || []) + [{
          type: "trust_inheritance",
          parent_agent_id: parent.id,
          policy: policy,
          multiplier: multiplier,
          evaluated_at: Time.current.iso8601
        }]
        child_trust.recalculate!

        # Cap inherited tier to the policy's maximum
        tier_idx = Ai::AgentTrustScore::TIERS.index(initial_tier) || 0
        computed_idx = Ai::AgentTrustScore::TIERS.index(child_trust.tier) || 0
        child_trust.update!(tier: initial_tier) if computed_idx > tier_idx

        child_trust
      end

      # Bulk evaluate all agents that need re-evaluation
      def evaluate_pending
        scores = Ai::AgentTrustScore.where(account_id: account.id).needs_evaluation.includes(:agent)
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
          ts.overall_score = 0.65
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
        when "completed_with_warnings" then 0.7
        when "timeout" then 0.3
        when "failed" then 0.0
        when "cancelled" then 0.5
        else 0.5
        end
      end

      def calculate_cost_efficiency(execution)
        cost = execution.try(:cost_usd) || 0
        tokens = execution.try(:tokens_used) || 0
        return 0.5 if tokens.zero? && cost.zero?

        # Factor 1: Budget remaining ratio (if budget exists)
        budget = Ai::AgentBudget.where(agent_id: execution.try(:ai_agent_id)).active.first
        budget_ratio = if budget && budget.total_budget_cents > 0
                         1.0 - budget.utilization_ratio
                       else
                         0.5
                       end

        # Factor 2: Cost vs expected (normalize against model pricing)
        cost_score = if cost > 0 && tokens > 0
                       cost_per_1k = (cost / (tokens / 1000.0))
                       # Lower cost per 1K tokens = higher efficiency
                       [1.0 - (cost_per_1k / 0.05).clamp(0.0, 1.0), 0.0].max
                     else
                       0.5
                     end

        (budget_ratio * 0.4 + cost_score * 0.6).round(4)
      end

      def calculate_safety(execution)
        violations = execution.try(:error_details)&.dig("safety_violations")
        return 0.0 if violations.present? && violations.any?

        guardrail_blocked = execution.try(:error_details)&.dig("guardrail_blocked")
        return 0.2 if guardrail_blocked

        # Factor in anomaly signals from execution metadata
        anomaly_score = execution.try(:performance_metrics)&.dig("anomaly_score")
        return (1.0 - anomaly_score.to_f).clamp(0.0, 1.0) if anomaly_score.present?

        # Factor in PII redaction trigger count
        pii_triggers = execution.try(:performance_metrics)&.dig("pii_triggers")
        return 0.7 if pii_triggers.to_i > 0

        1.0
      end

      def calculate_quality(execution)
        eval_score = execution.try(:performance_metrics)&.dig("quality_score")
        return eval_score.to_f.clamp(0.0, 1.0) if eval_score.present?

        # Factor in reflection quality score (from reasoning framework)
        reflection_score = execution.try(:performance_metrics)&.dig("reflection_quality_score")
        if reflection_score.present?
          base = reflection_score.to_f.clamp(0.0, 1.0)
          # Self-correcting agents (should_retry was true and succeeded) get a reliability boost
          self_corrected = execution.try(:performance_metrics)&.dig("self_corrected")
          base = [base + 0.1, 1.0].min if self_corrected
          return base
        end

        # Factor in evaluator verdict
        evaluator_verdict = execution.try(:performance_metrics)&.dig("evaluator_verdict")
        if evaluator_verdict.present?
          return case evaluator_verdict
                 when "pass" then 0.9
                 when "revise" then 0.6
                 when "reject" then 0.2
                 else 0.5
                 end
        end

        review_score = execution.try(:performance_metrics)&.dig("review_approval_rate")
        return review_score.to_f.clamp(0.0, 1.0) if review_score.present?

        user_feedback = execution.try(:performance_metrics)&.dig("user_rating")
        return (user_feedback.to_f / 5.0).clamp(0.0, 1.0) if user_feedback.present?

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
            # Cooling-off: skip promotion if recently demoted or too soon at current tier
            if !recently_demoted?(trust_score) && !too_soon_for_promotion?(trust_score)
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

      # Cancel all running executions for an agent (called during emergency demotion)
      def cancel_running_executions(agent, reason)
        agent.executions.running.find_each do |execution|
          execution.cancel_execution!("Emergency demotion: #{reason}")
        rescue StandardError => e
          Rails.logger.error("[TrustEngine] Failed to cancel execution #{execution.id}: #{e.message}")
        end
      end

      # Check if agent was recently demoted (within PROMOTION_COOLDOWN_HOURS)
      def recently_demoted?(trust_score)
        history = trust_score.evaluation_history || []
        history.any? do |entry|
          entry_type = entry["type"] || entry[:type]
          evaluated_at = entry["evaluated_at"] || entry[:evaluated_at]
          next false unless entry_type.to_s.include?("demotion") || entry_type.to_s.include?("emergency")
          next false unless evaluated_at

          Time.parse(evaluated_at.to_s) >= PROMOTION_COOLDOWN_HOURS.hours.ago
        rescue StandardError
          false
        end
      end

      # Check if agent has been at current tier for less than MIN_HOURS_AT_CURRENT_TIER
      def too_soon_for_promotion?(trust_score)
        history = trust_score.evaluation_history || []
        last_tier_change = history.select do |entry|
          entry_type = entry["type"] || entry[:type]
          %w[promotion demotion trust_inheritance].include?(entry_type.to_s)
        end.last

        return false unless last_tier_change

        evaluated_at = last_tier_change["evaluated_at"] || last_tier_change[:evaluated_at]
        return false unless evaluated_at

        Time.parse(evaluated_at.to_s) >= MIN_HOURS_AT_CURRENT_TIER.hours.ago
      rescue StandardError
        false
      end

      def aggregate_execution_metrics(executions)
        totals = { reliability: 0.0, cost_efficiency: 0.0, safety: 0.0, quality: 0.0, speed: 0.0 }
        total_weight = 0.0

        executions.each_with_index do |exec, idx|
          # Exponential decay: more recent executions get higher weight
          weight = Math.exp(-0.05 * idx)
          total_weight += weight

          totals[:reliability] += calculate_reliability(exec) * weight
          totals[:cost_efficiency] += calculate_cost_efficiency(exec) * weight
          totals[:safety] += calculate_safety(exec) * weight
          totals[:quality] += calculate_quality(exec) * weight
          totals[:speed] += calculate_speed(exec) * weight
        end

        return totals.transform_values { 0.5 } if total_weight.zero?

        totals.transform_values { |v| (v / total_weight).round(4) }
      end
    end
  end
end
