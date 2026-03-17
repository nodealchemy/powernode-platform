# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Tracks signal prediction accuracy per confidence bucket and adjusts
      # future probability/confidence estimates for better Kelly sizing.
      #
      # Calibration data is stored in strategy_config["signal_calibration"]
      # and persists across ticks. The concern reads historical precision
      # data and applies adjustments:
      #
      #   calibrated = raw × (precision / expected_precision)
      #
      # Where precision = TP/(TP+FP) for a confidence bucket and
      # expected_precision = bucket midpoint.
      #
      # When no calibration data exists, all adjustments are identity (1.0).
      module SignalCalibration
        CONFIDENCE_BUCKETS = [
          [0.0, 0.3],
          [0.3, 0.5],
          [0.5, 0.7],
          [0.7, 0.9],
          [0.9, 1.01]  # 1.01 to capture exactly 1.0
        ].freeze

        # Apply calibration factor to a confidence value.
        # Used in build_signal to adjust the reported confidence.
        #
        # @param raw_confidence [Float] original confidence (0-1)
        # @param type [String] signal type ("entry" or "exit")
        # @return [Float] calibrated confidence
        def calibrate_confidence(raw_confidence, type: "entry")
          return raw_confidence unless type == "entry"

          factor = calibration_factor_for(raw_confidence)
          (raw_confidence * factor).clamp(0.0, 1.0)
        end

        # Apply calibration to a probability estimate.
        # Used by evaluators before passing to Kelly sizing.
        #
        # @param raw_prob [Float] raw probability estimate (0-1)
        # @return [Float] calibrated probability
        def calibrate_probability(raw_prob)
          factor = calibration_factor_for(raw_prob)
          (raw_prob * factor).clamp(0.001, 0.999)
        end

        # Record a signal outcome for calibration tracking.
        # Call this when a trade closes to update the rolling precision data.
        #
        # @param confidence [Float] the signal's original confidence at entry
        # @param profitable [Boolean] whether the trade was profitable
        # @param direction [String] "long" or "short"
        def record_signal_outcome(confidence:, profitable:, direction: nil)
          bucket = bucket_for(confidence)
          return unless bucket

          calibration_data = load_calibration_data
          key = bucket_key(bucket)
          entry = calibration_data["buckets"][key] ||= { "tp" => 0, "fp" => 0, "total" => 0 }

          if profitable
            entry["tp"] += 1
          else
            entry["fp"] += 1
          end
          entry["total"] += 1

          # Rolling window: cap at max_samples to prevent stale data dominance
          max_samples = param("calibration_max_samples", 200)
          if entry["total"] > max_samples
            scale = max_samples.to_f / entry["total"]
            entry["tp"] = (entry["tp"] * scale).round
            entry["fp"] = (entry["fp"] * scale).round
            entry["total"] = entry["tp"] + entry["fp"]
          end

          calibration_data["last_updated"] = Time.current.iso8601
          @_pending_calibration_update = calibration_data
        end

        # Flush pending calibration updates to strategy config.
        # Called after evaluation to batch config writes.
        #
        # @return [Hash, nil] calibration data to merge into config_updates, or nil
        def pending_calibration_config
          @_pending_calibration_update
        end

        private

        def calibration_factor_for(value)
          bucket = bucket_for(value)
          return 1.0 unless bucket

          calibration_data = load_calibration_data
          key = bucket_key(bucket)
          entry = calibration_data.dig("buckets", key)
          return 1.0 unless entry

          total = (entry["total"] || 0).to_i
          min_samples = param("calibration_min_samples", 10)
          return 1.0 if total < min_samples

          tp = (entry["tp"] || 0).to_i
          fp = (entry["fp"] || 0).to_i
          return 1.0 if (tp + fp) == 0

          precision = tp.to_f / (tp + fp)
          expected = (bucket[0] + bucket[1]) / 2.0
          expected = [expected, 0.1].max # Floor to avoid division explosion

          factor = precision / expected
          factor = factor.clamp(0.5, 2.0)
          log("Calibration: bucket=#{key} precision=#{precision.round(3)} factor=#{factor.round(3)} (#{total} samples)")
          factor
        end

        def bucket_for(value)
          CONFIDENCE_BUCKETS.find { |low, high| value >= low && value < high }
        end

        def bucket_key(bucket)
          "#{bucket[0]}-#{bucket[1]}"
        end

        def load_calibration_data
          @_calibration_data ||= begin
            raw = strategy_config["signal_calibration"]
            if raw.is_a?(Hash)
              raw["buckets"] ||= {}
              raw
            else
              { "buckets" => {} }
            end
          end
        end
      end
    end
  end
end
