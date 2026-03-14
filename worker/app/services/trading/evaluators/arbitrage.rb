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

        min_gap = param("min_parity_gap", 0.005)
        max_gap = param("max_parity_gap", 0.10)  # Sanity cap: >10% gap is likely data error
        yes_price = (parity_data["yes_price"] || parity_data[:yes_price]).to_f
        no_price = (parity_data["no_price"] || parity_data[:no_price]).to_f
        return signals if yes_price <= 0 || no_price <= 0

        # Sanity check: YES + NO should be close to 1.0 for binary markets
        parity_sum = yes_price + no_price
        if parity_sum < 0.80 || parity_sum > 1.20
          log("#{strategy_pair}: parity sanity failed — YES=#{yes_price.round(4)} + NO=#{no_price.round(4)} = #{parity_sum.round(4)}")
          return signals
        end

        # Mode 1: Buy-both arb using ask prices (true execution cost)
        buy_gap = (parity_data["buy_both_gap"] || 0).to_f
        if buy_gap > min_gap && buy_gap <= max_gap
          log("#{strategy_pair}: buy-both arb gap=#{(buy_gap * 100).round(2)}%")
          generate_buy_both_signal(signals, buy_gap, yes_price, no_price)
          return signals
        elsif buy_gap > max_gap
          log("#{strategy_pair}: buy-both gap #{(buy_gap * 100).round(1)}% exceeds max #{(max_gap * 100).round(1)}% — likely data error")
        end

        # Mode 2: Sell-both arb using bid prices (reverse parity)
        sell_gap = (parity_data["sell_both_gap"] || 0).to_f
        if sell_gap > min_gap && sell_gap <= max_gap
          log("#{strategy_pair}: sell-both arb gap=#{(sell_gap * 100).round(2)}%")
          generate_sell_both_signal(signals, sell_gap, yes_price, no_price)
          return signals
        elsif sell_gap > max_gap
          log("#{strategy_pair}: sell-both gap #{(sell_gap * 100).round(1)}% exceeds max #{(max_gap * 100).round(1)}% — likely data error")
        end

        signals
      end

      def generate_buy_both_signal(signals, gap, yes_price, no_price)
        # Pass ask prices for accurate execution cost (not midpoints)
        yes_ask = (parity_data["yes_ask"] || parity_data[:yes_ask] || yes_price).to_f
        no_ask = (parity_data["no_ask"] || parity_data[:no_ask] || no_price).to_f

        signals << build_signal(
          type: "entry", direction: "long",
          confidence: [(gap / 0.03), 0.9].min.clamp(0.3, 0.9),
          strength: (gap / 0.05).clamp(0.0, 1.0),
          reasoning: "Buy-both parity arb: YES_ask=$#{yes_ask.round(4)} + NO_ask=$#{no_ask.round(4)} = $#{(yes_ask + no_ask).round(4)}, guaranteed $1 payout (gap: #{(gap * 100).round(2)}%)",
          indicators: {
            edge: gap, yes_price: yes_ask, no_price: no_ask,
            parity_gap: gap, arb_mode: "buy_both",
            complementary_pair: parity_data["complementary_pair"] || parity_data[:complementary_pair],
            multi_leg: true,
            legs: [
              { pair: strategy_pair, side: "buy" },
              { pair: parity_data["complementary_pair"] || parity_data[:complementary_pair], side: "buy" }
            ]
          }
        )
      end

      def generate_sell_both_signal(signals, gap, yes_price, no_price)
        # Pass bid prices for accurate execution proceeds (not midpoints)
        yes_bid = (parity_data["yes_bid"] || parity_data[:yes_bid] || yes_price).to_f
        no_bid = (parity_data["no_bid"] || parity_data[:no_bid] || no_price).to_f

        signals << build_signal(
          type: "entry", direction: "short",
          confidence: [(gap / 0.03), 0.9].min.clamp(0.3, 0.9),
          strength: (gap / 0.05).clamp(0.0, 1.0),
          reasoning: "Sell-both parity arb: YES_bid=$#{yes_bid.round(4)} + NO_bid=$#{no_bid.round(4)} = $#{(yes_bid + no_bid).round(4)} > $1 (gap: #{(gap * 100).round(2)}%)",
          indicators: {
            edge: gap, yes_price: yes_bid, no_price: no_bid,
            parity_gap: gap, arb_mode: "sell_both",
            complementary_pair: parity_data["complementary_pair"] || parity_data[:complementary_pair],
            multi_leg: true,
            legs: [
              { pair: strategy_pair, side: "sell" },
              { pair: parity_data["complementary_pair"] || parity_data[:complementary_pair], side: "sell" }
            ]
          }
        )
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
