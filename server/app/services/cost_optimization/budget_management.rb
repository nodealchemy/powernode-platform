# frozen_string_literal: true

module CostOptimization
  module BudgetManagement
    def budget_status(start_date, end_date)
      monthly_budget = get_monthly_budget

      executions = @account.ai_agent_executions
                           .where(created_at: start_date..end_date)
                           .where.not(cost_usd: nil)

      current_spending = executions.sum(:cost_usd) || BigDecimal("0")
      remaining_budget = [monthly_budget - current_spending, BigDecimal("0")].max

      days_elapsed = [(end_date.to_date - start_date.to_date).to_i, 1].max
      daily_avg = current_spending / days_elapsed
      projected_monthly = daily_avg * 30

      utilization_percent = monthly_budget > 0 ? ((current_spending / monthly_budget) * 100).round(1) : 0

      alerts = []
      if utilization_percent > 80
        alerts << "Budget utilization at #{utilization_percent}% - approaching limit"
      end

      {
        budget_limit: monthly_budget,
        current_spending: current_spending,
        remaining_budget: remaining_budget,
        projected_monthly_cost: projected_monthly,
        budget_utilization_percent: utilization_percent,
        alerts: alerts
      }
    end

    def generate_budget_recommendations(executions)
      current_monthly_cost = calculate_monthly_projection(calculate_daily_cost)

      budget_tiers = [
        { name: "Conservative", limit: current_monthly_cost * 0.8, savings_target: 20 },
        { name: "Moderate", limit: current_monthly_cost * 0.9, savings_target: 10 },
        { name: "Current", limit: current_monthly_cost, savings_target: 0 },
        { name: "Growth", limit: current_monthly_cost * 1.2, savings_target: -20 }
      ]

      recommendations = budget_tiers.map do |tier|
        {
          tier: tier[:name],
          monthly_limit: tier[:limit].round(2),
          savings_target_percentage: tier[:savings_target],
          actions_required: generate_budget_tier_actions(tier[:savings_target]),
          alert_threshold: (tier[:limit] * 0.8).round(2)
        }
      end

      {
        current_monthly_cost: current_monthly_cost.round(2),
        budget_recommendations: recommendations,
        suggested_tier: determine_suggested_budget_tier(current_monthly_cost)
      }
    end

    private

    def generate_budget_tier_actions(target)
      target > 0 ? ["Reduce usage", "Optimize providers"] : ["Maintain current efficiency"]
    end

    def determine_suggested_budget_tier(cost)
      "Moderate"
    end
  end
end
