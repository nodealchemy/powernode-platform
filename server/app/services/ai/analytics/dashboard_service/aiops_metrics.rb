# frozen_string_literal: true

module Ai
  module Analytics
    class DashboardService
      module AiopsMetrics
        extend ActiveSupport::Concern

        def aiops_dashboard(ops_time_range: 1.hour)
          overview = system_overview(ops_time_range)
          overview[:latency_aggregate] = ops_aggregate_latency(ops_time_range)

          {
            health: system_health,
            overview: overview,
            providers: ops_provider_metrics(ops_time_range),
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
          agents_health = calculate_agents_health
          infrastructure_health = calculate_infrastructure_health

          overall_score = (
            providers_health[:score] * 0.4 +
            agents_health[:score] * 0.3 +
            infrastructure_health[:score] * 0.3
          ).round(0)

          {
            overall_score: overall_score,
            status: determine_health_status(overall_score),
            components: {
              providers: providers_health,
              agents: agents_health,
              infrastructure: infrastructure_health
            },
            last_incident: last_incident_time,
            uptime_percentage: calculate_uptime_percentage
          }
        end

        def system_overview(ops_time_range = 1.hour)
          start_time = ops_time_range.ago

          ag_execs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)

          total_executions = ag_execs.count
          successful_executions = ag_execs.where(status: "completed").count

          {
            time_range_seconds: ops_time_range.to_i,
            executions: {
              total: total_executions,
              successful: successful_executions,
              failed: ag_execs.where(status: "failed").count,
              success_rate: total_executions > 0 ? (successful_executions.to_f / total_executions * 100).round(2) : 100
            },
            performance: {
              avg_execution_duration_ms: ag_execs.where(status: "completed").average(:duration_ms)&.to_f&.round(2) || 0,
              throughput_per_minute: (total_executions / (ops_time_range / 60.0)).round(2)
            },
            costs: {
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

        def ops_agent_metrics(ops_time_range = 1.hour)
          start_time = ops_time_range.ago

          account.ai_agents.where(status: "active").includes(:provider).limit(20).map do |agent|
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

          ag_costs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                                     .sum(:cost_usd)

          {
            time_range_seconds: ops_time_range.to_i,
            totals: {
              agent_cost: ag_costs.to_f.round(4),
              total_cost: ag_costs.to_f.round(4)
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

          ag_execs = agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
          requests_last_minute = ag_execs.count
          errors_last_minute = ag_execs.where(status: "failed").count

          {
            timestamp: Time.current.iso8601,
            # Windowed rates over the trailing minute.
            current_requests_per_second: (requests_last_minute / 60.0).round(2),
            current_avg_latency_ms: ops_calculate_combined_avg_latency(ag_execs),
            # 0.0–1.0 fraction (frontend multiplies by 100 for display).
            current_error_rate: requests_last_minute.positive? ? (errors_last_minute.to_f / requests_last_minute).round(4) : 0.0,
            # Point-in-time gauges: executions running / waiting right now.
            active_connections: agent_executions.running.count,
            queue_depth: agent_executions.pending.count
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

        # Aggregate provider latency across the account for a time window.
        # Single aggregate query over Ai::ProviderMetric (all granularities).
        # @param ops_time_range [ActiveSupport::Duration]
        # @return [Hash] { avg_ms:, p95_ms:, p99_ms:, max_ms:, sample_provider_count: }
        def ops_aggregate_latency(ops_time_range = 1.hour)
          metrics = ::Ai::ProviderMetric.for_account(account).recent(ops_time_range)

          avg, p95, p99, max, sample = metrics.pluck(
            Arel.sql("AVG(avg_latency_ms)"),
            Arel.sql("MAX(p95_latency_ms)"),
            Arel.sql("MAX(p99_latency_ms)"),
            Arel.sql("MAX(max_latency_ms)"),
            Arel.sql("COUNT(DISTINCT provider_id) FILTER (WHERE request_count > 0)")
          ).first

          {
            avg_ms: avg.to_f.round(2),
            p95_ms: p95.to_f.round(2),
            p99_ms: p99.to_f.round(2),
            max_ms: max.to_f.round(2),
            sample_provider_count: sample.to_i
          }
        end

        # Hourly operational trend series (latency, error rate, throughput, cost).
        # Every series is zero-filled to the full ascending UTC hourly bucket list,
        # so callers can chart without handling sparse/missing buckets. Bucket keys
        # are ISO8601 UTC strings truncated to the hour. Capped at 168 buckets (7d).
        #
        # Latency / error / throughput source from Ai::ProviderMetric.hourly_metrics
        # (the only place with real p95/p99). When the account has no hourly provider
        # metrics in range, it falls back to a grouped query over the account-scoped
        # agent executions (documented degradation: p95_ms == p99_ms == avg_ms). Cost
        # always comes from the account-scoped executions for consistency.
        #
        # @param ops_time_range [ActiveSupport::Duration]
        # @return [Hash]
        def aiops_trends(ops_time_range = 24.hours)
          buckets = ops_hourly_bucket_times(ops_time_range)
          keys = buckets.map(&:iso8601)
          start_time = buckets.first

          metric_buckets = ops_trend_metric_buckets(start_time)
          cost_buckets = ops_trend_cost_buckets(start_time)

          {
            time_range_seconds: ops_time_range.to_i,
            bucket: "hour",
            bucket_count: keys.length,
            latency: keys.map do |k|
              data = metric_buckets[k]
              {
                bucket: k,
                avg_ms: data ? data[:avg_ms] : 0.0,
                p95_ms: data ? data[:p95_ms] : 0.0,
                p99_ms: data ? data[:p99_ms] : 0.0
              }
            end,
            error_rate: keys.map do |k|
              data = metric_buckets[k]
              requests = data ? data[:request_count] : 0
              failures = data ? data[:failure_count] : 0
              {
                bucket: k,
                error_rate: requests.positive? ? (failures.to_f / requests).round(4) : 0.0,
                request_count: requests
              }
            end,
            throughput: keys.map do |k|
              data = metric_buckets[k]
              requests = data ? data[:request_count] : 0
              {
                bucket: k,
                requests: requests,
                requests_per_minute: requests / 60.0
              }
            end,
            cost: keys.map do |k|
              { bucket: k, cost_usd: (cost_buckets[k] || 0.0).round(4) }
            end
          }
        end

        # Recent failed executions for the account, newest first.
        # Reuses TrendsAndHighlights#recent_failures over the service's time_range.
        # @param limit [Integer]
        # @return [Array<Hash>] [{ execution_id:, agent_name:, error:, failed_at: }]
        def ops_recent_errors(limit: 20)
          recent_failures(@time_range.ago, limit: limit)
        end

        private

        # Canonical ascending (oldest -> newest) list of UTC hourly bucket Times,
        # ending at the current hour. Length capped at 168 (7d), floored at 1.
        def ops_hourly_bucket_times(ops_time_range)
          bucket_count = (ops_time_range / 1.hour).to_i
          bucket_count = 168 if bucket_count > 168
          bucket_count = 1 if bucket_count < 1

          current_hour = Time.current.utc.change(min: 0, sec: 0, usec: 0)
          (0...bucket_count).map { |i| current_hour - (bucket_count - 1 - i).hours }
        end

        # Normalize a grouped DATE_TRUNC('hour', ...) key (Time or String) to the
        # canonical UTC hour ISO8601 string. DATE_TRUNC preserves the stored UTC
        # wall-clock digits, so reconstruct the bucket from those digits as UTC
        # regardless of the adapter's local-offset decoding.
        def ops_hour_bucket_key(value)
          time = value.is_a?(String) ? Time.parse(value) : value
          Time.utc(time.year, time.month, time.day, time.hour).iso8601
        end

        # Per-hour latency/error/throughput buckets keyed by canonical UTC ISO key.
        # Primary source: hourly provider metrics. Fallback: account-scoped agent
        # executions (p95 == p99 == avg degradation).
        def ops_trend_metric_buckets(start_time)
          bucket_expr = Arel.sql("DATE_TRUNC('hour', recorded_at)")
          hourly = ::Ai::ProviderMetric.for_account(account)
                                       .hourly_metrics
                                       .where("recorded_at >= ?", start_time)

          if hourly.exists?
            hourly.group(bucket_expr).pluck(
              bucket_expr,
              Arel.sql("AVG(avg_latency_ms)"),
              Arel.sql("MAX(p95_latency_ms)"),
              Arel.sql("MAX(p99_latency_ms)"),
              Arel.sql("SUM(request_count)"),
              Arel.sql("SUM(failure_count)")
            ).each_with_object({}) do |(bucket, avg, p95, p99, requests, failures), result|
              result[ops_hour_bucket_key(bucket)] = {
                avg_ms: avg.to_f.round(2),
                p95_ms: p95.to_f.round(2),
                p99_ms: p99.to_f.round(2),
                request_count: requests.to_i,
                failure_count: failures.to_i
              }
            end
          else
            exec_bucket_expr = Arel.sql("DATE_TRUNC('hour', ai_agent_executions.created_at)")
            agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                            .group(exec_bucket_expr).pluck(
                              exec_bucket_expr,
                              Arel.sql("AVG(ai_agent_executions.duration_ms) FILTER (WHERE ai_agent_executions.status = 'completed')"),
                              Arel.sql("COUNT(*)"),
                              Arel.sql("COUNT(*) FILTER (WHERE ai_agent_executions.status = 'failed')")
                            ).each_with_object({}) do |(bucket, avg, requests, failures), result|
              avg_ms = avg.to_f.round(2)
              result[ops_hour_bucket_key(bucket)] = {
                avg_ms: avg_ms,
                p95_ms: avg_ms,
                p99_ms: avg_ms,
                request_count: requests.to_i,
                failure_count: failures.to_i
              }
            end
          end
        end

        # Per-hour cost buckets (USD) keyed by canonical UTC ISO key, sourced from
        # the account-scoped agent executions (consistent with ops_hourly_cost_trend).
        def ops_trend_cost_buckets(start_time)
          bucket_expr = Arel.sql("DATE_TRUNC('hour', ai_agent_executions.created_at)")
          agent_executions.where("ai_agent_executions.created_at >= ?", start_time)
                          .group(bucket_expr)
                          .sum(:cost_usd)
                          .each_with_object({}) do |(bucket, cost), result|
            result[ops_hour_bucket_key(bucket)] = cost.to_f
          end
        end

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

        def last_incident_time
          agent_executions.where(status: "failed").order(created_at: :desc).first&.created_at
        end

        def calculate_uptime_percentage
          total = agent_executions.where("ai_agent_executions.created_at >= ?", 24.hours.ago).count
          return 100.0 if total.zero?

          successful = agent_executions.where("ai_agent_executions.created_at >= ?", 24.hours.ago)
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

            ag_cost = agent_executions.where(created_at: start_time..end_time).sum(:cost_usd)

            { hour: end_time.strftime("%H:%M"), cost_usd: ag_cost.to_f.round(4) }
          end.reverse
        end

        def ops_calculate_combined_success_rate(ag_execs)
          total = ag_execs.count
          return 100.0 if total.zero?
          successful = ag_execs.where(status: "completed").count
          (successful.to_f / total * 100).round(2)
        end

        def ops_calculate_combined_avg_latency(ag_execs)
          all_latencies = ag_execs.where(status: "completed").pluck(:duration_ms).compact
          return 0 if all_latencies.empty?
          (all_latencies.sum.to_f / all_latencies.length).round(2)
        end
      end
    end
  end
end
