# frozen_string_literal: true

module Ai
  module Analytics
    # Service for generating AI metrics and KPIs
    #
    # Provides detailed metrics for:
    # - Agent performance metrics
    # - Provider utilization metrics
    # - Execution metrics
    #
    # Usage:
    #   service = Ai::Analytics::MetricsService.new(account: current_account, time_range: 30.days)
    #   metrics = service.all_metrics
    #
    class MetricsService
      attr_reader :account, :time_range

      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # Get all metrics
      # @return [Hash] All metrics
      def all_metrics
        {
          agents: agent_metrics,
          providers: provider_metrics,
          executions: execution_metrics,
          performance: performance_metrics
        }
      end

      # Get agent-specific metrics
      # @return [Hash] Agent metrics
      def agent_metrics
        start_time = time_range.ago

        {
          total_agents: agents.count,
          active_agents: agents.active.count,
          agents_by_type: agents.group(:agent_type).count,
          total_executions: count_agent_executions(start_time),
          success_rate: calculate_agent_success_rate(start_time),
          average_response_time_ms: calculate_agent_avg_response_time(start_time),
          total_tokens_used: calculate_agent_token_usage(start_time),
          total_cost: calculate_agent_cost(start_time)
        }
      end

      # Get provider utilization metrics
      # @return [Hash] Provider metrics
      def provider_metrics
        start_time = time_range.ago

        providers = ::Ai::Provider.where(account_id: account.id)

        provider_stats = providers.map do |provider|
          executions = provider_executions(provider, start_time)

          {
            id: provider.id,
            name: provider.name,
            provider_type: provider.provider_type,
            is_active: provider.is_active?,
            total_requests: executions.count,
            successful_requests: executions.where(status: "completed").count,
            failed_requests: executions.where(status: "failed").count,
            average_latency_ms: executions.average(:duration_ms)&.to_f&.round(2),
            total_tokens: calculate_provider_tokens(executions),
            total_cost: calculate_provider_cost(executions),
            error_rate: calculate_provider_error_rate(executions)
          }
        end

        {
          total_providers: providers.count,
          active_providers: providers.where(is_active: true).count,
          providers: provider_stats
        }
      end

      # Get execution metrics
      # @return [Hash] Execution metrics
      def execution_metrics
        start_time = time_range.ago
        executions = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)

        {
          total_executions: executions.count,
          concurrent_executions_peak: executions.where(status: "running").count,
          queue_time: {
            average_ms: calculate_avg_queue_time(executions),
            p95_ms: calculate_percentile_queue_time(executions, 95),
            max_ms: calculate_max_queue_time(executions)
          }
        }
      end

      # Get performance metrics
      # @return [Hash] Performance metrics
      def performance_metrics
        start_time = time_range.ago
        executions = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)

        {
          throughput: {
            executions_per_hour: calculate_throughput(executions, :hour),
            executions_per_day: calculate_throughput(executions, :day)
          },
          latency: {
            p50_ms: calculate_percentile_duration(executions, 50),
            p90_ms: calculate_percentile_duration(executions, 90),
            p95_ms: calculate_percentile_duration(executions, 95),
            p99_ms: calculate_percentile_duration(executions, 99)
          },
          availability: calculate_availability(start_time),
          error_budget: calculate_error_budget(executions)
        }
      end

      # Get metrics for a specific agent
      # @param agent [Ai::Agent] Agent to analyze
      # @return [Hash] Agent-specific metrics
      def agent_specific_metrics(agent)
        start_time = time_range.ago

        executions = ::Ai::AgentExecution
                       .where(ai_agent_id: agent.id)
                       .where("ai_agent_executions.created_at >= ?", start_time)

        {
          agent_id: agent.id,
          agent_name: agent.name,
          total_executions: executions.count,
          successful_executions: executions.where(status: "completed").count,
          failed_executions: executions.where(status: "failed").count,
          success_rate: calculate_execution_success_rate(executions),
          average_response_time_ms: executions.where(status: "completed").average(:duration_ms)&.to_f&.round(2),
          total_cost: executions.sum(:cost_usd).to_f.round(6),
          execution_timeline: executions.group("DATE(ai_agent_executions.created_at)").count.transform_keys(&:to_s)
        }
      end

      private

      # =============================================================================
      # QUERY HELPERS
      # =============================================================================

      def agents
        account.ai_agents
      end

      def agent_executions
        ::Ai::AgentExecution.where(account_id: account.id)
      end

      def provider_executions(provider, since)
        ::Ai::AgentExecution
          .where(account_id: account.id)
          .where(ai_provider_id: provider.id)
          .where("ai_agent_executions.created_at >= ?", since)
      end

      # =============================================================================
      # CALCULATION HELPERS
      # =============================================================================

      def calculate_execution_success_rate(executions)
        total = executions.where.not(status: %w[running pending]).count
        return nil if total.zero?

        completed = executions.where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_avg_execution_cost(executions)
        count = executions.where.not(cost_usd: nil).count
        return nil if count.zero?

        (executions.sum(:cost_usd).to_f / count).round(6)
      end

      def calculate_median_duration(executions)
        durations = executions.where(status: "completed").where.not(duration_ms: nil).pluck(:duration_ms).sort
        return nil if durations.empty?

        mid = durations.length / 2
        durations.length.odd? ? durations[mid] : (durations[mid - 1] + durations[mid]) / 2.0
      end

      def calculate_percentile_duration(executions, percentile)
        durations = executions.where(status: "completed").where.not(duration_ms: nil).pluck(:duration_ms).sort
        return nil if durations.empty?

        index = (percentile / 100.0 * durations.length).ceil - 1
        durations[[ index, 0 ].max]
      end

      def count_agent_executions(since)
        agent_executions.where("ai_agent_executions.created_at >= ?", since).count
      end

      def calculate_agent_success_rate(since)
        executions = agent_executions.where("ai_agent_executions.created_at >= ?", since)

        total = executions.where.not(status: %w[running pending]).count
        return nil if total.zero?

        completed = executions.where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_agent_avg_response_time(since)
        agent_executions
          .where("ai_agent_executions.created_at >= ?", since)
          .where(status: "completed")
          .average(:duration_ms)&.to_f&.round(2)
      end

      def calculate_agent_token_usage(since)
        agent_executions
          .where("ai_agent_executions.created_at >= ?", since)
          .sum(:tokens_used).to_i
      end

      def calculate_agent_cost(since)
        agent_executions
          .where("ai_agent_executions.created_at >= ?", since)
          .sum(:cost_usd).to_f.round(6)
      end

      def calculate_provider_tokens(executions)
        executions.sum(:tokens_used).to_i
      end

      def calculate_provider_cost(executions)
        executions.sum(:cost_usd).to_f.round(6)
      end

      def calculate_provider_error_rate(executions)
        total = executions.count
        return 0.0 if total.zero?

        failed = executions.where(status: "failed").count
        (failed.to_f / total * 100).round(2)
      end

      def calculate_avg_queue_time(executions)
        executions.where.not(started_at: nil)
            .select { |r| r.started_at && r.created_at }
            .map { |r| (r.started_at - r.created_at) * 1000 }
            .then { |times| times.empty? ? nil : (times.sum / times.length).round(2) }
      end

      def calculate_percentile_queue_time(executions, percentile)
        times = executions.where.not(started_at: nil)
                   .select { |r| r.started_at && r.created_at }
                   .map { |r| (r.started_at - r.created_at) * 1000 }
                   .sort

        return nil if times.empty?

        index = (percentile / 100.0 * times.length).ceil - 1
        times[[ index, 0 ].max].round(2)
      end

      def calculate_max_queue_time(executions)
        executions.where.not(started_at: nil)
            .select { |r| r.started_at && r.created_at }
            .map { |r| (r.started_at - r.created_at) * 1000 }
            .max&.round(2)
      end

      def calculate_throughput(executions, unit)
        total = executions.count
        hours = time_range.to_i / 3600.0

        case unit
        when :hour
          (total / hours).round(2)
        when :day
          (total / (hours / 24)).round(2)
        else
          total
        end
      end

      def calculate_availability(since)
        total = agent_executions.where("ai_agent_executions.created_at >= ?", since)
                                .where.not(status: %w[running pending])
                                .count
        return 100.0 if total.zero?

        successful = agent_executions.where("ai_agent_executions.created_at >= ?", since)
                                     .where(status: "completed")
                                     .count
        (successful.to_f / total * 100).round(2)
      end

      def calculate_error_budget(executions)
        target_slo = 99.9
        actual_success_rate = (calculate_execution_success_rate(executions) || 0) * 100
        remaining = actual_success_rate - target_slo

        {
          target_slo: target_slo,
          actual_success_rate: actual_success_rate.round(2),
          remaining_budget: remaining.round(2),
          budget_consumed: remaining < 0 ? 100 : ((target_slo - remaining) / target_slo * 100).round(2)
        }
      end
    end
  end
end
