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
          active_subscriptions: Subscription.active.count,
          total_revenue_cents: Subscription.active.joins(:plan).sum("plans.price"),
          successful_payments_today: Payment.successful.where("created_at >= ?", 1.day.ago).count
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
          total: Subscription.count,
          active: Subscription.active.count,
          cancelled: Subscription.cancelled.count,
          expired: Subscription.expired.count,
          trial: Subscription.trial.count,
          by_plan: Subscription.joins(:plan).group("plans.name").count,
          monthly_revenue_cents: Subscription.active.joins(:plan).sum("plans.price"),
          churn_rate_percent: calculate_churn_rate,
          new_this_month: Subscription.where("created_at >= ?", 1.month.ago).count
        }
      end

      def payment_metrics
        {
          total: Payment.count,
          successful: Payment.successful.count,
          failed: Payment.failed.count,
          pending: Payment.pending.count,
          total_amount_cents: Payment.successful.sum(:amount_cents),
          today: Payment.where("created_at >= ?", 1.day.ago).count,
          this_week: Payment.where("created_at >= ?", 1.week.ago).count,
          this_month: Payment.where("created_at >= ?", 1.month.ago).count,
          by_provider: Payment.group(:provider).count,
          average_amount_cents: Payment.successful.average(:amount_cents)&.round
        }
      end

      def api_metrics
        # This would need to be stored in Redis or database for persistence
        # For now, return placeholder data
        {
          total_requests: "tracked_in_prometheus",
          average_response_time: "tracked_in_prometheus",
          error_rate: "tracked_in_prometheus",
          endpoints: "tracked_in_prometheus"
        }
      end

      def job_metrics
        # This would integrate with Sidekiq stats if available
        {
          processed: "tracked_via_sidekiq_web",
          failed: "tracked_via_sidekiq_web",
          scheduled: "tracked_via_sidekiq_web",
          retries: "tracked_via_sidekiq_web"
        }
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
        current_month_start = Date.current.beginning_of_month
        last_month_start = 1.month.ago.beginning_of_month
        last_month_end = 1.month.ago.end_of_month

        active_last_month = Subscription.where(
          "created_at <= ? AND (cancelled_at IS NULL OR cancelled_at > ?)",
          last_month_end, last_month_end
        ).count

        cancelled_last_month = Subscription.where(
          cancelled_at: last_month_start..last_month_end
        ).count

        return 0 if active_last_month.zero?

        ((cancelled_last_month.to_f / active_last_month) * 100).round(2)
      rescue StandardError => e
        Rails.logger.error "Failed to calculate churn rate: #{e.message}"
        0
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
