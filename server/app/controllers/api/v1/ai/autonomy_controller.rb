# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AutonomyController < ApplicationController
        include ::Ai::AutonomyWriteActions
        include ::Ai::AutonomyCapabilityActions
        include ::Ai::AutonomyCircuitBreakerActions
        include ::Ai::AutonomyApprovalActions
        include ::Ai::AutonomyDelegationActions
        include ::Ai::AutonomyShadowActions
        include ::Ai::AutonomyTelemetryActions

        before_action :validate_permissions
        before_action :require_write_permission, only: [
          :evaluate, :override_trust_score, :emergency_demote,
          :create_budget, :update_budget, :destroy_budget, :allocate_child,
          :reset_circuit_breaker,
          :create_delegation_policy, :update_delegation_policy, :destroy_delegation_policy
        ]
        before_action :require_approval_permission, only: [:approve_action, :reject_action]

        # GET /api/v1/ai/autonomy/trust_scores
        def trust_scores
          scores = ::Ai::AgentTrustScore
            .where(account_id: current_account.id)
            .includes(:agent)
            .order(overall_score: :desc)

          scores = scores.by_tier(params[:tier]) if params[:tier].present?

          render_success(data: scores.map { |s| serialize_trust_score(s) })
        end

        # GET /api/v1/ai/autonomy/trust_scores/:agent_id
        def show_trust_score
          score = ::Ai::AgentTrustScore
            .where(account_id: current_account.id)
            .find_by(agent_id: params[:agent_id])

          if score
            render_success(data: serialize_trust_score(score, detailed: true))
          else
            render_not_found("Trust score")
          end
        end

        # GET /api/v1/ai/autonomy/lineage/:agent_id
        def lineage
          agent = current_account.ai_agents.find(params[:agent_id])

          children = ::Ai::AgentLineage
            .where(account_id: current_account.id)
            .for_parent(agent.id)
            .includes(:child_agent)
            .recent

          parents = ::Ai::AgentLineage
            .where(account_id: current_account.id)
            .for_child(agent.id)
            .includes(:parent_agent)
            .recent

          render_success(data: {
            agent_id: agent.id,
            agent_name: agent.name,
            children: children.map { |l| serialize_lineage(l, direction: :child) },
            parents: parents.map { |l| serialize_lineage(l, direction: :parent) },
            total_children: children.size,
            total_parents: parents.size
          })
        rescue ActiveRecord::RecordNotFound
          render_not_found("Agent")
        end

        # GET /api/v1/ai/autonomy/budgets
        def budgets
          budgets_scope = ::Ai::AgentBudget
            .where(account_id: current_account.id)
            .includes(:agent)
            .order(created_at: :desc)

          budgets_scope = budgets_scope.active if params[:active] == "true"
          budgets_scope = budgets_scope.for_period(params[:period]) if params[:period].present?

          render_success(data: budgets_scope.map { |b| serialize_budget(b) })
        end

        # POST /api/v1/ai/autonomy/trust_scores/decay
        def decay
          return render_error("Unauthorized", status: :forbidden) unless current_worker || current_service

          service = ::Ai::Autonomy::TrustEngineService.new(account: current_account)
          results = service.apply_decay!
          render_success(data: results)
        end

        # GET /api/v1/ai/autonomy/behavioral_fingerprints/:agent_id
        def behavioral_fingerprints
          agent = current_account.ai_agents.find(params[:agent_id])
          service = ::Ai::Autonomy::BehavioralFingerprintService.new(account: current_account)
          fingerprints = service.fingerprints_for(agent)

          render_success(data: fingerprints.map { |fp| serialize_behavioral_fingerprint(fp) })
        rescue ActiveRecord::RecordNotFound
          render_not_found("Agent")
        end

        # GET /api/v1/ai/autonomy/stats
        def stats
          scores = ::Ai::AgentTrustScore.where(account_id: current_account.id)
          budgets_scope = ::Ai::AgentBudget.where(account_id: current_account.id)

          tier_counts = scores.group(:tier).count
          # SQL-based promotable/demotable counting to avoid N+1
          pending_promotions = scores.where(
            "(tier = 'supervised' AND overall_score >= :monitored) OR " \
            "(tier = 'monitored' AND overall_score >= :trusted) OR " \
            "(tier = 'trusted' AND overall_score >= :autonomous)",
            monitored: ::Ai::AgentTrustScore::TIER_THRESHOLDS["monitored"],
            trusted: ::Ai::AgentTrustScore::TIER_THRESHOLDS["trusted"],
            autonomous: ::Ai::AgentTrustScore::TIER_THRESHOLDS["autonomous"]
          ).count

          pending_demotions = scores.where(
            "(tier = 'monitored' AND overall_score < :monitored) OR " \
            "(tier = 'trusted' AND overall_score < :trusted) OR " \
            "(tier = 'autonomous' AND overall_score < :autonomous)",
            monitored: ::Ai::AgentTrustScore::TIER_THRESHOLDS["monitored"],
            trusted: ::Ai::AgentTrustScore::TIER_THRESHOLDS["trusted"],
            autonomous: ::Ai::AgentTrustScore::TIER_THRESHOLDS["autonomous"]
          ).count

          render_success(data: {
            total_agents: scores.count,
            supervised: tier_counts["supervised"] || 0,
            monitored: tier_counts["monitored"] || 0,
            trusted: tier_counts["trusted"] || 0,
            autonomous: tier_counts["autonomous"] || 0,
            pending_promotions: pending_promotions,
            pending_demotions: pending_demotions,
            budgets: {
              total: budgets_scope.count,
              active: budgets_scope.active.count,
              total_budget_cents: budgets_scope.active.sum(:total_budget_cents),
              total_spent_cents: budgets_scope.active.sum(:spent_cents),
              exceeded: budgets_scope.active.where("spent_cents >= total_budget_cents").count
            }
          })
        end

        private

        def validate_permissions
          return if current_worker || current_service

          require_permission("ai.agents.read")
        end

        def serialize_trust_score(score, detailed: false)
          data = {
            id: score.id,
            agent_id: score.agent_id,
            agent_name: score.agent&.name,
            tier: score.tier,
            overall_score: score.overall_score&.round(4),
            reliability: score.reliability&.round(4),
            cost_efficiency: score.cost_efficiency&.round(4),
            safety: score.safety&.round(4),
            quality: score.quality&.round(4),
            speed: score.speed&.round(4),
            evaluation_count: score.evaluation_count,
            last_evaluated_at: score.last_evaluated_at,
            promotable: score.promotable?,
            demotable: score.demotable?
          }

          if detailed
            data[:evaluation_history] = score.evaluation_history || []
          end

          data
        end

        def serialize_lineage(lineage_record, direction:)
          agent = direction == :child ? lineage_record.child_agent : lineage_record.parent_agent

          {
            id: lineage_record.id,
            agent_id: agent&.id,
            agent_name: agent&.name,
            direction: direction,
            spawned_at: lineage_record.spawned_at,
            terminated_at: lineage_record.terminated_at,
            termination_reason: lineage_record.termination_reason,
            spawn_depth: lineage_record.spawn_depth,
            active: lineage_record.active?
          }
        end

        def serialize_behavioral_fingerprint(fp)
          {
            id: fp.id,
            agent_id: fp.agent_id,
            metric_name: fp.metric_name,
            baseline_mean: fp.baseline_mean,
            baseline_stddev: fp.baseline_stddev,
            rolling_window_days: fp.rolling_window_days,
            deviation_threshold: fp.deviation_threshold,
            observation_count: fp.observation_count,
            last_observation_at: fp.last_observation_at,
            anomaly_count: fp.anomaly_count
          }
        end

        def serialize_budget(budget)
          {
            id: budget.id,
            agent_id: budget.agent_id,
            agent_name: budget.agent&.name,
            total_budget_cents: budget.total_budget_cents,
            spent_cents: budget.spent_cents,
            reserved_cents: budget.reserved_cents,
            remaining_cents: budget.remaining_cents,
            currency: budget.currency,
            period_type: budget.period_type,
            period_start: budget.period_start,
            period_end: budget.period_end,
            utilization_percentage: budget.utilization_percentage,
            exceeded: budget.exceeded?,
            parent_budget_id: budget.parent_budget_id,
            created_at: budget.created_at
          }
        end
      end
    end
  end
end
