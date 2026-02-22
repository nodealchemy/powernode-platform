# frozen_string_literal: true

module Ai
  module Analytics
    class CostAnalysisService
      module RoiAnalytics
        extend ActiveSupport::Concern

        # Get comprehensive ROI dashboard data
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
        def roi_summary_metrics(period = nil)
          period ||= time_range
          start_date = period.ago.to_date
          end_date = Date.current

          metrics = ::Ai::RoiMetric.for_account(account).daily.for_date_range(start_date, end_date)
          attributions = ::Ai::CostAttribution.for_account(account).for_date_range(start_date, end_date)

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
            cost_breakdown: attributions.cost_breakdown_by_category(account, start_date: start_date, end_date: end_date)
          }
        end

        # Get ROI trends over time
        def roi_trends(period = nil)
          period ||= time_range
          ::Ai::RoiMetric.roi_trends(account, days: (period / 1.day).to_i)
        end

        # Get daily ROI metrics for charting
        def roi_daily_metrics(days: 30)
          start_date = days.days.ago.to_date

          (start_date..Date.current).map do |date|
            metric = ::Ai::RoiMetric.find_by(
              account: account, metric_type: "account_total", period_type: "daily", period_date: date
            )

            if metric
              {
                date: date, cost: metric.total_cost_usd.to_f.round(2),
                value: metric.total_value_usd.to_f.round(2), roi: metric.roi_percentage.to_f.round(2),
                net_benefit: metric.net_benefit_usd.to_f.round(2), tasks: metric.tasks_completed,
                time_saved: metric.time_saved_hours.to_f.round(2)
              }
            else
              { date: date, cost: 0, value: 0, roi: 0, net_benefit: 0, tasks: 0, time_saved: 0 }
            end
          end
        end

        # ROI by workflow
        def roi_by_workflow(period = nil)
          period ||= time_range
          start_date = period.ago

          workflow_data = ::Ai::WorkflowRun
            .joins(:workflow)
            .where(ai_workflows: { account_id: account.id })
            .where("ai_workflow_runs.created_at >= ?", start_date)
            .group("ai_workflows.id", "ai_workflows.name")
            .select(
              "ai_workflows.id", "ai_workflows.name",
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
              workflow_id: data.id, workflow_name: data.name,
              total_runs: data.total_runs, successful_runs: successful,
              success_rate: data.total_runs > 0 ? (successful.to_f / data.total_runs * 100).round(2) : 0,
              total_cost: cost.round(4), time_saved_hours: time_saved.round(2),
              value_generated: value.round(2),
              roi_percentage: cost > 0 ? ((value - cost) / cost * 100).round(2) : 0,
              cost_per_run: data.total_runs > 0 ? (cost / data.total_runs).round(4) : 0,
              avg_duration_ms: data.avg_duration_ms.to_f.round(2)
            }
          end.sort_by { |w| -(w[:roi_percentage] || 0) }
        end

        # ROI by agent
        def roi_by_agent(period = nil)
          period ||= time_range
          start_date = period.ago

          agent_data = ::Ai::AgentExecution
            .joins(:agent)
            .where(ai_agents: { account_id: account.id })
            .where("ai_agent_executions.created_at >= ?", start_date)
            .group("ai_agents.id", "ai_agents.name")
            .select(
              "ai_agents.id", "ai_agents.name",
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
              agent_id: data.id, agent_name: data.name,
              total_executions: data.total_executions, successful_executions: successful,
              success_rate: data.total_executions > 0 ? (successful.to_f / data.total_executions * 100).round(2) : 0,
              total_cost: cost.round(4), total_tokens: data.total_tokens.to_i,
              time_saved_hours: time_saved.round(2), value_generated: value.round(2),
              roi_percentage: cost > 0 ? ((value - cost) / cost * 100).round(2) : 0,
              cost_per_execution: data.total_executions > 0 ? (cost / data.total_executions).round(6) : 0,
              avg_duration_ms: data.avg_duration_ms.to_f.round(2)
            }
          end.sort_by { |a| -(a[:roi_percentage] || 0) }
        end

        # Cost by provider (ROI view)
        def roi_cost_by_provider(period = nil)
          period ||= time_range
          start_date = period.ago.to_date
          end_date = Date.current

          ::Ai::CostAttribution.cost_breakdown_by_provider(account, start_date: start_date, end_date: end_date)
        end

        # Get ROI projections
        def roi_projections(period = nil)
          period ||= time_range
          recent_metrics = ::Ai::RoiMetric.for_account(account).daily.recent(30).order(period_date: :asc)

          return nil if recent_metrics.count < 7

          avg_daily_cost = recent_metrics.average(:total_cost_usd).to_f
          avg_daily_value = recent_metrics.average(:total_value_usd).to_f
          avg_daily_tasks = recent_metrics.average(:tasks_completed).to_f
          avg_daily_roi = recent_metrics.average(:roi_percentage).to_f

          half = recent_metrics.count / 2
          first_half = recent_metrics.first(half)
          second_half = recent_metrics.last(half)

          first_avg_cost = first_half.sum(&:total_cost_usd) / first_half.size.to_f
          second_avg_cost = second_half.sum(&:total_cost_usd) / second_half.size.to_f
          first_avg_value = first_half.sum(&:total_value_usd) / first_half.size.to_f
          second_avg_value = second_half.sum(&:total_value_usd) / second_half.size.to_f

          cost_growth = second_avg_cost - first_avg_cost
          value_growth = second_avg_value - first_avg_value

          {
            based_on_days: recent_metrics.count,
            daily_averages: {
              cost: avg_daily_cost.round(2), value: avg_daily_value.round(2),
              tasks: avg_daily_tasks.round(1), roi: avg_daily_roi.round(2)
            },
            growth_trends: {
              cost_daily_change: cost_growth.round(2), value_daily_change: value_growth.round(2)
            },
            monthly_projection: {
              cost: (avg_daily_cost * 30).round(2), value: (avg_daily_value * 30).round(2),
              net_benefit: ((avg_daily_value - avg_daily_cost) * 30).round(2), tasks: (avg_daily_tasks * 30).round(0)
            },
            quarterly_projection: {
              cost: (avg_daily_cost * 90).round(2), value: (avg_daily_value * 90).round(2),
              net_benefit: ((avg_daily_value - avg_daily_cost) * 90).round(2), tasks: (avg_daily_tasks * 90).round(0)
            },
            yearly_projection: {
              cost: (avg_daily_cost * 365).round(2), value: (avg_daily_value * 365).round(2),
              net_benefit: ((avg_daily_value - avg_daily_cost) * 365).round(2), tasks: (avg_daily_tasks * 365).round(0)
            }
          }
        end

        # Get ROI improvement recommendations
        def roi_recommendations(period = nil)
          period ||= time_range
          recs = []
          summary = roi_summary_metrics(period)
          wf_roi = roi_by_workflow(period)
          agent_roi = roi_by_agent(period)

          if summary[:roi][:percentage] < 0
            recs << {
              type: "critical", priority: 1, title: "Negative ROI Detected",
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
              type: "optimization", priority: 2, title: "Underperforming Workflows",
              description: "#{underperforming.count} workflows have negative ROI", impact: "medium",
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
              type: "reliability", priority: 2, title: "Agents with High Failure Rate",
              description: "#{problematic_agents.count} agents have <80% success rate with significant costs", impact: "medium",
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
              type: "growth", priority: 3, title: "Expand High-ROI Workflows",
              description: "#{high_roi_workflows.count} workflows show >100% ROI", impact: "high",
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
              type: "cost_efficiency", priority: 2, title: "High Cost Per Task",
              description: "Average cost per task is $#{summary[:activity][:cost_per_task].round(2)}", impact: "medium",
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
        def roi_calculate_for_date(date: Date.current)
          ::Ai::RoiMetric.calculate_for_account(account, period_type: "daily", period_date: date)
        end

        # Calculate ROI metrics for a date range
        def roi_calculate_for_range(start_date:, end_date:)
          (start_date..end_date).map { |date| roi_calculate_for_date(date: date) }
        end

        # Aggregate daily metrics to weekly/monthly
        def roi_aggregate_metrics(period_type: "weekly", period_date: Date.current)
          ::Ai::RoiMetric.aggregate_for_period(account, period_type: period_type, period_date: period_date)
        end

        # Compare ROI between two periods
        def roi_compare_periods(current_period: 30.days, previous_period: 30.days)
          current_end = Date.current
          current_start = current_period.ago.to_date
          previous_end = current_start - 1.day
          previous_start = previous_end - (previous_period / 1.day).to_i.days + 1.day

          current_summary = roi_summary_for_range(current_start, current_end)
          previous_summary = roi_summary_for_range(previous_start, previous_end)

          {
            current_period: { start: current_start, end: current_end, metrics: current_summary },
            previous_period: { start: previous_start, end: previous_end, metrics: previous_summary },
            changes: roi_calculate_changes(current_summary, previous_summary)
          }
        end

        private

        def roi_summary_for_range(start_date, end_date)
          metrics = ::Ai::RoiMetric.for_account(account).daily.for_date_range(start_date, end_date)

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
end
