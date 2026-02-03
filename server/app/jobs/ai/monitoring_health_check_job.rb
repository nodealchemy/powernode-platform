# frozen_string_literal: true

module Ai
  class MonitoringHealthCheckJob < ApplicationJob
    queue_as :monitoring

    HEALTH_CACHE_TTL = 24.hours
    ALERT_THRESHOLD_SCORE = 50

    def perform(account_id)
      account = Account.find_by(id: account_id)
      unless account
        Rails.logger.warn "MonitoringHealthCheckJob: Account #{account_id} not found"
        return false
      end

      Rails.logger.info "Running comprehensive health check for account #{account_id}"

      begin
        service = Ai::MonitoringHealthService.new(account: account)
        health_data = service.comprehensive_health_check

        # Store health snapshot in Redis with 24h TTL for historical tracking
        store_health_snapshot(account_id, health_data)

        # Check health status and trigger alerts if necessary
        trigger_alerts_if_needed(account, health_data)

        Rails.logger.info "Health check completed for account #{account_id}: " \
                          "status=#{health_data[:status]}, score=#{health_data[:health_score]}"

        health_data[:status] == "healthy"
      rescue StandardError => e
        Rails.logger.error "Health check failed for account #{account_id}: #{e.message}"
        Rails.logger.error e.backtrace&.first(5)&.join("\n")

        # Store failure snapshot
        store_failure_snapshot(account_id, e)

        # Trigger critical alert on health check failure
        trigger_health_check_failure_alert(account, e)

        false
      end
    end

    private

    def store_health_snapshot(account_id, health_data)
      redis = Redis.new
      cache_key = health_snapshot_key(account_id)
      history_key = health_history_key(account_id)

      # Store current snapshot
      redis.setex(cache_key, HEALTH_CACHE_TTL.to_i, health_data.to_json)

      # Append to historical list (keep last 24 entries = 24 hours at 1 per hour)
      redis.lpush(history_key, health_data.to_json)
      redis.ltrim(history_key, 0, 23)
      redis.expire(history_key, HEALTH_CACHE_TTL.to_i)
    rescue Redis::BaseError => e
      Rails.logger.warn "Failed to store health snapshot in Redis: #{e.message}"
    end

    def store_failure_snapshot(account_id, error)
      redis = Redis.new
      cache_key = health_snapshot_key(account_id)

      failure_data = {
        timestamp: Time.current.iso8601,
        status: "check_failed",
        health_score: 0,
        error: error.message,
        error_class: error.class.name
      }

      redis.setex(cache_key, HEALTH_CACHE_TTL.to_i, failure_data.to_json)
    rescue Redis::BaseError => e
      Rails.logger.warn "Failed to store failure snapshot in Redis: #{e.message}"
    end

    def trigger_alerts_if_needed(account, health_data)
      return if health_data[:status] == "healthy"

      alert_level = case health_data[:status]
                    when "degraded" then :warning
                    when "unhealthy" then :error
                    when "critical" then :critical
                    else :info
      end

      # Build alert details
      alert_details = build_alert_details(health_data)

      # Log the alert
      Rails.logger.send(
        alert_level == :critical ? :error : :warn,
        "AI System Health Alert [#{account.id}]: #{health_data[:status]} " \
        "(score: #{health_data[:health_score]})"
      )

      # Send notification if NotificationService is available
      send_health_alert_notification(account, health_data, alert_details, alert_level)
    end

    def trigger_health_check_failure_alert(account, error)
      Rails.logger.error "CRITICAL: Health check execution failed for account #{account.id}"

      send_health_alert_notification(
        account,
        { status: "check_failed", health_score: 0 },
        { error: error.message, error_class: error.class.name },
        :critical
      )
    end

    def build_alert_details(health_data)
      details = {}

      # Database issues
      if health_data[:database][:status] != "healthy"
        details[:database] = health_data[:database][:error] || "Database unhealthy"
      end

      # Redis issues
      if health_data[:redis][:status] != "healthy"
        details[:redis] = health_data[:redis][:error] || "Redis unhealthy"
      end

      # Provider issues
      if health_data[:providers][:healthy_providers] < health_data[:providers][:total_providers]
        unhealthy_providers = health_data[:providers][:providers]
                               &.select { |p| !p[:is_healthy] }
                               &.map { |p| p[:name] }
        details[:providers] = "Unhealthy providers: #{unhealthy_providers&.join(', ')}"
      end

      # Worker issues
      if health_data[:workers][:status] != "healthy"
        details[:workers] = "Worker status: #{health_data[:workers][:status]}, " \
                           "backlog: #{health_data[:workers][:estimated_backlog]}"
      end

      details
    end

    def send_health_alert_notification(account, health_data, details, level)
      # Check if NotificationService exists and supports this
      return unless defined?(NotificationService)

      NotificationService.send_system_alert(
        account: account,
        type: "ai_health_check",
        level: level,
        title: "AI System Health: #{health_data[:status]&.titleize || 'Check Failed'}",
        message: "Health score: #{health_data[:health_score] || 0}",
        details: details,
        metadata: {
          timestamp: Time.current.iso8601,
          job_class: self.class.name
        }
      )
    rescue StandardError => e
      Rails.logger.warn "Failed to send health alert notification: #{e.message}"
    end

    def health_snapshot_key(account_id)
      "ai:health:snapshot:#{account_id}"
    end

    def health_history_key(account_id)
      "ai:health:history:#{account_id}"
    end
  end
end
