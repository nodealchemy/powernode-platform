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

        return signals if price_history.size < lookback

        prices = price_history.last(lookback).map { |s| (s["close"] || s[:close]).to_f }
        return signals if prices.any?(&:zero?)

        mean = prices.sum / prices.size
        variance = prices.sum { |p| (p - mean)**2 } / prices.size
        std_dev = Math.sqrt(variance)
        z_score = std_dev.zero? ? 0 : (current_price - mean) / std_dev

        # Autocorrelation check: negative = mean-reverting, positive = trending
        returns = prices.each_cons(2).map { |a, b| b - a }
        autocorr = compute_autocorrelation(returns)
        autocorr_boost = if autocorr < -0.2 then 1.15
                         elsif autocorr > 0.2 then 0.75
                         else 1.0
                         end

        if !has_open_position?
          if z_score < -std_devs
            base_conf = (z_score.abs / std_devs * 0.4 + 0.3).clamp(0.3, 0.9)
            signals << build_signal(
              type: "entry", direction: "long",
              confidence: (base_conf * autocorr_boost).clamp(0.3, 0.9),
              strength: (z_score.abs / (std_devs * 2)).clamp(0.0, 1.0),
              reasoning: "Price #{z_score.round(2)} std devs below mean (mean: #{mean.round(4)}, price: #{current_price}, autocorr: #{autocorr.round(3)})",
              indicators: { z_score: z_score, mean: mean, std_dev: std_dev, autocorrelation: autocorr, edge: (mean - current_price).abs,
                            limit_order: true, limit_price: current_price.round(4) }
            )
          elsif z_score > std_devs
            base_conf = (z_score.abs / std_devs * 0.4 + 0.3).clamp(0.3, 0.9)
            signals << build_signal(
              type: "entry", direction: "short",
              confidence: (base_conf * autocorr_boost).clamp(0.3, 0.9),
              strength: (z_score.abs / (std_devs * 2)).clamp(0.0, 1.0),
              reasoning: "Price #{z_score.round(2)} std devs above mean (mean: #{mean.round(4)}, price: #{current_price}, autocorr: #{autocorr.round(3)})",
              indicators: { z_score: z_score, mean: mean, std_dev: std_dev, autocorrelation: autocorr, edge: (current_price - mean).abs,
                            limit_order: true, limit_price: current_price.round(4) }
            )
          end
        elsif has_open_position?
          position = current_position
          entry_price = (position&.dig("entry_price") || 0).to_f
          side = position&.dig("side") || "long"
          pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
          stop_loss = param("stop_loss_pct", 5.0)

          if z_score.abs < exit_mean_distance
            signals << build_signal(
              type: "exit", direction: side,
              confidence: 0.7,
              reasoning: "Price returned to within #{exit_mean_distance} std devs of mean (z-score: #{z_score.round(2)})",
              indicators: { z_score: z_score, mean: mean, edge: (mean - current_price).abs }
            )
          elsif pnl_pct <= -stop_loss
            signals << build_signal(
              type: "exit", direction: side,
              confidence: 0.9, strength: 0.9,
              reasoning: "Stop-loss triggered: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit (z-score: #{z_score.round(2)})",
              indicators: { z_score: z_score, pnl_pct: pnl_pct, edge: 0 }
            )
          end
        end

        signals
      end

      private

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
