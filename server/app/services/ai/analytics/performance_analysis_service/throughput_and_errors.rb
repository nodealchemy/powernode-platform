# frozen_string_literal: true

module Ai
  module Analytics
    class PerformanceAnalysisService
      module ThroughputAndErrors
        extend ActiveSupport::Concern

        # Analyze success rates
        # @return [Hash] Success rate analysis
        def analyze_success_rates
          start_time = time_range.ago
          runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)
                             .where.not(status: %w[running initializing pending])

          total = runs.count
          return empty_success_stats if total.zero?

          completed = runs.where(status: "completed").count
          failed = runs.where(status: "failed").count
          cancelled = runs.where(status: "cancelled").count

          {
            total_executions: total,
            successful: completed,
            failed: failed,
            cancelled: cancelled,
            success_rate: (completed.to_f / total * 100).round(2),
            failure_rate: (failed.to_f / total * 100).round(2),
            cancellation_rate: (cancelled.to_f / total * 100).round(2),
            by_workflow: success_rates_by_workflow(start_time),
            by_day: success_rates_by_day(start_time),
            by_trigger_type: success_rates_by_trigger(start_time)
          }
        end

        # Analyze throughput
        # @return [Hash] Throughput analysis
        def analyze_throughput
          start_time = time_range.ago
          runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)

          total = runs.count
          hours = time_range.to_i / 3600.0
          days = hours / 24.0

          {
            total_executions: total,
            period_hours: hours.round(2),
            executions_per_hour: (total / hours).round(2),
            executions_per_day: (total / days).round(2),
            peak_hour: find_peak_hour(start_time),
            peak_day: find_peak_day(start_time),
            by_hour_of_day: throughput_by_hour_of_day(start_time),
            by_day_of_week: throughput_by_day_of_week(start_time),
            concurrent_peak: find_concurrent_peak(start_time)
          }
        end

        # Analyze error rates
        # @return [Hash] Error rate analysis
        def analyze_error_rates
          start_time = time_range.ago
          failed_runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).where(status: "failed")

          error_types = {}
          failed_runs.pluck(:error_details).each do |details|
            error_type = details&.dig("error_type") || "unknown"
            error_types[error_type] ||= 0
            error_types[error_type] += 1
          end

          {
            total_errors: failed_runs.count,
            error_rate: calculate_error_rate(start_time),
            by_error_type: error_types.sort_by { |_, v| -v }.to_h,
            by_workflow: error_rates_by_workflow(start_time),
            by_node_type: error_rates_by_node_type(start_time),
            recent_errors: recent_errors(start_time, limit: 10),
            mtbf_hours: calculate_mtbf(start_time)
          }
        end

        private

        def empty_success_stats
          {
            total_executions: 0, successful: 0, failed: 0, cancelled: 0,
            success_rate: nil, failure_rate: nil, cancellation_rate: nil,
            by_workflow: [], by_day: {}, by_trigger_type: {}
          }
        end

        def success_rates_by_workflow(since)
          workflows = account.ai_workflows

          workflows.map do |workflow|
            runs = workflow.runs.where("ai_workflow_runs.created_at >= ?", since)
                          .where.not(status: %w[running initializing pending])

            total = runs.count
            next nil if total.zero?

            completed = runs.where(status: "completed").count

            {
              id: workflow.id,
              name: workflow.name,
              total: total,
              success_rate: (completed.to_f / total * 100).round(2)
            }
          end.compact.sort_by { |w| w[:success_rate] }
        end

        def success_rates_by_day(since)
          runs_by_day = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                    .where.not(status: %w[running initializing pending])
                                    .group("DATE(ai_workflow_runs.created_at)")

          completed_by_day = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                         .where(status: "completed")
                                         .group("DATE(ai_workflow_runs.created_at)")
                                         .count

          runs_by_day.count.transform_keys(&:to_s).transform_values do |total|
            date = runs_by_day.count.key(total)
            completed = completed_by_day[date] || 0
            (completed.to_f / total * 100).round(2)
          end
        end

        def success_rates_by_trigger(since)
          runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                             .where.not(status: %w[running initializing pending])
                             .group(:trigger_type)

          total_by_trigger = runs.count
          completed_by_trigger = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                             .where(status: "completed")
                                             .group(:trigger_type)
                                             .count

          total_by_trigger.transform_values do |total|
            trigger = total_by_trigger.key(total)
            completed = completed_by_trigger[trigger] || 0
            (completed.to_f / total * 100).round(2)
          end
        end

        def calculate_error_rate(since)
          total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                              .where.not(status: %w[running initializing pending])
                              .count
          return 0.0 if total.zero?

          failed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "failed").count
          (failed.to_f / total * 100).round(2)
        end

        def error_rates_by_workflow(since)
          workflows = account.ai_workflows

          workflows.map do |workflow|
            runs = workflow.runs.where("ai_workflow_runs.created_at >= ?", since)
                          .where.not(status: %w[running initializing pending])

            total = runs.count
            next nil if total.zero?

            failed = runs.where(status: "failed").count

            {
              id: workflow.id,
              name: workflow.name,
              error_rate: (failed.to_f / total * 100).round(2)
            }
          end.compact.sort_by { |w| -w[:error_rate] }
        end

        def error_rates_by_node_type(since)
          node_executions.where("ai_workflow_node_executions.created_at >= ?", since)
                        .joins(:node)
                        .group("ai_workflow_nodes.node_type")
                        .count
                        .transform_values do |total|
            # Simplified - would need actual calculation
            0.0
          end
        end

        def recent_errors(since, limit:)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .where(status: "failed")
                       .includes(:workflow)
                       .order("ai_workflow_runs.completed_at DESC")
                       .limit(limit)
                       .map do |run|
            {
              run_id: run.run_id,
              workflow_name: run.workflow.name,
              error_type: run.error_details&.dig("error_type"),
              error_message: run.error_details&.dig("error_message")&.truncate(100),
              occurred_at: run.completed_at&.iso8601
            }
          end
        end

        def calculate_mtbf(since)
          failed_runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                    .where(status: "failed")
                                    .where.not(completed_at: nil)
                                    .order("ai_workflow_runs.completed_at")

          return nil if failed_runs.count < 2

          times = failed_runs.pluck(:completed_at)
          intervals = times.each_cons(2).map { |a, b| (b - a) / 3600.0 }

          (intervals.sum / intervals.length).round(2)
        end

        def find_peak_hour(since)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .group("DATE_TRUNC('hour', ai_workflow_runs.created_at)")
                       .count
                       .max_by { |_, v| v }
                       &.first&.iso8601
        end

        def find_peak_day(since)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .group("DATE(ai_workflow_runs.created_at)")
                       .count
                       .max_by { |_, v| v }
                       &.first&.to_s
        end

        def throughput_by_hour_of_day(since)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .group("EXTRACT(HOUR FROM ai_workflow_runs.created_at)")
                       .count
                       .transform_keys { |k| k.to_i.to_s }
        end

        def throughput_by_day_of_week(since)
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                       .group("EXTRACT(DOW FROM ai_workflow_runs.created_at)")
                       .count
                       .transform_keys { |k| %w[Sun Mon Tue Wed Thu Fri Sat][k.to_i] }
        end

        def find_concurrent_peak(since)
          # This would require more sophisticated tracking
          workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "running").count
        end
      end
    end
  end
end
