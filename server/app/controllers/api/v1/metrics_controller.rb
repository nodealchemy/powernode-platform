# frozen_string_literal: true

module Api
  module V1
    class MetricsController < ApplicationController
      skip_before_action :authenticate_request, only: [ :health, :prometheus ]

      # Prometheus metrics endpoint - DISABLED
      def prometheus
        render_error("Prometheus metrics disabled in development", status: :service_unavailable)
      end

      # Health check with basic metrics
      def health
        health_data = {
          status: "healthy",
          timestamp: Time.current.iso8601,
          version: Rails.application.class.module_parent_name,
          uptime: uptime_seconds,
          database: database_health,
          redis: redis_health,
          memory: memory_usage,
          business_metrics: business_health_metrics
        }

        render_success(health_data)
      rescue StandardError => e
        Rails.logger.error "Health check error: #{e.message}"
        render_error("Health check failed", status: :service_unavailable)
      end

      # Detailed application metrics (authenticated)
      def application
        require_permission("analytics.read")

        metrics = {
          users: user_metrics,
          subscriptions: subscription_metrics,
          payments: payment_metrics,
          api: api_metrics,
          background_jobs: job_metrics,
          system: system_metrics
        }

        render_success(metrics)
      rescue StandardError => e
        Rails.logger.error "Application metrics error: #{e.message}"
        render_error("Failed to retrieve metrics")
      end

      private

      def uptime_seconds
        Time.current - Rails.application.config.start_time
      rescue StandardError => e
        Rails.logger.error "Failed to calculate uptime: #{e.message}"
        0
      end

      def database_health
        start_time = Time.current
        ActiveRecord::Base.connection.execute("SELECT 1")
        {
          status: "healthy",
          response_time_ms: ((Time.current - start_time) * 1000).round(2)
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
      end

      def redis_health
        start_time = Time.current
        Rails.cache.write("health_check", Time.current.to_i, expires_in: 10.seconds)
        Rails.cache.read("health_check")

        {
          status: "healthy",
          response_time_ms: ((Time.current - start_time) * 1000).round(2)
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
      end

      def memory_usage
        if defined?(GC.stat)
          {
            heap_live_slots: GC.stat[:heap_live_slots],
            heap_free_slots: GC.stat[:heap_free_slots],
            total_allocated_pages: GC.stat[:total_allocated_pages],
            gc_count: GC.count
          }
        else
          { available: false }
        end
      rescue StandardError => e
        Rails.logger.error "Failed to fetch memory usage: #{e.message}"
        { available: false }
      end

      def business_health_metrics
        {
          total_users: User.count,
          active_subscriptions: subscription_class&.active&.count || 0,
          total_revenue_cents: (subscription_class&.active&.joins(:plan)&.sum("plans.price")) || 0,
          successful_payments_today: defined?(Billing::Payment) ? Billing::Payment.successful.where("created_at >= ?", 1.day.ago).count : 0
        }
      rescue StandardError => e
        Rails.logger.error "Business metrics error: #{e.message}"
        { error: "Unable to retrieve business metrics" }
      end

      def user_metrics
        {
          total: User.count,
          active: User.where(status: "active").count,
          inactive: User.where(status: "inactive").count,
          created_today: User.where("created_at >= ?", 1.day.ago).count,
          created_this_week: User.where("created_at >= ?", 1.week.ago).count,
          created_this_month: User.where("created_at >= ?", 1.month.ago).count,
          by_role: User.joins(:roles).group("roles.name").count
        }
      end

      def subscription_metrics
        {
          subscriptions: if subscription_class
            {
              total: subscription_class.count,
              active: subscription_class.active.count,
              cancelled: subscription_class.cancelled.count,
              expired: subscription_class.expired.count,
              trial: subscription_class.trial.count,
              by_plan: subscription_class.joins(:plan).group("plans.name").count,
              monthly_revenue_cents: subscription_class.active.joins(:plan).sum("plans.price"),
              mrr: (subscription_class.active.joins(:plan).sum("plans.price") / 100.0).round(2),
              new_this_month: subscription_class.where("created_at >= ?", 1.month.ago).count
            }
          else
            { total: 0, active: 0, cancelled: 0, expired: 0, trial: 0, by_plan: {}, monthly_revenue_cents: 0, mrr: 0, new_this_month: 0 }
          end,
          churn_rate_percent: calculate_churn_rate
        }
      end

      def payment_metrics
        return { total: 0, successful: 0, failed: 0, pending: 0, total_amount_cents: 0, today: 0, this_week: 0, this_month: 0, by_provider: {}, average_amount_cents: 0 } unless defined?(Billing::Payment)
        {
          total: Billing::Payment.count,
          successful: Billing::Payment.successful.count,
          failed: Billing::Payment.failed.count,
          pending: Billing::Payment.pending.count,
          total_amount_cents: Billing::Payment.successful.sum(:amount_cents),
          today: Billing::Payment.where("created_at >= ?", 1.day.ago).count,
          this_week: Billing::Payment.where("created_at >= ?", 1.week.ago).count,
          this_month: Billing::Payment.where("created_at >= ?", 1.month.ago).count,
          by_provider: Billing::Payment.group(:provider).count,
          average_amount_cents: Billing::Payment.successful.average(:amount_cents)&.round
        }
      end

      def api_metrics
        {
          total_requests_today: AuditLog.where("created_at >= ?", 1.day.ago).count,
          total_requests_this_week: AuditLog.where("created_at >= ?", 1.week.ago).count,
          total_requests_this_month: AuditLog.where("created_at >= ?", 1.month.ago).count,
          requests_by_action: AuditLog.where("created_at >= ?", 1.day.ago).group(:action).count,
          error_count_today: AuditLog.where("created_at >= ? AND action LIKE ?", 1.day.ago, "%error%").count
        }
      rescue StandardError => e
        Rails.logger.error "Failed to fetch API metrics: #{e.message}"
        { error: "Unable to retrieve API metrics" }
      end

      def job_metrics
        redis = Redis.new(url: ENV.fetch("WORKER_REDIS_URL", "redis://localhost:6379/1"))
        stats = {
          processed: redis.get("stat:processed").to_i,
          failed: redis.get("stat:failed").to_i,
          scheduled_size: redis.zcard("schedule"),
          retry_size: redis.zcard("retry"),
          dead_size: redis.zcard("dead"),
          queues: fetch_queue_sizes(redis)
        }
        redis.close
        stats
      rescue StandardError => e
        Rails.logger.error "Failed to fetch job metrics: #{e.message}"
        { error: "Unable to connect to job queue" }
      end

      def fetch_queue_sizes(redis)
        queues = redis.smembers("queues")
        queues.each_with_object({}) do |queue, sizes|
          sizes[queue] = redis.llen("queue:#{queue}")
        end
      rescue StandardError
        {}
      end

      def system_metrics
        {
          rails_version: Rails.version,
          ruby_version: RUBY_VERSION,
          environment: Rails.env,
          database_size: calculate_database_size,
          cache_stats: Rails.cache.respond_to?(:stats) ? Rails.cache.stats : "not_available"
        }
      end

      def calculate_churn_rate
        return 0.0 unless subscription_class

        current_month_start = Date.current.beginning_of_month
        last_month_start = 1.month.ago.beginning_of_month
        last_month_end = 1.month.ago.end_of_month

        active_last_month = subscription_class.where(
          "created_at <= ? AND (cancelled_at IS NULL OR cancelled_at > ?)",
          last_month_end, last_month_end
        ).count

        cancelled_last_month = subscription_class.where(
          cancelled_at: last_month_start..last_month_end
        ).count

        return 0 if active_last_month.zero?

        ((cancelled_last_month.to_f / active_last_month) * 100).round(2)
      rescue StandardError => e
        Rails.logger.error "Failed to calculate churn rate: #{e.message}"
        0
      end

      def subscription_class
        defined?(Billing::Subscription) ? Billing::Subscription : nil
      end

      def calculate_database_size
        conn = ActiveRecord::Base.connection
        db_name = conn.quote(conn.current_database)

        case conn.adapter_name.downcase
        when "postgresql"
          result = conn.execute(
            "SELECT pg_size_pretty(pg_database_size(#{db_name}))"
          )
          result.first["pg_size_pretty"]
        when "mysql2"
          result = conn.execute(
            "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB'
             FROM information_schema.tables
             WHERE table_schema=#{db_name}"
          )
          "#{result.first['DB Size in MB']} MB"
        else
          "not_available"
        end
      rescue StandardError => e
        Rails.logger.error "Failed to calculate database size: #{e.message}"
        "calculation_failed"
      end
    end
  end
end
