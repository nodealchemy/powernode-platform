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
            indicators: { market_price: market_price, estimated_probability: estimated_prob, edge: edge, edge_pct: (edge * 100).round(2) }
          )
        elsif edge < -edge_threshold && !has_open_position?
          signals << build_signal(
            type: "entry", direction: "short",
            confidence: [edge.abs / 0.10, 1.0].min,
            strength: [edge.abs / 0.075, 1.0].min,
            reasoning: "Prediction market edge (short): estimated #{(estimated_prob * 100).round(1)}% vs market #{(market_price * 100).round(1)}% (edge: #{(edge * 100).round(1)}%)",
            indicators: { market_price: market_price, estimated_probability: estimated_prob, edge: edge, edge_pct: (edge * 100).round(2) }
          )
        end

        # Exit if edge collapsed
        if has_open_position? && edge.abs < edge_threshold * 0.1
          position = current_position
          min_hold = param("min_hold_seconds", 30)
          opened_at = position&.dig("opened_at") ? Time.parse(position["opened_at"]) : nil
          if opened_at && opened_at < (Time.current - min_hold)
            signals << build_signal(
              type: "exit", direction: position["side"] || "long",
              confidence: 0.7, strength: 0.6,
              reasoning: "Edge collapsed to #{(edge * 100).round(2)}%, taking profit/loss",
              indicators: { edge: edge, edge_pct: (edge * 100).round(2) }
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
