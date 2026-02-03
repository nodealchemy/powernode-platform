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

    # =============================================================================
    # COMPREHENSIVE HEALTH CHECKS
    # =============================================================================

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

    private def fetch_comprehensive_health(time_range)
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
    public

    # Get detailed health information for all services
    # @return [Hash] Detailed health data
    def detailed_health
      {
        timestamp: Time.current.iso8601,
        services: {
          database: detailed_database_health,
          redis: detailed_redis_health,
          providers: detailed_provider_health,
          workflows: detailed_workflow_health,
          agents: detailed_agent_health,
          workers: detailed_worker_health
        },
        recent_activity: recent_activity_summary,
        error_analysis: recent_error_analysis,
        performance_metrics: performance_metrics,
        resource_metrics: resource_metrics
      }
    end

    # Get connectivity test results
    # @return [Hash] Connectivity data
    def connectivity_check
      {
        timestamp: Time.current.iso8601,
        database: test_database_connection,
        redis: test_redis_connection,
        providers: test_provider_connections,
        workers: test_worker_connectivity,
        external_services: test_external_services
      }
    end

    # =============================================================================
    # BASIC HEALTH CHECKS
    # =============================================================================

    def check_system_health
      {
        status: "healthy",
        uptime: estimate_system_uptime,
        active_workflows: ::Ai::Workflow.where(is_active: true).count,
        active_agents: ::Ai::Agent.where(status: "active").count,
        running_executions: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count
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
      redis = Redis.new
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
      recent_completions = ::Ai::WorkflowRun.where("completed_at >= ?", 10.minutes.ago).count
      recent_starts = ::Ai::WorkflowRun.where("created_at >= ?", 10.minutes.ago).count

      {
        status: recent_completions > 0 || recent_starts == 0 ? "healthy" : "degraded",
        recent_completions: recent_completions,
        recent_starts: recent_starts,
        estimated_backlog: [ recent_starts - recent_completions, 0 ].max,
        last_activity: last_worker_activity_time
      }
    end

    def circuit_breaker_summary
      ::Ai::WorkflowCircuitBreakerManager.health_summary
    end

    # =============================================================================
    # DETAILED HEALTH CHECKS
    # =============================================================================

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
          ai_providers: ::Ai::Provider.count,
          ai_workflows: ::Ai::Workflow.count,
          ai_agents: ::Ai::Agent.count,
          ai_workflow_runs_today: ::Ai::WorkflowRun.where("created_at >= ?", Date.current).count,
          ai_conversations_today: ::Ai::Conversation.where("created_at >= ?", Date.current).count
        }
      }
    rescue StandardError => e
      {
        status: "unhealthy",
        error: e.message
      }
    end

    def detailed_redis_health
      redis = Redis.new
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
      account.ai_providers.where(is_active: true).map do |provider|
        {
          id: provider.id,
          name: provider.name,
          provider_type: provider.provider_type,
          status: provider.is_active ? "active" : "inactive",
          credentials_count: provider.provider_credentials.where(is_active: true).count,
          recent_executions: ::Ai::AgentExecution.where(agent: ::Ai::Agent.where(provider: provider))
                                              .where("created_at >= ?", 24.hours.ago)
                                              .count
        }
      end
    end

    def detailed_workflow_health
      workflows = account.ai_workflows

      {
        total_workflows: workflows.count,
        active_workflows: workflows.where(is_active: true).count,
        running_executions: ::Ai::WorkflowRun.where(workflow: workflows)
                                          .where(status: %w[initializing running waiting_approval])
                                          .count,
        recent_runs: {
          last_hour: ::Ai::WorkflowRun.where(workflow: workflows).where("created_at >= ?", 1.hour.ago).count,
          last_24h: ::Ai::WorkflowRun.where(workflow: workflows).where("created_at >= ?", 24.hours.ago).count
        },
        success_rate: calculate_workflow_success_rate(workflows)
      }
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
          workflow_runs: ::Ai::WorkflowRun.where("created_at >= ?", 1.hour.ago).count,
          completed_runs: ::Ai::WorkflowRun.where(status: "completed").where("completed_at >= ?", 1.hour.ago).count,
          failed_runs: ::Ai::WorkflowRun.where(status: "failed").where("completed_at >= ?", 1.hour.ago).count
        },
        queue_health: {
          processing_rate: ::Ai::WorkflowRun.where("completed_at >= ?", 10.minutes.ago).count,
          creation_rate: ::Ai::WorkflowRun.where("created_at >= ?", 10.minutes.ago).count
        }
      }
    end

    # =============================================================================
    # CONNECTIVITY TESTS
    # =============================================================================

    def test_database_connection
      start_time = Time.current
      ActiveRecord::Base.connection.execute("SELECT 1")
      response_time = ((Time.current - start_time) * 1000).round(2)

      {
        status: "healthy",
        response_time_ms: response_time
      }
    rescue StandardError => e
      {
        status: "unhealthy",
        error: e.message
      }
    end

    def test_redis_connection
      redis = Redis.new
      redis.ping

      {
        status: "connected"
      }
    rescue StandardError => e
      {
        status: "disconnected",
        error: e.message
      }
    end

    def test_provider_connections
      account.ai_providers.where(is_active: true).map do |provider|
        {
          provider_id: provider.id,
          name: provider.name,
          type: provider.provider_type,
          has_credentials: provider.provider_credentials.where(is_active: true).exists?,
          status: provider.is_active ? "configured" : "inactive"
        }
      end
    end

    def test_worker_connectivity
      {
        last_activity: last_worker_activity_time,
        recent_completions: ::Ai::WorkflowRun.where("completed_at >= ?", 5.minutes.ago).count,
        pending_jobs: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count
      }
    end

    def test_external_services
      {
        redis: test_redis_connection,
        database: test_database_connection
      }
    end

    # =============================================================================
    # ACTIVITY & METRICS
    # =============================================================================

    def recent_activity_summary
      {
        last_hour: activity_for_period(1.hour.ago),
        last_24h: activity_for_period(24.hours.ago)
      }
    end

    def recent_error_analysis
      failed_runs = ::Ai::WorkflowRun.where("created_at >= ? AND status = ?", 24.hours.ago, "failed")
                                   .includes(:workflow)
                                   .limit(10)

      {
        total_failures: failed_runs.count,
        recent_failures: failed_runs.map do |run|
          {
            workflow_name: run.workflow.name,
            failed_at: run.completed_at,
            error_summary: run.error_details.is_a?(Hash) ? run.error_details["error_message"] : "Unknown error"
          }
        end
      }
    end

    def performance_metrics
      {
        average_execution_time: calculate_average_execution_time,
        throughput: {
          workflows_per_hour: ::Ai::WorkflowRun.where("created_at >= ?", 1.hour.ago).count,
          conversations_per_hour: ::Ai::Conversation.where("created_at >= ?", 1.hour.ago).count
        },
        resource_usage: {
          active_conversations: ::Ai::Conversation.where("updated_at >= ?", 1.hour.ago).count,
          running_workflows: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count,
          database_connections: ActiveRecord::Base.connection_pool.connections.size
        }
      }
    end

    def resource_metrics
      pool_stat = ActiveRecord::Base.connection_pool.stat
      {
        database: {
          connections: pool_stat[:connections],
          available: pool_stat[:idle]
        },
        redis: check_redis_health,
        active_records: {
          active_workflows: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count,
          active_conversations: ::Ai::Conversation.where("updated_at >= ?", 1.hour.ago).count
        }
      }
    end

    # =============================================================================
    # CALCULATION HELPERS
    # =============================================================================

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

    def activity_for_period(since)
      {
        workflow_runs: ::Ai::WorkflowRun.where("created_at >= ?", since).count,
        completed_runs: ::Ai::WorkflowRun.where("created_at >= ? AND status = ?", since, "completed").count,
        failed_runs: ::Ai::WorkflowRun.where("created_at >= ? AND status = ?", since, "failed").count
      }
    end

    def calculate_workflow_success_rate(workflows)
      runs = ::Ai::WorkflowRun.where(workflow: workflows).where("created_at >= ?", 24.hours.ago)
      total = runs.count
      successful = runs.where(status: "completed").count

      total > 0 ? (successful.to_f / total * 100).round(2) : 0
    end

    def calculate_average_execution_time
      completed_runs = ::Ai::WorkflowRun.where(status: "completed")
                                      .where("completed_at >= ?", 24.hours.ago)
                                      .where.not(duration_ms: nil)

      return 0 if completed_runs.empty?

      (completed_runs.average(:duration_ms) || 0).round(2)
    end

    def estimate_system_uptime
      oldest_active = ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval])
                                     .order(:created_at)
                                     .first&.created_at

      return 0 unless oldest_active

      (Time.current - oldest_active).to_i
    end

    def last_worker_activity_time
      recent_completion = ::Ai::WorkflowRun.where(status: %w[completed failed])
                                         .order(completed_at: :desc)
                                         .first&.completed_at

      recent_message = ::Ai::Message.where(role: "assistant")
                                 .order(created_at: :desc)
                                 .first&.created_at

      [ recent_completion, recent_message ].compact.max
    end
  end
end
