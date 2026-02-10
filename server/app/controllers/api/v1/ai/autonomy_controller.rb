# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AutonomyController < ApplicationController
        before_action :validate_permissions

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

        # GET /api/v1/ai/autonomy/stats
        def stats
          trust_scores_scope = ::Ai::AgentTrustScore.where(account_id: current_account.id)
          budgets_scope = ::Ai::AgentBudget.where(account_id: current_account.id)
          lineages_scope = ::Ai::AgentLineage.where(account_id: current_account.id)

          render_success(data: {
            trust_scores: {
              total: trust_scores_scope.count,
              by_tier: ::Ai::AgentTrustScore::TIERS.each_with_object({}) do |tier, h|
                h[tier] = trust_scores_scope.by_tier(tier).count
              end,
              needs_evaluation: trust_scores_scope.needs_evaluation.count,
              average_score: trust_scores_scope.average(:overall_score)&.round(4) || 0
            },
            budgets: {
              total: budgets_scope.count,
              active: budgets_scope.active.count,
              total_budget_cents: budgets_scope.active.sum(:total_budget_cents),
              total_spent_cents: budgets_scope.active.sum(:spent_cents),
              exceeded: budgets_scope.active.where("spent_cents >= total_budget_cents").count
            },
            lineages: {
              total: lineages_scope.count,
              active: lineages_scope.active.count,
              terminated: lineages_scope.terminated.count
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
