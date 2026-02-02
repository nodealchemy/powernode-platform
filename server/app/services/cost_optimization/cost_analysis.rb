# frozen_string_literal: true

module CostOptimization
  module CostAnalysis
    def analyze_current_costs(executions)
      total_cost = executions.sum(&:cost_usd) || 0.0
      execution_count = executions.count
      avg_cost_per_execution = execution_count > 0 ? total_cost / execution_count : 0.0

      provider_costs = executions.group_by(&:provider)
                                .transform_values { |execs| execs.sum(&:cost_usd) }
                                .sort_by { |_, cost| -cost }

      agent_type_costs = executions.joins(:agent)
                                   .group("ai_agents.agent_type")
                                   .sum(:cost_usd)

      daily_costs = executions.group_by { |e| e.created_at.to_date }
                             .transform_values { |execs| execs.sum(&:cost_usd) }

      {
        total_cost: total_cost.round(4),
        execution_count: execution_count,
        avg_cost_per_execution: avg_cost_per_execution.round(6),
        provider_breakdown: provider_costs.map { |provider, cost|
          {
            provider: provider.name,
            cost: cost.round(4),
            percentage: ((cost / total_cost) * 100).round(2)
          }
        },
        agent_type_breakdown: agent_type_costs.map { |type, cost|
          {
            agent_type: type,
            cost: cost.round(4),
            percentage: ((cost / total_cost) * 100).round(2)
          }
        },
        daily_trend: daily_costs.transform_values { |cost| cost.round(4) }
      }
    end

    def calculate_current_period_cost
      recent_executions = @account.ai_agent_executions
                                 .where(created_at: @start_date..@end_date)
                                 .where.not(cost_usd: nil)

      recent_executions.sum(&:cost_usd) || 0.0
    end

    def calculate_daily_cost
      today_executions = @account.ai_agent_executions
                                .where(created_at: Time.current.beginning_of_day..Time.current)
                                .where.not(cost_usd: nil)

      today_executions.sum(&:cost_usd) || 0.0
    end

    def calculate_monthly_projection(daily_cost)
      recent_days = [ @time_range.to_i.days, 30 ].min
      recent_daily_costs = (0..recent_days - 1).map do |days_ago|
        day_start = days_ago.days.ago.beginning_of_day
        day_end = days_ago.days.ago.end_of_day

        @account.ai_agent_executions
                .where(created_at: day_start..day_end)
                .where.not(cost_usd: nil)
                .sum(&:cost_usd) || 0.0
      end

      avg_daily_cost = recent_daily_costs.sum / recent_days.to_f
      avg_daily_cost * 30
    end

    def generate_cost_report(time_period)
      start_date = time_period.ago
      executions = @account.ai_agent_executions
                           .where(created_at: start_date..Time.current)
                           .where.not(cost_usd: nil)

      total_cost = executions.sum(:cost_usd) || BigDecimal("0")
      total_requests = executions.count
      avg_cost = total_requests > 0 ? total_cost / total_requests : BigDecimal("0")

      prev_start = (time_period * 2).ago
      prev_end = time_period.ago
      prev_cost = @account.ai_agent_executions
                          .where(created_at: prev_start..prev_end)
                          .where.not(cost_usd: nil)
                          .sum(:cost_usd) || BigDecimal("0")

      cost_change_pct = prev_cost > 0 ? (((total_cost - prev_cost) / prev_cost) * 100).round(1) : 0

      top_driver = executions.joins(:provider)
                             .group("ai_providers.name")
                             .sum(:cost_usd)
                             .max_by { |_, cost| cost }
      top_cost_driver = top_driver&.first || "None"

      daily_avg = total_cost / [ time_period.to_i / 86400, 1 ].max
      next_month_projection = daily_avg * 30

      {
        executive_summary: {
          total_cost: total_cost,
          total_requests: total_requests,
          average_cost_per_request: avg_cost,
          cost_change_percentage: cost_change_pct,
          top_cost_driver: top_cost_driver
        },
        detailed_breakdown: analyze_current_costs(executions),
        trends_analysis: {
          direction: cost_change_pct > 5 ? "increasing" : (cost_change_pct < -5 ? "decreasing" : "stable"),
          daily_average: daily_avg
        },
        optimization_recommendations: generate_report_recommendations(total_cost, cost_change_pct),
        forecast: {
          next_month_projected_cost: next_month_projection,
          confidence_interval: { low: next_month_projection * 0.8, high: next_month_projection * 1.2 },
          key_assumptions: [ "Based on current usage patterns", "Assumes no major changes in workload" ]
        }
      }
    end

    private

    def generate_report_recommendations(total_cost, cost_change_pct)
      recommendations = []

      if cost_change_pct > 20
        recommendations << {
          priority: "high",
          description: "Costs increasing significantly - review usage patterns",
          estimated_savings: BigDecimal((total_cost * 0.15).to_s),
          implementation_effort: "medium"
        }
      end

      if total_cost > 50
        recommendations << {
          priority: "medium",
          description: "Consider implementing request caching for repeated queries",
          estimated_savings: BigDecimal((total_cost * 0.1).to_s),
          implementation_effort: "low"
        }
      end

      recommendations
    end
  end
end
