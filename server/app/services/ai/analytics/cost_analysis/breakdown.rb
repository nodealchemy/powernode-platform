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
            executions = node_executions.where("ai_node_executions.created_at >= ?", start_time)
                                       .where("ai_node_executions.metadata->>'provider_id' = ?", provider.id.to_s)

            cost = executions.sum(:cost).to_f
            tokens = calculate_tokens(executions)

            {
              provider_id: provider.id,
              provider_name: provider.name,
              provider_type: provider.provider_type,
              total_cost: cost.round(6),
              execution_count: executions.count,
              input_tokens: tokens[:input],
              output_tokens: tokens[:output],
              cost_per_execution: executions.count.positive? ? (cost / executions.count).round(6) : 0
            }
          end.sort_by { |p| -p[:total_cost] }
        end

        # Cost breakdown by agent
        def cost_breakdown_by_agent
          start_time = time_range.ago

          agents.map do |agent|
            executions = node_executions.where("ai_node_executions.created_at >= ?", start_time)
                                       .joins(:node)
                                       .where("ai_workflow_nodes.configuration->>'agent_id' = ?", agent.id.to_s)

            cost = executions.sum(:cost).to_f

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

        # Cost breakdown by workflow
        def cost_breakdown_by_workflow
          start_time = time_range.ago

          workflows.map do |workflow|
            runs = workflow.runs.where("ai_workflow_runs.created_at >= ?", start_time)
            cost = runs.sum(:total_cost).to_f

            {
              workflow_id: workflow.id,
              workflow_name: workflow.name,
              total_cost: cost.round(6),
              execution_count: runs.count,
              cost_per_execution: runs.count.positive? ? (cost / runs.count).round(6) : 0,
              avg_duration_ms: runs.where(status: "completed").average(:duration_ms)&.to_f&.round(2)
            }
          end.sort_by { |w| -w[:total_cost] }
        end

        # Cost breakdown by model
        def cost_breakdown_by_model
          start_time = time_range.ago

          model_costs = {}

          node_executions.where("ai_node_executions.created_at >= ?", start_time)
                        .pluck(:metadata, :cost).each do |metadata, cost|
            model = metadata&.dig("model") || "unknown"
            model_costs[model] ||= { cost: 0.0, count: 0, tokens: { input: 0, output: 0 } }
            model_costs[model][:cost] += cost.to_f
            model_costs[model][:count] += 1
            model_costs[model][:tokens][:input] += metadata&.dig("token_usage", "input_tokens") || 0
            model_costs[model][:tokens][:output] += metadata&.dig("token_usage", "output_tokens") || 0
          end

          model_costs.map do |model, data|
            {
              model: model,
              total_cost: data[:cost].round(6),
              execution_count: data[:count],
              input_tokens: data[:tokens][:input],
              output_tokens: data[:tokens][:output],
              cost_per_execution: data[:count].positive? ? (data[:cost] / data[:count]).round(6) : 0
            }
          end.sort_by { |m| -m[:total_cost] }
        end

        # Daily cost breakdown for charts
        def daily_cost_breakdown
          start_time = time_range.ago

          workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)
                       .group("DATE(ai_workflow_runs.created_at)")
                       .sum(:total_cost)
                       .transform_keys(&:to_s)
                       .transform_values { |v| v.to_f.round(6) }
        end

        # Estimate potential cost savings
        def estimate_cost_savings
          opportunities = []

          expensive_workflows = cost_breakdown_by_workflow.first(5)
          expensive_workflows.each do |workflow|
            if workflow[:cost_per_execution] > 0.10
              opportunities << {
                type: "expensive_workflow",
                resource_id: workflow[:workflow_id],
                resource_name: workflow[:workflow_name],
                current_cost: workflow[:total_cost],
                potential_savings: (workflow[:total_cost] * 0.2).round(6),
                recommendation: "Consider optimizing prompts or using a more cost-effective model"
              }
            end
          end

          retry_cost = calculate_retry_cost
          if retry_cost > 0
            opportunities << {
              type: "retry_cost",
              current_cost: retry_cost.round(6),
              potential_savings: (retry_cost * 0.5).round(6),
              recommendation: "Reduce error rates to minimize retry costs"
            }
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

        def calculate_tokens(executions)
          input = 0
          output = 0

          executions.pluck(:metadata).each do |metadata|
            usage = metadata&.dig("token_usage") || {}
            input += usage["input_tokens"] || 0
            output += usage["output_tokens"] || 0
          end

          { input: input, output: output }
        end

        def calculate_retry_cost
          start_time = time_range.ago

          node_executions.where("ai_node_executions.created_at >= ?", start_time)
                        .where("ai_node_executions.retry_count > 0")
                        .sum(:cost).to_f
        end

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
