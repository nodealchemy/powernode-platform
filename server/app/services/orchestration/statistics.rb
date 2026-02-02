# frozen_string_literal: true

module Orchestration
  module Statistics
    def execution_statistics(run, include_performance: false)
      executions = run.node_executions

      total_cost = executions.sum(:cost) || 0

      stats = {
        total_nodes: executions.count,
        completed_nodes: executions.where(status: "completed").count,
        failed_nodes: executions.where(status: "failed").count,
        cancelled_nodes: executions.where(status: "cancelled").count,
        success_rate: calculate_success_rate(executions),
        total_cost: total_cost,
        total_tokens: (total_cost / 0.002 * 1000).to_i
      }

      if include_performance
        completed_executions = executions.where(status: "completed").where.not(duration_ms: nil)

        stats.merge!({
          average_node_execution_time: completed_executions.average(:duration_ms)&.to_f || 0,
          execution_efficiency_score: calculate_efficiency_score(run),
          cost_per_token: stats[:total_tokens] > 0 ? (stats[:total_cost] / stats[:total_tokens]).round(6) : 0
        })
      end

      stats
    end

    private

    def calculate_success_rate(executions)
      return 0.0 if executions.empty?

      successful = executions.where(status: [ "completed", "skipped" ]).count
      (successful.to_f / executions.count * 100).round(2)
    end

    def calculate_efficiency_score(run)
      return 0.0 unless run.completed_at && run.started_at

      actual_duration = run.completed_at - run.started_at
      expected_duration = estimate_expected_duration(run)

      return 100.0 if expected_duration <= 0

      efficiency = (expected_duration / actual_duration.to_f * 100).round(2)
      [ efficiency, 100.0 ].min
    end

    def estimate_expected_duration(run)
      node_count = run.workflow.nodes.count
      base_time_per_node = 30

      node_count * base_time_per_node
    end
  end
end
