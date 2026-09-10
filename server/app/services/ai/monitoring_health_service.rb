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
  # It reports MEASUREMENTS ONLY. It deliberately returns no health score and no
  # overall status: the status-plane rollup is the one health score (E7, E7b,
  # design section 4.4). Callers that need a verdict compose it themselves from
  # Platform::Status::Rollup.
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

      # NO `health_score` AND NO `status` (E7b). This service used to blend the
      # four checks above into a 0-100 number and then bucket that number into
      # healthy/degraded/unhealthy/critical — a third derivation of "is this
      # healthy?", disagreeing with both the status-plane rollup and the
      # component-check string that AiMonitoringConcern used to produce.
      #
      # The checks themselves stay: they are real measurements, and the A3
      # contributors are what turn measurements of this kind into conditions.
      # What is gone is this service's opinion about what they add up to.
      health_data
    end
  end
end
