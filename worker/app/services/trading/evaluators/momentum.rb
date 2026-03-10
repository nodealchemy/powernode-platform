# frozen_string_literal: true

module Trading
  module Evaluators
    class Momentum < Base
      register "momentum"

      def evaluate
        signals = []
        lookback = param("lookback_periods", 20)
        entry_threshold = param("entry_threshold", 0.02)
        exit_threshold = param("exit_threshold", -0.01)

        return signals if price_history.size < lookback

        prices = price_history.last(lookback).map { |s| (s["close"] || s[:close]).to_f }
        return signals if prices.any?(&:zero?)

        # Log returns with median filtering for spike resistance
        log_returns = prices.each_cons(2).map { |a, b| Math.log(b / a) }
        sorted_returns = log_returns.sort
        median_return = sorted_returns[sorted_returns.size / 2] || 0
        momentum = log_returns.select { |r| (r - median_return).abs < median_return.abs * 3 + 0.01 }.sum

        volumes = price_history.last(lookback).map { |s| (s["volume"] || s[:volume] || 0).to_f }
        avg_volume = volumes.sum / volumes.size
        volume_ratio = (volumes.last || 0).to_f / [avg_volume, 0.001].max

        volume_boost = if volume_ratio > 1.5 then 0.15
                       elsif volume_ratio > 1.0 then 0.05
                       else -0.10
                       end

        if !has_open_position? && momentum > entry_threshold
          base_confidence = (momentum / entry_threshold * 0.5).clamp(0.3, 0.85)
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: (base_confidence + volume_boost).clamp(0.3, 0.95),
            strength: momentum.abs.clamp(0.0, 1.0),
            reasoning: "Momentum #{(momentum * 100).round(2)}% over #{lookback} periods exceeds threshold #{(entry_threshold * 100).round(2)}%",
            indicators: { momentum: momentum, volume_ratio: volume_ratio, volume_boost: volume_boost, lookback: lookback,
                          limit_order: true, limit_price: current_price.round(4), edge: momentum.abs }
          )
        elsif has_open_position?
          position = current_position
          entry_price = (position&.dig("entry_price") || 0).to_f
          pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100) : 0

          stop_loss = param("stop_loss_pct", 5.0)
          take_profit = param("take_profit_pct", 5.0)

          if momentum < exit_threshold
            signals << build_signal(
              type: "exit", direction: position&.dig("side") || "long",
              confidence: (exit_threshold.abs / [momentum.abs, 0.001].max).clamp(0.5, 0.95),
              strength: momentum.abs.clamp(0.0, 1.0),
              reasoning: "Momentum reversed to #{(momentum * 100).round(2)}%, below exit threshold #{(exit_threshold * 100).round(2)}%",
              indicators: { momentum: momentum, edge: momentum.abs }
            )
          elsif pnl_pct <= -stop_loss
            signals << build_signal(
              type: "exit", direction: position&.dig("side") || "long",
              confidence: 0.9, strength: 0.9,
              reasoning: "Stop-loss triggered: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit",
              indicators: { pnl_pct: pnl_pct, edge: 0 }
            )
          elsif pnl_pct >= take_profit
            signals << build_signal(
              type: "exit", direction: position&.dig("side") || "long",
              confidence: 0.85, strength: 0.8,
              reasoning: "Take-profit triggered: PnL #{pnl_pct.round(2)}% exceeds +#{take_profit}% target",
              indicators: { pnl_pct: pnl_pct, edge: 0 }
            )
          end
        end

        signals
      end
    end
  end
end
