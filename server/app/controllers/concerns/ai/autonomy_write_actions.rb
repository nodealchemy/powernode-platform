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
        return render_error("Invalid tier: #{tier}", status: :unprocessable_content)
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
      render_error(e.message, status: :unprocessable_content)
    end

    # PUT budgets/:id
    def update_budget
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])
      budget.update!(budget_params)

      render_success(data: serialize_budget(budget))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_content)
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
        render_error("Insufficient budget remaining", status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget or Agent")
    end

    # GET budgets/:id/check
    def check_budget
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])

      render_success(data: {
        allowed: !budget.over_budget?,
        remaining_cents: budget.remaining_cents,
        utilization_ratio: budget.utilization_ratio
      })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget")
    end

    # GET budgets/expired
    def expired_budgets
      budgets = ::Ai::AgentBudget.where(account_id: current_account.id).expired
      render_success(data: budgets.map { |b| serialize_budget(b) })
    end

    # POST budgets/:id/rollover
    def rollover_budget
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])
      new_budget = budget.auto_rollover!

      if new_budget
        render_success(data: serialize_budget(new_budget), status: :created)
      else
        render_error("Budget cannot be rolled over", status: :unprocessable_content)
      end
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget")
    end

    # GET budgets/reconcile
    def reconcile_budgets
      budgets = ::Ai::AgentBudget.where(account_id: current_account.id).active.includes(:budget_transactions)
      discrepancies = []

      budgets.find_each do |budget|
        transaction_total = budget.budget_transactions.debits.sum(:amount_cents) - budget.budget_transactions.credits.sum(:amount_cents)
        if transaction_total != budget.spent_cents
          discrepancies << {
            budget_id: budget.id,
            agent_id: budget.agent_id,
            recorded_spent: budget.spent_cents,
            transaction_sum: transaction_total,
            difference: budget.spent_cents - transaction_total
          }
        end
      end

      render_success(data: { discrepancies: discrepancies, checked: budgets.size })
    end

    # GET budgets/:id/transactions
    def budget_transactions
      budget = ::Ai::AgentBudget.where(account_id: current_account.id).find(params[:id])
      transactions = budget.budget_transactions.recent

      transactions = transactions.where(transaction_type: params[:type]) if params[:type].present?

      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 25).to_i
      total = transactions.count
      transactions = transactions.offset((page - 1) * per_page).limit(per_page)

      render_success(data: {
        transactions: transactions.map { |t| serialize_transaction(t) },
        pagination: { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil }
      })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Budget")
    end

    # GET budgets/alerts
    def budget_alerts
      budgets = ::Ai::AgentBudget.where(account_id: current_account.id).active
      alerts = []

      budgets.find_each do |budget|
        pct = budget.utilization_percentage
        next if pct < 75

        level = if pct >= 100 then "exhausted"
                elsif pct >= 90 then "danger"
                else "warning"
                end

        alerts << {
          budget_id: budget.id,
          agent_id: budget.agent_id,
          agent_name: budget.agent&.name,
          level: level,
          utilization_pct: pct,
          remaining_cents: budget.remaining_cents,
          total_budget_cents: budget.total_budget_cents
        }
      end

      render_success(data: alerts)
    end

    # POST pricing/sync
    def sync_pricing
      result = ::Ai::Autonomy::PricingSyncService.sync!
      render_success(data: result)
    end

    # GET pricing
    def pricing_catalog
      pricings = ::Ai::ModelPricing.order(:provider_type, :model_id)
      pricings = pricings.for_provider(params[:provider_type]) if params[:provider_type].present?

      render_success(data: pricings.map { |p| serialize_pricing(p) })
    end

    # PATCH pricing/:model_id
    def update_pricing
      pricing = ::Ai::ModelPricing.find_by!(model_id: params[:model_id])
      pricing.update!(
        input_per_1k: params[:input_per_1k],
        output_per_1k: params[:output_per_1k],
        cached_input_per_1k: params[:cached_input_per_1k],
        source: "manual",
        last_synced_at: Time.current
      )

      render_success(data: serialize_pricing(pricing))
    rescue ActiveRecord::RecordNotFound
      render_not_found("Pricing")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_content)
    end

    # POST trust_scores/:agent_id/evaluate_from_execution
    def evaluate_from_execution
      account = resolve_account_for_agent(params[:agent_id])
      return render_error("Agent not found", status: :not_found) unless account

      agent = account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::TrustEngineService.new(account: account)
      result = service.evaluate_pending_for(agent: agent)

      render_success(data: result)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    # POST budgets/rollover_expired
    def rollover_expired
      results = []

      if current_account
        budgets_scope = ::Ai::AgentBudget.where(account_id: current_account.id).expired
      else
        budgets_scope = ::Ai::AgentBudget.expired
      end

      budgets_scope.find_each do |budget|
        new_budget = budget.auto_rollover!
        results << { original_id: budget.id, new_id: new_budget&.id, success: new_budget.present? }
      rescue StandardError => e
        results << { original_id: budget.id, success: false, error: e.message }
      end

      render_success(data: {
        rolled_over: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] },
        results: results
      })
    end

    # GET pricing/lookup
    def pricing_lookup
      pricing = Ai::Autonomy::PricingSyncService.pricing_for(params[:model_id])

      if pricing
        render_success(data: {
          input_per_1k: pricing["input"],
          output_per_1k: pricing["output"],
          cached_input_per_1k: pricing["cached_input"],
          tier: pricing["tier"],
          model_id: params[:model_id],
          provider_type: params[:provider_type]
        })
      else
        render_success(data: nil)
      end
    end

    private

    def require_write_permission
      return if current_worker

      require_permission("ai.autonomy.manage")
    end

    def budget_params
      params.permit(:total_budget_cents, :currency, :period_type, :period_start, :period_end)
    end

    def serialize_transaction(txn)
      {
        id: txn.id,
        budget_id: txn.ai_agent_budget_id,
        execution_id: txn.ai_agent_execution_id,
        transaction_type: txn.transaction_type,
        amount_cents: txn.amount_cents,
        running_balance_cents: txn.running_balance_cents,
        metadata: txn.metadata,
        created_at: txn.created_at
      }
    end

    def serialize_pricing(pricing)
      {
        id: pricing.id,
        model_id: pricing.model_id,
        provider_type: pricing.provider_type,
        input_per_1k: pricing.input_per_1k.to_f,
        output_per_1k: pricing.output_per_1k.to_f,
        cached_input_per_1k: pricing.cached_input_per_1k.to_f,
        tier: pricing.tier,
        source: pricing.source,
        last_synced_at: pricing.last_synced_at
      }
    end
  end
end
