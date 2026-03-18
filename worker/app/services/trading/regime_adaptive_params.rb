# frozen_string_literal: true

module Trading
  # Computes parameter adjustments when a market regime shift is detected.
  # Called by the session orchestrator's periodic review cycle.
  #
  # Safety rails:
  #   - No parameter can change by more than 2x from its base value
  #   - Regime must persist for 3+ consecutive evaluations before adjustments apply
  #   - All adjustments logged as audit entries
  #   - Opt-in: strategy must have use_regime_adaptation: true in params
  class RegimeAdaptiveParams
    REGIME_ADJUSTMENTS = {
      "volatile" => {
        "stop_loss_pct" => { multiplier: 1.5 },
        "position_size_pct" => { multiplier: 0.7 },
        "confidence_threshold" => { delta: 0.1 },
        "tick_interval_seconds" => { multiplier: 0.75 }
      },
      "calm" => {
        "tick_interval_seconds" => { multiplier: 0.8 },
        "position_size_pct" => { multiplier: 1.2 },
        "confidence_threshold" => { delta: -0.05 }
      },
      "trending_up" => {
        "autocorr_threshold" => { delta: 0.1 },
        "max_positions" => { multiplier: 0.8 },
        "entry_threshold" => { multiplier: 0.8 }
      },
      "trending_down" => {
        "stop_loss_pct" => { multiplier: 0.8 },
        "position_size_pct" => { multiplier: 0.7 },
        "max_positions" => { multiplier: 0.7 }
      },
      "high_attention" => {
        "tick_interval_seconds" => { multiplier: 0.6 },
        "position_size_pct" => { multiplier: 1.1 },
        "confidence_threshold" => { delta: -0.05 }
      }
    }.freeze

    MAX_CHANGE_FACTOR = 2.0 # No param can change by more than 2x
    MIN_REGIME_PERSISTENCE = 3 # Consecutive evaluations before adjustment

    # Redis key tracking consecutive regime observations per strategy
    REGIME_COUNTER_PREFIX = "trading:regime_count"
    REGIME_COUNTER_TTL = 3600 # 1 hour

    # Compute parameter deltas for a regime shift.
    #
    # @param strategy_type [String]
    # @param current_params [Hash] Current strategy parameters
    # @param regime [String] Current market regime
    # @param strategy_id [String] For regime persistence tracking
    # @return [Hash] Adjusted parameters (merged with current), or nil if no adjustment
    def self.compute_adjustments(strategy_type:, current_params:, regime:, strategy_id:)
      return nil unless current_params["use_regime_adaptation"]
      return nil unless REGIME_ADJUSTMENTS.key?(regime)

      # Check regime persistence — must see the same regime N times before adjusting
      counter_key = "#{REGIME_COUNTER_PREFIX}:#{strategy_id}"
      persistence = increment_regime_counter(counter_key, regime)
      return nil if persistence < MIN_REGIME_PERSISTENCE

      adjustments = REGIME_ADJUSTMENTS[regime]
      adjusted = current_params.dup
      changes = {}

      adjustments.each do |param_key, adjustment|
        base_value = current_params[param_key]
        next unless base_value.is_a?(Numeric)

        new_value = if adjustment[:multiplier]
                      base_value * adjustment[:multiplier]
                    elsif adjustment[:delta]
                      base_value + adjustment[:delta]
                    else
                      base_value
                    end

        # Safety: clamp to 2x range of base value
        min_allowed = base_value / MAX_CHANGE_FACTOR
        max_allowed = base_value * MAX_CHANGE_FACTOR
        new_value = new_value.clamp(min_allowed, max_allowed)

        # Round appropriately
        new_value = new_value.is_a?(Integer) ? new_value.round : new_value.round(4)

        if new_value != base_value
          adjusted[param_key] = new_value
          changes[param_key] = { from: base_value, to: new_value }
        end
      end

      return nil if changes.empty?

      {
        params: adjusted,
        changes: changes,
        regime: regime,
        persistence: persistence
      }
    end

    # Reset the regime counter (called when regime changes)
    def self.reset_regime_counter(strategy_id)
      key = "#{REGIME_COUNTER_PREFIX}:#{strategy_id}"
      Sidekiq.redis { |conn| conn.del(key) }
    rescue StandardError
      # Non-critical
    end

    private_class_method def self.increment_regime_counter(key, regime)
      Sidekiq.redis do |conn|
        # Store as "regime:count" — reset if regime changed
        current = conn.get(key)
        if current
          stored_regime, count = current.split(":", 2)
          if stored_regime == regime
            new_count = count.to_i + 1
            conn.set(key, "#{regime}:#{new_count}", ex: REGIME_COUNTER_TTL)
            return new_count
          end
        end

        # New regime or first observation
        conn.set(key, "#{regime}:1", ex: REGIME_COUNTER_TTL)
        1
      end
    rescue StandardError
      0
    end
  end
end
