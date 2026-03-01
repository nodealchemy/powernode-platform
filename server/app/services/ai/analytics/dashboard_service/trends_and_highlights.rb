# frozen_string_literal: true

module Ai
  module Analytics
    class DashboardService
      module TrendsAndHighlights
        extend ActiveSupport::Concern

        # Generate trend data for charts
        # @return [Hash] Trend data
        def generate_trend_data
          start_time = time_range.ago

          {
            executions_by_day: executions_by_day(start_time),
            cost_by_day: cost_by_day(start_time),
            success_rate_by_day: success_rate_by_day(start_time),
            messages_by_day: messages_by_day(start_time)
          }
        end

        # Generate dashboard highlights
        # @return [Hash] Highlights
        def generate_highlights
          start_time = time_range.ago

          {
            top_workflows: top_workflows(start_time, limit: 5),
            top_agents: top_agents(start_time, limit: 5),
            recent_failures: recent_failures(start_time, limit: 5),
            cost_leaders: cost_leaders(start_time, limit: 5)
          }
        end

        private

        def executions_by_day(since)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .group("DATE(ai_workflow_runs.created_at)")
                       .count
                       .transform_keys(&:to_s)
        end

        def cost_by_day(since)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .group("DATE(ai_workflow_runs.created_at)")
                       .sum(:total_cost)
                       .transform_keys(&:to_s)
                       .transform_values { |v| v.to_f.round(6) }
        end

        def success_rate_by_day(since)
          completed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                  .where(status: "completed")
                                  .group("DATE(ai_workflow_runs.created_at)")
                                  .count

          total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                              .where.not(status: %w[running initializing pending])
                              .group("DATE(ai_workflow_runs.created_at)")
                              .count

          total.transform_keys(&:to_s).transform_values do |count|
            date = total.key(count)
            next 0.0 if count.zero?

            ((completed[date] || 0).to_f / count * 100).round(2)
          end
        end

        def messages_by_day(since)
          messages.where("ai_messages.created_at >= ?", since)
                 .group("DATE(ai_messages.created_at)")
                 .count
                 .transform_keys(&:to_s)
        end

        def top_workflows(since, limit:)
          workflows.joins(:runs)
                   .where("ai_workflow_runs.created_at >= ?", since)
                   .group("ai_workflows.id", "ai_workflows.name")
                   .order("COUNT(ai_workflow_runs.id) DESC")
                   .limit(limit)
                   .pluck("ai_workflows.id", "ai_workflows.name", Arel.sql("COUNT(ai_workflow_runs.id)"))
                   .map { |id, name, count| { id: id, name: name, execution_count: count } }
        end

        def top_agents(since, limit:)
          agents.joins(:executions)
                .where("ai_agent_executions.created_at >= ?", since)
                .group("ai_agents.id", "ai_agents.name")
                .order("COUNT(ai_agent_executions.id) DESC")
                .limit(limit)
                .pluck("ai_agents.id", "ai_agents.name", Arel.sql("COUNT(ai_agent_executions.id)"))
                .map { |id, name, count| { id: id, name: name, execution_count: count } }
        rescue StandardError
          []
        end

        def recent_failures(since, limit:)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .where(status: "failed")
                       .includes(:workflow)
                       .order("ai_workflow_runs.created_at DESC")
                       .limit(limit)
                       .map do |run|
            {
              run_id: run.run_id,
              workflow_name: run.workflow.name,
              error: run.error_details&.dig("error_message") || "Unknown error",
              failed_at: run.completed_at&.iso8601
            }
          end
        end

        def cost_leaders(since, limit:)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .joins(:workflow)
                       .group("ai_workflows.id", "ai_workflows.name")
                       .order(Arel.sql("SUM(ai_workflow_runs.total_cost) DESC"))
                       .limit(limit)
                       .pluck("ai_workflows.id", "ai_workflows.name", Arel.sql("SUM(ai_workflow_runs.total_cost)"))
                       .map { |id, name, cost| { id: id, name: name, total_cost: cost.to_f.round(6) } }
        end
      end
    end
  end
end
