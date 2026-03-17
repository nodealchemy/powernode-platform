# frozen_string_literal: true

module Trading
  module Evaluators
    # Aggregates signals from multiple zero-cost evaluator types on the same market.
    # Inspired by Random Forest voting: each evaluator independently evaluates the
    # market, then signals are aggregated using calibration-weighted consensus.
    #
    # Safe evaluator types (no external API calls, no circular market lookups):
    #   momentum, mean_reversion, prediction_market_making, longshot_fading,
    #   tail_end_yield, arbitrage
    #
    # Excluded (would cause circular deps or incur API costs):
    #   combinatorial_arbitrage, cross_platform_arbitrage, agent_ensemble,
    #   spot_lag_arbitrage, weather_model_alpha, whale_copying
    class MultiStrategyEnsemble < Base
      include Concerns::EnsembleAggregation
      register "multi_strategy_ensemble"

      DEFAULT_ENSEMBLE_TYPES = %w[
        momentum mean_reversion prediction_market_making
        longshot_fading tail_end_yield arbitrage
      ].freeze

      # Types excluded from ensemble to avoid circular deps or external API costs
      EXCLUDED_TYPES = %w[
        combinatorial_arbitrage cross_platform_arbitrage agent_ensemble
        spot_lag_arbitrage weather_model_alpha whale_copying
        multi_strategy_ensemble
      ].freeze

      def evaluate
        types = param("ensemble_types", DEFAULT_ENSEMBLE_TYPES)
        types = types.reject { |t| EXCLUDED_TYPES.include?(t) }

        signal_groups = types.filter_map do |eval_type|
          klass = Base.for_type(eval_type)
          unless klass
            log("Ensemble: unknown evaluator type '#{eval_type}', skipping")
            next
          end

          sub_context = build_sub_context(eval_type)
          evaluator = klass.new(sub_context, data_fetcher: @data_fetcher, price_cache: @price_cache, graph_cache: @graph_cache)
          signals = evaluator.evaluate
          next if signals.nil? || signals.empty?

          { evaluator_type: eval_type, signals: signals }
        rescue StandardError => e
          log("Ensemble: #{eval_type} failed: #{e.message}", level: :warn)
          nil
        end

        if signal_groups.empty?
          log("Ensemble: no evaluators produced signals")
          return []
        end

        log("Ensemble: #{signal_groups.size}/#{types.size} evaluators produced signals " \
            "(#{signal_groups.map { |g| g[:evaluator_type] }.join(', ')})")

        aggregate_signals(signal_groups)
      end

      private

      # Build a sub-context for an individual evaluator type.
      # Clones the current context and swaps strategy parameters with type-specific
      # defaults from ensemble_params overrides or StrategyParameterService defaults.
      def build_sub_context(eval_type)
        overrides = param("ensemble_params", {})[eval_type] || {}

        # Resolve default params for this evaluator type from training parameters
        default_params = default_params_for(eval_type)
        type_params = default_params.merge(overrides)

        # Build a strategy data hash with the sub-evaluator's params
        sub_strategy = @strategy_data.dup
        sub_strategy["parameters"] = type_params
        sub_strategy["strategy_type"] = eval_type

        {
          "strategy" => sub_strategy,
          "market_data" => @market_data,
          "positions" => @positions,
          "provider_config" => nil, # No LLM calls for ensemble sub-evaluators
          "agent_id" => @agent_id,
          "trading_context" => @trading_context,
          "market_question" => @market_question,
          "pair_registry" => @pair_registry,
          "price_history" => @price_history,
          "allocated_capital" => @allocated_capital,
          "market_expiry" => @market_expiry_raw,
          "parity_data" => @parity_data,
          "spot_price" => @spot_price_data,
          "last_entry_indicators" => @last_entry_indicators,
          "order_book" => @order_book_data,
          "performance_context" => @performance_context,
          "is_training" => @is_training
        }
      end

      # Look up default parameters for a given evaluator type.
      # Uses the TRAINING_PARAMETERS constant from LiveTrainingRunner (via the
      # strategy's own parameters which are seeded from there).
      def default_params_for(eval_type)
        # The current strategy's params contain the ensemble config.
        # For sub-evaluators, we need their type-specific defaults.
        # These are available via the strategy_data's parameters hash
        # (seeded by StrategyParameterService/LiveTrainingRunner).
        # Fall back to minimal sensible defaults.
        FALLBACK_PARAMS.fetch(eval_type, {})
      end

      # Minimal fallback params per evaluator type — used when no seeded params exist.
      # In practice, StrategyParameterService provides full params via ensemble_params.
      FALLBACK_PARAMS = {
        "momentum" => {
          "lookback_periods" => 12, "entry_threshold" => 0.02,
          "exit_threshold" => -0.005, "position_size_pct" => 8.0,
          "confidence_threshold" => 0.20, "min_volatility" => 0.001,
          "min_edge_pct" => 3.0, "fee_deduction_rate" => 0.0
        },
        "mean_reversion" => {
          "lookback_periods" => 8, "std_dev_threshold" => 1.0,
          "exit_mean_distance" => 0.3, "position_size_pct" => 6.0,
          "confidence_threshold" => 0.05, "price_bound_min" => 0.05,
          "price_bound_max" => 0.95, "fee_deduction_rate" => 0.0
        },
        "prediction_market_making" => {
          "min_spread_cents" => 2, "max_spread_cents" => 6,
          "risk_aversion_gamma" => 0.08, "max_inventory_pct" => 12.0,
          "quote_size_pct" => 5.0, "confidence_threshold" => 0.3,
          "fee_deduction_rate" => 0.0
        },
        "longshot_fading" => {
          "min_price" => 0.02, "max_price" => 0.30,
          "min_edge_pct" => 0.3, "max_position_pct" => 2.0,
          "kelly_fraction" => 0.25, "confidence_threshold" => 0.40,
          "fee_deduction_rate" => 0.0
        },
        "tail_end_yield" => {
          "min_price" => 0.80, "max_price" => 0.99,
          "min_yield_pct" => 0.5, "reversal_exit_price" => 0.70,
          "position_size_pct" => 15.0, "confidence_threshold" => 0.5,
          "fee_deduction_rate" => 0.0
        },
        "arbitrage" => {
          "min_parity_gap" => 0.003, "max_parity_gap" => 0.10,
          "position_size_pct" => 5.0, "confidence_threshold" => 0.3,
          "use_multi_leg" => true, "fee_deduction_rate" => 0.0
        }
      }.freeze
    end
  end
end
