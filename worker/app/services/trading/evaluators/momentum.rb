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
            indicators: { momentum: momentum, volume_ratio: volume_ratio, volume_boost: volume_boost, lookback: lookback }
          )
        elsif has_open_position? && momentum < exit_threshold
          signals << build_signal(
            type: "exit", direction: current_position&.dig("side") || "long",
            confidence: (exit_threshold.abs / [momentum.abs, 0.001].max).clamp(0.5, 0.95),
            strength: momentum.abs.clamp(0.0, 1.0),
            reasoning: "Momentum reversed to #{(momentum * 100).round(2)}%, below exit threshold #{(exit_threshold * 100).round(2)}%"
          )
        end

        signals
      end
    end
  end
end
