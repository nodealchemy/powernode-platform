# frozen_string_literal: true

module Ai
  class WorkflowNode
    module Statistics
      extend ActiveSupport::Concern

      # Node execution summary
      def execution_summary(days = 30)
        executions = node_executions.where("created_at >= ?", days.days.ago)

        {
          total_executions: executions.count,
          successful_executions: executions.where(status: "completed").count,
          failed_executions: executions.where(status: "failed").count,
          average_duration: executions.where(status: "completed").average(:duration_ms)&.to_i || 0,
          total_cost: executions.sum(:cost),
          last_execution: executions.order(created_at: :desc).first&.created_at
        }
      end
    end
  end
end
