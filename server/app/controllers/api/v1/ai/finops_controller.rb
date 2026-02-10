# frozen_string_literal: true

# FinOps Controller — Smart Model Routing & Financial Operations for AI
#
# Provides endpoints for:
# - Cost overview and breakdowns
# - Budget utilization tracking
# - Token analytics and waste analysis
# - Forecasting and optimization scoring
#
module Api
  module V1
    module Ai
      class FinopsController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :validate_permissions
        before_action :set_time_range, only: %i[index cost_breakdown trends budget_utilization token_analytics]

        # ==========================================================================
        # OVERVIEW
        # ==========================================================================

        # GET /api/v1/ai/finops
        def index
          cost_service = build_cost_service

          render_success({
            overview: {
              total_cost: cost_service.calculate_total_cost,
              cost_trend: cost_service.calculate_cost_trend,
              budget_status: cost_service.budget_analysis,
              optimization_score: token_analytics_service.optimization_score[:score],
              top_models: token_analytics_service.usage_summary(period: @time_range)[:by_model]&.first(5)
            },
            time_range: time_range_info,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # COST ANALYSIS
        # ==========================================================================

        # GET /api/v1/ai/finops/cost_breakdown
        def cost_breakdown
          cost_service = build_cost_service

          render_success({
            cost_breakdown: {
              by_provider: cost_service.cost_breakdown_by_provider,
              by_model: cost_service.cost_breakdown_by_model,
              by_workflow: cost_service.cost_breakdown_by_workflow,
              by_agent: cost_service.cost_breakdown_by_agent,
              daily: cost_service.daily_cost_breakdown
            },
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/finops/trends
        def trends
          cost_service = build_cost_service

          render_success({
            trends: {
              cost_trend: cost_service.calculate_cost_trend,
              daily_costs: cost_service.daily_cost_breakdown,
              forecast: cost_service.generate_budget_forecast,
              anomalies: cost_service.detect_cost_anomalies
            },
            time_range: time_range_info
          })
        end

        # ==========================================================================
        # BUDGET
        # ==========================================================================

        # GET /api/v1/ai/finops/budget_utilization
        def budget_utilization
          cost_service = build_cost_service
          enforcement = budget_enforcement_data

          render_success({
            budget: cost_service.budget_analysis,
            enforcement: enforcement,
            agent_budgets: agent_budget_summary,
            time_range: time_range_info
          })
        end

        # ==========================================================================
        # TOKEN ANALYTICS
        # ==========================================================================

        # GET /api/v1/ai/finops/token_analytics
        def token_analytics
          summary = token_analytics_service.usage_summary(period: @time_range)

          render_success({
            token_analytics: summary,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/finops/waste_analysis
        def waste_analysis
          waste = token_analytics_service.waste_analysis

          render_success({
            waste_analysis: waste,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # FORECASTING
        # ==========================================================================

        # GET /api/v1/ai/finops/forecast
        def forecast
          months = [params[:months]&.to_i || 3, 12].min

          forecast_data = token_analytics_service.forecast(months: months)

          render_success({
            forecast: forecast_data,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # OPTIMIZATION
        # ==========================================================================

        # GET /api/v1/ai/finops/optimization_score
        def optimization_score
          score_data = token_analytics_service.optimization_score

          render_success({
            optimization: score_data,
            generated_at: Time.current.iso8601
          })
        end

        private

        # ==========================================================================
        # SERVICE ACCESSORS
        # ==========================================================================

        def build_cost_service
          ::Ai::Analytics::CostAnalysisService.new(
            account: current_user.account,
            time_range: @time_range
          )
        end

        def token_analytics_service
          @token_analytics_service ||= ::Ai::Finops::TokenAnalyticsService.new(
            account: current_user.account
          )
        end

        # ==========================================================================
        # BUDGET HELPERS
        # ==========================================================================

        def budget_enforcement_data
          account = current_user.account
          monthly_budget = account.settings&.dig("ai_monthly_budget")
          return nil unless monthly_budget

          month_cost = ::Ai::WorkflowRun.joins(:workflow)
                                         .where(ai_workflows: { account_id: account.id })
                                         .where("ai_workflow_runs.created_at >= ?", Time.current.beginning_of_month)
                                         .sum(:total_cost).to_f

          utilization = (month_cost / monthly_budget * 100).round(2)

          level = if utilization >= 100
                    "critical"
                  elsif utilization >= 90
                    "warning"
                  elsif utilization >= 70
                    "info"
                  else
                    "normal"
                  end

          {
            monthly_budget: monthly_budget,
            month_spend: month_cost.round(4),
            utilization_percentage: utilization,
            alert_level: level,
            remaining: [(monthly_budget - month_cost), 0].max.round(4)
          }
        end

        def agent_budget_summary
          ::Ai::AgentBudget.where(account: current_user.account)
                           .active
                           .includes(:agent)
                           .map do |budget|
            {
              agent_id: budget.agent_id,
              agent_name: budget.agent&.name,
              total_budget_cents: budget.total_budget_cents,
              spent_cents: budget.spent_cents,
              utilization: budget.utilization_percentage,
              period_type: budget.period_type,
              exceeded: budget.exceeded?
            }
          end
        end

        # ==========================================================================
        # AUTHORIZATION
        # ==========================================================================

        def validate_permissions
          require_permission("ai.finops.view")
        end

        # ==========================================================================
        # PARAMETER HANDLING
        # ==========================================================================

        def set_time_range
          @time_range = case params[:time_range]
                        when "1h" then 1.hour
                        when "24h", "1d" then 1.day
                        when "7d", "1w" then 1.week
                        when "30d", "1m" then 30.days
                        when "90d", "3m" then 90.days
                        when "1y" then 1.year
                        else 30.days
                        end
        end

        def time_range_info
          {
            start: @time_range.ago.iso8601,
            end: Time.current.iso8601,
            period: params[:time_range] || "30d",
            seconds: @time_range.to_i
          }
        end
      end
    end
  end
end
