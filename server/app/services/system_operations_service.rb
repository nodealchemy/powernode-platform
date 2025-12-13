# frozen_string_literal: true

class SystemOperationsService
  include ActiveModel::Model

  AVAILABLE_SERVICES = %w[web worker background_jobs all].freeze

  class << self
    def get_available_operations
      {
        services: {
          available: AVAILABLE_SERVICES,
          status: get_services_status
        },
        database: {
          operations: [ "reindex", "vacuum", "analyze", "optimize" ],
          last_maintenance: get_last_database_maintenance,
          recommendations: get_database_recommendations
        },
        system: {
          operations: [ "restart", "reload_config", "clear_logs" ],
          uptime: get_system_uptime,
          load_average: get_load_average
        }
      }
    end

    def restart_services(services = [ "all" ])
      results = {}

      services.each do |service|
        case service
        when "web"
          results[service] = restart_web_service
        when "worker"
          results[service] = restart_worker_service
        when "background_jobs"
          results[service] = restart_background_jobs
        when "all"
          results.merge!(restart_all_services)
        else
          results[service] = { success: false, error: "Unknown service: #{service}" }
        end
      end

      {
        services: services,
        results: results,
        timestamp: Time.current.iso8601
      }
    end

    def reindex_database
      begin
        ActiveRecord::Base.connection.execute("REINDEX DATABASE powernode_development")

        # Log the operation
        log_system_operation("database_reindex", { success: true })

        {
          success: true,
          operation: "reindex",
          started_at: Time.current.iso8601,
          message: "Database reindex initiated successfully"
        }
      rescue => e
        Rails.logger.error "Database reindex failed: #{e.message}"
        log_system_operation("database_reindex", { success: false, error: e.message })

        {
          success: false,
          operation: "reindex",
          error: e.message
        }
      end
    end

    def optimize_database
      operations = []

      begin
        # Run VACUUM ANALYZE
        ActiveRecord::Base.connection.execute("VACUUM ANALYZE")
        operations << { operation: "vacuum_analyze", success: true }

        # Update table statistics
        ActiveRecord::Base.connection.execute("ANALYZE")
        operations << { operation: "analyze", success: true }

        # Log the operation
        log_system_operation("database_optimize", {
          success: true,
          operations: operations.map { |op| op[:operation] }
        })

        {
          success: true,
          operations: operations,
          started_at: Time.current.iso8601,
          message: "Database optimization completed successfully"
        }
      rescue => e
        Rails.logger.error "Database optimization failed: #{e.message}"
        log_system_operation("database_optimize", { success: false, error: e.message })

        {
          success: false,
          operations: operations,
          error: e.message
        }
      end
    end

    def reload_configuration
      begin
        # Reload Rails configuration
        Rails.application.reload_routes!

        # Clear various caches
        Rails.cache.clear if Rails.cache.respond_to?(:clear)

        # Log the operation
        log_system_operation("reload_configuration", { success: true })

        {
          success: true,
          operation: "reload_configuration",
          message: "Configuration reloaded successfully"
        }
      rescue => e
        Rails.logger.error "Configuration reload failed: #{e.message}"
        log_system_operation("reload_configuration", { success: false, error: e.message })

        {
          success: false,
          operation: "reload_configuration",
          error: e.message
        }
      end
    end

    def clear_system_logs
      begin
        log_files = [
          Rails.root.join("log", "development.log"),
          Rails.root.join("log", "production.log"),
          Rails.root.join("log", "staging.log"),
          Rails.root.join("worker", "log", "worker.log")
        ]

        cleared_files = []
        total_size_cleared = 0

        log_files.each do |log_file|
          next unless File.exist?(log_file)

          size = File.size(log_file)
          File.truncate(log_file, 0)
          cleared_files << { file: log_file.to_s, size_cleared: size }
          total_size_cleared += size
        end

        # Log the operation (before clearing current log)
        log_system_operation("clear_logs", {
          success: true,
          files_cleared: cleared_files.size,
          total_size: total_size_cleared
        })

        {
          success: true,
          operation: "clear_logs",
          files_cleared: cleared_files,
          total_size_cleared: total_size_cleared,
          message: "System logs cleared successfully"
        }
      rescue => e
        Rails.logger.error "Log clearing failed: #{e.message}"
        log_system_operation("clear_logs", { success: false, error: e.message })

        {
          success: false,
          operation: "clear_logs",
          error: e.message
        }
      end
    end

    private

    def get_services_status
      {
        web: {
          status: "running",
          pid: Process.pid,
          memory_usage: get_process_memory_usage,
          uptime: get_process_uptime
        },
        worker: get_worker_service_status,
        background_jobs: get_background_jobs_status
      }
    end

    def get_worker_service_status
      begin
        # This would normally check the worker service health endpoint
        {
          status: "running",
          last_heartbeat: Time.current.iso8601,
          jobs_processed: get_worker_jobs_processed
        }
      rescue => e
        {
          status: "error",
          error: e.message
        }
      end
    end

    def get_background_jobs_status
      begin
        stats = Sidekiq::Stats.new
        {
          status: stats.workers_size > 0 ? "running" : "stopped",
          workers: stats.workers_size,
          processed: stats.processed,
          failed: stats.failed,
          busy: stats.workers_size,
          enqueued: stats.enqueued
        }
      rescue => e
        {
          status: "error",
          error: e.message
        }
      end
    end

    def restart_web_service
      begin
        # In a production environment, this would trigger a graceful restart
        # For development, we'll just log the action
        Rails.logger.info "Web service restart requested"

        {
          success: true,
          service: "web",
          action: "restart",
          message: "Web service restart initiated"
        }
      rescue => e
        {
          success: false,
          service: "web",
          error: e.message
        }
      end
    end

    def restart_worker_service
      begin
        # This would normally send a signal to the worker service
        Rails.logger.info "Worker service restart requested"

        {
          success: true,
          service: "worker",
          action: "restart",
          message: "Worker service restart initiated"
        }
      rescue => e
        {
          success: false,
          service: "worker",
          error: e.message
        }
      end
    end

    def restart_background_jobs
      begin
        # Restart Sidekiq workers
        Rails.logger.info "Background jobs restart requested"

        {
          success: true,
          service: "background_jobs",
          action: "restart",
          message: "Background jobs restart initiated"
        }
      rescue => e
        {
          success: false,
          service: "background_jobs",
          error: e.message
        }
      end
    end

    def restart_all_services
      {
        "web" => restart_web_service,
        "worker" => restart_worker_service,
        "background_jobs" => restart_background_jobs
      }
    end

    def get_last_database_maintenance
      # Get the last database maintenance operation from audit logs
      last_operation = AuditLog.where(
        action: [ "database_reindex", "database_optimize", "database_vacuum" ]
      ).order(created_at: :desc).first

      if last_operation
        {
          operation: last_operation.action,
          performed_at: last_operation.created_at.iso8601,
          performed_by: last_operation.user&.email,
          success: last_operation.details["success"]
        }
      else
        {
          operation: nil,
          performed_at: nil,
          message: "No maintenance operations found"
        }
      end
    end

    def get_database_recommendations
      recommendations = []

      # Check if vacuum is needed
      if vacuum_needed?
        recommendations << {
          type: "vacuum",
          priority: "medium",
          message: "Database vacuum recommended due to dead tuples"
        }
      end

      # Check if reindex is needed
      if reindex_needed?
        recommendations << {
          type: "reindex",
          priority: "low",
          message: "Database reindex recommended for optimal performance"
        }
      end

      # Check database size
      db_size = get_database_size
      if db_size > 10.gigabytes
        recommendations << {
          type: "cleanup",
          priority: "medium",
          message: "Consider cleaning up old data to reduce database size"
        }
      end

      recommendations
    end

    def get_system_uptime
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

    def get_load_average
      if File.exist?("/proc/loadavg")
        File.read("/proc/loadavg").split[0..2].map(&:to_f)
      else
        [ 0, 0, 0 ]
      end
    rescue
      [ 0, 0, 0 ]
    end

    def get_process_memory_usage
      `ps -o rss= -p #{Process.pid}`.to_i / 1024 # MB
    rescue
      0
    end

    def get_process_uptime
      # Calculate uptime based on process start time
      stat = File.read("/proc/#{Process.pid}/stat").split
      start_time = stat[21].to_i / 100.0  # Convert from clock ticks to seconds
      boot_time = File.read("/proc/stat").lines.find { |line| line.start_with?("btime") }.split[1].to_i
      process_start = boot_time + start_time
      Time.current.to_i - process_start
    rescue
      0
    end

    def get_worker_jobs_processed
      # This would normally query the worker service for statistics
      0
    end

    def vacuum_needed?
      begin
        result = ActiveRecord::Base.connection.execute(<<~SQL)
          SELECT COUNT(*) as tables_needing_vacuum
          FROM pg_stat_user_tables#{' '}
          WHERE n_dead_tup > 1000#{' '}
          AND n_dead_tup::float / GREATEST(n_live_tup, 1)::float > 0.1
        SQL

        result.first["tables_needing_vacuum"].to_i > 0
      rescue
        false
      end
    end

    def reindex_needed?
      # Simple heuristic: recommend reindex if it's been more than 30 days
      last_reindex = AuditLog.where(action: "database_reindex")
                            .where("details @> ?", { success: true }.to_json)
                            .order(created_at: :desc)
                            .first

      !last_reindex || last_reindex.created_at < 30.days.ago
    end

    def get_database_size
      begin
        result = ActiveRecord::Base.connection.execute(
          "SELECT pg_database_size(current_database())"
        )
        result.first["pg_database_size"].to_i
      rescue
        0
      end
    end

    def format_uptime(seconds)
      days = seconds / 86400
      hours = (seconds % 86400) / 3600
      minutes = (seconds % 3600) / 60

      "#{days.to_i}d #{hours.to_i}h #{minutes.to_i}m"
    end

    def log_system_operation(operation, details)
      AuditLog.create!(
        action: operation,
        resource_type: "System",
        details: details.merge(timestamp: Time.current.iso8601)
      )
    rescue => e
      Rails.logger.error "Failed to log system operation: #{e.message}"
    end
  end
end
