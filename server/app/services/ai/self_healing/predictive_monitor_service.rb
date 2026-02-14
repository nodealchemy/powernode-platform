# frozen_string_literal: true

module Ai
  module SelfHealing
    class PredictiveMonitorService
      ROLLING_WINDOW = 15.minutes
      TREND_WINDOWS = [5.minutes, 15.minutes, 1.hour].freeze
      ERROR_RATE_THRESHOLD = 0.3        # 30% error rate triggers alert
      LATENCY_SPIKE_MULTIPLIER = 2.5    # 2.5x baseline = spike
      COST_SPIKE_MULTIPLIER = 3.0       # 3x baseline = cost anomaly
      FAILURE_PROBABILITY_THRESHOLD = 0.7

      def initialize(account:)
        @account = account
      end

      # Analyze trends and return failure predictions
      def analyze
        predictions = []

        predictions.concat(analyze_provider_health)
        predictions.concat(analyze_execution_trends)
        predictions.concat(analyze_cost_trends)

        predictions.select { |p| p[:probability] >= FAILURE_PROBABILITY_THRESHOLD }
                   .sort_by { |p| -p[:probability] }
      end

      # Run analysis and trigger preemptive remediation for high-probability failures
      def analyze_and_remediate!
        predictions = analyze
        remediations = []

        predictions.each do |prediction|
          action = determine_preemptive_action(prediction)
          next unless action

          result = RemediationDispatcher.dispatch(
            account: @account,
            trigger_source: "predictive_monitor",
            trigger_event: prediction[:event_type],
            context: prediction.merge(preemptive: true, action_hint: action)
          )

          remediations << {
            prediction: prediction,
            action: action,
            result: result
          }

          record_learning(prediction, action, result)
        end

        {
          predictions_count: predictions.size,
          remediations_count: remediations.size,
          predictions: predictions,
          remediations: remediations,
          analyzed_at: Time.current.iso8601
        }
      end

      private

      def analyze_provider_health
        predictions = []

        active_credentials = Ai::ProviderCredential
          .where(account_id: @account.id, is_active: true)
          .includes(:provider)

        active_credentials.each do |credential|
          metrics = provider_metrics(credential)
          next unless metrics[:total_requests] >= 5

          probability = calculate_provider_failure_probability(metrics)
          next if probability < FAILURE_PROBABILITY_THRESHOLD

          predictions << {
            event_type: "provider_degradation",
            source: "provider",
            source_id: credential.ai_provider_id,
            source_name: credential.provider&.name,
            probability: probability.round(3),
            signals: metrics[:signals],
            metrics: metrics.except(:signals),
            message: "Provider #{credential.provider&.name} showing degradation signals"
          }
        end

        predictions
      end

      def analyze_execution_trends
        predictions = []

        TREND_WINDOWS.each do |window|
          recent = execution_metrics(window)
          baseline = execution_metrics(window * 4, offset: window)
          next unless recent[:total] >= 3 && baseline[:total] >= 3

          error_rate_trend = recent[:error_rate] - baseline[:error_rate]
          latency_trend = baseline[:avg_latency] > 0 ? recent[:avg_latency] / baseline[:avg_latency] : 1.0

          signals = []
          probability = 0.0

          if recent[:error_rate] > ERROR_RATE_THRESHOLD
            signals << "error_rate_#{(recent[:error_rate] * 100).round}pct"
            probability += 0.4
          end

          if error_rate_trend > 0.15
            signals << "error_rate_rising"
            probability += 0.2
          end

          if latency_trend > LATENCY_SPIKE_MULTIPLIER
            signals << "latency_spike_#{latency_trend.round(1)}x"
            probability += 0.3
          end

          next if signals.empty?

          predictions << {
            event_type: "execution_degradation",
            source: "executions",
            source_id: nil,
            source_name: "AI Executions (#{window.inspect} window)",
            probability: [probability, 1.0].min.round(3),
            signals: signals,
            metrics: {
              window: window.to_i,
              recent_error_rate: recent[:error_rate].round(3),
              baseline_error_rate: baseline[:error_rate].round(3),
              recent_avg_latency: recent[:avg_latency].round(0),
              baseline_avg_latency: baseline[:avg_latency].round(0),
              latency_ratio: latency_trend.round(2)
            },
            message: "Execution quality degrading: #{signals.join(', ')}"
          }
        end

        # Deduplicate: keep highest probability across windows
        predictions.group_by { |p| p[:event_type] }
                   .values
                   .map { |group| group.max_by { |p| p[:probability] } }
      end

      def analyze_cost_trends
        predictions = []

        recent_cost = cost_metrics(1.hour)
        baseline_cost = cost_metrics(6.hours, offset: 1.hour)

        return predictions unless recent_cost[:total_cost] > 0 && baseline_cost[:hourly_avg] > 0

        cost_ratio = recent_cost[:total_cost] / baseline_cost[:hourly_avg]

        if cost_ratio > COST_SPIKE_MULTIPLIER
          predictions << {
            event_type: "cost_anomaly",
            source: "cost",
            source_id: nil,
            source_name: "AI Cost Monitor",
            probability: [0.5 + (cost_ratio - COST_SPIKE_MULTIPLIER) * 0.1, 1.0].min.round(3),
            signals: ["cost_spike_#{cost_ratio.round(1)}x"],
            metrics: {
              recent_cost: recent_cost[:total_cost].round(4),
              baseline_hourly_avg: baseline_cost[:hourly_avg].round(4),
              cost_ratio: cost_ratio.round(2)
            },
            message: "Cost spike detected: #{cost_ratio.round(1)}x baseline"
          }
        end

        predictions
      end

      def provider_metrics(credential)
        window_start = ROLLING_WINDOW.ago
        executions = Ai::AgentExecution.where(account_id: @account.id)
                                        .where("created_at >= ?", window_start)

        # Filter by provider via agent association
        provider_executions = executions.joins(:agent)
                                         .where(ai_agents: { ai_provider_id: credential.ai_provider_id })

        total = provider_executions.count
        return { total_requests: 0, signals: [] } if total.zero?

        failed = provider_executions.where(status: %w[failed error]).count
        error_rate = failed.to_f / total

        durations = provider_executions.where.not(completed_at: nil)
                                        .pluck(Arel.sql("EXTRACT(EPOCH FROM (completed_at - started_at))"))
                                        .compact
        avg_latency = durations.any? ? durations.sum / durations.size : 0

        signals = []
        signals << "high_error_rate" if error_rate > ERROR_RATE_THRESHOLD
        signals << "consecutive_failures" if credential.respond_to?(:consecutive_failures) && (credential.consecutive_failures || 0) >= 3

        {
          total_requests: total,
          failed_requests: failed,
          error_rate: error_rate,
          avg_latency_seconds: avg_latency,
          signals: signals
        }
      end

      def calculate_provider_failure_probability(metrics)
        probability = 0.0

        if metrics[:error_rate] > ERROR_RATE_THRESHOLD
          probability += 0.4 + (metrics[:error_rate] - ERROR_RATE_THRESHOLD) * 0.5
        end

        if metrics[:signals].include?("consecutive_failures")
          probability += 0.3
        end

        [probability, 1.0].min
      end

      def execution_metrics(window, offset: 0.seconds)
        window_end = offset.ago
        window_start = (window + offset).ago

        executions = Ai::AgentExecution.where(account_id: @account.id)
                                        .where("created_at >= ? AND created_at < ?", window_start, window_end)

        total = executions.count
        return { total: 0, error_rate: 0.0, avg_latency: 0.0 } if total.zero?

        failed = executions.where(status: %w[failed error]).count
        durations = executions.where.not(completed_at: nil)
                              .pluck(Arel.sql("EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000"))
                              .compact
        avg_latency = durations.any? ? durations.sum / durations.size : 0

        {
          total: total,
          failed: failed,
          error_rate: failed.to_f / total,
          avg_latency: avg_latency
        }
      end

      def cost_metrics(window, offset: 0.seconds)
        window_end = offset.ago
        window_start = (window + offset).ago

        total_cost = Ai::AgentExecution.where(account_id: @account.id)
                                        .where("created_at >= ? AND created_at < ?", window_start, window_end)
                                        .sum(:cost_usd)

        hours = window.to_f / 1.hour
        hourly_avg = hours > 0 ? total_cost / hours : 0

        { total_cost: total_cost.to_f, hourly_avg: hourly_avg, hours: hours }
      end

      def determine_preemptive_action(prediction)
        case prediction[:event_type]
        when "provider_degradation"
          "provider_failover"
        when "execution_degradation"
          if prediction[:signals]&.include?("latency_spike")
            "model_downgrade"
          else
            "alert_escalation"
          end
        when "cost_anomaly"
          "alert_escalation"
        end
      end

      def record_learning(prediction, action, result)
        return unless defined?(Ai::CompoundLearningService)

        Ai::CompoundLearningService.new(account: @account).record_extraction(
          source_type: "self_healing",
          source_id: prediction[:source_id],
          learning_type: "remediation_outcome",
          content: "Predictive remediation: #{action} triggered by #{prediction[:event_type]} " \
                   "(probability: #{prediction[:probability]}, signals: #{prediction[:signals]&.join(', ')})",
          effectiveness: result.is_a?(Hash) && result[:status] == "success" ? 0.8 : 0.3,
          metadata: {
            prediction: prediction.except(:metrics),
            action: action,
            result_status: result.is_a?(Hash) ? result[:status] : nil
          }
        )
      rescue StandardError => e
        Rails.logger.warn "[PredictiveMonitor] Failed to record learning: #{e.message}"
      end
    end
  end
end
