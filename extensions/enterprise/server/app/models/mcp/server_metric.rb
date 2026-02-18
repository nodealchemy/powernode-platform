# frozen_string_literal: true

# MCP Server Metric Model - Time-series metrics for hosted servers
#
# Stores time-series metrics for performance monitoring and cost tracking.
#
module Mcp
  class ServerMetric < ApplicationRecord
    self.table_name = "mcp_server_metrics"

    # Associations
    belongs_to :hosted_server, class_name: "Mcp::HostedServer"

    # Validations
    validates :recorded_at, presence: true
    validates :granularity, presence: true, inclusion: {
      in: %w[minute hour day week month]
    }

    # Scopes
    scope :for_server, ->(server) { where(hosted_server: server) }
    scope :for_period, ->(start_time, end_time) {
      where(recorded_at: start_time..end_time)
    }
    scope :by_granularity, ->(granularity) { where(granularity: granularity) }
    scope :recent, ->(period = 24.hours) { where("recorded_at >= ?", period.ago) }
    scope :ordered_by_time, -> { order(recorded_at: :desc) }

    # Class methods
    class << self
      def aggregate_for_period(server_id, start_time, end_time)
        metrics = where(hosted_server_id: server_id)
                  .for_period(start_time, end_time)

        return nil if metrics.empty?

        {
          total_requests: metrics.sum(:total_requests),
          successful_requests: metrics.sum(:successful_requests),
          failed_requests: metrics.sum(:failed_requests),
          timeout_requests: metrics.sum(:timeout_requests),
          avg_latency_ms: metrics.average(:avg_latency_ms)&.round(2),
          p95_latency_ms: metrics.maximum(:p95_latency_ms),
          total_cost_usd: metrics.sum(:total_cost_usd)
        }
      end

      def record_metric(hosted_server:, granularity: "minute")
        # This would be called by a background job to aggregate metrics
        create!(
          hosted_server: hosted_server,
          recorded_at: Time.current,
          granularity: granularity
        )
      end
    end

    # Instance methods
    def success_rate
      return 0 if total_requests.zero?
      (successful_requests.to_f / total_requests * 100).round(2)
    end

    def error_rate
      return 0 if total_requests.zero?
      (failed_requests.to_f / total_requests * 100).round(2)
    end

    def summary
      {
        id: id,
        recorded_at: recorded_at,
        granularity: granularity,
        requests: {
          total: total_requests,
          successful: successful_requests,
          failed: failed_requests,
          timeout: timeout_requests,
          success_rate: success_rate
        },
        latency: {
          avg_ms: avg_latency_ms&.to_f,
          p50_ms: p50_latency_ms&.to_f,
          p95_ms: p95_latency_ms&.to_f,
          p99_ms: p99_latency_ms&.to_f
        },
        resources: {
          active_instances: active_instances,
          cpu_usage_percent: cpu_usage_percent&.to_f,
          memory_usage_percent: memory_usage_percent&.to_f
        },
        cost: {
          compute_usd: compute_cost_usd&.to_f,
          bandwidth_usd: bandwidth_cost_usd&.to_f,
          total_usd: total_cost_usd&.to_f
        }
      }
    end
  end
end
