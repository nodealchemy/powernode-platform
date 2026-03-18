# frozen_string_literal: true

module Trading
  module Evaluators
    class MeanReversion < Base
      include Concerns::BayesianBelief

      register "mean_reversion"

      def evaluate
        signals = []
        lookback = param("lookback_periods", 30)
        std_devs = param("std_dev_threshold", 2.0)
        exit_mean_distance = param("exit_mean_distance", 0.5)

        # Settlement halt: stop new entries near expiry (skip in training — ticks are compressed)
        unless training?
          halt_hours = param("settlement_halt_hours", 2)
          if market_expiry
            hours_left = (market_expiry - Time.now) / 3600.0
            if hours_left < halt_hours
              return has_open_position? ? check_exits(signals, 0, 0, mid_price) : signals
            end
          end
        end

        if price_history.size < lookback
          log("Skipped: #{price_history.size}/#{lookback} history entries")
          return signals
        end

        prices = price_history.last(lookback).map { |s| (s["close"] || s[:close]).to_f }
        prices.reject!(&:zero?) # Skip zero prices instead of aborting entire evaluation
        return signals if prices.size < [lookback / 2, 5].max

        # Use EMA for faster adaptation — seed from SMA of first N for stability
        alpha = 2.0 / (prices.size + 1)
        seed_count = [5, prices.size].min
        ema = prices.first(seed_count).sum / seed_count.to_f
        prices[seed_count..].each { |p| ema = alpha * p + (1 - alpha) * ema } if prices.size > seed_count
        variance = prices.sum { |p| (p - ema)**2 } / prices.size
        std_dev = Math.sqrt(variance)
        z_score = std_dev.zero? ? 0 : (mid_price - ema) / std_dev

        # Bayesian belief update from price movements
        if price_history.size >= 2
          prev = (price_history[-2]["close"] || price_history[-2][:close]).to_f
          update_belief_from_price(previous_price: prev, mid_price: mid_price) if prev > 0
        end

        # Autocorrelation check: negative = mean-reverting, positive = trending
        # Use log returns (not simple diffs) for scale-invariant regime detection
        returns = prices.each_cons(2).map { |a, b| a > 0 ? Math.log(b / a) : 0.0 }
        autocorr = compute_autocorrelation(returns)

        # Hard-block in trending regimes — mean reversion fails when prices trend
        autocorr_limit = param("autocorr_threshold", 0.3)
        if autocorr > autocorr_limit
          return has_open_position? ? check_exits(signals, z_score, std_dev, ema) : signals
        end
        # Block near-certain outcomes where prices don't revert.
        # Only applies to prediction market prices (0-1 probability range).
        # Crypto spot prices (e.g., BTC at $74,000) are unbounded and should skip this gate.
        is_pm_price = ema.between?(0.01, 0.99)
        if is_pm_price
          price_lo = param("price_bound_min", 0.10)
          price_hi = param("price_bound_max", 0.90)
          if mid_price < price_lo || mid_price > price_hi
            return has_open_position? ? check_exits(signals, z_score, std_dev, ema) : signals
          end
        end

        autocorr_boost = if autocorr < -0.2 then 1.15
                         elsif autocorr > 0.2 then 0.75
                         else 1.0
                         end

        # Bayesian regime detection: if posterior has drifted toward current price
        # (away from EMA), the move may be justified — reduce MR confidence
        posterior = bayesian_posterior
        if posterior && std_dev > 0 && is_pm_price
          posterior_drift = (posterior - ema) / std_dev
          autocorr_boost *= 0.7 if posterior_drift.abs > 1.0
        end

        # Volume gate: skip entries in illiquid conditions
        if !has_open_position? && @market_data
          vol_data = @market_data["volume_24h"] || @market_data[:volume_24h]
          if vol_data
            volumes = price_history.last(lookback).map { |s| (s["volume"] || s[:volume] || 0).to_f }
            avg_vol = volumes.sum / [volumes.size, 1].max
            vol_ratio = avg_vol > 0 ? vol_data.to_f / [avg_vol, 1].max : 1.0
            return signals if vol_ratio < param("min_volume_ratio", 0.3)
          end
        end

        if !has_open_position?
          # Spread gate: ensure edge exceeds execution cost before entering
          price_edge = (mid_price - ema).abs
          min_edge = min_limit_order_cost

          if z_score < -std_devs && price_edge > min_edge
            base_conf = (z_score.abs / std_devs * 0.4 + 0.3).clamp(0.3, 0.9)
            signals << build_signal(
              type: "entry", direction: "long",
              confidence: (base_conf * autocorr_boost).clamp(0.3, 0.9),
              strength: (z_score.abs / (std_devs * 2)).clamp(0.0, 1.0),
              reasoning: "Price #{z_score.round(2)} std devs below EMA (ema: #{ema.round(4)}, price: #{mid_price}, autocorr: #{autocorr.round(3)})",
              indicators: { z_score: z_score, mean: ema, std_dev: std_dev, autocorrelation: autocorr, edge: price_edge,
                            bayesian_posterior: bayesian_posterior, bayesian_observations: bayesian_observations,
                            limit_order: true, limit_price: mid_price.round(4) }
            )
          elsif z_score > std_devs && price_edge > min_edge
            base_conf = (z_score.abs / std_devs * 0.4 + 0.3).clamp(0.3, 0.9)
            signals << build_signal(
              type: "entry", direction: "short",
              confidence: (base_conf * autocorr_boost).clamp(0.3, 0.9),
              strength: (z_score.abs / (std_devs * 2)).clamp(0.0, 1.0),
              reasoning: "Price #{z_score.round(2)} std devs above EMA (ema: #{ema.round(4)}, price: #{mid_price}, autocorr: #{autocorr.round(3)})",
              indicators: { z_score: z_score, mean: ema, std_dev: std_dev, autocorrelation: autocorr, edge: price_edge,
                            bayesian_posterior: bayesian_posterior, bayesian_observations: bayesian_observations,
                            limit_order: true, limit_price: mid_price.round(4) }
            )
          end
        elsif has_open_position?
          check_exits(signals, z_score, std_dev, ema)
        end

        signals
      end

      private

      def check_exits(signals, z_score, _std_dev, ema)
        exit_mean_distance = param("exit_mean_distance", 0.5)
        position = current_position
        entry_price = (position&.dig("entry_price") || 0).to_f
        side = position&.dig("side") || "long"
        pnl_pct = entry_price > 0 ? ((mid_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
        stop_loss = param("stop_loss_pct", 5.0)
        take_profit = param("take_profit_pct", 3.0)

        # Take-profit takes priority
        if pnl_pct >= take_profit
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.8, strength: 0.7,
            reasoning: "Take-profit: PnL #{pnl_pct.round(2)}% >= #{take_profit}%",
            indicators: { z_score: z_score, pnl_pct: pnl_pct, edge: 0 }
          )
          return signals
        end

        if z_score.abs < exit_mean_distance
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.7,
            reasoning: "Price returned to within #{exit_mean_distance} std devs of EMA (z-score: #{z_score.round(2)})",
            indicators: { z_score: z_score, mean: ema, edge: (ema - mid_price).abs }
          )
        elsif pnl_pct <= -stop_loss
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.9, strength: 0.9,
            reasoning: "Stop-loss triggered: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit (z-score: #{z_score.round(2)})",
            indicators: { z_score: z_score, pnl_pct: pnl_pct, edge: 0 }
          )
        end
        signals
      end

      def compute_autocorrelation(returns)
        return 0.0 if returns.size < 5
        mean = returns.sum / returns.size
        n = returns.size
        numerator = (0...(n - 1)).sum { |i| (returns[i] - mean) * (returns[i + 1] - mean) }
        denominator = returns.sum { |r| (r - mean)**2 }
        return 0.0 if denominator.zero?
        (numerator / denominator).clamp(-1.0, 1.0)
      end
    end
  end
end
