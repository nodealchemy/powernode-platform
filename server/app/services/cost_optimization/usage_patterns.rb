# frozen_string_literal: true

module CostOptimization
  module UsagePatterns
    def analyze_usage_patterns(time_period)
      start_date = time_period.ago
      executions = @account.ai_agent_executions
                           .where(created_at: start_date..Time.current)
                           .where.not(cost_usd: nil)

      total_cost = executions.sum(:cost_usd) || BigDecimal("0")
      total_tokens = executions.sum(:tokens_used) || 0

      provider_costs = {}
      executions.joins(:ai_provider).group("ai_providers.name").sum(:cost_usd).each do |name, cost|
        provider_costs[name] = BigDecimal(cost.to_s)
      end

      mid_point = start_date + (time_period / 2)
      first_half_cost = executions.where(created_at: start_date..mid_point).sum(:cost_usd) || 0
      second_half_cost = executions.where(created_at: mid_point..Time.current).sum(:cost_usd) || 0

      usage_trend = if second_half_cost > first_half_cost * 1.1
                      "increasing"
      elsif second_half_cost < first_half_cost * 0.9
                      "decreasing"
      else
                      "stable"
      end

      avg_cost_per_token = total_tokens > 0 ? total_cost / total_tokens : BigDecimal("0")
      avg_response_time = executions.average(:duration_ms)&.to_i || 0
      success_count = executions.where(status: "completed").count
      total_count = executions.count
      success_rate = total_count > 0 ? (success_count.to_f / total_count) : 0.0

      opportunities = []
      if usage_trend == "increasing" && total_cost > 10
        opportunities << {
          type: "cost_reduction",
          description: "Usage is increasing - consider implementing caching or batch processing",
          potential_savings: BigDecimal((total_cost * 0.15).to_s)
        }
      end

      {
        total_cost: total_cost,
        total_tokens: total_tokens,
        average_cost_per_token: avg_cost_per_token,
        usage_trend: usage_trend,
        cost_breakdown_by_provider: provider_costs,
        optimization_opportunities: opportunities,
        efficiency_metrics: {
          tokens_per_dollar: total_cost > 0 ? (total_tokens / total_cost).to_i : 0,
          average_response_time: avg_response_time,
          success_rate: success_rate,
          cost_efficiency_score: calculate_efficiency_score_from_metrics(avg_cost_per_token, avg_response_time, success_rate)
        }
      }
    end

    def analyze_usage_pattern_savings(executions)
      hourly_usage = executions.group_by { |e| e.created_at.hour }
                              .transform_values { |execs|
                                {
                                  count: execs.size,
                                  cost: execs.sum(&:cost_usd).round(4)
                                }
                              }

      daily_usage = executions.group_by { |e| e.created_at.strftime("%A") }
                             .transform_values { |execs|
                               {
                                 count: execs.size,
                                 cost: execs.sum(&:cost_usd).round(4)
                               }
                             }

      peak_hours = hourly_usage.select { |_, data| data[:cost] > 0 }
                              .sort_by { |_, data| -data[:cost] }
                              .first(3)
                              .map(&:first)

      off_peak_hours = (0..23).to_a - peak_hours

      recommendations = []

      if peak_hours.any? && off_peak_hours.any?
        peak_cost_per_hour = peak_hours.sum { |hour| hourly_usage[hour]&.dig(:cost) || 0 } / peak_hours.size
        off_peak_cost_per_hour = off_peak_hours.sum { |hour| hourly_usage[hour]&.dig(:cost) || 0 } / off_peak_hours.size

        if peak_cost_per_hour > off_peak_cost_per_hour * 1.2
          potential_savings = (peak_cost_per_hour - off_peak_cost_per_hour) * 30

          recommendations << {
            type: "usage_scheduling",
            description: "Schedule non-urgent AI tasks during off-peak hours",
            peak_hours: peak_hours,
            off_peak_hours: off_peak_hours.first(8),
            estimated_monthly_savings: potential_savings.round(2),
            implementation: "Use delayed job scheduling for non-urgent tasks"
          }
        end
      end

      {
        hourly_usage: hourly_usage,
        daily_usage: daily_usage,
        peak_analysis: {
          peak_hours: peak_hours,
          off_peak_hours: off_peak_hours
        },
        recommendations: recommendations
      }
    end

    def analyze_agent_cost_efficiency(executions)
      agent_analysis = {}

      executions.joins(:ai_agent).group_by(&:ai_agent).each do |agent, agent_executions|
        costs = agent_executions.map(&:cost_usd).compact
        next if costs.empty?

        total_cost = costs.sum
        avg_cost = total_cost / costs.size
        success_count = agent_executions.count { |e| e.status == "completed" }
        success_rate = (success_count.to_f / agent_executions.size * 100)

        cost_per_success = success_count > 0 ? total_cost / success_count : total_cost

        agent_analysis[agent.name] = {
          total_cost: total_cost.round(4),
          avg_cost_per_execution: avg_cost.round(6),
          cost_per_successful_execution: cost_per_success.round(6),
          success_rate: success_rate.round(2),
          execution_count: agent_executions.size,
          efficiency_rating: calculate_agent_efficiency_rating(cost_per_success, success_rate)
        }
      end

      underperforming = agent_analysis.select { |_, data|
        data[:efficiency_rating] < 3 && data[:total_cost] > 1.0
      }

      recommendations = underperforming.map do |agent_name, data|
        {
          type: "agent_optimization",
          agent: agent_name,
          description: "Optimize or consider replacing #{agent_name} (low efficiency: #{data[:efficiency_rating]}/5)",
          current_monthly_cost: (data[:total_cost] * (30.0 / @time_range.to_i.days)).round(2),
          success_rate: data[:success_rate],
          suggested_actions: generate_agent_optimization_actions(data)
        }
      end

      {
        agent_analysis: agent_analysis,
        recommendations: recommendations
      }
    end

    private

    def calculate_agent_efficiency_rating(cost_per_success, success_rate)
      case
      when cost_per_success < 0.01 && success_rate > 90
        5
      when cost_per_success < 0.05 && success_rate > 80
        4
      when cost_per_success < 0.10 && success_rate > 70
        3
      when cost_per_success < 0.20 && success_rate > 60
        2
      else
        1
      end
    end

    def generate_agent_optimization_actions(data)
      ["Review agent configuration", "Consider alternative providers"]
    end
  end
end
