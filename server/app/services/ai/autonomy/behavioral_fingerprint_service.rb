# frozen_string_literal: true

module Ai
  module Autonomy
    class BehavioralFingerprintService
      DEFAULT_ROLLING_WINDOW_DAYS = 7
      DEFAULT_DEVIATION_THRESHOLD = 2.0
      MAX_RECENT_OBSERVATIONS = 100

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Record an observation for a metric
      # @param agent [Ai::Agent] The agent
      # @param metric_name [String] The metric name (e.g., "tool_call_rate", "error_rate")
      # @param value [Float] The observed value
      # @return [Hash] { anomaly: Boolean, z_score: Float, fingerprint: BehavioralFingerprint }
      def record_observation(agent:, metric_name:, value:)
        fingerprint = find_or_create(agent, metric_name)
        is_anomaly = fingerprint.observation_count >= 5 && fingerprint.anomalous?(value)

        # Append observation
        observations = (fingerprint.recent_observations || []).last(MAX_RECENT_OBSERVATIONS - 1)
        observations << { value: value, timestamp: Time.current.iso8601, anomaly: is_anomaly }

        attrs = {
          recent_observations: observations,
          observation_count: fingerprint.observation_count + 1,
          last_observation_at: Time.current
        }
        attrs[:anomaly_count] = fingerprint.anomaly_count + 1 if is_anomaly

        fingerprint.update!(attrs)

        # Update baseline with rolling window
        update_baseline(fingerprint) if fingerprint.observation_count % 10 == 0

        z_score = fingerprint.baseline_stddev.positive? ? ((value - fingerprint.baseline_mean).abs / fingerprint.baseline_stddev).round(4) : 0.0

        { anomaly: is_anomaly, z_score: z_score, fingerprint: fingerprint }
      end

      # Detect anomaly for a specific metric value without recording
      # @return [Hash] { anomaly: Boolean, z_score: Float }
      def detect_anomaly(agent:, metric_name:, value:)
        fingerprint = Ai::BehavioralFingerprint.find_by(agent_id: agent.id, metric_name: metric_name)
        return { anomaly: false, z_score: 0.0, insufficient_data: true } unless fingerprint&.observation_count&.>=(5)

        z_score = fingerprint.baseline_stddev.positive? ? ((value - fingerprint.baseline_mean).abs / fingerprint.baseline_stddev).round(4) : 0.0

        { anomaly: fingerprint.anomalous?(value), z_score: z_score, insufficient_data: false }
      end

      # Update baseline from recent observations within the rolling window
      # @param fingerprint [Ai::BehavioralFingerprint]
      def update_baseline(fingerprint)
        cutoff = fingerprint.rolling_window_days.days.ago
        recent = (fingerprint.recent_observations || []).select do |obs|
          Time.parse(obs["timestamp"]) >= cutoff
        rescue StandardError
          false
        end

        return if recent.size < 3

        values = recent.map { |obs| obs["value"].to_f }
        mean = values.sum / values.size
        variance = values.sum { |v| (v - mean)**2 } / values.size
        stddev = Math.sqrt(variance)

        fingerprint.update!(
          baseline_mean: mean.round(6),
          baseline_stddev: [stddev.round(6), 0.001].max # Avoid zero stddev
        )
      end

      # Get all fingerprints for an agent
      def fingerprints_for(agent)
        Ai::BehavioralFingerprint.for_agent(agent.id).where(account_id: account.id)
      end

      private

      def find_or_create(agent, metric_name)
        Ai::BehavioralFingerprint.find_or_create_by!(agent_id: agent.id, metric_name: metric_name) do |fp|
          fp.account = account
          fp.rolling_window_days = DEFAULT_ROLLING_WINDOW_DAYS
          fp.deviation_threshold = DEFAULT_DEVIATION_THRESHOLD
        end
      end
    end
  end
end
