# frozen_string_literal: true

module Ai
  module Provisioning
    # Single source of truth for the "rich plan" shape consumed by the
    # provisioning frontend (BriefCard, ProvisioningPlanReview,
    # ChatProvisioningCardSlot, StackTopologyPreview, CostBreakdown,
    # StepProgressStream).
    #
    # Both surfaces that surface a plan use this:
    #   - Ai::Tools::ProvisioningTool#compose_plan (chat tool returning a card)
    #   - Api::V1::Ai::MissionsController#compose_plan (REST endpoint hit by
    #     the deep-link page /app/system/provision?mission_id=…)
    #
    # Returned shape:
    #   {
    #     plan_id:,
    #     dag: { nodes: [...], edges: [...] },   # nodes/edges, not steps
    #     cost_estimate: { monthly_usd:, one_time_usd:, by_resource:, ... },
    #     topology_preview: { nodes:, edges:, regions:, estimated_resources: },
    #     risk: { score:, severity:, factors: }
    #   }
    #
    # Each enrichment is wrapped in `rescue StandardError` with a sane fallback
    # so a failing renderer doesn't 500 the response — the operator sees a
    # placeholder card instead.
    class PlanSnapshotService
      def initialize(account:)
        @account = account
      end

      # @param plan [Ai::GoalPlan]
      # @return [Hash] rich plan snapshot
      def snapshot(plan:)
        {
          plan_id: plan.id,
          dag: build_dag(plan),
          cost_estimate: build_cost_estimate(plan),
          topology_preview: build_topology_preview(plan),
          risk: build_risk(plan)
        }
      end

      private

      attr_reader :account

      # Frontend ProvisioningPlanReview reads `plan.dag.nodes` with each node
      # having { id, name, skill, description, status, dependencies }. The
      # legacy `serialize_dag` returned `{steps: [...]}` which silently
      # rendered as "0 steps" everywhere it was consumed.
      def build_dag(plan)
        steps = plan.steps.reload.to_a.sort_by { |s| s.step_number.to_i }
        nodes = steps.map { |s| node_for(s) }
        edges = build_edges(steps)
        { nodes: nodes, edges: edges }
      end

      def node_for(step)
        cfg = step.execution_config.is_a?(Hash) ? step.execution_config : {}
        skill = cfg["skill"] || cfg[:skill]
        {
          id: step.id.to_s,
          step_number: step.step_number,
          name: cfg["name"] || cfg[:name] || skill || "step #{step.step_number}",
          skill: skill,
          description: cfg["description"] || cfg[:description],
          dependencies: Array(step.dependencies).map(&:to_i),
          status: step.respond_to?(:status) ? step.status.to_s : "pending",
          on_failure: cfg["on_failure"] || cfg[:on_failure]
        }
      end

      # Each step's `dependencies` field stores upstream step_numbers; resolve
      # them back to step IDs so the frontend can draw arrows between nodes.
      def build_edges(steps)
        by_number = steps.each_with_object({}) { |s, h| h[s.step_number.to_i] = s }
        edges = []
        steps.each do |s|
          Array(s.dependencies).each do |dep_num|
            source = by_number[dep_num.to_i]
            edges << { from: source.id.to_s, to: s.id.to_s } if source
          end
        end
        edges
      end

      def build_cost_estimate(plan)
        ::Ai::Provisioning::CostEstimatorService.new(account: account).estimate(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[PlanSnapshotService] cost estimate failed: #{e.class}: #{e.message}")
        { monthly_usd: 0.0, one_time_usd: 0.0, by_resource: [], confidence: "low" }
      end

      def build_topology_preview(plan)
        ::Ai::Provisioning::TopologyRendererService.new(account: account, plan: plan).render
      rescue StandardError => e
        Rails.logger.warn("[PlanSnapshotService] topology render failed: #{e.class}: #{e.message}")
        { nodes: [], edges: [], regions: [], estimated_resources: [] }
      end

      def build_risk(plan)
        ::Ai::Provisioning::RiskScorerService.new(account: account).score(plan: plan)
      rescue StandardError => e
        Rails.logger.warn("[PlanSnapshotService] risk scoring failed: #{e.class}: #{e.message}")
        { score: 0, severity: "low", factors: [] }
      end
    end
  end
end
