# frozen_string_literal: true

# Health check controller for monitoring and load balancer health checks
# Provides basic and detailed health status for all system components
module Api
  module V1
    class HealthController < ApplicationController
      skip_before_action :authenticate_request

      # GET /api/v1/health - Basic health check (for load balancers)
      def index
        render_success({
          status: "healthy",
          timestamp: Time.current.iso8601,
          uptime_seconds: uptime_seconds,
          version: app_version
        })
      end

      # GET /api/v1/health/detailed - Detailed health check with component status
      def detailed
        checks = perform_health_checks

        overall_status = checks.values.all? { |c| c[:status] == "healthy" } ? "healthy" : "degraded"

        render_success({
          status: overall_status,
          timestamp: Time.current.iso8601,
          uptime_seconds: uptime_seconds,
          version: app_version,
          checks: checks
        })
      end

      # GET /api/v1/health/ready - Readiness probe (for Kubernetes)
      def ready
        if database_healthy? && redis_healthy?
          render_success({ ready: true })
        else
          render_error("Service not ready", status: :service_unavailable)
        end
      end

      # GET /api/v1/health/live - Liveness probe (for Kubernetes)
      def live
        render_success({ live: true })
      end

      private

      def perform_health_checks
        {
          database: check_database,
          redis: check_redis,
          memory: check_memory,
          disk: check_disk
        }
      end

      def check_database
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecord::Base.connection.execute("SELECT 1")
        response_time = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        {
          status: "healthy",
          response_time_ms: response_time,
          pool_size: ActiveRecord::Base.connection_pool.size,
          connections_in_use: ActiveRecord::Base.connection_pool.connections.count(&:in_use?)
        }
      rescue StandardError => e
        { status: "unhealthy", error: e.message }
      end

      def check_redis
        return { status: "skipped", message: "Redis not configured" } unless redis_configured?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Redis.new(url: ENV["REDIS_URL"]).ping
        response_time = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        { status: "healthy", response_time_ms: response_time }
      rescue StandardError => e
        { status: "unhealthy", error: e.message }
      end

      def check_memory
        memory_info = memory_usage

        {
          status: memory_info[:used_percent] < 90 ? "healthy" : "warning",
          used_mb: memory_info[:used_mb],
          used_percent: memory_info[:used_percent]
        }
      rescue StandardError => e
        { status: "unknown", error: e.message }
      end

      def check_disk
        disk_info = disk_usage

        {
          status: disk_info[:used_percent] < 90 ? "healthy" : "warning",
          used_percent: disk_info[:used_percent],
          available_gb: disk_info[:available_gb]
        }
      rescue StandardError => e
        { status: "unknown", error: e.message }
      end

      def database_healthy?
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue StandardError
        false
      end

      def redis_healthy?
        return true unless redis_configured?

        Redis.new(url: ENV["REDIS_URL"]).ping == "PONG"
      rescue StandardError
        false
      end

      def redis_configured?
        ENV["REDIS_URL"].present?
      end

      def uptime_seconds
        boot_time = Rails.application.config.respond_to?(:boot_time) ? Rails.application.config.boot_time : Time.current
        (Time.current - boot_time).round
      end

      def app_version
        ENV.fetch("APP_VERSION") { "unknown" }
      end

      def memory_usage
        if File.exist?("/proc/meminfo")
          meminfo = File.read("/proc/meminfo")
          total = meminfo[/MemTotal:\s+(\d+)/, 1].to_i / 1024
          available = meminfo[/MemAvailable:\s+(\d+)/, 1].to_i / 1024
          used = total - available
          { used_mb: used, used_percent: ((used.to_f / total) * 100).round(1) }
        else
          { used_mb: 0, used_percent: 0 }
        end
      end

      def disk_usage
        if File.exist?("/")
          stat = Sys::Filesystem.stat("/") rescue nil
          return { used_percent: 0, available_gb: 0 } unless stat

          total = stat.blocks * stat.block_size
          available = stat.blocks_available * stat.block_size
          used_percent = (((total - available).to_f / total) * 100).round(1)
          available_gb = (available / 1024.0 / 1024.0 / 1024.0).round(2)

          { used_percent: used_percent, available_gb: available_gb }
        else
          { used_percent: 0, available_gb: 0 }
        end
      rescue StandardError
        { used_percent: 0, available_gb: 0 }
      end
    end
  end
end
