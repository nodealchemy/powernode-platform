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
          :rollover_budget, :sync_pricing, :update_pricing,
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

        # GET /api/v1/ai/autonomy/lineage
        def lineage_forest
          trust_scores_map = ::Ai::AgentTrustScore
            .where(account_id: current_account.id)
            .index_by(&:agent_id)

          parent_ids = ::Ai::AgentLineage
            .where(account_id: current_account.id)
            .active
            .distinct
            .pluck(:parent_agent_id)

          child_ids = ::Ai::AgentLineage
            .where(account_id: current_account.id)
            .active
            .distinct
            .pluck(:child_agent_id)

          # Root agents: appear as parents but never as children
          root_ids = parent_ids - child_ids

          # Orphans: agents with no lineage at all
          all_lineage_ids = (parent_ids + child_ids).uniq
          orphan_agents = current_account.ai_agents.active.where.not(id: all_lineage_ids)

          roots = current_account.ai_agents.where(id: root_ids).order(:name)
          trees = roots.map { |agent| build_lineage_tree(agent, trust_scores_map, depth: 0) }

          orphan_trees = orphan_agents.order(:name).map do |agent|
            {
              id: agent.id,
              name: agent.name,
              type: agent.agent_type,
              status: agent.status,
              trust_level: trust_scores_map[agent.id]&.tier,
              depth: 0,
              children: []
            }
          end

          render_success(data: { trees: trees, orphans: orphan_trees })
        end

        # GET /api/v1/ai/autonomy/lineage/:agent_id
        def lineage
          agent = current_account.ai_agents.find(params[:agent_id])

          trust_scores_map = ::Ai::AgentTrustScore
            .where(account_id: current_account.id)
            .index_by(&:agent_id)

          children_tree = build_lineage_tree(agent, trust_scores_map, depth: 0)
          parent_ids = ::Ai::AgentLineage
            .where(account_id: current_account.id, child_agent_id: agent.id)
            .active
            .pluck(:parent_agent_id)

          parents = current_account.ai_agents.where(id: parent_ids).map do |p|
            { id: p.id, name: p.name, type: p.agent_type, status: p.status }
          end

          render_success(data: {
            agent_id: agent.id,
            children: children_tree[:children],
            parents: parents,
            total_children: count_descendants(children_tree),
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
          return render_error("Unauthorized", status: :forbidden) unless current_worker

          if current_account
            service = ::Ai::Autonomy::TrustEngineService.new(account: current_account)
            results = service.apply_decay!
          else
            results = []
            Account.find_each do |acct|
              service = ::Ai::Autonomy::TrustEngineService.new(account: acct)
              results.concat(service.apply_decay!)
            end
          end

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
            "evaluation_count >= 10 AND (" \
            "(tier = 'supervised' AND overall_score >= :monitored) OR " \
            "(tier = 'monitored' AND overall_score >= :trusted) OR " \
            "(tier = 'trusted' AND overall_score >= :autonomous))",
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

        # POST /api/v1/ai/autonomy/broadcast
        def relay_broadcast
          return render_error("Unauthorized", status: :forbidden) unless current_worker

          broadcast_type = params[:broadcast_type]
          data = params[:data]&.to_unsafe_h || {}

          case broadcast_type
          when "cost_status"
            Account.find_each do |acct|
              AiWorkflowMonitoringChannel.broadcast_cost_alert(acct.id, data)
            end
          when "health_status"
            Account.find_each do |acct|
              AiWorkflowMonitoringChannel.broadcast_system_alert(acct.id, data)
            end
          when "provider_health"
            Account.find_each do |acct|
              AiWorkflowMonitoringChannel.broadcast_system_alert(acct.id, data.merge(source: "provider_health"))
            end
          else
            return render_error("Unknown broadcast type: #{broadcast_type}", status: :unprocessable_content)
          end

          render_success(data: { broadcast: true, type: broadcast_type })
        end

        # GET /api/v1/ai/autonomy/cost_thresholds
        def cost_thresholds
          render_success(data: {
            hourly_warning: 50.0,
            hourly_critical: 100.0,
            daily_warning: 500.0,
            daily_critical: 1000.0,
            spike_percentage: 200
          })
        end

        private

        def validate_permissions
          return if current_worker

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

        def build_lineage_tree(agent, trust_scores_map, depth:, visited: Set.new)
          visited.add(agent.id)

          child_lineages = ::Ai::AgentLineage
            .where(account_id: current_account.id)
            .for_parent(agent.id)
            .active
            .includes(:child_agent)

          children = child_lineages.filter_map do |lineage|
            child = lineage.child_agent
            next if child.nil? || visited.include?(child.id)

            build_lineage_tree(child, trust_scores_map, depth: depth + 1, visited: visited)
          end

          {
            id: agent.id,
            name: agent.name,
            type: agent.agent_type,
            status: agent.status,
            trust_level: trust_scores_map[agent.id]&.tier,
            depth: depth,
            children: children
          }
        end

        def count_descendants(tree)
          return 0 unless tree[:children]

          tree[:children].size + tree[:children].sum { |c| count_descendants(c) }
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
