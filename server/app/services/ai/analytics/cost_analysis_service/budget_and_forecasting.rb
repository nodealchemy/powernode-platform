# frozen_string_literal: true

module Ai
  module Analytics
    class CostAnalysisService
      module BudgetAndForecasting
        extend ActiveSupport::Concern

        # Budget analysis
        def budget_analysis
          budget_limit = account.settings&.dig("ai_budget_limit")
          monthly_budget = account.settings&.dig("ai_monthly_budget")

          current_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", time_range.ago).sum(:total_cost).to_f
          month_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", Time.current.beginning_of_month).sum(:total_cost).to_f

          {
            period_budget: budget_limit,
            monthly_budget: monthly_budget,
            current_period_spend: current_cost.round(6),
            current_month_spend: month_cost.round(6),
            budget_utilization: budget_limit ? ((current_cost / budget_limit) * 100).round(2) : nil,
            monthly_utilization: monthly_budget ? ((month_cost / monthly_budget) * 100).round(2) : nil,
            projected_month_end: project_month_end_cost(month_cost),
            days_remaining: (Time.current.end_of_month.to_date - Date.current).to_i,
            budget_alert: generate_budget_alert(current_cost, month_cost, budget_limit, monthly_budget)
          }
        end

        # Budget enforcement with alert thresholds.
        def budget_enforcement(account_id: nil)
          target_account = account_id ? Account.find(account_id) : account
          monthly_budget = target_account.settings&.dig("ai_monthly_budget")

          return { configured: false, message: "No monthly budget configured" } unless monthly_budget

          month_cost = ::Ai::WorkflowRun.joins(:workflow)
                                         .where(ai_workflows: { account_id: target_account.id })
                                         .where("ai_workflow_runs.created_at >= ?", Time.current.beginning_of_month)
                                         .sum(:total_cost).to_f

          utilization = (month_cost / monthly_budget * 100).round(2)

          alert = if utilization >= 100
                    { level: "critical", message: "Monthly budget exceeded (#{utilization}%)" }
                  elsif utilization >= 90
                    { level: "warning", message: "Monthly budget at #{utilization}% - approaching limit" }
                  elsif utilization >= 70
                    { level: "info", message: "Monthly budget at #{utilization}% - on track" }
                  else
                    { level: "normal", message: "Budget utilization healthy at #{utilization}%" }
                  end

          {
            configured: true,
            monthly_budget: monthly_budget,
            month_spend: month_cost.round(4),
            utilization_percentage: utilization,
            remaining: [(monthly_budget - month_cost), 0].max.round(4),
            alert: alert
          }
        end

        # Composite FinOps optimization score.
        def finops_optimization_score(account_id: nil)
          target_account = account_id ? Account.find(account_id) : account
          token_service = ::Ai::Finops::TokenAnalyticsService.new(account: target_account)
          token_service.optimization_score
        end

        private

        def project_month_end_cost(current_month_spend)
          days_elapsed = Date.current.day
          days_in_month = Time.current.end_of_month.day

          return nil if days_elapsed.zero?

          daily_avg = current_month_spend / days_elapsed
          (daily_avg * days_in_month).round(6)
        end

        def generate_budget_alert(current_cost, month_cost, budget_limit, monthly_budget)
          alerts = []

          if budget_limit && current_cost > budget_limit * 0.8
            alerts << { level: "warning", message: "Period budget is #{((current_cost / budget_limit) * 100).round(0)}% utilized" }
          end

          if monthly_budget && month_cost > monthly_budget * 0.8
            alerts << { level: "warning", message: "Monthly budget is #{((month_cost / monthly_budget) * 100).round(0)}% utilized" }
          end

          if budget_limit && current_cost > budget_limit
            alerts << { level: "critical", message: "Period budget exceeded" }
          end

          if monthly_budget && month_cost > monthly_budget
            alerts << { level: "critical", message: "Monthly budget exceeded" }
          end

          alerts
        end
      end
    end
  end
end
