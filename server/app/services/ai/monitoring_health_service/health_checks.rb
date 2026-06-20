# frozen_string_literal: true

module Ai
  class MonitoringHealthService
    module HealthChecks
      extend ActiveSupport::Concern

      # Get detailed health information for all services
      # @return [Hash] Detailed health data
      def detailed_health
        {
          timestamp: Time.current.iso8601,
          services: {
            database: detailed_database_health,
            redis: detailed_redis_health,
            providers: detailed_provider_health,
            agents: detailed_agent_health,
            workers: detailed_worker_health
          },
          recent_activity: recent_activity_summary,
          error_analysis: recent_error_analysis,
          performance_metrics: performance_metrics,
          resource_metrics: resource_metrics
        }
      end

      def check_system_health
        {
          status: "healthy",
          uptime: estimate_system_uptime,
          active_agents: account.ai_agents.where(status: "active").count
        }
      end

      def check_database_health
        ActiveRecord::Base.connection.execute("SELECT 1")

        pool_stat = ActiveRecord::Base.connection_pool.stat
        {
          status: "healthy",
          connection: "active",
          connection_pool: {
            size: pool_stat[:size],
            connections: pool_stat[:connections],
            busy: pool_stat[:busy],
            idle: pool_stat[:idle],
            available: pool_stat[:idle]
          }
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
      end

      def check_redis_health
        redis = Powernode::Redis.new_client
        redis.ping

        info = redis.info
        {
          status: "healthy",
          used_memory: info["used_memory_human"],
          connected_clients: info["connected_clients"]&.to_i || 0
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
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

      # Invalidate provider health cache (call when provider status changes)
      def self.invalidate_provider_health_cache(account_id)
        cache_key = "ai:monitoring:provider_health:#{account_id}"
        Rails.cache.delete(cache_key)

        # Also invalidate comprehensive health cache
        Rails.cache.delete_matched("ai:monitoring:comprehensive:#{account_id}:*")
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

      # Detailed health checks

      def detailed_database_health
        pool_stat = ActiveRecord::Base.connection_pool.stat
        {
          status: "healthy",
          connection_pool: {
            size: pool_stat[:size],
            connections: pool_stat[:connections],
            busy: pool_stat[:busy],
            idle: pool_stat[:idle],
            available: pool_stat[:idle]
          },
          table_counts: {
            ai_providers: account.ai_providers.count,
            ai_agents: account.ai_agents.count,
            ai_conversations_today: account.ai_conversations.where("created_at >= ?", Date.current).count
          }
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
      end

      def detailed_redis_health
        redis = Powernode::Redis.new_client
        info = redis.info

        {
          status: "healthy",
          version: info["redis_version"],
          used_memory: info["used_memory_human"],
          used_memory_peak: info["used_memory_peak_human"],
          connected_clients: info["connected_clients"]&.to_i || 0,
          uptime_days: info["uptime_in_days"]&.to_i || 0
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
      end

      def detailed_provider_health
        account.ai_providers.where(is_active: true).includes(:provider_credentials).map do |provider|
          {
            id: provider.id,
            name: provider.name,
            provider_type: provider.provider_type,
            status: provider.is_active ? "active" : "inactive",
            credentials_count: provider.provider_credentials.select(&:is_active?).size,
            recent_executions: ::Ai::AgentExecution.where(agent: ::Ai::Agent.where(provider: provider))
                                                .where("created_at >= ?", 24.hours.ago)
                                                .count
          }
        end
      end

      def detailed_agent_health
        agents = account.ai_agents

        {
          total_agents: agents.count,
          active_agents: agents.where(status: "active").count,
          recent_executions: {
            last_hour: ::Ai::AgentExecution.where(agent: agents).where("created_at >= ?", 1.hour.ago).count,
            last_24h: ::Ai::AgentExecution.where(agent: agents).where("created_at >= ?", 24.hours.ago).count
          }
        }
      end

      def detailed_worker_health
        {
          recent_activity: {
            agent_executions: ::Ai::AgentExecution.where("created_at >= ?", 1.hour.ago).count,
            completed_executions: ::Ai::AgentExecution.where(status: "completed").where("created_at >= ?", 1.hour.ago).count,
            failed_executions: ::Ai::AgentExecution.where(status: "failed").where("created_at >= ?", 1.hour.ago).count
          },
          queue_health: {
            processing_rate: ::Ai::AgentExecution.where(status: "completed").where("created_at >= ?", 10.minutes.ago).count,
            creation_rate: ::Ai::AgentExecution.where("created_at >= ?", 10.minutes.ago).count
          }
        }
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
