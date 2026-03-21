# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Multi-source weather probability blending using inverse-variance weighting.
      # Combines GFS forecasts, real-time observations, CPC outlooks, and climate
      # normals into a single blended probability estimate.
      module WeatherEnsemble
        DEFAULT_SOURCE_WEIGHTS = {
          "noaa_gfs" => 1.0,
          "noaa_observations" => 0.6,
          "noaa_cpc" => 0.8,
          "noaa_ncei" => 0.4
        }.freeze

        # Blend multiple weather source estimates into a single probability.
        #
        # @param source_estimates [Array<Hash>] each: { source:, probability:, confidence:, freshness_hours: }
        # @return [Hash] { blended_probability:, source_count:, source_details: [] }
        def blend_weather_sources(source_estimates)
          valid = source_estimates.select { |e| e[:probability] && e[:probability].between?(0.0, 1.0) }
          return nil if valid.empty?

          if valid.size == 1
            return {
              blended_probability: valid.first[:probability],
              source_count: 1,
              source_details: valid
            }
          end

          weight_overrides = param("weather_source_weights", {})
          base_weights = DEFAULT_SOURCE_WEIGHTS.merge(
            weight_overrides.transform_keys(&:to_s)
          )
          disagreement_penalty = param("ensemble_disagreement_penalty", 0.15).to_f

          # Calculate weighted probability
          weights = valid.map do |est|
            w = (base_weights[est[:source].to_s] || 0.5).to_f

            # Freshness decay: halve weight for each 12 hours of age
            if est[:freshness_hours] && est[:freshness_hours] > 0
              decay = 0.5**(est[:freshness_hours].to_f / 12.0)
              w *= decay
            end

            # Confidence scaling
            w *= (est[:confidence] || 0.7).to_f

            [w, 0.01].max # Floor to prevent zero-weight
          end

          total_weight = weights.sum
          blended = valid.zip(weights).sum { |est, w| est[:probability] * w } / total_weight

          # Disagreement penalty: pull toward 0.5 when sources diverge
          probs = valid.map { |e| e[:probability] }
          spread = probs.max - probs.min
          if spread > 0.15 # Significant disagreement
            penalty_factor = 1.0 - (disagreement_penalty * spread)
            blended = blended * penalty_factor + 0.5 * (1.0 - penalty_factor)
          end

          # Corroboration bonus: when sources agree, boost away from 0.5
          if spread < 0.08 && valid.size >= 2
            mean_prob = probs.sum / probs.size
            # Push 5% further from 0.5 in the direction of agreement
            direction = mean_prob > 0.5 ? 1.0 : -1.0
            blended += direction * 0.05 * (1.0 - spread / 0.08)
          end

          {
            blended_probability: blended.clamp(0.01, 0.99),
            source_count: valid.size,
            spread: spread.round(4),
            source_details: valid.zip(weights).map do |est, w|
              {
                source: est[:source],
                probability: est[:probability].round(4),
                weight: (w / total_weight).round(3),
                freshness_hours: est[:freshness_hours]
              }
            end
          }
        end
      end
    end
  end
end
