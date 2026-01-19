# frozen_string_literal: true

module Ai
  class Workflow
    module Statistics
      extend ActiveSupport::Concern

      # Statistics and metrics methods
      def execution_stats
        all_runs = workflow_runs.limit(100)
        completed_runs = all_runs.where(status: "completed")
        failed_runs = all_runs.where(status: "failed")

        {
          total_executions: all_runs.count,
          successful_executions: completed_runs.count,
          failed_executions: failed_runs.count,
          completed_runs: completed_runs.count,
          failed_runs: failed_runs.count,
          success_rate: calculate_success_rate_for_runs(all_runs),
          avg_execution_time: calculate_average_duration_for_runs(completed_runs),
          average_execution_time: calculate_average_duration_for_runs(completed_runs),
          total_cost: completed_runs.sum(:total_cost)
        }
      end

      def recent_runs(period = 24.hours)
        workflow_runs.where("created_at >= ?", period.ago)
      end

      def total_cost
        workflow_runs.where(status: "completed").sum(:total_cost)
      end

      def average_execution_time
        completed_runs = workflow_runs.where(status: "completed").where.not(duration_ms: nil)
        return 0.0 if completed_runs.empty?

        completed_runs.average(:duration_ms).to_f
      end

      private

      def calculate_success_rate_for_runs(runs)
        return 0.0 if runs.empty?

        successful = runs.where(status: "completed").count
        (successful.to_f / runs.count * 100).round(2)
      end

      def calculate_average_duration_for_runs(runs)
        return 0.0 if runs.empty?

        completed_with_duration = runs.where.not(duration_ms: nil)
        return 0.0 if completed_with_duration.empty?

        completed_with_duration.average(:duration_ms).to_f
      end
    end
  end
end
