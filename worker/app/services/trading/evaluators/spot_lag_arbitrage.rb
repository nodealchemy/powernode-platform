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

        # Extract strike from market question when available, fall back to parameter.
        # Default of $70K was BTC-specific; market_question parsing handles other assets.
        strike = extract_strike_from_question || param("strike_price", 70000.0).to_f
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

        # Undervaluation entry filter (Random Forest research — @noisyb0y1):
        # Only enter when market price is significantly below model estimate.
        # With multiplier=0.5, market must be at 50% of implied value (2x margin of safety).
        # Even with 20% model error, still profitable. Default 1.0 = disabled (any edge).
        underval_mult = param("undervaluation_multiplier", 1.0).to_f

        if !has_open_position? && edge.abs > min_edge && (spread_pct.nil? || spread_pct <= max_spread)
          # Apply undervaluation filter: for longs, market must be below implied × multiplier
          # For shorts, market must be above implied × (2 - multiplier) [symmetric]
          if underval_mult < 1.0
            if edge > 0 # long candidate
              return signals unless market_price <= implied_prob * underval_mult
            else # short candidate
              return signals unless market_price >= implied_prob * (2.0 - underval_mult)
            end
          end

          direction = edge > 0 ? "long" : "short"
          signals << build_signal(
            type: "entry", direction: direction,
            confidence: (edge.abs / 0.15).clamp(0.3, 0.95),
            strength: (edge.abs / 0.10).clamp(0.0, 1.0),
            reasoning: "Spot-lag arbitrage: spot $#{spot.round(2)} implies #{(implied_prob * 100).round(1)}% vs market #{(market_price * 100).round(1)}% (edge: #{(edge * 100).round(1)}%)",
            indicators: { spot_price: spot, strike_price: strike, implied_probability: implied_prob, market_price: market_price, edge: edge, edge_pct: (edge * 100).round(2),
                          limit_order: true, limit_price: market_price.round(4) }
          )
        elsif has_open_position?
          # Exit value ratio (0.9x rule): exit when market reaches X% of model estimate.
          # With ratio=0.9, sell when market hits 90% of model value — leaves 10% on table
          # but avoids reversals. Default 1.0 = only exit when edge collapses (original).
          exit_ratio = param("exit_value_ratio", 1.0).to_f
          position_side = current_position&.dig("side") || "long"

          should_exit = if exit_ratio < 1.0
                          if position_side == "long"
                            market_price >= implied_prob * exit_ratio
                          else
                            market_price <= implied_prob * (2.0 - exit_ratio)
                          end
                        else
                          edge.abs < exit_edge
                        end

          if should_exit
            signals << build_signal(
              type: "exit", direction: position_side,
              confidence: 0.7, strength: 0.6,
              reasoning: exit_ratio < 1.0 ?
                "Exit at #{(exit_ratio * 100).round(0)}% of model value: market #{(market_price * 100).round(1)}% vs target #{(implied_prob * exit_ratio * 100).round(1)}%" :
                "Spot-lag edge collapsed to #{(edge * 100).round(2)}%, market has caught up",
              indicators: { edge: edge, edge_pct: (edge * 100).round(2), exit_ratio: exit_ratio }
            )
          end
        end

        signals
      end

      private

      # Logit Jump-Diffusion model for prediction market implied probability.
      #
      # Standard Black-Scholes assumes log-normal prices unbounded above zero —
      # WRONG for prediction markets where p ∈ (0,1). This model applies the
      # logit transform L(p) = ln(p/(1-p)) which maps (0,1) → (-∞,+∞), runs
      # the diffusion in logit-space, then maps back.
      #
      # Jump component (λ) handles discrete event-driven price jumps (e.g.,
      # earnings, policy announcements) that continuous diffusion can't capture.
      #
      # Reference: "Toward Black-Scholes for Prediction Markets" (arXiv 2510.15205)
      def calculate_implied_probability(spot, strike)
        vol = estimate_volatility
        return simple_implied_probability(spot, strike) if vol.nil? || vol.zero?

        time_remaining = time_to_expiry
        return simple_implied_probability(spot, strike) if time_remaining.nil? || time_remaining <= 0

        r = param("risk_free_rate", 0.05).to_f
        lambda_jump = param("jump_intensity", 0.0).to_f

        # Belief volatility: for prediction markets, σ_b captures the volatility
        # of the belief process, not the underlying asset. Scale down raw vol
        # since prediction market prices are bounded and less volatile than spot.
        sigma_b = param("belief_volatility", nil)&.to_f
        sigma_b = vol * 0.5 if sigma_b.nil? || sigma_b <= 0

        # Logit-space d1: operates on ln(S/K) like Black-Scholes but with
        # belief volatility σ_b instead of asset volatility σ.
        logit_d1 = (Math.log(spot / strike) + (r + 0.5 * sigma_b**2) * time_remaining) / (sigma_b * Math.sqrt(time_remaining))

        # Continuous component: N(logit_d1) gives base implied probability
        continuous_prob = normal_cdf(logit_d1)

        # Jump component: jumps reduce certainty by pulling probability toward 0.5.
        # With jump intensity λ and time T, the probability of at least one jump
        # is 1 - e^(-λT). Each jump introduces uncertainty (mean-reversion to 0.5).
        if lambda_jump > 0 && time_remaining > 0
          jump_prob = 1.0 - Math.exp(-lambda_jump * time_remaining)
          # Blend: weighted average between continuous estimate and 0.5 (max uncertainty)
          implied = continuous_prob * (1.0 - jump_prob) + 0.5 * jump_prob
        else
          implied = continuous_prob
        end

        # Logit-space boundary: ensure result stays in valid prediction market range
        # Apply calibration if available (SignalCalibration concern)
        implied = calibrate_probability(implied) if respond_to?(:calibrate_probability, true)
        implied.clamp(0.01, 0.99)
      rescue StandardError
        simple_implied_probability(spot, strike)
      end

      # Sigmoid/logistic fallback — uses logit transform for bounded (0,1) output.
      # The scaling factor 5.0 controls steepness around the strike.
      def simple_implied_probability(spot, strike)
        logit = Math.log(spot / strike) * 5.0
        1.0 / (1.0 + Math.exp(-logit))
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

      # Try to extract a numeric strike/threshold from the market question.
      # E.g. "Will BTC be above $80,000?" → 80000.0
      def extract_strike_from_question
        return nil unless @market_question

        match = @market_question.match(/\$?([\d,]+(?:\.\d+)?)/)
        return nil unless match

        value = match[1].delete(",").to_f
        value > 0 ? value : nil
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
