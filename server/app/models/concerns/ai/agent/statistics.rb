# frozen_string_literal: true

module Ai
  class Agent
    module Statistics
      extend ActiveSupport::Concern

      # Get execution count (total executions)
      def execution_count
        executions.count
      end

      # Get success rate as percentage
      def success_rate
        total = executions.count
        return 0 if total.zero?

        successful = executions.where(status: "completed").count
        (successful.to_f / total * 100).round(2)
      end

      # Get execution statistics for a period
      def execution_stats(period = 30.days)
        scope = executions.where("created_at >= ?", period.ago)

        {
          total_executions: scope.count,
          successful_executions: scope.where(status: "completed").count,
          failed_executions: scope.where(status: "failed").count,
          average_duration: scope.where.not(duration_ms: nil).average(:duration_ms) || 0,
          success_rate: calculate_success_rate(scope)
        }
      end

      # Get recent executions within a time period
      def recent_executions(period = 24.hours)
        executions.where("created_at >= ?", period.ago)
      end

      # Get average response time from completed executions
      def average_response_time
        completed = executions.where(status: "completed")
        return 0 if completed.empty?
        completed.average(:duration_ms)&.to_f || 0
      end

      # Get total tokens used across all executions
      def total_tokens_used
        executions.where(status: "completed").sum do |exec|
          exec.output_data&.dig("metrics", "tokens_used") || 0
        end
      end

      # Get estimated total cost across all executions
      def estimated_total_cost
        executions.where(status: "completed").sum do |exec|
          exec.output_data&.dig("metrics", "cost_estimate") || 0.0
        end
      end

      private

      def calculate_success_rate(scope)
        total = scope.count
        return 0 if total.zero?

        successful = scope.where(status: "completed").count
        (successful.to_f / total * 100).round(2)
      end
    end
  end
end
