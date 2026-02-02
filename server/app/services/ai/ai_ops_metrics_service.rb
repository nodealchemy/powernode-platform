# frozen_string_literal: true

module Ai
  class AiOpsMetricsService
    include ActiveModel::Model

    # Thresholds for health status determination
    HEALTH_THRESHOLDS = {
      healthy: { success_rate: 95, latency_p95: 5000, error_rate: 5 },
      degraded: { success_rate: 80, latency_p95: 10000, error_rate: 20 },
      unhealthy: { success_rate: 0, latency_p95: Float::INFINITY, error_rate: 100 }
    }.freeze

    def initialize(account:)
      @account = account
      @logger = Rails.logger
      @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
    end

    # ==========================================================================
    # DASHBOARD
    # ==========================================================================

    # Get comprehensive AIOps dashboard data
    def dashboard(time_range: 1.hour)
      {
        health: system_health,
        overview: system_overview(time_range),
        providers: provider_metrics(time_range),
        workflows: workflow_metrics(time_range),
        agents: agent_metrics(time_range),
        cost_analysis: cost_analysis(time_range),
        alerts: active_alerts,
        circuit_breakers: circuit_breaker_status,
        real_time: real_time_metrics,
        generated_at: Time.current.iso8601
      }
    end

    # ==========================================================================
    # SYSTEM HEALTH
    # ==========================================================================

    # Calculate overall system health score
    def system_health
      providers_health = calculate_providers_health
      workflows_health = calculate_workflows_health
      agents_health = calculate_agents_health
      infrastructure_health = calculate_infrastructure_health

      # Weighted health score
      overall_score = (
        providers_health[:score] * 0.3 +
        workflows_health[:score] * 0.3 +
        agents_health[:score] * 0.2 +
        infrastructure_health[:score] * 0.2
      ).round(0)

      {
        overall_score: overall_score,
        status: determine_health_status(overall_score),
        components: {
          providers: providers_health,
          workflows: workflows_health,
          agents: agents_health,
          infrastructure: infrastructure_health
        },
        last_incident: last_incident_time,
        uptime_percentage: calculate_uptime_percentage
      }
    end

    # ==========================================================================
    # SYSTEM OVERVIEW
    # ==========================================================================

    # Get system overview metrics
    def system_overview(time_range = 1.hour)
      start_time = time_range.ago

      workflow_runs = Ai::WorkflowRun.joins(:workflow)
                                      .where(ai_workflows: { account_id: @account.id })
                                      .where("ai_workflow_runs.created_at >= ?", start_time)

      agent_executions = Ai::AgentExecution.joins(:agent)
                                            .where(ai_agents: { account_id: @account.id })
                                            .where("ai_agent_executions.created_at >= ?", start_time)

      total_workflows = workflow_runs.count
      successful_workflows = workflow_runs.where(status: "completed").count
      failed_workflows = workflow_runs.where(status: "failed").count

      total_executions = agent_executions.count
      successful_executions = agent_executions.where(status: "completed").count

      {
        time_range_seconds: time_range.to_i,
        workflows: {
          total: total_workflows,
          successful: successful_workflows,
          failed: failed_workflows,
          running: workflow_runs.where(status: %w[initializing running waiting_approval]).count,
          success_rate: total_workflows > 0 ? (successful_workflows.to_f / total_workflows * 100).round(2) : 100
        },
        executions: {
          total: total_executions,
          successful: successful_executions,
          failed: agent_executions.where(status: "failed").count,
          success_rate: total_executions > 0 ? (successful_executions.to_f / total_executions * 100).round(2) : 100
        },
        performance: {
          avg_workflow_duration_ms: workflow_runs.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
          avg_execution_duration_ms: agent_executions.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
          throughput_per_minute: (total_workflows / (time_range / 60.0)).round(2)
        },
        costs: {
          total_workflow_cost: workflow_runs.sum(:total_cost).to_f.round(4),
          total_execution_cost: agent_executions.sum(:cost_usd).to_f.round(4),
          total_tokens: agent_executions.sum(:tokens_used)
        }
      }
    end

    # ==========================================================================
    # PROVIDER METRICS
    # ==========================================================================

    # Get provider-level metrics
    def provider_metrics(time_range = 1.hour)
      @account.ai_providers.map do |provider|
        metrics = Ai::ProviderMetric.for_provider(provider)
                                     .for_account(@account)
                                     .recent(time_range)

        if metrics.any?
          latest = metrics.ordered_by_time.first
          {
            provider_id: provider.id,
            provider_name: provider.name,
            provider_type: provider.provider_type,
            is_active: provider.is_active,
            health_status: latest.health_status,
            metrics: {
              request_count: metrics.sum(:request_count),
              success_count: metrics.sum(:success_count),
              failure_count: metrics.sum(:failure_count),
              success_rate: calculate_aggregate_success_rate(metrics),
              avg_latency_ms: metrics.average(:avg_latency_ms)&.to_f&.round(2) || 0,
              p95_latency_ms: metrics.maximum(:p95_latency_ms)&.to_f&.round(2) || 0,
              total_tokens: metrics.sum(:total_tokens),
              total_cost_usd: metrics.sum(:total_cost_usd).to_f.round(4)
            },
            circuit_breaker: {
              state: latest.circuit_state || "closed",
              consecutive_failures: latest.consecutive_failures
            },
            error_breakdown: aggregate_error_breakdown(metrics)
          }
        else
          {
            provider_id: provider.id,
            provider_name: provider.name,
            provider_type: provider.provider_type,
            is_active: provider.is_active,
            health_status: "unknown",
            metrics: empty_provider_metrics,
            circuit_breaker: { state: "closed", consecutive_failures: 0 },
            error_breakdown: {}
          }
        end
      end
    end

    # Get provider comparison
    def provider_comparison(time_range: 1.hour)
      Ai::ProviderMetric.provider_comparison(@account, time_range: time_range)
    end

    # ==========================================================================
    # WORKFLOW METRICS
    # ==========================================================================

    # Get workflow-level metrics
    def workflow_metrics(time_range = 1.hour)
      start_time = time_range.ago

      @account.ai_workflows.active.limit(20).map do |workflow|
        runs = workflow.runs.where("created_at >= ?", start_time)

        total = runs.count
        successful = runs.where(status: "completed").count
        failed = runs.where(status: "failed").count

        {
          workflow_id: workflow.id,
          workflow_name: workflow.name,
          is_active: workflow.is_active,
          metrics: {
            total_runs: total,
            successful: successful,
            failed: failed,
            running: runs.where(status: %w[initializing running waiting_approval]).count,
            success_rate: total > 0 ? (successful.to_f / total * 100).round(2) : 100,
            avg_duration_ms: runs.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
            total_cost: runs.sum(:total_cost).to_f.round(4)
          },
          recent_status: runs.order(created_at: :desc).first&.status || "idle",
          last_run_at: runs.order(created_at: :desc).first&.created_at
        }
      end
    end

    # ==========================================================================
    # AGENT METRICS
    # ==========================================================================

    # Get agent-level metrics
    def agent_metrics(time_range = 1.hour)
      start_time = time_range.ago

      @account.ai_agents.where(status: "active").limit(20).map do |agent|
        executions = agent.executions.where("created_at >= ?", start_time)

        total = executions.count
        successful = executions.where(status: "completed").count

        {
          agent_id: agent.id,
          agent_name: agent.name,
          agent_type: agent.agent_type,
          status: agent.status,
          provider_name: agent.provider&.name,
          metrics: {
            total_executions: total,
            successful: successful,
            failed: executions.where(status: "failed").count,
            success_rate: total > 0 ? (successful.to_f / total * 100).round(2) : 100,
            avg_duration_ms: executions.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
            total_tokens: executions.sum(:tokens_used),
            total_cost: executions.sum(:cost_usd).to_f.round(4)
          },
          last_execution_at: executions.order(created_at: :desc).first&.created_at
        }
      end
    end

    # ==========================================================================
    # COST ANALYSIS
    # ==========================================================================

    # Get cost analysis metrics
    def cost_analysis(time_range = 1.hour)
      start_time = time_range.ago
      start_date = start_time.to_date

      # Get attributions for the period
      attributions = Ai::CostAttribution.for_account(@account)
                                         .where("created_at >= ?", start_time)

      workflow_costs = Ai::WorkflowRun.joins(:workflow)
                                       .where(ai_workflows: { account_id: @account.id })
                                       .where("ai_workflow_runs.created_at >= ?", start_time)
                                       .sum(:total_cost)

      agent_costs = Ai::AgentExecution.joins(:agent)
                                       .where(ai_agents: { account_id: @account.id })
                                       .where("ai_agent_executions.created_at >= ?", start_time)
                                       .sum(:cost_usd)

      {
        time_range_seconds: time_range.to_i,
        totals: {
          workflow_cost: workflow_costs.to_f.round(4),
          agent_cost: agent_costs.to_f.round(4),
          total_cost: (workflow_costs + agent_costs).to_f.round(4)
        },
        by_category: attributions.any? ?
          attributions.group(:cost_category).sum(:amount_usd) : {},
        by_provider: cost_by_provider(start_time),
        hourly_trend: hourly_cost_trend(time_range),
        optimization_opportunities: Ai::CostOptimizationLog.stats_for_account(@account, period: time_range)
      }
    end

    # ==========================================================================
    # ALERTS
    # ==========================================================================

    # Get active alerts
    def active_alerts
      alerts = []

      # Check for provider issues
      @account.ai_providers.each do |provider|
        recent_metrics = Ai::ProviderMetric.for_provider(provider)
                                            .for_account(@account)
                                            .recent(5.minutes)
                                            .ordered_by_time
                                            .first

        next unless recent_metrics

        if recent_metrics.unhealthy?
          alerts << {
            type: "provider_unhealthy",
            severity: "critical",
            provider_id: provider.id,
            provider_name: provider.name,
            message: "Provider #{provider.name} is unhealthy (success rate: #{recent_metrics.success_rate}%)",
            detected_at: Time.current
          }
        elsif recent_metrics.degraded?
          alerts << {
            type: "provider_degraded",
            severity: "warning",
            provider_id: provider.id,
            provider_name: provider.name,
            message: "Provider #{provider.name} is degraded",
            detected_at: Time.current
          }
        end

        if recent_metrics.circuit_state == "open"
          alerts << {
            type: "circuit_breaker_open",
            severity: "warning",
            provider_id: provider.id,
            provider_name: provider.name,
            message: "Circuit breaker is open for #{provider.name}",
            detected_at: Time.current
          }
        end
      end

      # Check for high failure rate in workflows
      recent_workflows = Ai::WorkflowRun.joins(:workflow)
                                         .where(ai_workflows: { account_id: @account.id })
                                         .where("ai_workflow_runs.created_at >= ?", 15.minutes.ago)

      if recent_workflows.count > 10
        failure_rate = recent_workflows.where(status: "failed").count.to_f / recent_workflows.count * 100
        if failure_rate > 20
          alerts << {
            type: "high_failure_rate",
            severity: "critical",
            message: "High workflow failure rate: #{failure_rate.round(1)}%",
            detected_at: Time.current
          }
        end
      end

      alerts
    end

    # ==========================================================================
    # CIRCUIT BREAKER STATUS
    # ==========================================================================

    # Get circuit breaker status for all providers
    def circuit_breaker_status
      @account.ai_providers.map do |provider|
        recent_metric = Ai::ProviderMetric.for_provider(provider)
                                           .for_account(@account)
                                           .recent(5.minutes)
                                           .ordered_by_time
                                           .first

        {
          provider_id: provider.id,
          provider_name: provider.name,
          state: recent_metric&.circuit_state || "closed",
          consecutive_failures: recent_metric&.consecutive_failures || 0,
          last_failure_at: nil, # Would need separate tracking
          last_success_at: nil
        }
      end
    end

    # ==========================================================================
    # REAL-TIME METRICS
    # ==========================================================================

    # Get real-time metrics (last 1 minute)
    def real_time_metrics
      start_time = 1.minute.ago

      workflow_runs = Ai::WorkflowRun.joins(:workflow)
                                      .where(ai_workflows: { account_id: @account.id })
                                      .where("ai_workflow_runs.created_at >= ?", start_time)

      agent_executions = Ai::AgentExecution.joins(:agent)
                                            .where(ai_agents: { account_id: @account.id })
                                            .where("ai_agent_executions.created_at >= ?", start_time)

      {
        timestamp: Time.current.iso8601,
        active_workflows: Ai::WorkflowRun.joins(:workflow)
                                          .where(ai_workflows: { account_id: @account.id })
                                          .where(status: %w[initializing running waiting_approval])
                                          .count,
        requests_per_minute: workflow_runs.count + agent_executions.count,
        success_rate: calculate_combined_success_rate(workflow_runs, agent_executions),
        avg_latency_ms: calculate_combined_avg_latency(workflow_runs, agent_executions),
        errors_last_minute: workflow_runs.where(status: "failed").count + agent_executions.where(status: "failed").count,
        cost_last_minute: (workflow_runs.sum(:total_cost) + agent_executions.sum(:cost_usd)).to_f.round(4)
      }
    end

    # ==========================================================================
    # METRIC RECORDING
    # ==========================================================================

    # Record provider metrics from an execution
    def record_execution_metrics(provider:, execution_data:)
      Ai::ProviderMetric.record_metrics(
        provider: provider,
        account: @account,
        metrics_data: {
          requests: 1,
          successes: execution_data[:success] ? 1 : 0,
          failures: execution_data[:success] ? 0 : 1,
          timeouts: execution_data[:timeout] ? 1 : 0,
          rate_limits: execution_data[:rate_limited] ? 1 : 0,
          input_tokens: execution_data[:input_tokens] || 0,
          output_tokens: execution_data[:output_tokens] || 0,
          cost_usd: execution_data[:cost_usd] || 0,
          latency_ms: execution_data[:latency_ms],
          error_type: execution_data[:error_type],
          model_name: execution_data[:model_name],
          circuit_state: execution_data[:circuit_state],
          consecutive_failures: execution_data[:consecutive_failures]
        }
      )
    end

    private

    # ==========================================================================
    # PRIVATE HELPER METHODS
    # ==========================================================================

    def calculate_providers_health
      providers = @account.ai_providers.where(is_active: true)
      return { score: 100, status: "healthy", issues: [] } if providers.empty?

      healthy_count = 0
      issues = []

      providers.each do |provider|
        metric = Ai::ProviderMetric.for_provider(provider)
                                    .for_account(@account)
                                    .recent(15.minutes)
                                    .ordered_by_time
                                    .first

        if metric.nil? || metric.healthy?
          healthy_count += 1
        else
          issues << "#{provider.name}: #{metric.health_status}"
        end
      end

      score = (healthy_count.to_f / providers.count * 100).round(0)

      { score: score, status: determine_health_status(score), issues: issues }
    end

    def calculate_workflows_health
      recent_runs = Ai::WorkflowRun.joins(:workflow)
                                    .where(ai_workflows: { account_id: @account.id })
                                    .where("ai_workflow_runs.created_at >= ?", 1.hour.ago)

      return { score: 100, status: "healthy", issues: [] } if recent_runs.count < 5

      total = recent_runs.count
      successful = recent_runs.where(status: "completed").count
      score = (successful.to_f / total * 100).round(0)

      issues = []
      issues << "#{total - successful} failed workflows in last hour" if score < 95

      { score: score, status: determine_health_status(score), issues: issues }
    end

    def calculate_agents_health
      recent_executions = Ai::AgentExecution.joins(:agent)
                                             .where(ai_agents: { account_id: @account.id })
                                             .where("ai_agent_executions.created_at >= ?", 1.hour.ago)

      return { score: 100, status: "healthy", issues: [] } if recent_executions.count < 5

      total = recent_executions.count
      successful = recent_executions.where(status: "completed").count
      score = (successful.to_f / total * 100).round(0)

      issues = []
      issues << "#{total - successful} failed executions in last hour" if score < 95

      { score: score, status: determine_health_status(score), issues: issues }
    end

    def calculate_infrastructure_health
      issues = []
      score = 100

      # Check database
      begin
        ActiveRecord::Base.connection.execute("SELECT 1")
      rescue StandardError => e
        score -= 50
        issues << "Database connectivity issue"
      end

      # Check Redis
      begin
        @redis.ping
      rescue StandardError => e
        score -= 30
        issues << "Redis connectivity issue"
      end

      { score: [ score, 0 ].max, status: determine_health_status(score), issues: issues }
    end

    def determine_health_status(score)
      case score
      when 90..100 then "healthy"
      when 70..89 then "degraded"
      when 50..69 then "unhealthy"
      else "critical"
      end
    end

    def last_incident_time
      # Find the most recent failure
      last_failure = Ai::WorkflowRun.joins(:workflow)
                                     .where(ai_workflows: { account_id: @account.id })
                                     .where(status: "failed")
                                     .order(created_at: :desc)
                                     .first

      last_failure&.created_at
    end

    def calculate_uptime_percentage
      # Calculate based on workflow success rate over 24 hours
      total = Ai::WorkflowRun.joins(:workflow)
                              .where(ai_workflows: { account_id: @account.id })
                              .where("ai_workflow_runs.created_at >= ?", 24.hours.ago)
                              .count

      return 100.0 if total.zero?

      successful = Ai::WorkflowRun.joins(:workflow)
                                   .where(ai_workflows: { account_id: @account.id })
                                   .where("ai_workflow_runs.created_at >= ?", 24.hours.ago)
                                   .where(status: "completed")
                                   .count

      (successful.to_f / total * 100).round(2)
    end

    def calculate_aggregate_success_rate(metrics)
      total_requests = metrics.sum(:request_count)
      return 100.0 if total_requests.zero?

      total_successes = metrics.sum(:success_count)
      (total_successes.to_f / total_requests * 100).round(2)
    end

    def aggregate_error_breakdown(metrics)
      metrics.pluck(:error_breakdown).each_with_object({}) do |breakdown, result|
        next unless breakdown.is_a?(Hash)

        breakdown.each do |error_type, count|
          result[error_type] ||= 0
          result[error_type] += count.to_i
        end
      end
    end

    def empty_provider_metrics
      {
        request_count: 0,
        success_count: 0,
        failure_count: 0,
        success_rate: 100,
        avg_latency_ms: 0,
        p95_latency_ms: 0,
        total_tokens: 0,
        total_cost_usd: 0
      }
    end

    def cost_by_provider(start_time)
      Ai::AgentExecution.joins(agent: :provider)
                         .where(ai_agents: { account_id: @account.id })
                         .where("ai_agent_executions.created_at >= ?", start_time)
                         .group("ai_providers.id", "ai_providers.name")
                         .sum(:cost_usd)
                         .map { |(id, name), cost| { provider_id: id, provider_name: name, cost_usd: cost.round(4) } }
    end

    def hourly_cost_trend(time_range)
      hours = (time_range / 1.hour).to_i
      hours = [ hours, 24 ].min

      (0...hours).map do |hours_ago|
        start_time = (hours_ago + 1).hours.ago
        end_time = hours_ago.hours.ago

        workflow_cost = Ai::WorkflowRun.joins(:workflow)
                                        .where(ai_workflows: { account_id: @account.id })
                                        .where(created_at: start_time..end_time)
                                        .sum(:total_cost)

        agent_cost = Ai::AgentExecution.joins(:agent)
                                        .where(ai_agents: { account_id: @account.id })
                                        .where(created_at: start_time..end_time)
                                        .sum(:cost_usd)

        {
          hour: end_time.strftime("%H:%M"),
          cost_usd: (workflow_cost + agent_cost).to_f.round(4)
        }
      end.reverse
    end

    def calculate_combined_success_rate(workflows, executions)
      total = workflows.count + executions.count
      return 100.0 if total.zero?

      successful = workflows.where(status: "completed").count + executions.where(status: "completed").count
      (successful.to_f / total * 100).round(2)
    end

    def calculate_combined_avg_latency(workflows, executions)
      workflow_latencies = workflows.where(status: "completed").pluck(:duration_ms).compact
      execution_latencies = executions.where(status: "completed").pluck(:duration_ms).compact

      all_latencies = workflow_latencies + execution_latencies
      return 0 if all_latencies.empty?

      (all_latencies.sum.to_f / all_latencies.length).round(2)
    end
  end
end
