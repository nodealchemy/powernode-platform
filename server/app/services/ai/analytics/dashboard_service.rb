# frozen_string_literal: true

module Ai
  module Analytics
    # Service for generating AI analytics dashboard data and AIOps metrics
    class DashboardService
      include SummaryMetrics
      include TrendsAndHighlights
      include AiopsMetrics

      attr_reader :account, :time_range

      # Cache TTLs
      DASHBOARD_CACHE_TTL = 15.minutes
      REAL_TIME_CACHE_TTL = 1.minute

      # Thresholds for health status determination
      HEALTH_THRESHOLDS = {
        healthy: { success_rate: 95, latency_p95: 5000, error_rate: 5 },
        degraded: { success_rate: 80, latency_p95: 10000, error_rate: 20 },
        unhealthy: { success_rate: 0, latency_p95: Float::INFINITY, error_rate: 100 }
      }.freeze

      # Initialize the service
      # @param account [Account] Account to analyze
      # @param time_range [ActiveSupport::Duration] Time range for analysis
      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # Generate complete dashboard data (cached for 15 minutes)
      # @param force_refresh [Boolean] Skip cache and regenerate
      # @return [Hash] Dashboard data
      def generate(force_refresh: false)
        cache_key = "ai:dashboard:#{account.id}:#{time_range.to_i}"

        return Rails.cache.fetch(cache_key, expires_in: DASHBOARD_CACHE_TTL, force: force_refresh) do
          {
            summary: generate_summary_metrics,
            trends: generate_trend_data,
            highlights: generate_highlights,
            quick_stats: generate_quick_stats,
            resource_usage: generate_resource_usage,
            recent_activity: generate_recent_activity
          }
        end
      end

      # Invalidate dashboard cache for an account
      def self.invalidate_cache(account_id)
        Rails.cache.delete_matched("ai:dashboard:#{account_id}:*")
      end

      # Provider health metrics for MCP introspection tool
      # @param ops_time_range [ActiveSupport::Duration] Time range for analysis
      # @return [Array<Hash>] Per-provider health data
      def provider_metrics(ops_time_range = 1.hour)
        ops_provider_metrics(ops_time_range)
      end

      # Cost analysis for MCP introspection tool
      # @param ops_time_range [ActiveSupport::Duration] Time range for analysis
      # @return [Hash] Cost breakdown data
      def cost_analysis(ops_time_range = 1.hour)
        ops_cost_analysis(ops_time_range)
      end

      private

      def workflows
        account.ai_workflows
      end

      def agents
        account.ai_agents
      end

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def agent_executions
        ::Ai::AgentExecution.joins(:agent).where(ai_agents: { account_id: account.id })
      end

      def conversations
        account.ai_conversations
      end

      def messages
        ::Ai::Message.joins(:conversation).where(ai_conversations: { account_id: account.id })
      end
    end
  end
end
