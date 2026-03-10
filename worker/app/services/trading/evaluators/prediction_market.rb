# frozen_string_literal: true

module Trading
  module Evaluators
    class PredictionMarket < Base
      register "prediction_market"

      def evaluate
        signals = []
        edge_threshold = param("edge_threshold_pct", 5.0) / 100.0
        market_price = current_price
        return signals unless market_price.between?(0.01, 0.99)

        estimated_prob = estimate_fair_probability(market_price)
        edge = estimated_prob - market_price

        if edge > edge_threshold && !has_open_position?
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: [edge / 0.10, 1.0].min,
            strength: [edge / 0.075, 1.0].min,
            reasoning: "Prediction market edge: estimated #{(estimated_prob * 100).round(1)}% vs market #{(market_price * 100).round(1)}% (edge: #{(edge * 100).round(1)}%)",
            indicators: { market_price: market_price, estimated_probability: estimated_prob, edge: edge, edge_pct: (edge * 100).round(2),
                          limit_order: true, limit_price: market_price.round(4) }
          )
        elsif edge < -edge_threshold && !has_open_position?
          signals << build_signal(
            type: "entry", direction: "short",
            confidence: [edge.abs / 0.10, 1.0].min,
            strength: [edge.abs / 0.075, 1.0].min,
            reasoning: "Prediction market edge (short): estimated #{(estimated_prob * 100).round(1)}% vs market #{(market_price * 100).round(1)}% (edge: #{(edge * 100).round(1)}%)",
            indicators: { market_price: market_price, estimated_probability: estimated_prob, edge: edge, edge_pct: (edge * 100).round(2),
                          limit_order: true, limit_price: market_price.round(4) }
          )
        end

        # Exit if edge collapsed or stop-loss hit
        if has_open_position?
          position = current_position
          min_hold = param("min_hold_seconds", 30)
          opened_at = position&.dig("opened_at") ? Time.parse(position["opened_at"]) : nil
          held_long_enough = opened_at && opened_at < (Time.current - min_hold)
          entry_price = (position&.dig("entry_price") || 0).to_f
          side = position&.dig("side") || "long"
          pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
          stop_loss = param("stop_loss_pct", 10.0)

          if held_long_enough && edge.abs < edge_threshold * 0.5
            signals << build_signal(
              type: "exit", direction: side,
              confidence: 0.7, strength: 0.6,
              reasoning: "Edge collapsed to #{(edge * 100).round(2)}%, taking profit/loss",
              indicators: { edge: edge, edge_pct: (edge * 100).round(2) }
            )
          elsif pnl_pct <= -stop_loss
            signals << build_signal(
              type: "exit", direction: side,
              confidence: 0.9, strength: 0.9,
              reasoning: "Stop-loss triggered: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit",
              indicators: { pnl_pct: pnl_pct, edge: 0 }
            )
          end
        end

        signals
      end

      private

      def estimate_fair_probability(market_price)
        lookback = param("lookback_periods", 20)
        return market_price if price_history.size < 3

        prices = price_history.last(lookback).map { |s| (s["close"] || s[:close]).to_f }
        return market_price if prices.size < 3

        mean = prices.sum / prices.size
        recent_trend = (prices.last(3).sum / 3.0 - prices.first(3).sum / 3.0) / [mean, 0.001].max

        # Logit-space extrapolation to stay within 0-1
        clamped_price = market_price.clamp(0.02, 0.98)
        logit = Math.log(clamped_price / (1.0 - clamped_price))
        adjusted_logit = logit + recent_trend * 1.5
        estimated = 1.0 / (1.0 + Math.exp(-adjusted_logit))
        estimated.clamp(0.01, 0.99)
      end
    end
  end
end
