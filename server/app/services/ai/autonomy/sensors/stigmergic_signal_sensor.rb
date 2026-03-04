# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class StigmergicSignalSensor < Base
        def collect
          observations = []

          # Check for strong signals that require attention
          strong_signals = Ai::StigmergicSignal.active
            .for_account(account.id)
            .where("strength >= ?", 0.7)
            .where(signal_type: %w[warning beacon])
            .order(strength: :desc)
            .limit(5)

          strong_signals.each do |signal|
            observations << build_observation(
              sensor_type: "stigmergic_signal",
              observation_type: signal.signal_type == "warning" ? "alert" : "recommendation",
              severity: signal.strength >= 0.9 ? "critical" : "warning",
              title: "Strong #{signal.signal_type} signal: #{signal.signal_key}",
              data: {
                signal_id: signal.id,
                signal_type: signal.signal_type,
                signal_key: signal.signal_key,
                strength: signal.strength,
                payload: signal.payload,
                fingerprint: "stigmergic_#{signal.id}"
              },
              requires_action: signal.signal_type == "warning",
              expires_at: 2.hours.from_now
            )
          end

          # Check for fading pheromone trails that may need reinforcement
          fading_count = Ai::StigmergicSignal.fading.for_account(account.id).count
          if fading_count > 10
            observations << build_observation(
              sensor_type: "stigmergic_signal",
              observation_type: "degradation",
              severity: "info",
              title: "#{fading_count} stigmergic signals are fading",
              data: { fading_count: fading_count, fingerprint: "fading_signals_#{fading_count / 10}" },
              requires_action: false,
              expires_at: 6.hours.from_now
            )
          end

          observations
        end
      end
    end
  end
end
