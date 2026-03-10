# frozen_string_literal: true

module Trading
  module Evaluators
    class Arbitrage < Base
      register "arbitrage"

      def evaluate
        signals = []
        mode = param("arbitrage_mode", "parity")

        case mode
        when "parity" then parity_arbitrage(signals)
        when "cross_venue" then cross_venue_arbitrage(signals)
        else parity_arbitrage(signals)
        end

        check_exit_conditions(signals)
        signals
      end

      private

      def parity_arbitrage(signals)
        return signals if has_open_position?
        return signals if parity_data.nil? || parity_data.empty?

        min_gap = param("min_parity_gap", 0.05)
        gap = (parity_data["parity_gap"] || parity_data[:parity_gap]).to_f
        return signals unless gap > min_gap

        yes_price = (parity_data["yes_price"] || parity_data[:yes_price]).to_f
        no_price = (parity_data["no_price"] || parity_data[:no_price]).to_f
        total_cost = yes_price + no_price
        profit_per_unit = 1.0 - total_cost
        confidence = [(gap / (min_gap * 3)), 1.0].min.clamp(0.0, 1.0)

        signals << build_signal(
          type: "entry", direction: "long",
          confidence: confidence,
          strength: (gap / 0.10).clamp(0.0, 1.0),
          reasoning: "Parity arbitrage: YES=$#{yes_price.round(4)} + NO=$#{no_price.round(4)} = $#{total_cost.round(4)} (gap: #{(gap * 100).round(2)}%, profit/unit: $#{profit_per_unit.round(4)})",
          indicators: {
            edge: profit_per_unit, market_price: yes_price,
            yes_price: yes_price, no_price: no_price,
            parity_gap: gap, total_cost: total_cost, profit_per_unit: profit_per_unit,
            complementary_pair: parity_data["complementary_pair"] || parity_data[:complementary_pair],
            multi_leg: param("use_multi_leg", false),
            legs: [
              { pair: strategy_pair, side: "buy" },
              { pair: parity_data["complementary_pair"] || parity_data[:complementary_pair], side: "buy" }
            ]
          }
        )
        signals
      end

      def cross_venue_arbitrage(signals)
        venues = param("arbitrage_venues", [])
        return signals if venues.size < 2

        min_spread = param("min_spread_pct", 0.5)
        base = current_price

        simulated_prices = venues.map do |venue_slug|
          variance = rand(-0.02..0.02)
          { venue: venue_slug, price: base * (1 + variance) }
        end

        best_bid = simulated_prices.max_by { |v| v[:price] }
        best_ask = simulated_prices.min_by { |v| v[:price] }
        spread = ((best_bid[:price] - best_ask[:price]) / best_ask[:price] * 100).round(4)

        if spread >= min_spread && !has_open_position?
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: [spread / (min_spread * 3), 1.0].min,
            strength: [spread / 2.0, 1.0].min,
            reasoning: "Cross-venue arb: #{spread}% spread between #{best_ask[:venue]} and #{best_bid[:venue]}",
            indicators: { edge: spread / 100.0, spread_pct: spread, buy_venue: best_ask[:venue], sell_venue: best_bid[:venue] }
          )
        end
        signals
      end

      def check_exit_conditions(signals)
        return signals unless has_open_position?
        position = current_position
        return signals unless position

        max_hold = param("max_hold_seconds", 3600)
        opened_at = position["opened_at"] ? Time.parse(position["opened_at"]) : nil
        if opened_at && opened_at < (Time.current - max_hold)
          signals << build_signal(
            type: "exit", direction: position["side"],
            confidence: 0.8, strength: 0.7,
            reasoning: "Parity arbitrage max hold time reached, closing position",
            indicators: { edge: 0.05, max_hold_exit: true }
          )
        end
        signals
      end
    end
  end
end
