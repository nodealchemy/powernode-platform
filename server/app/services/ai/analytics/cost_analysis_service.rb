# frozen_string_literal: true

module Ai
  module Analytics
    # Service for AI cost analysis, optimization insights, and ROI tracking
    #
    # Provides detailed cost analysis including:
    # - Cost breakdown by provider, agent, workflow
    # - Cost trends and forecasting
    # - Budget tracking and alerts
    # - Optimization recommendations
    # - ROI calculations by workflow, agent, and provider
    # - ROI projections and recommendations
    #
    # Usage:
    #   service = Ai::Analytics::CostAnalysisService.new(account: current_account, time_range: 30.days)
    #   analysis = service.full_analysis
    #   roi_data = service.roi_dashboard
    #
    class CostAnalysisService
      attr_reader :account, :time_range, :hourly_rate

      # Default hourly rate for time savings calculations
      DEFAULT_HOURLY_RATE = 75.0

      # Average time saved per automated task (in hours)
      DEFAULT_TIME_SAVED_PER_TASK = 0.25

      def initialize(account:, time_range: 30.days, hourly_rate: DEFAULT_HOURLY_RATE)
        @account = account
        @time_range = time_range
        @hourly_rate = hourly_rate
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

      # =========================================================================
      # ROI ANALYTICS (consolidated from Ai::RoiAnalyticsService)
      # =========================================================================

      # Get comprehensive ROI dashboard data
      # @param period [ActiveSupport::Duration] Time period for analysis
      # @return [Hash] Complete ROI dashboard
      def roi_dashboard(period: nil)
        period ||= time_range
        {
          summary: roi_summary_metrics(period),
          trends: roi_trends(period),
          by_workflow: roi_by_workflow(period),
          by_agent: roi_by_agent(period),
          by_provider: roi_cost_by_provider(period),
          projections: roi_projections(period),
          recommendations: roi_recommendations(period),
          generated_at: Time.current.iso8601
        }
      end

      # Get ROI summary metrics
      # @param period [ActiveSupport::Duration] Time period
      # @return [Hash] Summary metrics with costs, value, and ROI
      def roi_summary_metrics(period = nil)
        period ||= time_range
        start_date = period.ago.to_date
        end_date = Date.current

        metrics = ::Ai::RoiMetric.for_account(account)
                                  .daily
                                  .for_date_range(start_date, end_date)

        attributions = ::Ai::CostAttribution.for_account(account)
                                             .for_date_range(start_date, end_date)

        total_ai_cost = metrics.sum(:ai_cost_usd)
        total_infra_cost = metrics.sum(:infrastructure_cost_usd)
        total_cost = total_ai_cost + total_infra_cost
        total_time_saved = metrics.sum(:time_saved_hours)
        total_value = metrics.sum(:total_value_usd)
        total_tasks = metrics.sum(:tasks_completed)
        total_automated = metrics.sum(:tasks_automated)

        roi_percentage = total_cost > 0 ? ((total_value - total_cost) / total_cost * 100).round(2) : 0
        net_benefit = total_value - total_cost

        {
          period_days: (period / 1.day).to_i,
          costs: {
            ai: total_ai_cost.to_f.round(2),
            infrastructure: total_infra_cost.to_f.round(2),
            total: total_cost.to_f.round(2),
            daily_average: (total_cost / (period / 1.day)).to_f.round(2)
          },
          value: {
            time_saved_hours: total_time_saved.to_f.round(2),
            time_saved_monetary: (total_time_saved * hourly_rate).round(2),
            total: total_value.to_f.round(2)
          },
          roi: {
            percentage: roi_percentage,
            net_benefit: net_benefit.to_f.round(2),
            is_positive: roi_percentage > 0
          },
          activity: {
            total_tasks: total_tasks,
            automated_tasks: total_automated,
            automation_rate: total_tasks > 0 ? (total_automated.to_f / total_tasks * 100).round(2) : 0,
            cost_per_task: total_tasks > 0 ? (total_cost / total_tasks).to_f.round(4) : 0
          },
          cost_breakdown: attributions.cost_breakdown_by_category(
            account,
            start_date: start_date,
            end_date: end_date
          )
        }
      end

      # Get ROI trends over time
      # @param period [ActiveSupport::Duration] Time period
      # @return [Array<Hash>] Trend data
      def roi_trends(period = nil)
        period ||= time_range
        ::Ai::RoiMetric.roi_trends(account, days: (period / 1.day).to_i)
      end

      # Get daily ROI metrics for charting
      # @param days [Integer] Number of days
      # @return [Array<Hash>] Daily metrics
      def roi_daily_metrics(days: 30)
        start_date = days.days.ago.to_date

        (start_date..Date.current).map do |date|
          metric = ::Ai::RoiMetric.find_by(
            account: account,
            metric_type: "account_total",
            period_type: "daily",
            period_date: date
          )

          if metric
            {
              date: date,
              cost: metric.total_cost_usd.to_f.round(2),
              value: metric.total_value_usd.to_f.round(2),
              roi: metric.roi_percentage.to_f.round(2),
              net_benefit: metric.net_benefit_usd.to_f.round(2),
              tasks: metric.tasks_completed,
              time_saved: metric.time_saved_hours.to_f.round(2)
            }
          else
            {
              date: date,
              cost: 0,
              value: 0,
              roi: 0,
              net_benefit: 0,
              tasks: 0,
              time_saved: 0
            }
          end
        end
      end

      # ROI by workflow
      # @param period [ActiveSupport::Duration] Time period
      # @return [Array<Hash>] Workflow ROI data
      def roi_by_workflow(period = nil)
        period ||= time_range
        start_date = period.ago

        workflow_data = ::Ai::WorkflowRun
                          .joins(:workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .where("ai_workflow_runs.created_at >= ?", start_date)
                          .group("ai_workflows.id", "ai_workflows.name")
                          .select(
                            "ai_workflows.id",
                            "ai_workflows.name",
                            "COUNT(*) as total_runs",
                            "SUM(CASE WHEN ai_workflow_runs.status = 'completed' THEN 1 ELSE 0 END) as successful_runs",
                            "SUM(ai_workflow_runs.total_cost) as total_cost",
                            "AVG(ai_workflow_runs.duration_ms) as avg_duration_ms"
                          )

        workflow_data.map do |data|
          successful = data.successful_runs.to_i
          cost = data.total_cost.to_f
          time_saved = successful * DEFAULT_TIME_SAVED_PER_TASK
          value = time_saved * hourly_rate

          {
            workflow_id: data.id,
            workflow_name: data.name,
            total_runs: data.total_runs,
            successful_runs: successful,
            success_rate: data.total_runs > 0 ? (successful.to_f / data.total_runs * 100).round(2) : 0,
            total_cost: cost.round(4),
            time_saved_hours: time_saved.round(2),
            value_generated: value.round(2),
            roi_percentage: cost > 0 ? ((value - cost) / cost * 100).round(2) : 0,
            cost_per_run: data.total_runs > 0 ? (cost / data.total_runs).round(4) : 0,
            avg_duration_ms: data.avg_duration_ms.to_f.round(2)
          }
        end.sort_by { |w| -(w[:roi_percentage] || 0) }
      end

      # ROI by agent
      # @param period [ActiveSupport::Duration] Time period
      # @return [Array<Hash>] Agent ROI data
      def roi_by_agent(period = nil)
        period ||= time_range
        start_date = period.ago

        agent_data = ::Ai::AgentExecution
                       .joins(:agent)
                       .where(ai_agents: { account_id: account.id })
                       .where("ai_agent_executions.created_at >= ?", start_date)
                       .group("ai_agents.id", "ai_agents.name")
                       .select(
                         "ai_agents.id",
                         "ai_agents.name",
                         "COUNT(*) as total_executions",
                         "SUM(CASE WHEN ai_agent_executions.status = 'completed' THEN 1 ELSE 0 END) as successful",
                         "SUM(ai_agent_executions.cost_usd) as total_cost",
                         "SUM(ai_agent_executions.tokens_used) as total_tokens",
                         "AVG(ai_agent_executions.duration_ms) as avg_duration_ms"
                       )

        agent_data.map do |data|
          successful = data.successful.to_i
          cost = data.total_cost.to_f
          time_saved = successful * (DEFAULT_TIME_SAVED_PER_TASK / 2)
          value = time_saved * hourly_rate

          {
            agent_id: data.id,
            agent_name: data.name,
            total_executions: data.total_executions,
            successful_executions: successful,
            success_rate: data.total_executions > 0 ? (successful.to_f / data.total_executions * 100).round(2) : 0,
            total_cost: cost.round(4),
            total_tokens: data.total_tokens.to_i,
            time_saved_hours: time_saved.round(2),
            value_generated: value.round(2),
            roi_percentage: cost > 0 ? ((value - cost) / cost * 100).round(2) : 0,
            cost_per_execution: data.total_executions > 0 ? (cost / data.total_executions).round(6) : 0,
            avg_duration_ms: data.avg_duration_ms.to_f.round(2)
          }
        end.sort_by { |a| -(a[:roi_percentage] || 0) }
      end

      # Cost by provider (ROI view)
      # @param period [ActiveSupport::Duration] Time period
      # @return [Array<Hash>] Provider cost data
      def roi_cost_by_provider(period = nil)
        period ||= time_range
        start_date = period.ago.to_date
        end_date = Date.current

        ::Ai::CostAttribution.cost_breakdown_by_provider(
          account,
          start_date: start_date,
          end_date: end_date
        )
      end

      # Get ROI projections
      # @param period [ActiveSupport::Duration] Time period
      # @return [Hash, nil] Projection data or nil if insufficient data
      def roi_projections(period = nil)
        period ||= time_range
        recent_metrics = ::Ai::RoiMetric.for_account(account)
                                         .daily
                                         .recent(30)
                                         .order(period_date: :asc)

        return nil if recent_metrics.count < 7

        avg_daily_cost = recent_metrics.average(:total_cost_usd).to_f
        avg_daily_value = recent_metrics.average(:total_value_usd).to_f
        avg_daily_tasks = recent_metrics.average(:tasks_completed).to_f
        avg_daily_roi = recent_metrics.average(:roi_percentage).to_f

        first_half = recent_metrics.first(recent_metrics.count / 2)
        second_half = recent_metrics.last(recent_metrics.count / 2)

        cost_growth = second_half.average(:total_cost_usd).to_f - first_half.average(:total_cost_usd).to_f
        value_growth = second_half.average(:total_value_usd).to_f - first_half.average(:total_value_usd).to_f

        {
          based_on_days: recent_metrics.count,
          daily_averages: {
            cost: avg_daily_cost.round(2),
            value: avg_daily_value.round(2),
            tasks: avg_daily_tasks.round(1),
            roi: avg_daily_roi.round(2)
          },
          growth_trends: {
            cost_daily_change: cost_growth.round(2),
            value_daily_change: value_growth.round(2)
          },
          monthly_projection: {
            cost: (avg_daily_cost * 30).round(2),
            value: (avg_daily_value * 30).round(2),
            net_benefit: ((avg_daily_value - avg_daily_cost) * 30).round(2),
            tasks: (avg_daily_tasks * 30).round(0)
          },
          quarterly_projection: {
            cost: (avg_daily_cost * 90).round(2),
            value: (avg_daily_value * 90).round(2),
            net_benefit: ((avg_daily_value - avg_daily_cost) * 90).round(2),
            tasks: (avg_daily_tasks * 90).round(0)
          },
          yearly_projection: {
            cost: (avg_daily_cost * 365).round(2),
            value: (avg_daily_value * 365).round(2),
            net_benefit: ((avg_daily_value - avg_daily_cost) * 365).round(2),
            tasks: (avg_daily_tasks * 365).round(0)
          }
        }
      end

      # Get ROI improvement recommendations
      # @param period [ActiveSupport::Duration] Time period
      # @return [Array<Hash>] Recommendations
      def roi_recommendations(period = nil)
        period ||= time_range
        recs = []

        summary = roi_summary_metrics(period)
        wf_roi = roi_by_workflow(period)
        agent_roi = roi_by_agent(period)

        if summary[:roi][:percentage] < 0
          recs << {
            type: "critical",
            priority: 1,
            title: "Negative ROI Detected",
            description: "Your AI investment is currently showing negative returns (#{summary[:roi][:percentage]}%)",
            impact: "high",
            actions: [
              "Review high-cost workflows and optimize or disable them",
              "Consider switching to more cost-effective AI providers",
              "Increase automation of high-value tasks"
            ]
          }
        end

        underperforming = wf_roi.select { |w| w[:roi_percentage] < 0 && w[:total_runs] > 10 }
        if underperforming.any?
          recs << {
            type: "optimization",
            priority: 2,
            title: "Underperforming Workflows",
            description: "#{underperforming.count} workflows have negative ROI",
            impact: "medium",
            workflows: underperforming.first(3).map { |w| w[:workflow_name] },
            actions: [
              "Review and optimize workflow configurations",
              "Consider disabling or consolidating these workflows",
              "Analyze if the use cases are appropriate for AI automation"
            ]
          }
        end

        problematic_agents = agent_roi.select { |a| a[:success_rate] < 80 && a[:total_cost] > 10 }
        if problematic_agents.any?
          recs << {
            type: "reliability",
            priority: 2,
            title: "Agents with High Failure Rate",
            description: "#{problematic_agents.count} agents have <80% success rate with significant costs",
            impact: "medium",
            agents: problematic_agents.first(3).map { |a| a[:agent_name] },
            actions: [
              "Review agent configurations and prompts",
              "Check provider reliability",
              "Consider implementing fallback mechanisms"
            ]
          }
        end

        high_roi_workflows = wf_roi.select { |w| w[:roi_percentage] > 100 && w[:total_runs] > 10 }
        if high_roi_workflows.any? && high_roi_workflows.count < wf_roi.count / 2
          recs << {
            type: "growth",
            priority: 3,
            title: "Expand High-ROI Workflows",
            description: "#{high_roi_workflows.count} workflows show >100% ROI",
            impact: "high",
            workflows: high_roi_workflows.first(3).map { |w| w[:workflow_name] },
            actions: [
              "Increase usage of high-performing workflows",
              "Apply similar patterns to other use cases",
              "Document successful patterns for replication"
            ]
          }
        end

        if summary[:costs][:ai] > 100 && summary[:activity][:cost_per_task] > 0.10
          recs << {
            type: "cost_efficiency",
            priority: 2,
            title: "High Cost Per Task",
            description: "Average cost per task is $#{summary[:activity][:cost_per_task].round(2)}",
            impact: "medium",
            actions: [
              "Evaluate alternative AI providers",
              "Implement caching for repetitive queries",
              "Optimize prompts to reduce token usage"
            ]
          }
        end

        recs.sort_by { |r| r[:priority] }
      end

      # Calculate and store ROI metrics for a specific date
      # @param date [Date] Date to calculate for
      # @return [Ai::RoiMetric] Calculated metric
      def roi_calculate_for_date(date: Date.current)
        ::Ai::RoiMetric.calculate_for_account(account, period_type: "daily", period_date: date)
      end

      # Calculate ROI metrics for a date range
      # @param start_date [Date] Start date
      # @param end_date [Date] End date
      # @return [Array<Ai::RoiMetric>] Calculated metrics
      def roi_calculate_for_range(start_date:, end_date:)
        (start_date..end_date).map do |date|
          roi_calculate_for_date(date: date)
        end
      end

      # Aggregate daily metrics to weekly/monthly
      # @param period_type [String] "weekly" or "monthly"
      # @param period_date [Date] Date within the period
      # @return [Ai::RoiMetric, nil] Aggregated metric
      def roi_aggregate_metrics(period_type: "weekly", period_date: Date.current)
        ::Ai::RoiMetric.aggregate_for_period(account, period_type: period_type, period_date: period_date)
      end

      # Compare ROI between two periods
      # @param current_period [ActiveSupport::Duration] Current period
      # @param previous_period [ActiveSupport::Duration] Previous period
      # @return [Hash] Period comparison
      def roi_compare_periods(current_period: 30.days, previous_period: 30.days)
        current_end = Date.current
        current_start = current_period.ago.to_date
        previous_end = current_start - 1.day
        previous_start = previous_end - previous_period.to_i.days + 1.day

        current_summary = roi_summary_for_range(current_start, current_end)
        previous_summary = roi_summary_for_range(previous_start, previous_end)

        {
          current_period: {
            start: current_start,
            end: current_end,
            metrics: current_summary
          },
          previous_period: {
            start: previous_start,
            end: previous_end,
            metrics: previous_summary
          },
          changes: roi_calculate_changes(current_summary, previous_summary)
        }
      end

      # ==========================================================================
      # FINOPS METHODS
      # ==========================================================================

      # Budget enforcement with alert thresholds.
      # @param account_id [String] Account ID (defaults to current account)
      # @return [Hash] Budget enforcement status with alert levels
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
      # @param account_id [String] Account ID (defaults to current account)
      # @return [Hash] Optimization score from 0-100 with breakdown
      def finops_optimization_score(account_id: nil)
        target_account = account_id ? Account.find(account_id) : account
        token_service = ::Ai::Finops::TokenAnalyticsService.new(account: target_account)
        token_service.optimization_score
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

      # ROI private helpers

      def roi_summary_for_range(start_date, end_date)
        metrics = ::Ai::RoiMetric.for_account(account)
                                  .daily
                                  .for_date_range(start_date, end_date)

        {
          total_cost: metrics.sum(:total_cost_usd).to_f.round(2),
          total_value: metrics.sum(:total_value_usd).to_f.round(2),
          total_tasks: metrics.sum(:tasks_completed),
          roi_percentage: metrics.average(:roi_percentage).to_f.round(2),
          time_saved_hours: metrics.sum(:time_saved_hours).to_f.round(2)
        }
      end

      def roi_calculate_changes(current, previous)
        {
          cost_change: roi_percentage_change(previous[:total_cost], current[:total_cost]),
          value_change: roi_percentage_change(previous[:total_value], current[:total_value]),
          tasks_change: roi_percentage_change(previous[:total_tasks], current[:total_tasks]),
          roi_change: current[:roi_percentage] - previous[:roi_percentage],
          time_saved_change: roi_percentage_change(previous[:time_saved_hours], current[:time_saved_hours])
        }
      end

      def roi_percentage_change(old_value, new_value)
        return 0 if old_value.nil? || old_value.zero?

        ((new_value - old_value) / old_value.to_f * 100).round(2)
      end
    end
  end
end
