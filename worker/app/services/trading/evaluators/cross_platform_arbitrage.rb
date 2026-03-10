# frozen_string_literal: true

module Trading
  module Evaluators
    class CrossPlatformArbitrage < Base
      register "cross_platform_arbitrage"

      def evaluate
        signals = []

        # Load cross-venue mappings from strategy parameters
        mappings = param("cross_venue_mappings", [])
        return signals if mappings.empty?

        # Check concurrent position limits
        max_positions = param("max_arb_positions", 3)
        open_count = @positions.count { |p| p["status"] == "open" }
        return signals if open_count >= max_positions

        min_divergence = param("min_divergence_pct", 2.0) / 100.0
        exit_divergence = param("exit_divergence_pct", 0.5) / 100.0

        # Get current venue info
        current_venue_id = @strategy_data.dig("config", "venue_id") || @strategy_data["venue_id"]

        mappings.each do |mapping|
          kalshi_pair = mapping["kalshi_pair"]
          pm_pair = mapping["polymarket_pair"]
          settlement_match = mapping.fetch("settlement_rules_match", true)

          # Skip if settlement rules don't match
          unless settlement_match
            log("Skipping #{kalshi_pair} <> #{pm_pair}: settlement rules differ")
            next
          end

          # Fetch counterpart price via data_fetcher
          counterpart_venue_id = mapping["counterpart_venue_id"]
          next unless counterpart_venue_id

          begin
            counterpart_data = @data_fetcher&.fetch_ticker(
              pair: pm_pair,
              venue_id: counterpart_venue_id
            )
          rescue => e
            log("Failed to fetch counterpart price for #{pm_pair}: #{e.message}", level: :warn)
            next
          end

          next unless counterpart_data

          # Current market price (Kalshi side)
          kalshi_price = current_price
          pm_price = (counterpart_data["last_price"] || counterpart_data[:last_price] || 0).to_f

          next if kalshi_price <= 0 || pm_price <= 0

          divergence = (kalshi_price - pm_price).abs

          # Check for exit on existing positions
          has_arb_position = @positions.any? do |p|
            p["status"] == "open" &&
              (p.dig("metadata", "arb_pair") == "#{kalshi_pair}:#{pm_pair}" ||
               p.dig("config", "arb_pair") == "#{kalshi_pair}:#{pm_pair}")
          end

          if has_arb_position && divergence < exit_divergence
            signals << build_signal(
              type: "exit",
              direction: "close",
              confidence: 0.85,
              strength: 0.6,
              reasoning: "Arbitrage convergence: #{kalshi_pair} <> #{pm_pair} divergence collapsed to #{(divergence * 100).round(2)}% (< #{(exit_divergence * 100).round(1)}% threshold)",
              indicators: {
                edge: 0,
                market_price: kalshi_price,
                counterpart_price: pm_price,
                divergence: divergence,
                divergence_pct: (divergence * 100).round(2),
                exit_reason: "convergence",
                arb_pair: "#{kalshi_pair}:#{pm_pair}"
              }
            )
            next
          end

          # Entry signal when divergence exceeds threshold
          next unless divergence >= min_divergence
          next if has_arb_position  # Already in this arb

          # Determine direction: buy cheap, sell expensive
          if kalshi_price < pm_price
            direction = "long"  # Buy on Kalshi (cheap), sell on Polymarket (expensive)
            entry_price = kalshi_price
          else
            direction = "short"  # Sell on Kalshi (expensive), buy on Polymarket (cheap)
            entry_price = kalshi_price
          end

          confidence = calculate_arb_confidence(divergence, settlement_match, mapping)

          signals << build_signal(
            type: "entry",
            direction: direction,
            confidence: confidence,
            strength: classify_arb_strength(divergence),
            reasoning: "Cross-venue arbitrage: Kalshi #{(kalshi_price * 100).round(1)}c vs Polymarket #{(pm_price * 100).round(1)}c. Divergence: #{(divergence * 100).round(2)}%. #{direction == 'long' ? 'Buying' : 'Selling'} on Kalshi.",
            indicators: {
              edge: divergence,
              edge_pct: (divergence * 100).round(2),
              market_price: kalshi_price,
              counterpart_price: pm_price,
              divergence: divergence,
              divergence_pct: (divergence * 100).round(2),
              limit_order: true,
              limit_price: entry_price,
              arb_pair: "#{kalshi_pair}:#{pm_pair}",
              kalshi_pair: kalshi_pair,
              polymarket_pair: pm_pair,
              counterpart_venue_id: counterpart_venue_id,
              position_sizing_method: "percent_equity"
            }
          )
        end

        signals
      end

      def tick_cost_usd
        0.0  # No LLM calls -- price comparison only
      end

      private

      def calculate_arb_confidence(divergence, settlement_match, mapping)
        base = 0.4

        # Larger divergence -> higher confidence
        div_bonus = [divergence * 5, 0.3].min

        # Manual mapping -> higher confidence than fuzzy
        source_bonus = mapping["match_source"] == "manual" ? 0.15 : 0.05

        # Settlement rules match -> bonus
        settlement_bonus = settlement_match ? 0.1 : 0.0

        [base + div_bonus + source_bonus + settlement_bonus, 0.95].min.clamp(0.2, 0.95)
      end

      def classify_arb_strength(divergence)
        case divergence
        when (0.08..) then 1.0
        when (0.05..0.08) then 0.8
        when (0.03..0.05) then 0.6
        else 0.4
        end
      end
    end
  end
end
