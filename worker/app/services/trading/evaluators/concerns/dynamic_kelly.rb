# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Computes dynamic Kelly fractions from current edge + historical performance.
      #
      # Replaces hardcoded kelly_fraction params in evaluators with edge-derived,
      # impact-adjusted sizing. Blends real-time edge-based Kelly with server-
      # computed optimal_kelly_fraction from MonteCarloService based on sample size.
      #
      # Depends on DepthAware (included in Base) for price impact estimation.
      module DynamicKelly
        # Compute a dynamic Kelly fraction for position sizing.
        #
        # @param estimated_prob [Float] evaluator's probability estimate (0-1)
        # @param market_price [Float] current market price (0-1 for prediction markets)
        # @return [Hash] { kelly_fraction:, kelly_full:, edge_after_impact:, safety_multiplier:, blend_source: }
        def dynamic_kelly(estimated_prob:, market_price:)
          safety = param("kelly_safety_multiplier", 0.25)
          max_kelly = param("max_kelly_fraction", 0.15)

          # Edge-based Kelly from current tick
          edge = (estimated_prob - market_price).abs
          edge_kelly = compute_edge_kelly(estimated_prob, market_price)

          # Blend with historical optimal Kelly from MonteCarloService
          historical_kelly = @performance_context["optimal_kelly"] || @performance_context[:optimal_kelly]
          edge_profile = @performance_context["edge_profile"] || @performance_context[:edge_profile] || {}
          total_trades = (edge_profile["total_trades"] || edge_profile[:total_trades] || 0).to_i

          blended = blend_kelly(edge_kelly, historical_kelly, total_trades)

          # Adjust for price impact: reduce Kelly when impact eats into edge
          impact = estimate_price_impact(side: estimated_prob > market_price ? "buy" : "sell",
                                         size_usd: @allocated_capital * blended * safety)
          edge_after_impact = [edge - impact[:slippage_pct], 0.0].max

          # If impact consumes more than half the edge, reduce proportionally
          impact_ratio = edge > 0 ? edge_after_impact / edge : 1.0
          adjusted = blended * impact_ratio

          # Apply safety multiplier and hard cap
          final = [adjusted * safety, max_kelly].min
          final = [final, 0.0].max

          {
            kelly_fraction: final.round(4),
            kelly_full: edge_kelly.round(4),
            edge_after_impact: edge_after_impact.round(4),
            safety_multiplier: safety,
            blend_source: blend_source_label(historical_kelly, total_trades),
            total_trades: total_trades
          }
        end

        private

        # Standard Kelly for binary outcome: f* = (bp - q) / b
        # where b = payout odds, p = win probability, q = 1-p
        def compute_edge_kelly(estimated_prob, market_price)
          return 0.0 if market_price <= 0 || market_price >= 1

          if estimated_prob > market_price
            # Long: buy YES at market_price, payout 1.0 on win
            b = (1.0 / market_price) - 1.0 # net odds
            p = estimated_prob
          else
            # Short: sell YES at market_price, payout market_price on win
            b = market_price / (1.0 - market_price)
            p = 1.0 - estimated_prob
          end

          return 0.0 if b <= 0

          q = 1.0 - p
          kelly = (b * p - q) / b
          kelly.clamp(0.0, 1.0)
        end

        # Blend edge-based Kelly with historical optimal Kelly weighted by sample size.
        #
        # < 10 trades: 100% edge-based (no history to trust)
        # 10-100 trades: log-weighted blend toward historical
        # 100+ trades: 75% historical, 25% edge-based
        def blend_kelly(edge_kelly, historical_kelly, total_trades)
          return edge_kelly unless historical_kelly && historical_kelly > 0

          if total_trades < 10
            edge_kelly
          elsif total_trades < 100
            # Log-weighted blend: at 10 trades → ~0% historical, at 100 → ~75%
            historical_weight = Math.log10(total_trades) - 1.0 # 0 at 10, 1 at 100
            historical_weight = (historical_weight * 0.75).clamp(0.0, 0.75)
            edge_kelly * (1.0 - historical_weight) + historical_kelly * historical_weight
          else
            edge_kelly * 0.25 + historical_kelly * 0.75
          end
        end

        def blend_source_label(historical_kelly, total_trades)
          if historical_kelly.nil? || historical_kelly <= 0
            "edge_only"
          elsif total_trades < 10
            "edge_only_insufficient_history"
          elsif total_trades < 100
            "blended"
          else
            "historical_dominant"
          end
        end
      end
    end
  end
end
