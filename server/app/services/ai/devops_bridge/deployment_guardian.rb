# frozen_string_literal: true

module Ai
  module DevopsBridge
    class DeploymentGuardian
      HEALTH_CHECK_INTERVAL = 30.seconds
      MAX_MONITORING_DURATION = 30.minutes

      def initialize(account:)
        @account = account
      end

      def monitor_deployment(pipeline_run:, strategy: :canary)
        return { recommendation: "skip", reason: "Feature not enabled" } unless Shared::FeatureFlagService.enabled?(:cross_system_triggers)

        health_data = collect_health_data(pipeline_run)
        analysis = analyze_deployment_health(health_data, strategy)

        log_guardian_decision(pipeline_run, analysis)

        analysis
      end

      def recommend_action(pipeline_run:)
        health = collect_health_data(pipeline_run)

        if health[:error_rate] > 10
          { recommendation: "rollback", confidence: 0.9, reason: "Error rate #{health[:error_rate]}% exceeds 10% threshold" }
        elsif health[:latency_p95] > health[:baseline_latency] * 2
          { recommendation: "hold", confidence: 0.7, reason: "Latency #{health[:latency_p95]}ms is 2x baseline" }
        elsif health[:error_rate] < 1 && health[:latency_p95] <= health[:baseline_latency] * 1.2
          { recommendation: "promote", confidence: 0.8, reason: "Deployment metrics within acceptable range" }
        else
          { recommendation: "hold", confidence: 0.5, reason: "Metrics inconclusive, continue monitoring" }
        end
      end

      private

      def collect_health_data(pipeline_run)
        # Collect recent execution metrics since deployment started
        since = pipeline_run.started_at || 30.minutes.ago

        recent_events = Ai::ExecutionEvent.by_account(@account.id)
                                          .in_time_range(since)

        total = recent_events.count
        errors = recent_events.with_errors.count
        durations = recent_events.where.not(duration_ms: nil).pluck(:duration_ms)

        {
          error_rate: total > 0 ? (errors.to_f / total * 100).round(1) : 0,
          total_events: total,
          error_count: errors,
          latency_p95: calculate_p95(durations),
          baseline_latency: calculate_baseline_latency,
          deployment_age_minutes: since ? ((Time.current - since) / 60).round(1) : 0
        }
      end

      def analyze_deployment_health(health_data, strategy)
        recommendation = if health_data[:error_rate] > 10
          "rollback"
        elsif health_data[:error_rate] > 5
          "hold"
        elsif health_data[:deployment_age_minutes] < 5
          "hold"
        else
          "promote"
        end

        {
          recommendation: recommendation,
          mode: "recommendation_only",
          strategy: strategy,
          health: health_data,
          analyzed_at: Time.current.iso8601
        }
      end

      def calculate_p95(durations)
        return 0 if durations.empty?

        sorted = durations.sort
        index = (sorted.size * 0.95).ceil - 1
        sorted[[index, 0].max]
      end

      def calculate_baseline_latency
        baseline_events = Ai::ExecutionEvent.by_account(@account.id)
                                            .in_time_range(7.days.ago, 1.day.ago)
                                            .where.not(duration_ms: nil)

        durations = baseline_events.pluck(:duration_ms)
        calculate_p95(durations)
      end

      def log_guardian_decision(pipeline_run, analysis)
        Ai::RemediationLog.create!(
          account: @account,
          trigger_source: "DeploymentGuardian",
          trigger_event: "deployment_analysis",
          action_type: "alert_escalation",
          action_config: { pipeline_run_id: pipeline_run.id, strategy: analysis[:strategy] },
          before_state: analysis[:health],
          after_state: { recommendation: analysis[:recommendation] },
          result: "success",
          result_message: "Recommendation: #{analysis[:recommendation]}",
          executed_at: Time.current
        )
      rescue => e
        Rails.logger.error "[DeploymentGuardian] Failed to log decision: #{e.message}"
      end
    end
  end
end
