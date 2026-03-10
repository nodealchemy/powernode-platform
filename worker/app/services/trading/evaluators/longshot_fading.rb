# frozen_string_literal: true

module Trading
  module Evaluators
    class LongshotFading < Base
      register "longshot_fading"

      # Empirical mispricing data from 72.1M Kalshi trades (Becker, 2026)
      EMPIRICAL_WIN_RATES = {
        [0.01, 0.05] => 0.0418,   # 4.18% actual vs 5% implied → -16.36% mispricing
        [0.05, 0.10] => 0.065,    # ~6.5% actual vs 7.5% implied → -13.3%
        [0.10, 0.15] => 0.110,    # ~11.0% actual vs 12.5% implied → -12.0%
        [0.15, 0.20] => 0.158,    # ~15.8% actual vs 17.5% implied → -9.7%
        [0.20, 0.25] => 0.210     # ~21.0% actual vs 22.5% implied → -6.7%
      }.freeze

      def evaluate
        signals = []
        price = current_price
        min_price = param("min_price", 0.03)
        max_price = param("max_price", 0.15)

        # Check if market is in longshot range
        return signals unless price.between?(min_price, max_price)

        # Check time to expiry
        min_hours = param("min_hours_to_expiry", 2)
        if market_expiry
          hours_remaining = (market_expiry - Time.now) / 3600.0
          return signals if hours_remaining < min_hours
        end

        # Check concurrent position limits
        max_concurrent = param("max_concurrent_positions", 5)
        open_count = @positions.count { |p| p["status"] == "open" }
        return signals if open_count >= max_concurrent

        # Calculate mispricing edge
        empirical_rate = lookup_empirical_rate(price)
        implied_prob = price # In prediction markets, price ≈ implied probability
        edge_pct = ((implied_prob - empirical_rate) / implied_prob * 100.0)

        min_edge = param("min_edge_pct", 1.0)
        return signals unless edge_pct >= min_edge

        # Check total exposure limit
        max_exposure_pct = param("max_total_exposure_pct", 15.0)
        total_exposure = @positions.select { |p| p["status"] == "open" }
                                   .sum { |p| (p["entry_price"] || 0).to_f * (p["quantity"] || 0).to_f }
        current_exposure_pct = @allocated_capital > 0 ? (total_exposure / @allocated_capital * 100.0) : 0
        return signals if current_exposure_pct >= max_exposure_pct

        # Position sizing via half-Kelly for binary outcomes
        kelly_fraction = param("kelly_fraction", 0.5)
        b = (1.0 / price) - 1.0    # Net payout odds for selling YES
        p_win = 1.0 - empirical_rate # Probability of YES expiring worthless (we profit)
        q_lose = empirical_rate      # Probability of YES settling (we lose)
        kelly_full = (b * p_win - q_lose) / b
        kelly_f = [kelly_full * kelly_fraction, param("max_position_pct", 3.0) / 100.0].min

        confidence = calculate_confidence(edge_pct, hours_to_expiry, open_count)
        stop_loss_price = [price * param("stop_loss_multiplier", 2.0), 0.95].min

        signals << build_signal(
          type: "entry",
          direction: "short",
          confidence: confidence,
          strength: classify_strength(edge_pct),
          reasoning: "Longshot fading: market at #{(price * 100).round(1)}c, empirical win rate " \
                     "#{(empirical_rate * 100).round(2)}% vs implied #{(implied_prob * 100).round(1)}%. " \
                     "Edge: #{edge_pct.round(2)}%. Selling overpriced YES contract via limit order.",
          indicators: {
            edge: edge_pct / 100.0,
            edge_pct: edge_pct,
            market_price: price,
            empirical_win_rate: empirical_rate,
            implied_probability: implied_prob,
            mispricing_pct: edge_pct,
            kelly_fraction: kelly_f,
            limit_order: true,
            limit_price: ask_price.positive? ? ask_price : price,
            stop_loss_price: stop_loss_price,
            hours_to_expiry: hours_to_expiry,
            open_longshot_positions: open_count,
            total_exposure_pct: current_exposure_pct,
            position_sizing_method: "kelly"
          }
        )

        # Check for exit signals on existing positions
        check_exit_conditions(signals, price)

        signals
      end

      def tick_cost_usd
        0.0 # No LLM calls — pure heuristic
      end

      private

      def lookup_empirical_rate(price)
        EMPIRICAL_WIN_RATES.each do |(low, high), rate|
          return rate if price >= low && price < high
        end
        # Extrapolate for prices outside defined buckets
        price * 0.85 # Conservative: assume 15% mispricing at any level
      end

      def calculate_confidence(edge_pct, hours_remaining, open_count)
        base = 0.5

        # Higher edge → higher confidence
        edge_bonus = [edge_pct / 20.0, 0.25].min

        # More time to settlement → higher confidence
        time_bonus = if hours_remaining && hours_remaining > 48
                       0.15
                     elsif hours_remaining && hours_remaining > 12
                       0.10
                     else
                       0.0
                     end

        # Fewer open positions → higher confidence (less correlated risk)
        concentration_penalty = open_count * 0.03

        (base + edge_bonus + time_bonus - concentration_penalty).clamp(0.1, 0.95)
      end

      def classify_strength(edge_pct)
        case edge_pct
        when (15..) then 1.0
        when (10..15) then 0.8
        when (5..10) then 0.6
        else 0.4
        end
      end

      def hours_to_expiry
        return nil unless market_expiry

        (market_expiry - Time.now) / 3600.0
      end

      def check_exit_conditions(signals, price)
        @positions.select { |p| p["status"] == "open" }.each do |pos|
          entry_price = (pos["entry_price"] || pos["avg_entry_price"] || 0).to_f
          stop_loss = [entry_price * param("stop_loss_multiplier", 2.0), 0.95].min

          next unless price >= stop_loss

          signals << build_signal(
            type: "exit",
            direction: "close",
            confidence: 0.95,
            strength: 0.8,
            reasoning: "Stop-loss triggered: price #{(price * 100).round(1)}c exceeded " \
                       "#{(stop_loss * 100).round(1)}c stop (#{param('stop_loss_multiplier', 2.0)}x " \
                       "entry at #{(entry_price * 100).round(1)}c)",
            indicators: {
              edge: 0,
              market_price: price,
              entry_price: entry_price,
              stop_loss_price: stop_loss,
              exit_reason: "stop_loss"
            }
          )
        end
      end
    end
  end
end
