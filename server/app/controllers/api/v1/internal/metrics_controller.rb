# frozen_string_literal: true

module Api
  module V1
    module Internal
      class MetricsController < InternalBaseController
        before_action :require_internal_access

        # GET /api/v1/internal/metrics/jobs
        def jobs
          stats = {
            queues: fetch_queue_stats,
            processed: fetch_processed_stats,
            failed: fetch_failed_stats,
            scheduled: fetch_scheduled_stats,
            workers: fetch_worker_stats
          }

          render_success({ job_metrics: stats })
        end

        # GET /api/v1/internal/metrics/errors
        def errors
          time_range = params[:range] || "24h"
          since = parse_time_range(time_range)

          errors = SystemError.where("created_at >= ?", since)
                              .group(:error_class)
                              .count

          error_details = SystemError.where("created_at >= ?", since)
                                     .order(created_at: :desc)
                                     .limit(100)
                                     .map do |error|
            {
              id: error.id,
              error_class: error.error_class,
              message: error.message&.truncate(200),
              source: error.source,
              severity: error.severity,
              occurred_at: error.created_at.iso8601,
              resolved: error.resolved
            }
          end

          render_success({
            error_metrics: {
              total_count: errors.values.sum,
              by_class: errors,
              time_range: time_range,
              recent_errors: error_details
            }
          })
        end

        # GET /api/v1/internal/metrics/custom
        def custom
          metric_names = params[:metrics]&.split(",") || []

          if metric_names.empty?
            return render_error("metrics parameter is required", status: :unprocessable_entity)
          end

          time_range = params[:range] || "1h"
          since = parse_time_range(time_range)
          interval = params[:interval] || "5m"

          metrics = {}
          metric_names.each do |name|
            metrics[name] = fetch_custom_metric(name, since, interval)
          end

          render_success({
            custom_metrics: metrics,
            time_range: time_range,
            interval: interval
          })
        end

        private

        def fetch_queue_stats
          queues = {}

          # Get stats from Sidekiq or similar job processor
          if defined?(Sidekiq)
            Sidekiq::Queue.all.each do |queue|
              queues[queue.name] = {
                size: queue.size,
                latency: queue.latency.round(2)
              }
            end
          end

          queues
        end

        def fetch_processed_stats
          if defined?(Sidekiq)
            stats = Sidekiq::Stats.new
            {
              total: stats.processed,
              today: stats.processed - (stats.processed_at_midnight || 0),
              success_rate: calculate_success_rate(stats)
            }
          else
            { total: 0, today: 0, success_rate: 100.0 }
          end
        end

        def fetch_failed_stats
          if defined?(Sidekiq)
            stats = Sidekiq::Stats.new
            retry_set = Sidekiq::RetrySet.new
            dead_set = Sidekiq::DeadSet.new

            {
              total: stats.failed,
              today: stats.failed - (stats.failed_at_midnight || 0),
              retry_queue: retry_set.size,
              dead_queue: dead_set.size
            }
          else
            { total: 0, today: 0, retry_queue: 0, dead_queue: 0 }
          end
        end

        def fetch_scheduled_stats
          if defined?(Sidekiq)
            scheduled = Sidekiq::ScheduledSet.new
            {
              count: scheduled.size,
              next_job_at: scheduled.first&.at&.iso8601
            }
          else
            { count: 0, next_job_at: nil }
          end
        end

        def fetch_worker_stats
          if defined?(Sidekiq)
            workers = Sidekiq::Workers.new
            {
              active: workers.size,
              processes: Sidekiq::ProcessSet.new.size
            }
          else
            { active: 0, processes: 0 }
          end
        end

        def fetch_custom_metric(name, since, interval)
          case name
          when "response_time"
            fetch_response_time_metric(since, interval)
          when "request_count"
            fetch_request_count_metric(since, interval)
          when "error_rate"
            fetch_error_rate_metric(since, interval)
          when "memory_usage"
            fetch_memory_usage_metric
          when "cpu_usage"
            fetch_cpu_usage_metric
          else
            { error: "Unknown metric: #{name}" }
          end
        end

        def fetch_response_time_metric(since, interval)
          # Aggregate from request logs or APM data
          data_points = RequestMetric.where("created_at >= ?", since)
                                     .group_by_period(interval, :created_at)
                                     .average(:duration_ms)

          {
            current: RequestMetric.where("created_at >= ?", 1.minute.ago).average(:duration_ms)&.round(2),
            average: RequestMetric.where("created_at >= ?", since).average(:duration_ms)&.round(2),
            p95: calculate_percentile(RequestMetric.where("created_at >= ?", since).pluck(:duration_ms), 95),
            p99: calculate_percentile(RequestMetric.where("created_at >= ?", since).pluck(:duration_ms), 99),
            data_points: data_points
          }
        rescue
          { current: nil, average: nil, p95: nil, p99: nil, data_points: {} }
        end

        def fetch_request_count_metric(since, interval)
          data_points = RequestMetric.where("created_at >= ?", since)
                                     .group_by_period(interval, :created_at)
                                     .count

          {
            total: RequestMetric.where("created_at >= ?", since).count,
            rate_per_minute: RequestMetric.where("created_at >= ?", 1.minute.ago).count,
            data_points: data_points
          }
        rescue
          { total: 0, rate_per_minute: 0, data_points: {} }
        end

        def fetch_error_rate_metric(since, interval)
          total = RequestMetric.where("created_at >= ?", since).count
          errors = RequestMetric.where("created_at >= ?", since).where("status_code >= 500").count

          {
            rate: total > 0 ? ((errors.to_f / total) * 100).round(2) : 0,
            error_count: errors,
            total_requests: total
          }
        rescue
          { rate: 0, error_count: 0, total_requests: 0 }
        end

        def fetch_memory_usage_metric
          memory_info = `cat /proc/meminfo 2>/dev/null`.lines.map { |l| l.strip.split(/:\s+/) }.to_h rescue {}

          if memory_info.any?
            total = memory_info["MemTotal"]&.to_i || 0
            available = memory_info["MemAvailable"]&.to_i || 0
            used = total - available

            {
              total_kb: total,
              used_kb: used,
              available_kb: available,
              usage_percent: total > 0 ? ((used.to_f / total) * 100).round(2) : 0
            }
          else
            { total_kb: 0, used_kb: 0, available_kb: 0, usage_percent: 0 }
          end
        end

        def fetch_cpu_usage_metric
          load_avg = `cat /proc/loadavg 2>/dev/null`.strip.split rescue []
          cpu_count = `nproc 2>/dev/null`.to_i rescue 1
          cpu_count = 1 if cpu_count < 1

          {
            load_1m: load_avg[0]&.to_f || 0,
            load_5m: load_avg[1]&.to_f || 0,
            load_15m: load_avg[2]&.to_f || 0,
            cpu_count: cpu_count,
            normalized_load: ((load_avg[0]&.to_f || 0) / cpu_count * 100).round(2)
          }
        end

        def parse_time_range(range)
          case range
          when "1h" then 1.hour.ago
          when "6h" then 6.hours.ago
          when "24h" then 24.hours.ago
          when "7d" then 7.days.ago
          when "30d" then 30.days.ago
          else 24.hours.ago
          end
        end

        def calculate_success_rate(stats)
          total = stats.processed + stats.failed
          return 100.0 if total == 0
          ((stats.processed.to_f / total) * 100).round(2)
        end

        def calculate_percentile(values, percentile)
          return nil if values.empty?
          sorted = values.compact.sort
          k = (percentile / 100.0 * (sorted.length - 1)).ceil
          sorted[k]&.round(2)
        end
      end
    end
  end
end
