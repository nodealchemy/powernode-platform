# frozen_string_literal: true

module Trading
  # Pure-computation module for filtering strategy-market assignments.
  # Moved from LiveTrainingRunner to the worker so affinity filtering
  # runs locally without a backend API call.
  #
  # Markets are expected as hashes with symbol keys:
  #   { question:, volume_24h:, pairs:, yes_price:, parity_gap:, category:, event_ticker: }
  module MarketAffinity
    # Per-strategy-type market affinity filters.
    # Each entry defines a lambda that receives (market_hash, pair_prices, opts)
    # and returns true if the strategy type is compatible with that market.
    # Strategies not listed here receive all markets (backwards compatible).
    STRATEGY_MARKET_AFFINITY = {
      # --- Price-range specialists ---
      "longshot_fading" => {
        price_range: (0.02..0.25),
        filter: ->(market, _pp, _opts) {
          market[:yes_price]&.between?(0.02, 0.25) ||
            (1.0 - (market[:yes_price] || 0.5)).between?(0.02, 0.25)
        }
      },
      "tail_end_yield" => {
        price_range: (0.80..0.99),
        filter: ->(market, _pp, _opts) {
          market[:yes_price]&.between?(0.80, 0.99) ||
            (1.0 - (market[:yes_price] || 0.5)).between?(0.80, 0.99)
        }
      },
      "combinatorial_arbitrage" => {
        price_range: (0.15..0.85),
        filter: ->(market, _pp, _opts) {
          next false unless market[:yes_price]&.between?(0.15, 0.85)
          next false if market[:volume_24h].to_f < 100
          low_efficiency = %w[Entertainment Sports]
          next false if low_efficiency.include?(market[:category])
          true
        }
      },

      # --- Parity/spread-dependent ---
      "arbitrage" => {
        filter: ->(market, _pp, _opts) {
          (market[:parity_gap] || 0) > 0.003
        }
      },

      # --- Volume/volatility-dependent ---
      "momentum" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          market[:volume_24h].to_f >= 5_000 && p.between?(0.10, 0.90)
        }
      },
      "mean_reversion" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          p.between?(0.10, 0.90) && market[:volume_24h].to_f >= 1_000
        }
      },

      # --- Orderbook-dependent ---
      "market_making" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          market[:volume_24h].to_f >= 1_000 && p.between?(0.05, 0.95)
        }
      },
      "prediction_market_making" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          p.between?(0.01, 0.99) && market[:volume_24h].to_f >= 500
        }
      },

      # --- Question-text-dependent (LLM strategies) ---
      "llm_probability" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          market[:question].present? && p.between?(0.01, 0.99)
        }
      },
      "agent_ensemble" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          market[:question].present? && p.between?(0.01, 0.99)
        }
      },
      "sentiment_analysis" => {
        filter: ->(market, _pp, _opts) { market[:question].present? }
      },
      "news_reactive" => {
        filter: ->(market, _pp, _opts) { market[:question].present? }
      },

      # --- External data ---
      "weather_model_alpha" => {
        filter: ->(market, _pp, _opts) {
          q = market[:question].to_s.downcase
          q.present? && q.match?(/\b(temperature|weather|rain|snow|wind|hurricane|storm|degrees|precipitation|heat|cold|noaa|nws|forecast)\b/)
        }
      },
      "spot_lag_arbitrage" => {
        filter: ->(market, _pp, _opts) {
          q = market[:question].to_s.downcase
          q.match?(/\b(bitcoin|btc|ethereum|eth|crypto|gold|oil|commodity|price)\b/i)
        }
      },

      # --- Pass-through ---
      "cross_platform_arbitrage" => { filter: ->(_m, _pp, _opts) { true } },
      "prediction_market" => {
        filter: ->(market, _pp, _opts) {
          p = market[:yes_price] || 0.5
          p.between?(0.01, 0.99)
        }
      }
    }.freeze

    # Filter discovered markets against strategy types using affinity rules.
    # Returns { assignments: [{ pair:, strategy_type: }], stats: { type => { total:, matched: } } }
    #
    # Affinity is a **soft preference**: if at least one market passes the filter
    # for a type, only matched markets are used. If zero markets pass, ALL markets
    # are assigned (fallback). This matches the old monolithic behavior where
    # every market got a strategy for every type — affinity only influenced pair
    # selection, not strategy creation.
    #
    # @param markets [Array<Hash>] Markets with symbol keys from discover_markets API
    # @param strategy_types [Array<String>] Strategy type names to filter for
    # @param markets [Array<Hash>] Markets with symbol keys from discover_markets API
    # @param strategy_types [Array<String>] Strategy type names to filter for
    # @param learning_context [Hash, nil] Cross-session learning data from server:
    #   - :strategy_type_blacklist [Array<Hash>] combos to exclude (strategy_type, category, avg_pnl, sessions)
    #   - :strategy_type_category_performance [Hash] raw perf data keyed by "type:category"
    #   - :per_type_category_modifiers [Hash] per-type category modifiers from learnings
    def self.filter_assignments(markets:, strategy_types:, learning_context: nil)
      # Build price lookup from market discovery data
      pair_prices = {}
      markets.each do |m|
        yes_pair = m[:pairs]&.find { |p| p.end_with?("/YES") }
        no_pair = m[:pairs]&.find { |p| p.end_with?("/NO") }
        next unless yes_pair && m[:yes_price]
        pair_prices[yes_pair] = m[:yes_price]
        pair_prices[no_pair] = (1.0 - m[:yes_price]).round(4) if no_pair
      end

      compatible = []
      stats = {}

      strategy_types.each do |strategy_type|
        affinity = STRATEGY_MARKET_AFFINITY[strategy_type]
        stats[strategy_type] = { total: markets.size, matched: 0, fallback: false }

        # First pass: collect markets that pass the affinity filter
        matched_markets = []
        markets.each do |market|
          if affinity&.dig(:filter)
            next unless affinity[:filter].call(market, pair_prices, {})
          end
          matched_markets << market
        end

        # Soft fallback: if no markets passed the filter, use all markets.
        # The discovery process already selected these as the best available;
        # rejecting them all would leave the strategy type with zero strategies.
        use_markets = if matched_markets.empty? && affinity&.dig(:filter)
                        stats[strategy_type][:fallback] = true
                        markets
                      else
                        matched_markets
                      end

        stats[strategy_type][:matched] = matched_markets.size

        use_markets.each do |market|
          # Determine which pairs from this market to use
          if affinity&.dig(:price_range)
            candidates = market[:pairs].select { |p| pair_prices[p]&.then { |px| affinity[:price_range].cover?(px) } }
            candidates = market[:pairs].select { |p| p.end_with?("/YES") } if candidates.empty?
          else
            candidates = market[:pairs].select { |p| p.end_with?("/YES") }
          end

          candidates.each { |pair| compatible << { pair: pair, strategy_type: strategy_type, category: market[:category] } }
        end
      end

      # Post-filter: apply learning-based exclusions from cross-session performance data
      if learning_context.is_a?(Hash) && compatible.any?
        blacklist = learning_context[:strategy_type_blacklist] || learning_context["strategy_type_blacklist"] || []
        blacklisted_combos = blacklist.map do |b|
          st = b[:strategy_type] || b["strategy_type"]
          cat = b[:category] || b["category"]
          [st, cat]
        end.to_set

        if blacklisted_combos.any?
          # Snapshot pre-learning assignments per type for soft fallback
          pre_learning_by_type = compatible.group_by { |a| a[:strategy_type] }

          compatible.reject! do |assignment|
            combo = [assignment[:strategy_type], assignment[:category]]
            if blacklisted_combos.include?(combo)
              stats[assignment[:strategy_type]][:learning_excluded] ||= 0
              stats[assignment[:strategy_type]][:learning_excluded] += 1
              true
            else
              false
            end
          end

          # Soft fallback: if learning filter removed ALL markets for a type,
          # restore the original affinity-filtered set. Learning exclusion is
          # advisory — never leave a strategy type with zero assignments.
          strategy_types.each do |st|
            next if compatible.any? { |a| a[:strategy_type] == st }

            original_for_type = pre_learning_by_type[st] || []
            compatible.concat(original_for_type)
            stats[st][:learning_fallback] = true
          end
        end
      end

      { assignments: compatible, stats: stats }
    end
  end
end
