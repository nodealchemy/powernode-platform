# frozen_string_literal: true

module Trading
  module Evaluators
    class YieldFarming < Base
      register "yield_farming"

      def evaluate
        signals = []
        min_apy_pct = param("min_apy_pct", 3.0)
        max_apy_pct = param("max_apy_pct", 50.0)

        current_apy = estimate_current_apy
        return signals unless current_apy

        if current_apy >= min_apy_pct && current_apy <= max_apy_pct && !has_open_position?
          risk_adjusted = current_apy / (1 + estimated_impermanent_loss)
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: [risk_adjusted / 20.0, 0.9].min,
            strength: [current_apy / 15.0, 1.0].min,
            reasoning: "Yield farming opportunity: #{current_apy.round(2)}% APY (risk-adjusted: #{risk_adjusted.round(2)}%)",
            indicators: { current_apy: current_apy, risk_adjusted_apy: risk_adjusted, impermanent_loss_estimate: estimated_impermanent_loss, protocol: strategy_pair }
          )
        end

        if has_open_position?
          if current_apy < min_apy_pct * 0.5
            signals << build_signal(
              type: "exit", direction: "long", confidence: 0.8, strength: 0.7,
              reasoning: "APY dropped to #{current_apy.round(2)}%, below minimum threshold",
              indicators: { current_apy: current_apy, min_apy: min_apy_pct }
            )
          elsif current_apy > max_apy_pct
            signals << build_signal(
              type: "exit", direction: "long", confidence: 0.9, strength: 0.9,
              reasoning: "APY spike to #{current_apy.round(2)}% — possible exploit or rug pull risk",
              indicators: { current_apy: current_apy, max_safe_apy: max_apy_pct }
            )
          end
        end

        signals
      end

      private

      def estimate_current_apy
        return nil if price_history.size < 2

        prices = price_history.map { |s| (s["close"] || s[:close]).to_f }
        volatility = prices.each_cons(2).map { |a, b| ((b - a) / [a, 0.001].max).abs }.sum / (prices.size - 1)
        base_apy = param("base_apy", 5.0)
        (base_apy + volatility * 100).round(4)
      end

      def estimated_impermanent_loss
        return 0.01 if price_history.size < 2

        initial_price = (price_history.first["close"] || price_history.first[:close]).to_f
        current = (price_history.last["close"] || price_history.last[:close]).to_f
        return 0.01 if initial_price.zero?

        ratio = current / initial_price
        il = 2 * Math.sqrt(ratio) / (1 + ratio) - 1
        il.abs.round(6)
      end
    end
  end
end
