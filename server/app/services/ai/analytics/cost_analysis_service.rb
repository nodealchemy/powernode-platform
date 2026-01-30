# frozen_string_literal: true

module Ai
  module Analytics
    # Service for AI cost analysis and optimization insights
    #
    # Provides detailed cost analysis including:
    # - Cost breakdown by provider, agent, workflow
    # - Cost trends and forecasting
    # - Budget tracking and alerts
    # - Optimization recommendations
    #
    # Usage:
    #   service = Ai::Analytics::CostAnalysisService.new(account: current_account, time_range: 30.days)
    #   analysis = service.full_analysis
    #
    class CostAnalysisService
      attr_reader :account, :time_range

      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # Generate full cost analysis
      # @return [Hash] Complete cost analysis
      def full_analysis
        {
          total_cost: calculate_total_cost,
          cost_trend: calculate_cost_trend,
          cost_by_provider: cost_breakdown_by_provider,
          cost_by_agent: cost_breakdown_by_agent,
          cost_by_workflow: cost_breakdown_by_workflow,
          cost_by_model: cost_breakdown_by_model,
          daily_costs: daily_cost_breakdown,
          budget_status: budget_analysis,
          optimization_potential: estimate_cost_savings,
          budget_forecast: generate_budget_forecast,
          anomalies: detect_cost_anomalies
        }
      end

      # Calculate total cost for time range
      # @return [Hash] Total cost with breakdown
      def calculate_total_cost
        start_time = time_range.ago

        workflow_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).sum(:total_cost).to_f
        node_cost = node_executions.where("ai_node_executions.created_at >= ?", start_time).sum(:cost).to_f

        {
          total: workflow_cost.round(6),
          workflow_cost: workflow_cost.round(6),
          node_cost: node_cost.round(6),
          currency: "USD",
          period_start: start_time.iso8601,
          period_end: Time.current.iso8601
        }
      end

      # Calculate cost trend (change from previous period)
      # @return [Hash] Cost trend data
      def calculate_cost_trend
        start_time = time_range.ago
        previous_start = start_time - time_range

        current_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).sum(:total_cost).to_f
        previous_cost = workflow_runs.where(ai_workflow_runs: { created_at: previous_start..start_time }).sum(:total_cost).to_f

        change = previous_cost.zero? ? nil : ((current_cost - previous_cost) / previous_cost * 100).round(2)

        {
          current_period_cost: current_cost.round(6),
          previous_period_cost: previous_cost.round(6),
          change_percentage: change,
          trend_direction: change.nil? ? "unknown" : (change.positive? ? "increasing" : "decreasing")
        }
      end

      # Cost breakdown by provider
      # @return [Array<Hash>] Provider cost breakdown
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
      # @return [Array<Hash>] Agent cost breakdown
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
      # @return [Array<Hash>] Workflow cost breakdown
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
      # @return [Array<Hash>] Model cost breakdown
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
      # @return [Hash] Daily costs
      def daily_cost_breakdown
        start_time = time_range.ago

        workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)
                     .group("DATE(ai_workflow_runs.created_at)")
                     .sum(:total_cost)
                     .transform_keys(&:to_s)
                     .transform_values { |v| v.to_f.round(6) }
      end

      # Budget analysis
      # @return [Hash] Budget status and projections
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

      # Estimate potential cost savings
      # @return [Hash] Optimization opportunities
      def estimate_cost_savings
        opportunities = []

        # Check for inefficient workflows
        expensive_workflows = cost_breakdown_by_workflow.first(5)
        expensive_workflows.each do |workflow|
          if workflow[:cost_per_execution] > 0.10 # Threshold for "expensive"
            opportunities << {
              type: "expensive_workflow",
              resource_id: workflow[:workflow_id],
              resource_name: workflow[:workflow_name],
              current_cost: workflow[:total_cost],
              potential_savings: (workflow[:total_cost] * 0.2).round(6), # Assume 20% savings possible
              recommendation: "Consider optimizing prompts or using a more cost-effective model"
            }
          end
        end

        # Check for retry costs
        retry_cost = calculate_retry_cost
        if retry_cost > 0
          opportunities << {
            type: "retry_cost",
            current_cost: retry_cost.round(6),
            potential_savings: (retry_cost * 0.5).round(6),
            recommendation: "Reduce error rates to minimize retry costs"
          }
        end

        # Model optimization suggestions
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
      # @return [Hash] Budget forecast
      def generate_budget_forecast
        daily_costs = daily_cost_breakdown
        return nil if daily_costs.empty?

        costs = daily_costs.values
        avg_daily_cost = costs.sum / costs.length
        trend = calculate_daily_trend(costs)

        days_in_period = time_range.to_i / 86400
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
      # @return [Array<Hash>] Detected anomalies
      def detect_cost_anomalies
        anomalies = []
        daily_costs = daily_cost_breakdown

        return anomalies if daily_costs.length < 7

        costs = daily_costs.values
        avg = costs.sum / costs.length
        std_dev = Math.sqrt(costs.map { |c| (c - avg)**2 }.sum / costs.length)

        daily_costs.each do |date, cost|
          z_score = std_dev.positive? ? ((cost - avg) / std_dev).abs : 0

          if z_score > 2 # More than 2 standard deviations
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

      def workflows
        account.ai_workflows
      end

      def agents
        account.ai_agents
      end

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def node_executions
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow).where(ai_workflows: { account_id: account.id })
      end

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

      def calculate_daily_trend(costs)
        return 0.0 if costs.length < 2

        # Simple linear regression to find trend
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
        # Simple linear forecast
        ((avg_daily + trend * days / 2) * days).round(6)
      end
    end
  end
end
