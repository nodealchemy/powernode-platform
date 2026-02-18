# frozen_string_literal: true

module Ai
  module AutonomyWriteActions
    extend ActiveSupport::Concern

    # POST trust_scores/:agent_id/evaluate
    def evaluate
      agent = current_account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::TrustEngineService.new(account: current_account)
      result = service.evaluate_pending_for(agent: agent)

      render_success(data: result)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    # PUT trust_scores/:agent_id/override
    def override_trust_score
      agent = current_account.ai_agents.find(params[:agent_id])
      trust_score = ::Ai::AgentTrustScore.find_by!(agent_id: agent.id, account_id: current_account.id)

      tier = params[:tier]
      reason = params[:reason]

      unless ::Ai::AgentTrustScore::TIERS.include?(tier)
        return render_error("Invalid tier: #{tier}", status: :unprocessable_entity)
      end

      previous_tier = trust_score.tier
      trust_score.update!(
        tier: tier,
        evaluation_history: (trust_score.evaluation_history || []) + [{
          type: "manual_override",
          from: previous_tier,
          to: tier,
          reason: reason,
          overridden_by: current_user.id,
          evaluated_at: Time.current.iso8601
        }]
      )

      agent.update!(trust_level: tier) if agent.respond_to?(:trust_level=)

      render_success(data: serialize_trust_score(trust_score))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Trust score")
    end

    # POST trust_scores/:agent_id/emergency_demote
    def emergency_demote
      agent = current_account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::TrustEngineService.new(account: current_account)
      result = service.emergency_demote!(agent: agent, reason: params[:reason] || "admin_action")

      render_success(data: result)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    # POST budgets
    def create_budget
      agent = current_account.ai_agents.find(params[:agent_id])
      budget = ::Ai::AgentBudget.create!(
        account: current_account,
        agent: agent,
        total_budget_cents: params[:total_budget_cents],
        spent_cents: 0,
        reserved_cents: 0,
        currency: params[:currency] || "USD",
        period_type: params[:period_type] || "monthly",
        period_start: params[:period_start] || Time.current,
        period_end: params[:period_end]
      )

      render_success(data: serialize_budget(budget), status: :created)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_entity)
    end

    # PUT budgets/:id
    def update_budget
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])
      budget.update!(budget_params)

      render_success(data: serialize_budget(budget))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_entity)
    end

    # DELETE budgets/:id
    def destroy_budget
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])
      budget.destroy!

      render_success(data: { deleted: true })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget")
    end

    # POST budgets/:id/allocate_child
    def allocate_child
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])
      agent = current_account.ai_agents.find(params[:agent_id])
      child_budget = budget.allocate_child(agent: agent, amount_cents: params[:amount_cents].to_i)

      if child_budget
        render_success(data: serialize_budget(child_budget), status: :created)
      else
        render_error("Insufficient budget remaining", status: :unprocessable_entity)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget or Agent")
    end

    private

    def require_write_permission
      return if current_worker || current_service

      require_permission("ai.autonomy.manage")
    end

    def budget_params
      params.permit(:total_budget_cents, :currency, :period_type, :period_start, :period_end)
    end
  end
end
