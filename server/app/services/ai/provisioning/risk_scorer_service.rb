# frozen_string_literal: true

module Ai
  module Provisioning
    # Heuristic risk scorer for a provisioning plan. Surfaces the operator-
    # facing chips the Plan Review modal renders below the cost breakdown.
    #
    # The scorer is intentionally explainable: every contributing factor names
    # itself, attaches its weight, and includes a one-line explanation so the
    # operator can understand *why* the plan is rated medium instead of low.
    #
    # Factors (initial weights — tune in M2 after the first 50 plans land):
    #   Instance count > 5             → +15  (med)
    #   Public IP allocations          → +10 each (med)
    #   SDWAN federation (cross-acct)  → +20  (high)
    #   Cross-region                   → +15  (med)
    #   Data residency override        → +25  (high)
    #   Budget headroom < 10%          → +10  (med)
    #
    # Severity bands: 0-29 low / 30-59 med / 60-100 high.
    #
    # Output shape:
    #   {
    #     score:    0..100,
    #     severity: "low" | "med" | "high",
    #     factors:  [{ name:, weight:, severity:, explanation: }]
    #   }
    class RiskScorerService
      INSTANCE_COUNT_THRESHOLD = 5
      INSTANCE_COUNT_WEIGHT    = 15

      PUBLIC_IP_WEIGHT         = 10
      SDWAN_FEDERATION_WEIGHT  = 20
      CROSS_REGION_WEIGHT      = 15
      DATA_RESIDENCY_WEIGHT    = 25
      BUDGET_HEADROOM_WEIGHT   = 10

      MAX_SCORE = 100
      LOW_THRESHOLD  = 29
      MED_THRESHOLD  = 59

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Score a plan. Walks the plan steps + the backing brief.
      #
      # @param plan [Ai::GoalPlan]
      # @return [Hash] { score:, severity:, factors: }
      def score(plan:)
        brief = brief_for(plan) || {}
        steps = ordered_steps(plan)
        factors = []

        factors.concat(instance_count_factors(steps: steps, brief: brief))
        factors.concat(public_ip_factors(steps: steps))
        factors.concat(sdwan_federation_factors(steps: steps))
        factors.concat(cross_region_factors(brief: brief))
        factors.concat(data_residency_factors(brief: brief))
        factors.concat(budget_headroom_factors(plan: plan, brief: brief))

        score = factors.sum { |f| f[:weight].to_i }
        score = MAX_SCORE if score > MAX_SCORE
        score = 0        if score.negative?

        { score: score, severity: severity_for(score), factors: factors }
      end

      private

      # ---------------- factor evaluators ----------------

      def instance_count_factors(steps:, brief:)
        total = total_instance_count(steps: steps, brief: brief)
        return [] unless total > INSTANCE_COUNT_THRESHOLD

        [factor(
          name: "Instance count",
          weight: INSTANCE_COUNT_WEIGHT,
          severity: "med",
          explanation: "Plan provisions #{total} instances (threshold: #{INSTANCE_COUNT_THRESHOLD}). Scale-out broadens blast radius."
        )]
      end

      def public_ip_factors(steps:)
        public_ip_count = steps.count do |step|
          inputs = step_inputs(step)
          truthy?(inputs["public_ip"] || inputs[:public_ip] || inputs["allocate_public_ip"] || inputs[:allocate_public_ip])
        end
        return [] if public_ip_count.zero?

        [factor(
          name: "Public IP allocations",
          weight: PUBLIC_IP_WEIGHT * public_ip_count,
          severity: "med",
          explanation: "#{public_ip_count} step(s) allocate a public IP — internet-reachable surface added."
        )]
      end

      def sdwan_federation_factors(steps:)
        federated = steps.any? do |step|
          inputs = step_inputs(step)
          fed = inputs["federation"] || inputs[:federation] || inputs["sdwan_federation"] || inputs[:sdwan_federation]
          truthy?(fed) || (fed.is_a?(Hash) && fed["enabled"]) || (fed.is_a?(Array) && fed.any?)
        end
        return [] unless federated

        [factor(
          name: "SDWAN federation",
          weight: SDWAN_FEDERATION_WEIGHT,
          severity: "high",
          explanation: "Plan creates cross-account SDWAN peering — requires partner-account approval."
        )]
      end

      def cross_region_factors(brief:)
        regions = Array(brief["regions"] || brief[:regions]).reject { |r| r.to_s.strip.empty? }.uniq
        return [] if regions.size < 2

        [factor(
          name: "Cross-region",
          weight: CROSS_REGION_WEIGHT,
          severity: "med",
          explanation: "Plan spans #{regions.size} regions (#{regions.join(', ')}) — adds replication & egress complexity."
        )]
      end

      def data_residency_factors(brief:)
        residency = Array(brief["data_residency"] || brief[:data_residency]).reject { |r| r.to_s.strip.empty? }
        return [] if residency.empty?

        [factor(
          name: "Data residency override",
          weight: DATA_RESIDENCY_WEIGHT,
          severity: "high",
          explanation: "Brief asserts data must remain in #{residency.join(', ')} — review provider region selection."
        )]
      end

      def budget_headroom_factors(plan:, brief:)
        cap = (brief["budget_cap_usd_monthly"] || brief[:budget_cap_usd_monthly]).to_f
        return [] unless cap.positive?

        estimated = estimate_monthly(plan)
        return [] unless estimated.positive?

        headroom = ((cap - estimated) / cap) * 100.0
        return [] if headroom >= 10.0

        [factor(
          name: "Budget headroom",
          weight: BUDGET_HEADROOM_WEIGHT,
          severity: "med",
          explanation: "Estimated $#{estimated.round(0)}/mo against $#{cap.round(0)}/mo cap (headroom: #{headroom.round(1)}%)."
        )]
      end

      # ---------------- helpers ----------------

      def total_instance_count(steps:, brief:)
        # Sum explicit `count` from compute steps; fall back to brief.scale.initial.
        from_steps = steps.sum do |step|
          cfg = step.respond_to?(:execution_config) ? (step.execution_config || {}) : {}
          cfg = cfg.is_a?(Hash) ? cfg : {}
          inputs = cfg["inputs"] || cfg[:inputs] || {}
          inputs = inputs.is_a?(Hash) ? inputs : {}
          (inputs["count"] || inputs[:count] || inputs["instance_count"] || inputs[:instance_count] || 0).to_i
        end
        return from_steps if from_steps.positive?

        scale = brief["scale"] || brief[:scale] || {}
        scale = scale.is_a?(Hash) ? scale : {}
        (scale["initial"] || scale[:initial] || 0).to_i
      end

      def estimate_monthly(plan)
        ::Ai::Provisioning::CostEstimatorService.new(account: account).estimate(plan: plan)[:monthly_usd].to_f
      rescue StandardError => e
        Rails.logger.warn("[RiskScorerService] cost estimate failed: #{e.class}: #{e.message}")
        0.0
      end

      def step_inputs(step)
        cfg = step.respond_to?(:execution_config) ? (step.execution_config || {}) : {}
        cfg = cfg.is_a?(Hash) ? cfg : {}
        inputs = cfg["inputs"] || cfg[:inputs] || {}
        inputs.is_a?(Hash) ? inputs : {}
      end

      def truthy?(val)
        return val if val == true || val == false
        return false if val.nil?
        return val.positive? if val.is_a?(Numeric)
        return val.casecmp("true").zero? || val.casecmp("yes").zero? if val.is_a?(String)
        false
      end

      def ordered_steps(plan)
        return [] unless plan&.respond_to?(:steps)
        relation = plan.steps
        relation.respond_to?(:in_order) ? relation.in_order.to_a : relation.to_a.sort_by { |s| s.step_number.to_i }
      end

      def brief_for(plan)
        meta = plan.respond_to?(:goal) ? plan.goal&.metadata : nil
        mission_id = meta.is_a?(Hash) ? meta["provisioning_mission_id"] : nil
        return nil unless mission_id

        mission = account.ai_missions.find_by(id: mission_id)
        cfg = mission&.configuration
        cfg.is_a?(Hash) ? (cfg["brief"] || cfg[:brief]) : nil
      rescue StandardError
        nil
      end

      def factor(name:, weight:, severity:, explanation:)
        { name: name, weight: weight, severity: severity, explanation: explanation }
      end

      def severity_for(score)
        return "low"  if score <= LOW_THRESHOLD
        return "med"  if score <= MED_THRESHOLD
        "high"
      end
    end
  end
end
