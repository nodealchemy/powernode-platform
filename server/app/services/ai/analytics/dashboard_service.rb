# frozen_string_literal: true

module Ai
  module Analytics
    # Service for generating AI analytics dashboard data and AIOps metrics
    #
    # Consolidates dashboard generation logic including:
    # - Summary metrics and KPIs
    # - Trend analysis
    # - Quick stats and highlights
    # - Real-time metrics
    # - System health monitoring
    # - Provider metrics and circuit breaker status
    # - Active alerts and cost analysis
    #
    # Usage:
    #   service = Ai::Analytics::DashboardService.new(account: current_account, time_range: 30.days)
    #   dashboard = service.generate
    #   health = service.system_health
    #
    class DashboardService
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

      # Generate summary metrics
      # @return [Hash] Summary metrics
      def generate_summary_metrics
        start_time = time_range.ago

        {
          workflows: {
            total: workflows.count,
            active: workflows.where(status: "active").count,
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).count,
            success_rate: calculate_workflow_success_rate(start_time)
          },
          agents: {
            total: agents.count,
            active: agents.active.count,
            executions: agent_executions.where("ai_agent_executions.created_at >= ?", start_time).count,
            success_rate: calculate_agent_success_rate(start_time)
          },
          conversations: {
            total: conversations.count,
            active: conversations.where(status: %w[active in_progress]).count,
            messages: messages.where("ai_messages.created_at >= ?", start_time).count
          },
          cost: {
            total: calculate_total_cost(start_time),
            trend: calculate_cost_trend(start_time),
            budget_utilization: calculate_budget_utilization
          }
        }
      end

      # Generate trend data for charts
      # @return [Hash] Trend data
      def generate_trend_data
        start_time = time_range.ago

        {
          executions_by_day: executions_by_day(start_time),
          cost_by_day: cost_by_day(start_time),
          success_rate_by_day: success_rate_by_day(start_time),
          messages_by_day: messages_by_day(start_time)
        }
      end

      # Generate dashboard highlights
      # @return [Hash] Highlights
      def generate_highlights
        start_time = time_range.ago

        {
          top_workflows: top_workflows(start_time, limit: 5),
          top_agents: top_agents(start_time, limit: 5),
          recent_failures: recent_failures(start_time, limit: 5),
          cost_leaders: cost_leaders(start_time, limit: 5)
        }
      end

      # Generate quick stats
      # @return [Hash] Quick stats
      def generate_quick_stats
        today = Date.current.beginning_of_day
        yesterday = 1.day.ago.beginning_of_day

        {
          today: {
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ?", today).count,
            cost: calculate_period_cost(today, Time.current),
            messages: messages.where("ai_messages.created_at >= ?", today).count
          },
          yesterday: {
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ? AND ai_workflow_runs.created_at < ?", yesterday, today).count,
            cost: calculate_period_cost(yesterday, today),
            messages: messages.where("ai_messages.created_at >= ? AND ai_messages.created_at < ?", yesterday, today).count
          },
          this_week: {
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ?", 1.week.ago).count,
            cost: calculate_period_cost(1.week.ago, Time.current),
            messages: messages.where("ai_messages.created_at >= ?", 1.week.ago).count
          }
        }
      end

      # Generate resource usage data
      # @return [Hash] Resource usage
      def generate_resource_usage
        {
          providers: provider_usage,
          models: model_usage,
          tokens: token_usage
        }
      end

      # Generate recent activity feed
      # @param limit [Integer] Number of activities to return
      # @return [Array<Hash>] Recent activities
      def generate_recent_activity(limit: 20)
        activities = []

        # Recent workflow runs
        workflow_runs.includes(:workflow, :triggered_by_user)
                     .order(created_at: :desc)
                     .limit(limit / 2)
                     .each do |run|
          activities << {
            type: "workflow_run",
            status: run.status,
            resource_name: run.workflow.name,
            user: run.triggered_by_user&.email,
            created_at: run.created_at.iso8601
          }
        end

        # Recent conversations
        conversations.includes(:user)
                     .order(created_at: :desc)
                     .limit(limit / 2)
                     .each do |conv|
          activities << {
            type: "conversation",
            status: conv.status,
            resource_name: conv.title || "Conversation",
            user: conv.user&.email,
            created_at: conv.created_at.iso8601
          }
        end

        activities.sort_by { |a| a[:created_at] }.reverse.first(limit)
      end

      # Generate real-time metrics (for live dashboards, cached for 1 minute)
      # @param force_refresh [Boolean] Skip cache
      # @return [Hash] Real-time metrics
      def real_time_metrics(force_refresh: false)
        cache_key = "ai:dashboard:realtime:#{account.id}"

        Rails.cache.fetch(cache_key, expires_in: REAL_TIME_CACHE_TTL, force: force_refresh) do
          {
            active_executions: workflow_runs.where(status: %w[running initializing]).count,
            active_conversations: conversations.where(status: %w[active in_progress]).count,
            queue_depth: pending_jobs_count,
            error_rate_last_hour: calculate_error_rate(1.hour.ago),
            avg_response_time_last_hour: calculate_avg_response_time(1.hour.ago),
            timestamp: Time.current.iso8601
          }
        end
      end

      # =========================================================================
      # AIOPS METRICS (consolidated from Ai::AiOpsMetricsService)
      # =========================================================================

      # Get comprehensive AIOps dashboard data
      # @param ops_time_range [ActiveSupport::Duration] Time range (default 1.hour)
      # @return [Hash] Complete AIOps dashboard
      def aiops_dashboard(ops_time_range: 1.hour)
        {
          health: system_health,
          overview: system_overview(ops_time_range),
          providers: ops_provider_metrics(ops_time_range),
          workflows: ops_workflow_metrics(ops_time_range),
          agents: ops_agent_metrics(ops_time_range),
          cost_analysis: ops_cost_analysis(ops_time_range),
          alerts: active_alerts,
          circuit_breakers: circuit_breaker_status,
          real_time: aiops_real_time_metrics,
          generated_at: Time.current.iso8601
        }
      end

      # Calculate overall system health score
      # @return [Hash] Health score with component breakdown
      def system_health
        providers_health = calculate_providers_health
        workflows_health = calculate_workflows_health
        agents_health = calculate_agents_health
        infrastructure_health = calculate_infrastructure_health

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

      # Get system overview metrics
      # @param ops_time_range [ActiveSupport::Duration] Time range
      # @return [Hash] System overview
      def system_overview(ops_time_range = 1.hour)
        start_time = ops_time_range.ago

        wf_runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)
        ag_execs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)

        total_workflows = wf_runs.count
        successful_workflows = wf_runs.where(status: "completed").count
        failed_workflows = wf_runs.where(status: "failed").count

        total_executions = ag_execs.count
        successful_executions = ag_execs.where(status: "completed").count

        {
          time_range_seconds: ops_time_range.to_i,
          workflows: {
            total: total_workflows,
            successful: successful_workflows,
            failed: failed_workflows,
            running: wf_runs.where(status: %w[initializing running waiting_approval]).count,
            success_rate: total_workflows > 0 ? (successful_workflows.to_f / total_workflows * 100).round(2) : 100
          },
          executions: {
            total: total_executions,
            successful: successful_executions,
            failed: ag_execs.where(status: "failed").count,
            success_rate: total_executions > 0 ? (successful_executions.to_f / total_executions * 100).round(2) : 100
          },
          performance: {
            avg_workflow_duration_ms: wf_runs.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
            avg_execution_duration_ms: ag_execs.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
            throughput_per_minute: (total_workflows / (ops_time_range / 60.0)).round(2)
          },
          costs: {
            total_workflow_cost: wf_runs.sum(:total_cost).to_f.round(4),
            total_execution_cost: ag_execs.sum(:cost_usd).to_f.round(4),
            total_tokens: ag_execs.sum(:tokens_used)
          }
        }
      end

      # Get provider-level metrics
      # @param ops_time_range [ActiveSupport::Duration] Time range
      # @return [Array<Hash>] Provider metrics
      def ops_provider_metrics(ops_time_range = 1.hour)
        account.ai_providers.map do |provider|
          metrics = ::Ai::ProviderMetric.for_provider(provider)
                                         .for_account(account)
                                         .recent(ops_time_range)

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
                success_rate: calculate_ops_aggregate_success_rate(metrics),
                avg_latency_ms: metrics.average(:avg_latency_ms)&.to_f&.round(2) || 0,
                p95_latency_ms: metrics.maximum(:p95_latency_ms)&.to_f&.round(2) || 0,
                total_tokens: metrics.sum(:total_tokens),
                total_cost_usd: metrics.sum(:total_cost_usd).to_f.round(4)
              },
              circuit_breaker: {
                state: latest.circuit_state || "closed",
                consecutive_failures: latest.consecutive_failures
              },
              error_breakdown: ops_aggregate_error_breakdown(metrics)
            }
          else
            {
              provider_id: provider.id,
              provider_name: provider.name,
              provider_type: provider.provider_type,
              is_active: provider.is_active,
              health_status: "unknown",
              metrics: ops_empty_provider_metrics,
              circuit_breaker: { state: "closed", consecutive_failures: 0 },
              error_breakdown: {}
            }
          end
        end
      end

      # Get provider comparison
      # @param ops_time_range [ActiveSupport::Duration] Time range
      # @return [Hash] Provider comparison data
      def ops_provider_comparison(ops_time_range: 1.hour)
        ::Ai::ProviderMetric.provider_comparison(account, time_range: ops_time_range)
      end

      # Get workflow-level metrics for AIOps
      # @param ops_time_range [ActiveSupport::Duration] Time range
      # @return [Array<Hash>] Workflow metrics
      def ops_workflow_metrics(ops_time_range = 1.hour)
        start_time = ops_time_range.ago

        account.ai_workflows.active.limit(20).map do |workflow|
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

      # Get agent-level metrics for AIOps
      # @param ops_time_range [ActiveSupport::Duration] Time range
      # @return [Array<Hash>] Agent metrics
      def ops_agent_metrics(ops_time_range = 1.hour)
        start_time = ops_time_range.ago

        account.ai_agents.where(status: "active").limit(20).map do |agent|
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

      # Get cost analysis metrics for AIOps
      # @param ops_time_range [ActiveSupport::Duration] Time range
      # @return [Hash] Cost analysis
      def ops_cost_analysis(ops_time_range = 1.hour)
        start_time = ops_time_range.ago

        attributions = ::Ai::CostAttribution.for_account(account)
                                             .where("created_at >= ?", start_time)

        wf_costs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)
                                .sum(:total_cost)

        ag_costs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                                   .sum(:cost_usd)

        {
          time_range_seconds: ops_time_range.to_i,
          totals: {
            workflow_cost: wf_costs.to_f.round(4),
            agent_cost: ag_costs.to_f.round(4),
            total_cost: (wf_costs + ag_costs).to_f.round(4)
          },
          by_category: attributions.any? ?
            attributions.group(:cost_category).sum(:amount_usd) : {},
          by_provider: ops_cost_by_provider(start_time),
          hourly_trend: ops_hourly_cost_trend(ops_time_range),
          optimization_opportunities: ::Ai::CostOptimizationLog.stats_for_account(account, period: ops_time_range)
        }
      end

      # Get active alerts
      # @return [Array<Hash>] Active alerts
      def active_alerts
        alerts = []

        account.ai_providers.each do |provider|
          recent_metrics = ::Ai::ProviderMetric.for_provider(provider)
                                                .for_account(account)
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

        recent_wf = workflow_runs.where("ai_workflow_runs.created_at >= ?", 15.minutes.ago)

        if recent_wf.count > 10
          failure_rate = recent_wf.where(status: "failed").count.to_f / recent_wf.count * 100
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

      # Get circuit breaker status for all providers
      # @return [Array<Hash>] Circuit breaker status
      def circuit_breaker_status
        account.ai_providers.map do |provider|
          recent_metric = ::Ai::ProviderMetric.for_provider(provider)
                                               .for_account(account)
                                               .recent(5.minutes)
                                               .ordered_by_time
                                               .first

          {
            provider_id: provider.id,
            provider_name: provider.name,
            state: recent_metric&.circuit_state || "closed",
            consecutive_failures: recent_metric&.consecutive_failures || 0,
            last_failure_at: nil,
            last_success_at: nil
          }
        end
      end

      # Get AIOps real-time metrics (last 1 minute)
      # @return [Hash] Real-time metrics
      def aiops_real_time_metrics
        start_time = 1.minute.ago

        wf_runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time)
        ag_execs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)

        {
          timestamp: Time.current.iso8601,
          active_workflows: workflow_runs.where(status: %w[initializing running waiting_approval]).count,
          requests_per_minute: wf_runs.count + ag_execs.count,
          success_rate: ops_calculate_combined_success_rate(wf_runs, ag_execs),
          avg_latency_ms: ops_calculate_combined_avg_latency(wf_runs, ag_execs),
          errors_last_minute: wf_runs.where(status: "failed").count + ag_execs.where(status: "failed").count,
          cost_last_minute: (wf_runs.sum(:total_cost) + ag_execs.sum(:cost_usd)).to_f.round(4)
        }
      end

      # Record provider metrics from an execution
      # @param provider [Ai::Provider] Provider
      # @param execution_data [Hash] Execution data
      def record_execution_metrics(provider:, execution_data:)
        ::Ai::ProviderMetric.record_metrics(
          provider: provider,
          account: account,
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

      def agent_executions
        ::Ai::AgentExecution.joins(:agent).where(ai_agents: { account_id: account.id })
      end

      def conversations
        account.ai_conversations
      end

      def messages
        ::Ai::Message.joins(:conversation).where(ai_conversations: { account_id: account.id })
      end

      # =============================================================================
      # CALCULATION HELPERS
      # =============================================================================

      def calculate_workflow_success_rate(since)
        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where.not(status: %w[running initializing pending]).count
        return nil if total.zero?

        completed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_agent_success_rate(since)
        total = agent_executions.where("ai_agent_executions.created_at >= ?", since).where.not(status: %w[running pending]).count
        return nil if total.zero?

        completed = agent_executions.where("ai_agent_executions.created_at >= ?", since).where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_total_cost(since)
        workflow_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).sum(:total_cost).to_f
        # ai_agent_executions uses cost_usd column, not total_cost
        agent_cost = agent_executions.where("ai_agent_executions.created_at >= ?", since).sum(:cost_usd).to_f
        (workflow_cost + agent_cost).round(6)
      end

      def calculate_period_cost(start_time, end_time)
        workflow_cost = workflow_runs.where(ai_workflow_runs: { created_at: start_time..end_time }).sum(:total_cost).to_f
        # ai_agent_executions uses cost_usd column, not total_cost
        agent_cost = agent_executions.where(ai_agent_executions: { created_at: start_time..end_time }).sum(:cost_usd).to_f
        (workflow_cost + agent_cost).round(6)
      end

      def calculate_cost_trend(since)
        previous_period_start = since - time_range
        current_cost = calculate_total_cost(since)
        previous_cost = calculate_period_cost(previous_period_start, since)

        return nil if previous_cost.zero?

        ((current_cost - previous_cost) / previous_cost * 100).round(2)
      end

      def calculate_budget_utilization
        budget = account.settings&.dig("ai_budget_limit") || Float::INFINITY
        return nil if budget.infinite?

        current_cost = calculate_total_cost(time_range.ago)
        ((current_cost / budget) * 100).round(2)
      end

      def calculate_error_rate(since)
        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).count
        return 0.0 if total.zero?

        failed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "failed").count
        (failed.to_f / total * 100).round(2)
      end

      def calculate_avg_response_time(since)
        avg = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                          .where(status: "completed")
                          .where.not(duration_ms: nil)
                          .average(:duration_ms)
        avg&.to_f&.round(2)
      end

      # =============================================================================
      # TREND DATA HELPERS
      # =============================================================================

      def executions_by_day(since)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .group("DATE(ai_workflow_runs.created_at)")
                     .count
                     .transform_keys(&:to_s)
      end

      def cost_by_day(since)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .group("DATE(ai_workflow_runs.created_at)")
                     .sum(:total_cost)
                     .transform_keys(&:to_s)
                     .transform_values { |v| v.to_f.round(6) }
      end

      def success_rate_by_day(since)
        completed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                .where(status: "completed")
                                .group("DATE(ai_workflow_runs.created_at)")
                                .count

        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                            .where.not(status: %w[running initializing pending])
                            .group("DATE(ai_workflow_runs.created_at)")
                            .count

        total.transform_keys(&:to_s).transform_values do |count|
          date = total.key(count)
          next 0.0 if count.zero?

          ((completed[date] || 0).to_f / count * 100).round(2)
        end
      end

      def messages_by_day(since)
        messages.where("ai_messages.created_at >= ?", since)
               .group("DATE(ai_messages.created_at)")
               .count
               .transform_keys(&:to_s)
      end

      # =============================================================================
      # HIGHLIGHTS HELPERS
      # =============================================================================

      def top_workflows(since, limit:)
        workflows.joins(:runs)
                 .where("ai_workflow_runs.created_at >= ?", since)
                 .group("ai_workflows.id", "ai_workflows.name")
                 .order("COUNT(ai_workflow_runs.id) DESC")
                 .limit(limit)
                 .pluck("ai_workflows.id", "ai_workflows.name", Arel.sql("COUNT(ai_workflow_runs.id)"))
                 .map { |id, name, count| { id: id, name: name, execution_count: count } }
      end

      def top_agents(since, limit:)
        agents.joins(:executions)
              .where("ai_agent_executions.created_at >= ?", since)
              .group("ai_agents.id", "ai_agents.name")
              .order("COUNT(ai_agent_executions.id) DESC")
              .limit(limit)
              .pluck("ai_agents.id", "ai_agents.name", Arel.sql("COUNT(ai_agent_executions.id)"))
              .map { |id, name, count| { id: id, name: name, execution_count: count } }
      rescue StandardError
        []
      end

      def recent_failures(since, limit:)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .where(status: "failed")
                     .includes(:workflow)
                     .order("ai_workflow_runs.created_at DESC")
                     .limit(limit)
                     .map do |run|
          {
            run_id: run.run_id,
            workflow_name: run.workflow.name,
            error: run.error_details&.dig("error_message") || "Unknown error",
            failed_at: run.completed_at&.iso8601
          }
        end
      end

      def cost_leaders(since, limit:)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .joins(:workflow)
                     .group("ai_workflows.id", "ai_workflows.name")
                     .order(Arel.sql("SUM(ai_workflow_runs.total_cost) DESC"))
                     .limit(limit)
                     .pluck("ai_workflows.id", "ai_workflows.name", Arel.sql("SUM(ai_workflow_runs.total_cost)"))
                     .map { |id, name, cost| { id: id, name: name, total_cost: cost.to_f.round(6) } }
      end

      # =============================================================================
      # RESOURCE USAGE HELPERS
      # =============================================================================

      def provider_usage
        # Aggregate usage by provider
        {}
      end

      def model_usage
        # Aggregate usage by model
        {}
      end

      def token_usage
        total_input = 0
        total_output = 0

        workflow_runs.where("ai_workflow_runs.created_at >= ?", time_range.ago).each do |run|
          run.node_executions.each do |exec|
            usage = exec.metadata&.dig("token_usage") || {}
            total_input += usage["input_tokens"] || 0
            total_output += usage["output_tokens"] || 0
          end
        end

        {
          total_input_tokens: total_input,
          total_output_tokens: total_output,
          total_tokens: total_input + total_output
        }
      end

      def pending_jobs_count
        # Count pending Sidekiq jobs (if available)
        0
      end

      # =============================================================================
      # AIOPS PRIVATE HELPERS
      # =============================================================================

      def calculate_providers_health
        providers = account.ai_providers.where(is_active: true)
        return { score: 100, status: "healthy", issues: [] } if providers.empty?

        healthy_count = 0
        issues = []

        providers.each do |provider|
          metric = ::Ai::ProviderMetric.for_provider(provider)
                                        .for_account(account)
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
        recent_runs = workflow_runs.where("ai_workflow_runs.created_at >= ?", 1.hour.ago)

        return { score: 100, status: "healthy", issues: [] } if recent_runs.count < 5

        total = recent_runs.count
        successful = recent_runs.where(status: "completed").count
        score = (successful.to_f / total * 100).round(0)

        issues = []
        issues << "#{total - successful} failed workflows in last hour" if score < 95

        { score: score, status: determine_health_status(score), issues: issues }
      end

      def calculate_agents_health
        recent_execs = agent_executions.where("ai_agent_executions.created_at >= ?", 1.hour.ago)

        return { score: 100, status: "healthy", issues: [] } if recent_execs.count < 5

        total = recent_execs.count
        successful = recent_execs.where(status: "completed").count
        score = (successful.to_f / total * 100).round(0)

        issues = []
        issues << "#{total - successful} failed executions in last hour" if score < 95

        { score: score, status: determine_health_status(score), issues: issues }
      end

      def calculate_infrastructure_health
        issues = []
        score = 100

        begin
          ActiveRecord::Base.connection.execute("SELECT 1")
        rescue StandardError
          score -= 50
          issues << "Database connectivity issue"
        end

        begin
          redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
          redis.ping
        rescue StandardError
          score -= 30
          issues << "Redis connectivity issue"
        end

        { score: [score, 0].max, status: determine_health_status(score), issues: issues }
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
        last_failure = workflow_runs.where(status: "failed")
                                    .order(created_at: :desc)
                                    .first

        last_failure&.created_at
      end

      def calculate_uptime_percentage
        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", 24.hours.ago).count

        return 100.0 if total.zero?

        successful = workflow_runs.where("ai_workflow_runs.created_at >= ?", 24.hours.ago)
                                  .where(status: "completed")
                                  .count

        (successful.to_f / total * 100).round(2)
      end

      def calculate_ops_aggregate_success_rate(metrics)
        total_requests = metrics.sum(:request_count)
        return 100.0 if total_requests.zero?

        total_successes = metrics.sum(:success_count)
        (total_successes.to_f / total_requests * 100).round(2)
      end

      def ops_aggregate_error_breakdown(metrics)
        metrics.pluck(:error_breakdown).each_with_object({}) do |breakdown, result|
          next unless breakdown.is_a?(Hash)

          breakdown.each do |error_type, count|
            result[error_type] ||= 0
            result[error_type] += count.to_i
          end
        end
      end

      def ops_empty_provider_metrics
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

      def ops_cost_by_provider(start_time)
        ::Ai::AgentExecution.joins(agent: :provider)
                             .where(ai_agents: { account_id: account.id })
                             .where("ai_agent_executions.created_at >= ?", start_time)
                             .group("ai_providers.id", "ai_providers.name")
                             .sum(:cost_usd)
                             .map { |(id, name), cost| { provider_id: id, provider_name: name, cost_usd: cost.round(4) } }
      end

      def ops_hourly_cost_trend(ops_time_range)
        hours = (ops_time_range / 1.hour).to_i
        hours = [hours, 24].min

        (0...hours).map do |hours_ago|
          start_time = (hours_ago + 1).hours.ago
          end_time = hours_ago.hours.ago

          wf_cost = workflow_runs.where(created_at: start_time..end_time).sum(:total_cost)
          ag_cost = agent_executions.where(created_at: start_time..end_time).sum(:cost_usd)

          {
            hour: end_time.strftime("%H:%M"),
            cost_usd: (wf_cost + ag_cost).to_f.round(4)
          }
        end.reverse
      end

      def ops_calculate_combined_success_rate(wf_runs, ag_execs)
        total = wf_runs.count + ag_execs.count
        return 100.0 if total.zero?

        successful = wf_runs.where(status: "completed").count + ag_execs.where(status: "completed").count
        (successful.to_f / total * 100).round(2)
      end

      def ops_calculate_combined_avg_latency(wf_runs, ag_execs)
        workflow_latencies = wf_runs.where(status: "completed").pluck(:duration_ms).compact
        execution_latencies = ag_execs.where(status: "completed").pluck(:duration_ms).compact

        all_latencies = workflow_latencies + execution_latencies
        return 0 if all_latencies.empty?

        (all_latencies.sum.to_f / all_latencies.length).round(2)
      end
    end
  end
end
