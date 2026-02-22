# frozen_string_literal: true

module Ai
  module Analytics
    # Service for generating AI metrics and KPIs
    #
    # Provides detailed metrics for:
    # - Workflow performance metrics
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
          workflows: workflow_metrics,
          agents: agent_metrics,
          providers: provider_metrics,
          executions: execution_metrics,
          performance: performance_metrics
        }
      end

      # Get workflow-specific metrics
      # @return [Hash] Workflow metrics
      def workflow_metrics
        start_time = time_range.ago
        runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)

        {
          total_workflows: workflows.count,
          active_workflows: workflows.where(status: "active").count,
          template_workflows: workflows.where(is_template: true).count,
          total_executions: runs.count,
          successful_executions: runs.where(status: "completed").count,
          failed_executions: runs.where(status: "failed").count,
          cancelled_executions: runs.where(status: "cancelled").count,
          success_rate: calculate_success_rate(runs),
          average_duration_ms: runs.where(status: "completed").average(:duration_ms)&.to_f&.round(2),
          median_duration_ms: calculate_median_duration(runs),
          p95_duration_ms: calculate_percentile_duration(runs, 95),
          p99_duration_ms: calculate_percentile_duration(runs, 99),
          total_cost: runs.sum(:total_cost).to_f.round(6),
          average_cost_per_execution: calculate_avg_cost(runs),
          executions_by_status: runs.group(:status).count,
          executions_by_trigger: runs.group(:trigger_type).count
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
            is_active: provider.active?,
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
          active_providers: providers.where(status: "active").count,
          providers: provider_stats
        }
      end

      # Get execution metrics
      # @return [Hash] Execution metrics
      def execution_metrics
        start_time = time_range.ago
        runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)

        {
          total_node_executions: count_node_executions(start_time),
          avg_nodes_per_workflow: runs.where(status: "completed").average(:total_nodes)&.to_f&.round(2),
          retry_count: count_retries(start_time),
          timeout_count: count_timeouts(start_time),
          concurrent_executions_peak: calculate_peak_concurrency(start_time),
          queue_time: {
            average_ms: calculate_avg_queue_time(runs),
            p95_ms: calculate_percentile_queue_time(runs, 95),
            max_ms: calculate_max_queue_time(runs)
          }
        }
      end

      # Get performance metrics
      # @return [Hash] Performance metrics
      def performance_metrics
        start_time = time_range.ago
        runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)

        {
          throughput: {
            executions_per_hour: calculate_throughput(runs, :hour),
            executions_per_day: calculate_throughput(runs, :day)
          },
          latency: {
            p50_ms: calculate_percentile_duration(runs, 50),
            p90_ms: calculate_percentile_duration(runs, 90),
            p95_ms: calculate_percentile_duration(runs, 95),
            p99_ms: calculate_percentile_duration(runs, 99)
          },
          availability: calculate_availability(start_time),
          error_budget: calculate_error_budget(runs)
        }
      end

      # Get metrics for a specific workflow
      # @param workflow [Ai::Workflow] Workflow to analyze
      # @return [Hash] Workflow-specific metrics
      def workflow_specific_metrics(workflow)
        start_time = time_range.ago
        runs = workflow.runs.where("ai_workflow_runs.created_at >= ?", start_time)

        {
          workflow_id: workflow.id,
          workflow_name: workflow.name,
          total_executions: runs.count,
          successful_executions: runs.where(status: "completed").count,
          failed_executions: runs.where(status: "failed").count,
          success_rate: calculate_success_rate(runs),
          average_duration_ms: runs.where(status: "completed").average(:duration_ms)&.to_f&.round(2),
          total_cost: runs.sum(:total_cost).to_f.round(6),
          average_cost_per_execution: calculate_avg_cost(runs),
          node_performance: analyze_node_performance(workflow, start_time),
          execution_timeline: runs.group("DATE(ai_workflow_runs.created_at)").count.transform_keys(&:to_s),
          trigger_distribution: runs.group(:trigger_type).count
        }
      end

      # Get metrics for a specific agent
      # @param agent [Ai::Agent] Agent to analyze
      # @return [Hash] Agent-specific metrics
      def agent_specific_metrics(agent)
        start_time = time_range.ago

        # Get executions through workflow node executions that reference this agent
        node_executions = ::Ai::WorkflowNodeExecution.joins(:node)
                                             .where("ai_workflow_nodes.configuration->>'agent_id' = ?", agent.id.to_s)
                                             .where("ai_workflow_node_executions.created_at >= ?", start_time)

        {
          agent_id: agent.id,
          agent_name: agent.name,
          total_executions: node_executions.count,
          successful_executions: node_executions.where(status: "completed").count,
          failed_executions: node_executions.where(status: "failed").count,
          success_rate: calculate_node_success_rate(node_executions),
          average_response_time_ms: node_executions.where(status: "completed").average(:execution_time_ms)&.to_f&.round(2),
          total_cost: node_executions.sum(:cost).to_f.round(6),
          execution_timeline: node_executions.group("DATE(ai_workflow_node_executions.created_at)").count.transform_keys(&:to_s)
        }
      end

      private

      # =============================================================================
      # QUERY HELPERS
      # =============================================================================

      def workflows
        account.ai_workflows
      end

      def agents
        account.ai_agents
      end

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def provider_executions(provider, since)
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .where("ai_workflow_node_executions.metadata->>'provider_id' = ?", provider.id.to_s)
                          .where("ai_workflow_node_executions.created_at >= ?", since)
      end

      # =============================================================================
      # CALCULATION HELPERS
      # =============================================================================

      def calculate_success_rate(runs)
        total = runs.where.not(status: %w[running initializing pending]).count
        return nil if total.zero?

        completed = runs.where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_node_success_rate(executions)
        total = executions.where.not(status: %w[running pending]).count
        return nil if total.zero?

        completed = executions.where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_avg_cost(runs)
        count = runs.where.not(total_cost: nil).count
        return nil if count.zero?

        (runs.sum(:total_cost).to_f / count).round(6)
      end

      def calculate_median_duration(runs)
        durations = runs.where(status: "completed").where.not(duration_ms: nil).pluck(:duration_ms).sort
        return nil if durations.empty?

        mid = durations.length / 2
        durations.length.odd? ? durations[mid] : (durations[mid - 1] + durations[mid]) / 2.0
      end

      def calculate_percentile_duration(runs, percentile)
        durations = runs.where(status: "completed").where.not(duration_ms: nil).pluck(:duration_ms).sort
        return nil if durations.empty?

        index = (percentile / 100.0 * durations.length).ceil - 1
        durations[[ index, 0 ].max]
      end

      def count_agent_executions(since)
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .joins("INNER JOIN ai_workflow_nodes ON ai_workflow_nodes.id = ai_workflow_node_executions.ai_workflow_node_id")
                          .where("ai_workflow_nodes.node_type = ?", "ai_agent")
                          .where("ai_workflow_node_executions.created_at >= ?", since)
                          .count
      end

      def calculate_agent_success_rate(since)
        executions = ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                                       .where(ai_workflows: { account_id: account.id })
                                       .joins("INNER JOIN ai_workflow_nodes ON ai_workflow_nodes.id = ai_workflow_node_executions.ai_workflow_node_id")
                                       .where("ai_workflow_nodes.node_type = ?", "ai_agent")
                                       .where("ai_workflow_node_executions.created_at >= ?", since)

        total = executions.where.not(status: %w[running pending]).count
        return nil if total.zero?

        completed = executions.where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_agent_avg_response_time(since)
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .joins("INNER JOIN ai_workflow_nodes ON ai_workflow_nodes.id = ai_workflow_node_executions.ai_workflow_node_id")
                          .where("ai_workflow_nodes.node_type = ?", "ai_agent")
                          .where("ai_workflow_node_executions.created_at >= ?", since)
                          .where(status: "completed")
                          .average(:execution_time_ms)&.to_f&.round(2)
      end

      def calculate_agent_token_usage(since)
        total = 0
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .joins("INNER JOIN ai_workflow_nodes ON ai_workflow_nodes.id = ai_workflow_node_executions.ai_workflow_node_id")
                          .where("ai_workflow_nodes.node_type = ?", "ai_agent")
                          .where("ai_workflow_node_executions.created_at >= ?", since)
                          .pluck(:metadata).each do |metadata|
          usage = metadata&.dig("token_usage") || {}
          total += (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
        end
        total
      end

      def calculate_agent_cost(since)
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .joins("INNER JOIN ai_workflow_nodes ON ai_workflow_nodes.id = ai_workflow_node_executions.ai_workflow_node_id")
                          .where("ai_workflow_nodes.node_type = ?", "ai_agent")
                          .where("ai_workflow_node_executions.created_at >= ?", since)
                          .sum(:cost).to_f.round(6)
      end

      def calculate_provider_tokens(executions)
        total = 0
        executions.pluck(:metadata).each do |metadata|
          usage = metadata&.dig("token_usage") || {}
          total += (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
        end
        total
      end

      def calculate_provider_cost(executions)
        executions.sum(:cost).to_f.round(6)
      end

      def calculate_provider_error_rate(executions)
        total = executions.count
        return 0.0 if total.zero?

        failed = executions.where(status: "failed").count
        (failed.to_f / total * 100).round(2)
      end

      def count_node_executions(since)
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .where("ai_workflow_node_executions.created_at >= ?", since)
                          .count
      end

      def count_retries(since)
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow)
                          .where(ai_workflows: { account_id: account.id })
                          .where("ai_workflow_node_executions.created_at >= ?", since)
                          .where("ai_workflow_node_executions.retry_count > 0")
                          .count
      end

      def count_timeouts(since)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .where("ai_workflow_runs.error_details->>'error_type' IN (?)", %w[workflow_timeout node_timeout])
                     .count
      end

      def calculate_peak_concurrency(since)
        # This would require more sophisticated tracking
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "running").count
      end

      def calculate_avg_queue_time(runs)
        runs.where.not(started_at: nil)
            .select { |r| r.started_at && r.created_at }
            .map { |r| (r.started_at - r.created_at) * 1000 }
            .then { |times| times.empty? ? nil : (times.sum / times.length).round(2) }
      end

      def calculate_percentile_queue_time(runs, percentile)
        times = runs.where.not(started_at: nil)
                   .select { |r| r.started_at && r.created_at }
                   .map { |r| (r.started_at - r.created_at) * 1000 }
                   .sort

        return nil if times.empty?

        index = (percentile / 100.0 * times.length).ceil - 1
        times[[ index, 0 ].max].round(2)
      end

      def calculate_max_queue_time(runs)
        runs.where.not(started_at: nil)
            .select { |r| r.started_at && r.created_at }
            .map { |r| (r.started_at - r.created_at) * 1000 }
            .max&.round(2)
      end

      def calculate_throughput(runs, unit)
        total = runs.count
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
        total_runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                  .where.not(status: %w[running initializing pending])
                                  .count
        return nil if total_runs.zero?

        successful = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                  .where(status: "completed")
                                  .count
        (successful.to_f / total_runs * 100).round(2)
      end

      def calculate_error_budget(runs)
        target_slo = 99.9
        actual_success_rate = (calculate_success_rate(runs) || 0) * 100
        remaining = actual_success_rate - target_slo

        {
          target_slo: target_slo,
          actual_success_rate: actual_success_rate.round(2),
          remaining_budget: remaining.round(2),
          budget_consumed: remaining < 0 ? 100 : ((target_slo - remaining) / target_slo * 100).round(2)
        }
      end

      def analyze_node_performance(workflow, since)
        workflow.nodes.map do |node|
          executions = node.executions.where("ai_workflow_node_executions.created_at >= ?", since)

          {
            node_id: node.node_id,
            node_name: node.name,
            node_type: node.node_type,
            total_executions: executions.count,
            success_rate: calculate_node_success_rate(executions),
            avg_duration_ms: executions.where(status: "completed").average(:execution_time_ms)&.to_f&.round(2),
            total_cost: executions.sum(:cost).to_f.round(6)
          }
        end
      end
    end
  end
end
