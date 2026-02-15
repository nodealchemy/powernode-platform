# frozen_string_literal: true

module Ai
  module Analytics
    class PerformanceAnalysisService
      module BottleneckIdentification
        extend ActiveSupport::Concern

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
end
