# frozen_string_literal: true

module Ai
  class MonitoringHealthService
    module HealthChecks
      extend ActiveSupport::Concern

      def check_system_health
        {
          status: "healthy",
          uptime: estimate_system_uptime,
          active_agents: account.ai_agents.where(status: "active").count
        }
      end

      # Both read the one shared check (Platform::Health::CoreChecks), keeping
      # the keys this service's consumers read.
      def check_database_health
        result = ::Platform::Health::CoreChecks.database
        return result unless result[:status] == "healthy"

        pool = result[:connection_pool]
        result.merge(connection: "active", connection_pool: pool.merge(available: pool[:idle]))
      end

      def check_redis_health
        ::Platform::Health::CoreChecks.redis
      end

      def check_provider_health
        providers = account.ai_providers.where(is_active: true)

        {
          total_providers: providers.count,
          healthy_providers: providers.count { |p| provider_healthy?(p) },
          providers: providers.map { |p| provider_health_summary(p) }
        }
      end

      # Cached version of provider health check (5-minute TTL)
      def check_provider_health_cached
        cache_key = "ai:monitoring:provider_health:#{account.id}"

        Rails.cache.fetch(cache_key, expires_in: PROVIDER_HEALTH_CACHE_TTL) do
          check_provider_health
        end
      end

      def check_worker_health
        recent_completions = ::Ai::AgentExecution.where(status: "completed")
                                                 .where("created_at >= ?", 10.minutes.ago).count
        recent_starts = ::Ai::AgentExecution.where("created_at >= ?", 10.minutes.ago).count

        {
          status: recent_completions > 0 || recent_starts == 0 ? "healthy" : "degraded",
          recent_completions: recent_completions,
          recent_starts: recent_starts,
          estimated_backlog: [ recent_starts - recent_completions, 0 ].max,
          last_activity: last_worker_activity_time
        }
      end

      def circuit_breaker_summary
        ::Ai::CircuitBreakerRegistry.health_summary
      end

      private

      def provider_healthy?(provider)
        recent_executions = ::Ai::AgentExecution.where(agent: ::Ai::Agent.where(provider: provider))
                                             .where("created_at >= ?", 5.minutes.ago)

        return true if recent_executions.empty?

        success_count = recent_executions.where(status: "completed").count
        success_rate = (success_count.to_f / recent_executions.count * 100).round(2)
        success_rate >= 95.0
      end

      def provider_health_summary(provider)
        {
          id: provider.id,
          name: provider.name,
          provider_type: provider.provider_type,
          status: provider.is_active ? "active" : "inactive",
          has_credentials: provider.provider_credentials.where(is_active: true).exists?,
          is_healthy: provider_healthy?(provider)
        }
      end

      def estimate_system_uptime
        oldest_active = ::Ai::AgentExecution.where(status: "running")
                                           .order(:created_at)
                                           .first&.created_at

        return 0 unless oldest_active

        (Time.current - oldest_active).to_i
      end

      def last_worker_activity_time
        recent_execution = ::Ai::AgentExecution.where(status: %w[completed failed])
                                              .order(created_at: :desc)
                                              .first&.created_at

        recent_message = ::Ai::Message.where(role: "assistant")
                                   .order(created_at: :desc)
                                   .first&.created_at

        [ recent_execution, recent_message ].compact.max
      end
    end
  end
end
