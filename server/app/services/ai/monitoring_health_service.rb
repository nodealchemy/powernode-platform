# frozen_string_literal: true

module Ai
  # Service for monitoring health checks and metrics
  #
  # Provides health monitoring including:
  # - System, database, redis health checks
  # - Provider and worker health
  # - Connectivity tests
  # - Performance metrics
  # - Activity summaries
  #
  # Usage:
  #   service = Ai::MonitoringHealthService.new(account: current_user.account)
  #   health_data = service.comprehensive_health_check
  #
  class MonitoringHealthService
    include HealthChecks
    include ConnectivityTests
    include ActivityMetrics

    attr_reader :account

    HEALTH_WEIGHTS = {
      database: 0.25,
      redis: 0.25,
      providers: 0.25,
      workers: 0.25
    }.freeze

    # Cache TTLs
    PROVIDER_HEALTH_CACHE_TTL = 5.minutes
    COMPREHENSIVE_HEALTH_CACHE_TTL = 2.minutes

    def initialize(account:)
      @account = account
    end

    # Get full health check data
    # @param time_range [ActiveSupport::Duration] Time range for metrics
    # @param skip_cache [Boolean] Force fresh data, bypassing cache
    # @return [Hash] Complete health data
    def comprehensive_health_check(time_range: 1.hour, skip_cache: false)
      cache_key = "ai:monitoring:comprehensive:#{account.id}:#{time_range.to_i}"

      return fetch_comprehensive_health(time_range) if skip_cache

      Rails.cache.fetch(cache_key, expires_in: COMPREHENSIVE_HEALTH_CACHE_TTL) do
        fetch_comprehensive_health(time_range)
      end
    end

    def calculate_overall_health_score(health_data)
      scores = []

      # Database health (25%)
      scores << (health_data[:database][:status] == "healthy" ? 100 : 0) * HEALTH_WEIGHTS[:database]

      # Redis health (25%)
      scores << (health_data[:redis][:status] == "healthy" ? 100 : 0) * HEALTH_WEIGHTS[:redis]

      # Provider health (25%)
      provider_score = if health_data[:providers][:total_providers] > 0
                        (health_data[:providers][:healthy_providers].to_f / health_data[:providers][:total_providers] * 100)
      else
                        100
      end
      scores << (provider_score * HEALTH_WEIGHTS[:providers])

      # Worker health (25%)
      worker_score = health_data[:workers][:status] == "healthy" ? 100 : 50
      scores << (worker_score * HEALTH_WEIGHTS[:workers])

      scores.sum.round
    end

    def determine_health_status(health_score)
      case health_score
      when 80..100 then "healthy"
      when 50..79 then "degraded"
      when 20..49 then "unhealthy"
      else "critical"
      end
    end

    private

    def fetch_comprehensive_health(time_range)
      health_data = {
        timestamp: Time.current.iso8601,
        time_range_seconds: time_range.to_i,
        system: check_system_health,
        database: check_database_health,
        redis: check_redis_health,
        providers: check_provider_health_cached,
        workers: check_worker_health,
        circuit_breakers: circuit_breaker_summary
      }

      health_score = calculate_overall_health_score(health_data)
      health_data[:health_score] = health_score
      health_data[:status] = determine_health_status(health_score)

      health_data
    end
  end
end
