# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Aggregates signals from multiple evaluator types running on the same market.
      # Implements weighted voting inspired by Random Forest — each evaluator votes,
      # weighted by its calibrated accuracy. Echo chamber detection (from AgentEnsemble)
      # penalizes suspiciously unanimous consensus.
      module EnsembleAggregation
        # Aggregate signal groups into consensus signals.
        #
        # @param signal_groups [Array<Hash>] each: { evaluator_type:, signals: [...] }
        # @return [Array<Hash>] aggregated signals (one per direction that meets threshold)
        def aggregate_signals(signal_groups)
          return [] if signal_groups.empty?

          # Flatten all signals and group by (type, direction)
          all_signals = signal_groups.flat_map do |group|
            group[:signals].map { |s| s.merge(_evaluator_type: group[:evaluator_type]) }
          end

          grouped = all_signals.group_by { |s| "#{s[:type]}_#{s[:direction]}" }
          min_voters = param("min_voters", 2).to_i
          echo_threshold = param("echo_chamber_threshold", 0.05).to_f
          echo_penalty = param("echo_chamber_penalty", 0.7).to_f

          aggregated = []

          grouped.each do |_group_key, signals|
            next if signals.size < min_voters

            # Weight each signal by its calibration factor.
            # Evaluators with higher historical precision get more vote weight.
            weights = signals.map do |s|
              calibration_weight_for_signal(s)
            end

            total_weight = weights.sum
            next if total_weight <= 0

            # Weighted average confidence
            weighted_conf = signals.zip(weights).sum { |s, w| s[:confidence].to_f * w } / total_weight

            # Echo chamber detection: if all voters agree with very low variance,
            # discount to prevent false confidence from correlated signals.
            confidences = signals.map { |s| s[:confidence].to_f }
            if confidences.size >= 2
              mean_conf = confidences.sum / confidences.size
              variance = confidences.sum { |c| (c - mean_conf)**2 } / confidences.size
              std_dev = Math.sqrt(variance)

              if std_dev < echo_threshold
                weighted_conf *= echo_penalty
              end
            end

            # Merge indicator data from individual signals
            individual_signals = signals.map do |s|
              { evaluator_type: s[:_evaluator_type], confidence: s[:confidence],
                direction: s[:direction], reasoning: s[:reasoning]&.truncate(120) }
            end

            # Use the best edge from any voter
            best_edge = signals.filter_map { |s| s.dig(:indicators, :edge) }.max
            best_net_edge = signals.filter_map { |s| s.dig(:indicators, :net_edge) }.max

            base_signal = signals.max_by { |s| s[:confidence].to_f }
            merged_indicators = (base_signal[:indicators] || {}).merge(
              individual_signals: individual_signals,
              ensemble_voters: signals.size,
              ensemble_weights: signals.zip(weights).map { |s, w| { type: s[:_evaluator_type], weight: w.round(3) } },
              edge: best_edge,
              net_edge: best_net_edge
            )

            aggregated << {
              type: base_signal[:type],
              direction: base_signal[:direction],
              confidence: weighted_conf.clamp(0.0, 1.0),
              strength: signals.map { |s| s[:strength] }.compact.max,
              reasoning: "Ensemble (#{signals.size} evaluators: #{signals.map { |s| s[:_evaluator_type] }.join(', ')}): " \
                         "weighted confidence #{weighted_conf.round(3)}",
              indicators: merged_indicators,
              urgency: base_signal[:urgency]
            }
          end

          aggregated
        end

        private

        # Derive a weight for a signal based on its evaluator type's calibration.
        # Falls back to 1.0 (equal weight) when no calibration data exists.
        def calibration_weight_for_signal(signal)
          # Use raw_confidence from indicators (pre-calibration) to look up factor
          raw_conf = signal.dig(:indicators, :raw_confidence) || signal[:confidence].to_f
          factor = calibration_factor_for(raw_conf)
          [factor, 0.1].max # Floor at 0.1 to never fully silence an evaluator
        rescue StandardError
          1.0
        end
      end
    end
  end
end
