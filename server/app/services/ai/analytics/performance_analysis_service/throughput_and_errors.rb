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
          runs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                                 .where.not(status: %w[running pending])

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
            by_agent: success_rates_by_agent(start_time),
            by_day: success_rates_by_day(start_time)
          }
        end

        # Analyze throughput
        # @return [Hash] Throughput analysis
        def analyze_throughput
          start_time = time_range.ago
          runs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)

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
          failed_runs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time).where(status: "failed")

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
            by_agent: error_rates_by_agent(start_time),
            recent_errors: recent_errors(start_time, limit: 10),
            mtbf_hours: calculate_mtbf(start_time)
          }
        end

        private

        def empty_success_stats
          {
            total_executions: 0, successful: 0, failed: 0, cancelled: 0,
            success_rate: nil, failure_rate: nil, cancellation_rate: nil,
            by_agent: [], by_day: {}
          }
        end

        def success_rates_by_agent(since)
          agents = account.ai_agents

          agents.map do |agent|
            runs = agent.executions.where("ai_agent_executions.created_at >= ?", since)
                        .where.not(status: %w[running pending])

            total = runs.count
            next nil if total.zero?

            completed = runs.where(status: "completed").count

            {
              id: agent.id,
              name: agent.name,
              total: total,
              success_rate: (completed.to_f / total * 100).round(2)
            }
          end.compact.sort_by { |a| a[:success_rate] }
        end

        def success_rates_by_day(since)
          runs_by_day = agent_executions.where("ai_agent_executions.created_at >= ?", since)
                                        .where.not(status: %w[running pending])
                                        .group("DATE(ai_agent_executions.created_at)")

          completed_by_day = agent_executions.where("ai_agent_executions.created_at >= ?", since)
                                             .where(status: "completed")
                                             .group("DATE(ai_agent_executions.created_at)")
                                             .count

          runs_by_day.count.transform_keys(&:to_s).transform_values do |total|
            date = runs_by_day.count.key(total)
            completed = completed_by_day[date] || 0
            (completed.to_f / total * 100).round(2)
          end
        end

        def calculate_error_rate(since)
          total = agent_executions.where("ai_agent_executions.created_at >= ?", since)
                                  .where.not(status: %w[running pending])
                                  .count
          return 0.0 if total.zero?

          failed = agent_executions.where("ai_agent_executions.created_at >= ?", since).where(status: "failed").count
          (failed.to_f / total * 100).round(2)
        end

        def error_rates_by_agent(since)
          agents = account.ai_agents

          agents.map do |agent|
            runs = agent.executions.where("ai_agent_executions.created_at >= ?", since)
                        .where.not(status: %w[running pending])

            total = runs.count
            next nil if total.zero?

            failed = runs.where(status: "failed").count

            {
              id: agent.id,
              name: agent.name,
              error_rate: (failed.to_f / total * 100).round(2)
            }
          end.compact.sort_by { |a| -a[:error_rate] }
        end

        def recent_errors(since, limit:)
          agent_executions.where("ai_agent_executions.created_at >= ?", since)
                          .where(status: "failed")
                          .includes(:agent)
                          .order("ai_agent_executions.completed_at DESC")
                          .limit(limit)
                          .map do |execution|
            {
              execution_id: execution.execution_id,
              agent_name: execution.agent.name,
              error_type: execution.error_details&.dig("error_type"),
              error_message: execution.error_message&.truncate(100),
              occurred_at: execution.completed_at&.iso8601
            }
          end
        end

        def calculate_mtbf(since)
          failed_runs = agent_executions.where("ai_agent_executions.created_at >= ?", since)
                                        .where(status: "failed")
                                        .where.not(completed_at: nil)
                                        .order("ai_agent_executions.completed_at")

          return nil if failed_runs.count < 2

          times = failed_runs.pluck(:completed_at)
          intervals = times.each_cons(2).map { |a, b| (b - a) / 3600.0 }

          (intervals.sum / intervals.length).round(2)
        end

        def find_peak_hour(since)
          agent_executions.where("ai_agent_executions.created_at >= ?", since)
                          .group("DATE_TRUNC('hour', ai_agent_executions.created_at)")
                          .count
                          .max_by { |_, v| v }
                          &.first&.iso8601
        end

        def find_peak_day(since)
          agent_executions.where("ai_agent_executions.created_at >= ?", since)
                          .group("DATE(ai_agent_executions.created_at)")
                          .count
                          .max_by { |_, v| v }
                          &.first&.to_s
        end

        def throughput_by_hour_of_day(since)
          agent_executions.where("ai_agent_executions.created_at >= ?", since)
                          .group("EXTRACT(HOUR FROM ai_agent_executions.created_at)")
                          .count
                          .transform_keys { |k| k.to_i.to_s }
        end

        def throughput_by_day_of_week(since)
          agent_executions.where("ai_agent_executions.created_at >= ?", since)
                          .group("EXTRACT(DOW FROM ai_agent_executions.created_at)")
                          .count
                          .transform_keys { |k| %w[Sun Mon Tue Wed Thu Fri Sat][k.to_i] }
        end

        def find_concurrent_peak(since)
          agent_executions.where("ai_agent_executions.created_at >= ?", since).where(status: "running").count
        end
      end
    end
  end
end
