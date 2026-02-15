# frozen_string_literal: true

module Ai
  module Analytics
    class PerformanceAnalysisService
      module ResponseTimeAnalysis
        extend ActiveSupport::Concern

        # Analyze response times
        # @return [Hash] Response time analysis
        def analyze_response_times
          start_time = time_range.ago
          runs = completed_runs.where("completed_at >= ?", start_time)

          durations = runs.where.not(duration_ms: nil).pluck(:duration_ms)

          return empty_duration_stats if durations.empty?

          sorted = durations.sort

          {
            count: durations.length,
            min_ms: sorted.first,
            max_ms: sorted.last,
            avg_ms: (durations.sum / durations.length.to_f).round(2),
            median_ms: percentile(sorted, 50),
            p75_ms: percentile(sorted, 75),
            p90_ms: percentile(sorted, 90),
            p95_ms: percentile(sorted, 95),
            p99_ms: percentile(sorted, 99),
            std_dev_ms: standard_deviation(durations).round(2),
            by_hour: response_times_by_hour(start_time),
            by_workflow: response_times_by_workflow(start_time)
          }
        end

        private

        def percentile(sorted_array, p)
          return nil if sorted_array.empty?

          index = (p / 100.0 * sorted_array.length).ceil - 1
          sorted_array[[ index, 0 ].max]
        end

        def standard_deviation(values)
          return 0.0 if values.empty?

          avg = values.sum / values.length.to_f
          Math.sqrt(values.map { |v| (v - avg)**2 }.sum / values.length)
        end

        def empty_duration_stats
          {
            count: 0, min_ms: nil, max_ms: nil, avg_ms: nil,
            median_ms: nil, p75_ms: nil, p90_ms: nil, p95_ms: nil, p99_ms: nil,
            std_dev_ms: nil, by_hour: {}, by_workflow: []
          }
        end

        def response_times_by_hour(since)
          completed_runs.where("ai_workflow_runs.completed_at >= ?", since)
                       .group("DATE_TRUNC('hour', ai_workflow_runs.completed_at)")
                       .average(:duration_ms)
                       .transform_keys { |k| k.iso8601 }
                       .transform_values { |v| v&.to_f&.round(2) }
        end

        def response_times_by_workflow(since)
          completed_runs.where("ai_workflow_runs.completed_at >= ?", since)
                       .joins(:workflow)
                       .group("ai_workflows.id", "ai_workflows.name")
                       .average(:duration_ms)
                       .map { |(id, name), avg| { id: id, name: name, avg_ms: avg&.to_f&.round(2) } }
                       .sort_by { |w| -(w[:avg_ms] || 0) }
        end
      end
    end
  end
end
