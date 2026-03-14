# frozen_string_literal: true

module Trading
  module Evaluators
    class MeanReversion < Base
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
              return has_open_position? ? check_exits(signals, 0, 0, current_price) : signals
            end
          end
        end

        return signals if price_history.size < lookback

        prices = price_history.last(lookback).map { |s| (s["close"] || s[:close]).to_f }
        return signals if prices.any?(&:zero?)

        # Use EMA for faster adaptation to regime changes
        alpha = 2.0 / (prices.size + 1)
        ema = prices.first
        prices[1..].each { |p| ema = alpha * p + (1 - alpha) * ema }
        variance = prices.sum { |p| (p - ema)**2 } / prices.size
        std_dev = Math.sqrt(variance)
        z_score = std_dev.zero? ? 0 : (current_price - ema) / std_dev

        # Autocorrelation check: negative = mean-reverting, positive = trending
        returns = prices.each_cons(2).map { |a, b| b - a }
        autocorr = compute_autocorrelation(returns)

        # Hard-block in trending regimes — mean reversion fails when prices trend
        autocorr_limit = param("autocorr_threshold", 0.3)
        if autocorr > autocorr_limit
          return has_open_position? ? check_exits(signals, z_score, std_dev, ema) : signals
        end
        # Block near-certain outcomes where prices don't revert
        price_lo = param("price_bound_min", 0.10)
        price_hi = param("price_bound_max", 0.90)
        if current_price < price_lo || current_price > price_hi
          return has_open_position? ? check_exits(signals, z_score, std_dev, ema) : signals
        end

        autocorr_boost = if autocorr < -0.2 then 1.15
                         elsif autocorr > 0.2 then 0.75
                         else 1.0
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
          if z_score < -std_devs
            base_conf = (z_score.abs / std_devs * 0.4 + 0.3).clamp(0.3, 0.9)
            signals << build_signal(
              type: "entry", direction: "long",
              confidence: (base_conf * autocorr_boost).clamp(0.3, 0.9),
              strength: (z_score.abs / (std_devs * 2)).clamp(0.0, 1.0),
              reasoning: "Price #{z_score.round(2)} std devs below EMA (ema: #{ema.round(4)}, price: #{current_price}, autocorr: #{autocorr.round(3)})",
              indicators: { z_score: z_score, mean: ema, std_dev: std_dev, autocorrelation: autocorr, edge: (ema - current_price).abs,
                            limit_order: true, limit_price: current_price.round(4) }
            )
          elsif z_score > std_devs
            base_conf = (z_score.abs / std_devs * 0.4 + 0.3).clamp(0.3, 0.9)
            signals << build_signal(
              type: "entry", direction: "short",
              confidence: (base_conf * autocorr_boost).clamp(0.3, 0.9),
              strength: (z_score.abs / (std_devs * 2)).clamp(0.0, 1.0),
              reasoning: "Price #{z_score.round(2)} std devs above EMA (ema: #{ema.round(4)}, price: #{current_price}, autocorr: #{autocorr.round(3)})",
              indicators: { z_score: z_score, mean: ema, std_dev: std_dev, autocorrelation: autocorr, edge: (current_price - ema).abs,
                            limit_order: true, limit_price: current_price.round(4) }
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
        pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
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
            indicators: { z_score: z_score, mean: ema, edge: (ema - current_price).abs }
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
        # Median-filter to reduce outlier sensitivity in short PM time series
        filtered = returns.each_cons(3).map { |window| window.sort[1] }
        return 0.0 if filtered.size < 3
        mean = filtered.sum / filtered.size
        n = filtered.size
        numerator = (0...(n - 1)).sum { |i| (filtered[i] - mean) * (filtered[i + 1] - mean) }
        denominator = filtered.sum { |r| (r - mean)**2 }
        return 0.0 if denominator.zero?
        (numerator / denominator).clamp(-1.0, 1.0)
      end
    end
  end
end
