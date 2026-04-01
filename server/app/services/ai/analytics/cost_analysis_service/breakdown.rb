# frozen_string_literal: true

module Ai
  module Analytics
    class CostAnalysisService
      module Breakdown
        extend ActiveSupport::Concern

        # Cost breakdown by provider
        def cost_breakdown_by_provider
          start_time = time_range.ago

          providers = ::Ai::Provider.where(account_id: account.id)

          providers.map do |provider|
            executions = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                                        .where(ai_provider_id: provider.id)

            cost = executions.sum(:cost_usd).to_f
            tokens = executions.sum(:tokens_used).to_i

            {
              provider_id: provider.id,
              provider_name: provider.name,
              provider_type: provider.provider_type,
              total_cost: cost.round(6),
              execution_count: executions.count,
              total_tokens: tokens,
              cost_per_execution: executions.count.positive? ? (cost / executions.count).round(6) : 0
            }
          end.sort_by { |p| -p[:total_cost] }
        end

        # Cost breakdown by agent
        def cost_breakdown_by_agent
          start_time = time_range.ago

          agents.map do |agent|
            executions = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                                        .where(ai_agent_id: agent.id)

            cost = executions.sum(:cost_usd).to_f

            {
              agent_id: agent.id,
              agent_name: agent.name,
              agent_type: agent.agent_type,
              total_cost: cost.round(6),
              execution_count: executions.count,
              cost_per_execution: executions.count.positive? ? (cost / executions.count).round(6) : 0
            }
          end.sort_by { |a| -a[:total_cost] }
        end

        # Cost breakdown by workflow (stub - workflows have been removed)
        def cost_breakdown_by_workflow
          []
        end

        # Cost breakdown by model
        def cost_breakdown_by_model
          start_time = time_range.ago

          model_costs = {}

          agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                         .where.not(performance_metrics: nil)
                         .pluck(:performance_metrics, :cost_usd).each do |metrics, cost|
            model = metrics&.dig("model") || "unknown"
            model_costs[model] ||= { cost: 0.0, count: 0, tokens: 0 }
            model_costs[model][:cost] += cost.to_f
            model_costs[model][:count] += 1
          end

          # Also aggregate by tokens_used from agent executions
          agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                         .where.not(performance_metrics: nil)
                         .pluck(:performance_metrics, :tokens_used).each do |metrics, tokens|
            model = metrics&.dig("model") || "unknown"
            model_costs[model][:tokens] += tokens.to_i if model_costs[model]
          end

          model_costs.map do |model, data|
            {
              model: model,
              total_cost: data[:cost].round(6),
              execution_count: data[:count],
              total_tokens: data[:tokens],
              cost_per_execution: data[:count].positive? ? (data[:cost] / data[:count]).round(6) : 0
            }
          end.sort_by { |m| -m[:total_cost] }
        end

        # Daily cost breakdown for charts
        def daily_cost_breakdown
          start_time = time_range.ago

          agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                         .group("DATE(ai_agent_executions.created_at)")
                         .sum(:cost_usd)
                         .transform_keys(&:to_s)
                         .transform_values { |v| v.to_f.round(6) }
        end

        # Estimate potential cost savings
        def estimate_cost_savings
          opportunities = []

          expensive_agents = cost_breakdown_by_agent.first(5)
          expensive_agents.each do |agent|
            if agent[:cost_per_execution] > 0.10
              opportunities << {
                type: "expensive_agent",
                resource_id: agent[:agent_id],
                resource_name: agent[:agent_name],
                current_cost: agent[:total_cost],
                potential_savings: (agent[:total_cost] * 0.2).round(6),
                recommendation: "Consider optimizing prompts or using a more cost-effective model"
              }
            end
          end

          model_costs = cost_breakdown_by_model
          model_costs.each do |model|
            if model[:model].include?("gpt-4") && model[:total_cost] > 10
              opportunities << {
                type: "model_downgrade",
                current_model: model[:model],
                current_cost: model[:total_cost],
                potential_savings: (model[:total_cost] * 0.7).round(6),
                recommendation: "Consider using GPT-3.5 for simpler tasks"
              }
            end
          end

          {
            total_potential_savings: opportunities.sum { |o| o[:potential_savings] }.round(6),
            opportunities: opportunities
          }
        end

        # Generate budget forecast
        def generate_budget_forecast
          daily_costs = daily_cost_breakdown
          return nil if daily_costs.empty?

          costs = daily_costs.values
          avg_daily_cost = costs.sum / costs.length
          trend = calculate_daily_trend(costs)

          days_remaining_in_month = (Time.current.end_of_month.to_date - Date.current).to_i

          {
            average_daily_cost: avg_daily_cost.round(6),
            daily_trend: trend.round(6),
            forecast_next_7_days: forecast_cost(avg_daily_cost, trend, 7),
            forecast_next_30_days: forecast_cost(avg_daily_cost, trend, 30),
            forecast_month_end: forecast_cost(avg_daily_cost, trend, days_remaining_in_month),
            confidence_level: costs.length > 7 ? "high" : "low"
          }
        end

        # Detect cost anomalies
        def detect_cost_anomalies
          anomalies = []
          daily_costs = daily_cost_breakdown

          return anomalies if daily_costs.length < 7

          costs = daily_costs.values
          avg = costs.sum / costs.length
          std_dev = Math.sqrt(costs.map { |c| (c - avg)**2 }.sum / costs.length)

          daily_costs.each do |date, cost|
            z_score = std_dev.positive? ? ((cost - avg) / std_dev).abs : 0

            if z_score > 2
              anomalies << {
                date: date,
                cost: cost.round(6),
                expected_cost: avg.round(6),
                deviation: ((cost - avg) / avg * 100).round(2),
                severity: z_score > 3 ? "high" : "medium"
              }
            end
          end

          anomalies.sort_by { |a| -a[:deviation].abs }
        end

        private

        def calculate_daily_trend(costs)
          return 0.0 if costs.length < 2

          n = costs.length
          x_sum = (0...n).sum
          y_sum = costs.sum
          xy_sum = costs.each_with_index.sum { |y, x| x * y }
          x2_sum = (0...n).sum { |x| x * x }

          denominator = n * x2_sum - x_sum * x_sum
          return 0.0 if denominator.zero?

          (n * xy_sum - x_sum * y_sum) / denominator
        end

        def forecast_cost(avg_daily, trend, days)
          ((avg_daily + trend * days / 2) * days).round(6)
        end
      end
    end
  end
end
