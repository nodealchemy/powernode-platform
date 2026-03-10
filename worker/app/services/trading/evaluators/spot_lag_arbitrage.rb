# frozen_string_literal: true

module Trading
  module Evaluators
    class SpotLagArbitrage < Base
      register "spot_lag_arbitrage"

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price&.between?(0.01, 0.99)

        spot = (spot_price_data["price"] || spot_price_data[:price]).to_f
        return signals unless spot > 0

        strike = param("strike_price", 70000.0).to_f
        return signals unless strike > 0

        implied_prob = if param("use_black_scholes", true)
          calculate_implied_probability(spot, strike)
        else
          simple_implied_probability(spot, strike)
        end
        return signals unless implied_prob

        edge = implied_prob - market_price
        min_edge = param("min_edge_pct", 10.0) / 100.0
        exit_edge = param("exit_edge_pct", 2.0) / 100.0

        max_spread = param("max_spread_pct", 5.0) / 100.0

        if !has_open_position? && edge.abs > min_edge && (spread_pct.nil? || spread_pct <= max_spread)
          direction = edge > 0 ? "long" : "short"
          signals << build_signal(
            type: "entry", direction: direction,
            confidence: (edge.abs / 0.15).clamp(0.3, 0.95),
            strength: (edge.abs / 0.10).clamp(0.0, 1.0),
            reasoning: "Spot-lag arbitrage: spot $#{spot.round(2)} implies #{(implied_prob * 100).round(1)}% vs market #{(market_price * 100).round(1)}% (edge: #{(edge * 100).round(1)}%)",
            indicators: { spot_price: spot, strike_price: strike, implied_probability: implied_prob, market_price: market_price, edge: edge, edge_pct: (edge * 100).round(2) }
          )
        elsif has_open_position? && edge.abs < exit_edge
          signals << build_signal(
            type: "exit", direction: current_position&.dig("side") || "long",
            confidence: 0.7, strength: 0.6,
            reasoning: "Spot-lag edge collapsed to #{(edge * 100).round(2)}%, market has caught up",
            indicators: { edge: edge, edge_pct: (edge * 100).round(2) }
          )
        end

        signals
      end

      private

      def calculate_implied_probability(spot, strike)
        vol = estimate_volatility
        return simple_implied_probability(spot, strike) if vol.nil? || vol.zero?

        time_remaining = time_to_expiry
        return simple_implied_probability(spot, strike) if time_remaining.nil? || time_remaining <= 0

        d = Math.log(spot / strike) / (vol * Math.sqrt(time_remaining))
        normal_cdf(d)
      rescue StandardError
        simple_implied_probability(spot, strike)
      end

      def simple_implied_probability(spot, strike)
        1.0 / (1.0 + Math.exp(-Math.log(spot / strike) * 5.0))
      end

      def estimate_volatility
        configured_vol = param("implied_volatility", nil)
        return configured_vol.to_f if configured_vol && configured_vol.to_f > 0
        return nil if price_history.size < 5

        closes = price_history.map { |s| (s["close"] || s[:close]).to_f }
        returns = closes.each_cons(2).map { |a, b| Math.log(b / a) }
        return nil if returns.empty?

        mean_return = returns.sum / returns.size
        variance = returns.sum { |r| (r - mean_return)**2 } / (returns.size - 1)
        daily_vol = Math.sqrt(variance)
        daily_vol * Math.sqrt(365)
      rescue StandardError
        nil
      end

      def time_to_expiry
        expiry_str = param("expiry_date", nil)
        return nil unless expiry_str

        expiry = Time.parse(expiry_str.to_s)
        remaining = (expiry - Time.current) / (365.25 * 24 * 3600)
        remaining > 0 ? remaining : nil
      rescue StandardError
        nil
      end

      def normal_cdf(x)
        return 0.0 if x < -10
        return 1.0 if x > 10

        t = 1.0 / (1.0 + 0.2316419 * x.abs)
        d = 0.3989422804014327
        p = d * Math.exp(-x * x / 2.0) *
            (0.319381530 * t - 0.356563782 * t**2 + 1.781477937 * t**3 - 1.821255978 * t**4 + 1.330274429 * t**5)
        x >= 0 ? 1.0 - p : p
      end
    end
  end
end
