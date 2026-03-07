# frozen_string_literal: true

module Ai
  module Analytics
    class DashboardService
      module AiopsMetrics
        extend ActiveSupport::Concern

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

        def ops_provider_comparison(ops_time_range: 1.hour) = ::Ai::ProviderMetric.provider_comparison(account, time_range: ops_time_range)

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
            redis = Powernode::Redis.client
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

        def last_incident_time = workflow_runs.where(status: "failed").order(created_at: :desc).first&.created_at

        def calculate_uptime_percentage
          total = workflow_runs.where("ai_workflow_runs.created_at >= ?", 24.hours.ago).count
          return 100.0 if total.zero?

          successful = workflow_runs.where("ai_workflow_runs.created_at >= ?", 24.hours.ago)
                                    .where(status: "completed").count
          (successful.to_f / total * 100).round(2)
        end

        def calculate_ops_aggregate_success_rate(metrics)
          total_requests = metrics.sum(:request_count)
          return 100.0 if total_requests.zero?
          (metrics.sum(:success_count).to_f / total_requests * 100).round(2)
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
          { request_count: 0, success_count: 0, failure_count: 0, success_rate: 100,
            avg_latency_ms: 0, p95_latency_ms: 0, total_tokens: 0, total_cost_usd: 0 }
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

            { hour: end_time.strftime("%H:%M"), cost_usd: (wf_cost + ag_cost).to_f.round(4) }
          end.reverse
        end

        def ops_calculate_combined_success_rate(wf_runs, ag_execs)
          total = wf_runs.count + ag_execs.count
          return 100.0 if total.zero?
          successful = wf_runs.where(status: "completed").count + ag_execs.where(status: "completed").count
          (successful.to_f / total * 100).round(2)
        end

        def ops_calculate_combined_avg_latency(wf_runs, ag_execs)
          all_latencies = wf_runs.where(status: "completed").pluck(:duration_ms).compact +
                          ag_execs.where(status: "completed").pluck(:duration_ms).compact
          return 0 if all_latencies.empty?
          (all_latencies.sum.to_f / all_latencies.length).round(2)
        end
      end
    end
  end
end
