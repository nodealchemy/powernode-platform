# frozen_string_literal: true

module Api
  module V1
    class WorkerHealthController < ApplicationController
      # GET /api/v1/workers/health
      def index
        health_data = {
          timestamp: Time.current.iso8601,
          worker_status: check_worker_status,
          sidekiq_stats: collect_sidekiq_stats,
          error_tracking: collect_error_tracking_stats,
          circuit_breaker_status: collect_circuit_breaker_status,
          recent_job_activity: collect_recent_job_activity,
          system_metrics: collect_worker_system_metrics
        }

        render json: {
          success: true,
          data: health_data
        }
      rescue StandardError => e
        PowernodeWorker.application.logger.error "Worker health check failed: #{e.message}"

        render json: {
          success: false,
          error: 'Worker health check failed',
          data: {
            timestamp: Time.current.iso8601,
            worker_status: 'unknown'
          }
        }, status: 500
      end

      private

      def check_worker_status
        # Check if worker processes are running
        begin
          stats = Sidekiq::Stats.new
          {
            status: 'healthy',
            processes: stats.processes_size,
            queues: stats.queues.keys.size,
            total_jobs: stats.processed + stats.failed,
            uptime: calculate_worker_uptime
          }
        rescue StandardError => e
          {
            status: 'unhealthy',
            error: e.message
          }
        end
      end

      def collect_sidekiq_stats
        begin
          stats = Sidekiq::Stats.new
          {
            processed: stats.processed,
            failed: stats.failed,
            busy: stats.processed - stats.failed,
            enqueued: stats.enqueued,
            scheduled: stats.scheduled_size,
            retry_size: stats.retry_size,
            dead_size: stats.dead_size,
            processes: stats.processes_size,
            default_queue_latency: stats.default_queue_latency,
            queues: collect_queue_stats(stats)
          }
        rescue StandardError => e
          { error: e.message }
        end
      end

      def collect_error_tracking_stats
        begin
          error_service = AiWorkflowErrorTrackingService.instance
          {
            recent_errors: error_service.analyze_errors(since: 1.hour.ago),
            system_health: error_service.system_health_status,
            error_patterns: error_service.error_patterns(limit: 5),
            critical_errors_count: error_service.critical_errors(since: 1.hour.ago).size
          }
        rescue StandardError => e
          { error: e.message }
        end
      end

      def collect_circuit_breaker_status
        begin
          # Access circuit breaker registry through a dummy service that includes the concern
          dummy_service = Class.new do
            include CircuitBreaker
          end.new

          {
            breakers: dummy_service.circuit_breaker_status,
            summary: summarize_circuit_breaker_status(dummy_service.circuit_breaker_status)
          }
        rescue StandardError => e
          { error: e.message }
        end
      end

      def collect_recent_job_activity
        begin
          stats = Sidekiq::Stats.new
          history = Sidekiq::Stats::History.new(1) # last 1 day

          {
            jobs_processed_today: history.processed.values.sum,
            jobs_failed_today: history.failed.values.sum,
            current_queue_sizes: collect_current_queue_sizes,
            busy_workers: stats.workers_size,
            longest_job_duration: find_longest_running_job
          }
        rescue StandardError => e
          { error: e.message }
        end
      end

      def collect_worker_system_metrics
        {
          memory_usage: collect_memory_metrics,
          cpu_usage: collect_cpu_metrics,
          connection_pool: collect_connection_pool_metrics,
          load_average: collect_load_metrics
        }
      end

      def calculate_worker_uptime
        # Estimate uptime based on oldest running process
        begin
          processes = Sidekiq::ProcessSet.new
          return 0 if processes.empty?

          oldest_process = processes.min_by { |p| p['started_at'] }
          Time.current - Time.parse(oldest_process['started_at'])
        rescue StandardError
          0
        end
      end

      def collect_queue_stats(stats)
        stats.queues.map do |name, size|
          {
            name: name,
            size: size,
            latency: begin
              Sidekiq::Queue.new(name).latency
            rescue StandardError
              0
            end
          }
        end
      end

      def summarize_circuit_breaker_status(breaker_status)
        return { healthy: 0, failing: 0, testing: 0 } if breaker_status.empty?

        summary = { healthy: 0, failing: 0, testing: 0 }

        breaker_status.each_value do |status|
          case status[:state]
          when :closed
            summary[:healthy] += 1
          when :open
            summary[:failing] += 1
          when :half_open
            summary[:testing] += 1
          end
        end

        summary
      end

      def collect_current_queue_sizes
        begin
          Sidekiq::Stats.new.queues
        rescue StandardError
          {}
        end
      end

      def find_longest_running_job
        begin
          workers = Sidekiq::Workers.new
          return 0 if workers.empty?

          longest_duration = workers.map do |_process_id, _thread_id, work|
            Time.current - Time.parse(work['run_at'])
          end.max

          longest_duration || 0
        rescue StandardError
          0
        end
      end

      def collect_memory_metrics
        begin
          # Basic memory metrics - could be enhanced with more detailed system info
          {
            estimated_usage: 'not_available',
            note: 'Detailed memory metrics require system monitoring tools'
          }
        rescue StandardError
          { error: 'Unable to collect memory metrics' }
        end
      end

      def collect_cpu_metrics
        begin
          {
            estimated_usage: 'not_available',
            note: 'Detailed CPU metrics require system monitoring tools'
          }
        rescue StandardError
          { error: 'Unable to collect CPU metrics' }
        end
      end

      def collect_connection_pool_metrics
        begin
          # Database connection pool metrics
          pool = ActiveRecord::Base.connection_pool
          {
            size: pool.size,
            connections: pool.connections.size,
            available: pool.available_connections.size,
            busy: pool.connections.size - pool.available_connections.size
          }
        rescue StandardError => e
          { error: e.message }
        end
      end

      def collect_load_metrics
        begin
          {
            note: 'Load metrics require system monitoring integration'
          }
        rescue StandardError
          { error: 'Unable to collect load metrics' }
        end
      end
    end
  end
end