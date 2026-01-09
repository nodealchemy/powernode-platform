# frozen_string_literal: true

module System
  class HealthService
    include ActiveModel::Model

    HEALTH_THRESHOLDS = {
      memory_warning: 80,
      memory_critical: 90,
      disk_warning: 80,
      disk_critical: 90,
      cpu_warning: 70,
      cpu_critical: 85
    }.freeze

    class << self
      def check_basic_health
        {
          timestamp: Time.current.iso8601,
          overall_status: calculate_overall_status,
          components: {
            database: check_database_health,
            redis: check_redis_health,
            storage: check_storage_health,
            memory: check_memory_health,
            services: check_services_health
          },
          last_check: Rails.cache.read("system_health_last_check"),
          uptime: calculate_uptime
        }
      end

      def check_detailed_health
        basic_health = check_basic_health

        basic_health.merge({
          detailed_metrics: {
            database: get_database_metrics,
            performance: get_performance_metrics,
            network: get_network_metrics,
            security: get_security_metrics,
            background_jobs: get_background_job_metrics
          },
          recent_incidents: get_recent_incidents,
          system_resources: get_system_resources
        })
      end

      def trigger_comprehensive_check
        # Run comprehensive health check in background
        HealthCheckJob.perform_async("comprehensive")

        # Update last check timestamp
        Rails.cache.write("system_health_last_check", Time.current.iso8601, expires_in: 1.hour)
      end

      private

      def calculate_overall_status
        components = [
          check_database_health[:status],
          check_redis_health[:status],
          check_storage_health[:status],
          check_memory_health[:status],
          check_services_health[:status]
        ]

        if components.any? { |status| status == "critical" }
          "critical"
        elsif components.any? { |status| status == "warning" }
          "warning"
        else
          "healthy"
        end
      end

      def check_database_health
        start_time = Time.current

        begin
          # Test basic connectivity
          ActiveRecord::Base.connection.execute("SELECT 1")

          # Check connection pool
          pool_size = ActiveRecord::Base.connection_pool.size
          active_connections = ActiveRecord::Base.connection_pool.connections.count(&:in_use?)

          # Check for long-running queries
          long_queries = get_long_running_queries

          response_time = ((Time.current - start_time) * 1000).round(2)

          status = if response_time > 1000
                     "critical"
          elsif response_time > 500 || active_connections > (pool_size * 0.8)
                     "warning"
          else
                     "healthy"
          end

          {
            status: status,
            response_time: response_time,
            active_connections: active_connections,
            pool_size: pool_size,
            long_queries_count: long_queries.count,
            last_check: Time.current.iso8601
          }
        rescue => e
          Rails.logger.error "Database health check failed: #{e.message}"
          {
            status: "critical",
            error: e.message,
            last_check: Time.current.iso8601
          }
        end
      end

      def check_redis_health
        start_time = Time.current

        begin
          # Test Redis connectivity
          Rails.cache.write("health_check", "test", expires_in: 1.minute)
          test_value = Rails.cache.read("health_check")

          response_time = ((Time.current - start_time) * 1000).round(2)

          status = if test_value != "test"
                     "critical"
          elsif response_time > 100
                     "warning"
          else
                     "healthy"
          end

          {
            status: status,
            response_time: response_time,
            last_check: Time.current.iso8601
          }
        rescue => e
          Rails.logger.error "Redis health check failed: #{e.message}"
          {
            status: "critical",
            error: e.message,
            last_check: Time.current.iso8601
          }
        end
      end

      def check_storage_health
        begin
          disk_usage = get_disk_usage

          status = if disk_usage > HEALTH_THRESHOLDS[:disk_critical]
                     "critical"
          elsif disk_usage > HEALTH_THRESHOLDS[:disk_warning]
                     "warning"
          else
                     "healthy"
          end

          {
            status: status,
            disk_usage_percent: disk_usage,
            available_space: get_available_space,
            last_check: Time.current.iso8601
          }
        rescue => e
          Rails.logger.error "Storage health check failed: #{e.message}"
          {
            status: "critical",
            error: e.message,
            last_check: Time.current.iso8601
          }
        end
      end

      def check_memory_health
        begin
          memory_usage = get_memory_usage

          status = if memory_usage > HEALTH_THRESHOLDS[:memory_critical]
                     "critical"
          elsif memory_usage > HEALTH_THRESHOLDS[:memory_warning]
                     "warning"
          else
                     "healthy"
          end

          {
            status: status,
            memory_usage_percent: memory_usage,
            available_memory: get_available_memory,
            last_check: Time.current.iso8601
          }
        rescue => e
          Rails.logger.error "Memory health check failed: #{e.message}"
          {
            status: "critical",
            error: e.message,
            last_check: Time.current.iso8601
          }
        end
      end

      def check_services_health
        services = {
          web_server: check_web_server,
          background_jobs: check_background_jobs,
          worker_service: check_worker_service
        }

        statuses = services.values.map { |service| service[:status] }

        overall_status = if statuses.any? { |status| status == "critical" }
                           "critical"
        elsif statuses.any? { |status| status == "warning" }
                           "warning"
        else
                           "healthy"
        end

        {
          status: overall_status,
          services: services,
          last_check: Time.current.iso8601
        }
      end

      def get_database_metrics
        {
          total_connections: ActiveRecord::Base.connection_pool.size,
          active_connections: ActiveRecord::Base.connection_pool.connections.count(&:in_use?),
          database_size: get_database_size,
          table_count: get_table_count,
          index_usage: get_index_usage_stats
        }
      end

      def get_performance_metrics
        {
          average_response_time: get_average_response_time,
          throughput: get_request_throughput,
          error_rate: get_error_rate,
          cache_hit_ratio: get_cache_hit_ratio
        }
      end

      def get_network_metrics
        {
          inbound_traffic: get_network_stats("inbound"),
          outbound_traffic: get_network_stats("outbound"),
          connection_count: get_active_connections,
          latency: measure_network_latency
        }
      end

      def get_security_metrics
        {
          failed_login_attempts: get_failed_login_count,
          suspicious_activity: get_suspicious_activity_count,
          ssl_certificate_status: check_ssl_certificate,
          security_scan_results: get_latest_security_scan
        }
      end

      def get_background_job_metrics
        begin
          sidekiq_stats = Sidekiq::Stats.new

          {
            processed: sidekiq_stats.processed,
            failed: sidekiq_stats.failed,
            busy: sidekiq_stats.workers_size,
            enqueued: sidekiq_stats.enqueued,
            retry_count: sidekiq_stats.retry_size,
            dead_count: sidekiq_stats.dead_size,
            queues: get_queue_stats
          }
        rescue => e
          Rails.logger.error "Background job metrics failed: #{e.message}"
          { error: e.message }
        end
      end

      def get_recent_incidents
        # Get recent audit logs for incidents
        AuditLog.where(
          action: [ "system_error", "security_incident", "performance_issue" ],
          created_at: 24.hours.ago..Time.current
        ).order(created_at: :desc).limit(10).map do |log|
          {
            id: log.id,
            type: log.action,
            severity: log.details["severity"] || "medium",
            message: log.details["message"],
            timestamp: log.created_at.iso8601
          }
        end
      end

      def get_system_resources
        {
          cpu_usage: get_cpu_usage,
          memory_usage: get_memory_usage,
          disk_usage: get_disk_usage,
          load_average: get_load_average,
          process_count: get_process_count
        }
      end

      # Helper methods for system metrics
      def get_disk_usage
        # Simple disk usage check for Rails.root
        stat = File.statvfs(Rails.root.to_s)
        total_space = stat.blocks * stat.fragment_size
        free_space = stat.bavail * stat.fragment_size
        used_space = total_space - free_space

        (used_space.to_f / total_space * 100).round(2)
      rescue
        0
      end

      def get_available_space
        stat = File.statvfs(Rails.root.to_s)
        (stat.bavail * stat.fragment_size / 1024 / 1024).round(2) # MB
      rescue
        0
      end

      def get_memory_usage
        # Basic memory usage estimation
        if File.exist?("/proc/meminfo")
          meminfo = File.read("/proc/meminfo")
          total = meminfo.match(/MemTotal:\s+(\d+)/)[1].to_i
          available = meminfo.match(/MemAvailable:\s+(\d+)/)[1].to_i
          used = total - available
          (used.to_f / total * 100).round(2)
        else
          0
        end
      rescue
        0
      end

      def get_available_memory
        if File.exist?("/proc/meminfo")
          meminfo = File.read("/proc/meminfo")
          meminfo.match(/MemAvailable:\s+(\d+)/)[1].to_i / 1024 # MB
        else
          0
        end
      rescue
        0
      end

      def get_cpu_usage
        # Simplified CPU usage check
        if File.exist?("/proc/loadavg")
          load_avg = File.read("/proc/loadavg").split.first.to_f
          # Convert load average to percentage (approximate)
          (load_avg * 100 / `nproc`.to_i).round(2)
        else
          0
        end
      rescue
        0
      end

      def get_load_average
        File.read("/proc/loadavg").split[0..2].map(&:to_f) if File.exist?("/proc/loadavg")
      rescue
        [ 0, 0, 0 ]
      end

      def get_process_count
        Dir["/proc/[0-9]*"].count
      rescue
        0
      end

      def calculate_uptime
        if File.exist?("/proc/uptime")
          uptime_seconds = File.read("/proc/uptime").split.first.to_f
          {
            seconds: uptime_seconds.to_i,
            human: format_uptime(uptime_seconds)
          }
        else
          { seconds: 0, human: "Unknown" }
        end
      rescue
        { seconds: 0, human: "Unknown" }
      end

      def format_uptime(seconds)
        days = seconds / 86400
        hours = (seconds % 86400) / 3600
        minutes = (seconds % 3600) / 60

        "#{days.to_i}d #{hours.to_i}h #{minutes.to_i}m"
      end

      # Placeholder methods for complex metrics
      def get_long_running_queries
        []
      end

      def get_database_size
        0
      end

      def get_table_count
        ActiveRecord::Base.connection.tables.count
      rescue
        0
      end

      def get_index_usage_stats
        {}
      end

      def get_average_response_time
        0
      end

      def get_request_throughput
        0
      end

      def get_error_rate
        0
      end

      def get_cache_hit_ratio
        0
      end

      def get_network_stats(direction)
        0
      end

      def get_active_connections
        0
      end

      def measure_network_latency
        0
      end

      def get_failed_login_count
        AuditLog.where(
          action: "login_failed",
          created_at: 1.hour.ago..Time.current
        ).count
      rescue
        0
      end

      def get_suspicious_activity_count
        AuditLog.where(
          action: [ "suspicious_activity", "security_violation" ],
          created_at: 1.hour.ago..Time.current
        ).count
      rescue
        0
      end

      def check_ssl_certificate
        "valid"
      end

      def get_latest_security_scan
        {}
      end

      def get_queue_stats
        Sidekiq::Queue.all.map do |queue|
          {
            name: queue.name,
            size: queue.size,
            latency: queue.latency
          }
        end
      rescue
        []
      end

      def check_web_server
        {
          status: "healthy",
          pid: Process.pid,
          memory_usage: get_process_memory_usage
        }
      end

      def check_background_jobs
        begin
          stats = Sidekiq::Stats.new
          failed_jobs = stats.failed

          status = if failed_jobs > 100
                     "critical"
          elsif failed_jobs > 50
                     "warning"
          else
                     "healthy"
          end

          {
            status: status,
            workers: stats.workers_size,
            processed: stats.processed,
            failed: failed_jobs
          }
        rescue => e
          {
            status: "critical",
            error: e.message
          }
        end
      end

      def check_worker_service
        # Simple check if worker service is responding
        begin
          # This would normally make an HTTP request to worker service
          {
            status: "healthy",
            last_heartbeat: Time.current.iso8601
          }
        rescue => e
          {
            status: "critical",
            error: e.message
          }
        end
      end

      def get_process_memory_usage
        `ps -o rss= -p #{Process.pid}`.to_i / 1024 # MB
      rescue
        0
      end
    end
  end
end
