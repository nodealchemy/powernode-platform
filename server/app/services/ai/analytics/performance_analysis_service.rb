# frozen_string_literal: true

module Ai
  module Analytics
    # Service for AI performance analysis
    #
    # Provides detailed performance analysis including:
    # - Response time analysis
    # - Success rate analysis
    # - Throughput analysis
    # - Error rate analysis
    # - Bottleneck identification
    #
    # Usage:
    #   service = Ai::Analytics::PerformanceAnalysisService.new(account: current_account, time_range: 30.days)
    #   analysis = service.full_analysis
    #
    class PerformanceAnalysisService
      attr_reader :account, :time_range

      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # Generate full performance analysis
      # @return [Hash] Complete performance analysis
      def full_analysis
        {
          response_times: analyze_response_times,
          success_rates: analyze_success_rates,
          throughput: analyze_throughput,
          error_rates: analyze_error_rates,
          resource_utilization: analyze_resource_utilization,
          bottlenecks: identify_bottlenecks,
          sla_compliance: analyze_sla_compliance,
          performance_trends: analyze_performance_trends
        }
      end

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

      # Analyze resource utilization
      # @return [Hash] Resource utilization
      def analyze_resource_utilization
        start_time = time_range.ago

        {
          provider_utilization: provider_utilization(start_time),
          model_utilization: model_utilization(start_time),
          token_utilization: token_utilization(start_time),
          queue_metrics: queue_metrics(start_time)
        }
      end

      # Identify bottlenecks
      # @return [Array<Hash>] Identified bottlenecks
      def identify_bottlenecks
        bottlenecks = []
        start_time = time_range.ago

        # Slow nodes
        slow_nodes = find_slow_nodes(start_time)
        slow_nodes.each do |node|
          bottlenecks << {
            type: "slow_node",
            resource_type: "node",
            resource_name: node[:name],
            metric: "avg_duration_ms",
            value: node[:avg_duration],
            threshold: 5000,
            impact: "high",
            recommendation: "Optimize node configuration or use caching"
          }
        end

        # High error rate workflows
        error_workflows = find_high_error_workflows(start_time)
        error_workflows.each do |workflow|
          bottlenecks << {
            type: "high_error_rate",
            resource_type: "workflow",
            resource_name: workflow[:name],
            metric: "error_rate",
            value: workflow[:error_rate],
            threshold: 10,
            impact: "high",
            recommendation: "Review error logs and fix common failure patterns"
          }
        end

        # Resource contention
        if queue_depth_high?(start_time)
          bottlenecks << {
            type: "queue_depth",
            resource_type: "system",
            resource_name: "execution_queue",
            metric: "avg_queue_time_ms",
            value: calculate_avg_queue_time(start_time),
            threshold: 5000,
            impact: "medium",
            recommendation: "Consider scaling worker capacity"
          }
        end

        bottlenecks.sort_by { |b| b[:impact] == "high" ? 0 : 1 }
      end

      # Analyze SLA compliance
      # @return [Hash] SLA compliance metrics
      def analyze_sla_compliance
        start_time = time_range.ago

        # Default SLA targets
        sla_targets = account.settings&.dig("ai_sla_targets") || {
          "availability" => 99.9,
          "response_time_p95_ms" => 10000,
          "success_rate" => 99.0
        }

        response_times = analyze_response_times
        success_rates = analyze_success_rates

        {
          availability: {
            target: sla_targets["availability"],
            actual: calculate_availability(start_time),
            compliant: calculate_availability(start_time) >= sla_targets["availability"]
          },
          response_time: {
            target_p95_ms: sla_targets["response_time_p95_ms"],
            actual_p95_ms: response_times[:p95_ms],
            compliant: (response_times[:p95_ms] || Float::INFINITY) <= sla_targets["response_time_p95_ms"]
          },
          success_rate: {
            target: sla_targets["success_rate"],
            actual: success_rates[:success_rate],
            compliant: (success_rates[:success_rate] || 0) >= sla_targets["success_rate"]
          },
          overall_compliant: true # Will be calculated
        }.tap do |result|
          result[:overall_compliant] = result[:availability][:compliant] &&
                                       result[:response_time][:compliant] &&
                                       result[:success_rate][:compliant]
        end
      end

      # Analyze performance trends
      # @return [Hash] Performance trends
      def analyze_performance_trends
        start_time = time_range.ago

        {
          response_time_trend: calculate_response_time_trend(start_time),
          success_rate_trend: calculate_success_rate_trend(start_time),
          throughput_trend: calculate_throughput_trend(start_time),
          error_rate_trend: calculate_error_rate_trend(start_time)
        }
      end

      private

      # =============================================================================
      # QUERY HELPERS
      # =============================================================================

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def completed_runs
        workflow_runs.where(status: "completed")
      end

      def node_executions
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow).where(ai_workflows: { account_id: account.id })
      end

      # =============================================================================
      # CALCULATION HELPERS
      # =============================================================================

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

      def empty_success_stats
        {
          total_executions: 0, successful: 0, failed: 0, cancelled: 0,
          success_rate: nil, failure_rate: nil, cancellation_rate: nil,
          by_workflow: [], by_day: {}, by_trigger_type: {}
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
                                  .order("ai_workflow_runs.created_at")

        return nil if failed_runs.count < 2

        times = failed_runs.pluck(:created_at)
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

      def provider_utilization(since)
        {}
      end

      def model_utilization(since)
        {}
      end

      def token_utilization(since)
        total = 0
        node_executions.where("ai_workflow_node_executions.created_at >= ?", since).pluck(:metadata).each do |metadata|
          usage = metadata&.dig("token_usage") || {}
          total += (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
        end
        { total_tokens: total }
      end

      def queue_metrics(since)
        { avg_queue_time_ms: calculate_avg_queue_time(since) }
      end

      def calculate_avg_queue_time(since)
        runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                           .where.not(started_at: nil)

        times = runs.map do |r|
          r.started_at && r.created_at ? (r.started_at - r.created_at) * 1000 : nil
        end.compact

        times.empty? ? 0 : (times.sum / times.length).round(2)
      end

      def find_slow_nodes(since)
        node_executions.where("ai_workflow_node_executions.created_at >= ?", since)
                      .where(status: "completed")
                      .joins(:node)
                      .group("ai_workflow_nodes.id", "ai_workflow_nodes.name", "ai_workflow_nodes.node_type")
                      .having("AVG(ai_workflow_node_executions.duration_ms) > ?", 5000)
                      .average(:duration_ms)
                      .map { |(id, name, type), avg| { id: id, name: name, type: type, avg_duration: avg&.to_f&.round(2) } }
      end

      def find_high_error_workflows(since)
        error_rates_by_workflow(since).select { |w| w[:error_rate] > 10 }
      end

      def queue_depth_high?(since)
        calculate_avg_queue_time(since) > 5000
      end

      def calculate_availability(since)
        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).count
        return 100.0 if total.zero?

        failed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                             .where(status: "failed")
                             .where("ai_workflow_runs.error_details->>'error_type' IN (?)", %w[system_error service_unavailable])
                             .count

        ((total - failed).to_f / total * 100).round(2)
      end

      def calculate_response_time_trend(since)
        daily_avg = completed_runs.where("ai_workflow_runs.completed_at >= ?", since)
                                 .group("DATE(ai_workflow_runs.completed_at)")
                                 .average(:duration_ms)
                                 .values

        return "stable" if daily_avg.length < 2

        first_half_avg = daily_avg.first(daily_avg.length / 2).sum / (daily_avg.length / 2)
        second_half_avg = daily_avg.last(daily_avg.length / 2).sum / (daily_avg.length / 2)

        if second_half_avg > first_half_avg * 1.1
          "increasing"
        elsif second_half_avg < first_half_avg * 0.9
          "decreasing"
        else
          "stable"
        end
      end

      def calculate_success_rate_trend(since)
        "stable"
      end

      def calculate_throughput_trend(since)
        "stable"
      end

      def calculate_error_rate_trend(since)
        "stable"
      end
    end
  end
end
