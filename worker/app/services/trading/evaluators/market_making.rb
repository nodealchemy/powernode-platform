# frozen_string_literal: true

module Trading
  module Evaluators
    class MarketMaking < Base
      register "market_making"

      def evaluate
        signals = []
        spread_bps = param("spread_bps", 20)
        min_spread_bps = param("min_spread_bps", 10)
        inventory_skew = param("inventory_skew", true)
        max_inventory_ratio = param("max_inventory_ratio", 0.6)

        bid = bid_price
        ask = ask_price
        return signals unless bid > 0 && ask > 0

        mid_price = (bid + ask) / 2.0
        current_spread = ((ask - bid) / mid_price * 10_000).round(2)
        return signals if current_spread < min_spread_bps

        inventory_ratio = calculate_inventory_ratio
        skew_factor = inventory_skew ? calculate_skew(inventory_ratio) : 0

        bid_p = mid_price * (1 - spread_bps / 20_000.0 - skew_factor)
        bid_confidence = calculate_bid_confidence(inventory_ratio, current_spread, spread_bps)

        if bid_confidence > 0.4 && inventory_ratio < max_inventory_ratio
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: bid_confidence,
            strength: [current_spread / (spread_bps * 2.0), 1.0].min,
            reasoning: "Market making bid: #{bid_p.round(4)} (spread: #{current_spread}bps, inventory: #{(inventory_ratio * 100).round(1)}%)",
            indicators: {
              bid_price: bid_p, mid_price: mid_price, spread_bps: current_spread,
              inventory_ratio: inventory_ratio, skew_factor: skew_factor,
              limit_order: true,
              limit_price: bid_p.round(4),
              edge: (mid_price - bid_p).abs
            }
          )
        end

        if has_open_position?
          ask_p = mid_price * (1 + spread_bps / 20_000.0 + skew_factor)
          ask_confidence = calculate_ask_confidence(inventory_ratio, current_spread, spread_bps)
          if ask_confidence > 0.4
            signals << build_signal(
              type: "exit", direction: "long",
              confidence: ask_confidence,
              strength: [current_spread / (spread_bps * 2.0), 1.0].min,
              reasoning: "Market making ask: #{ask_p.round(4)} (spread: #{current_spread}bps)",
              indicators: {
                ask_price: ask_p, mid_price: mid_price, spread_bps: current_spread,
                inventory_ratio: inventory_ratio,
                limit_order: true,
                limit_price: ask_p.round(4),
                edge: (ask_p - mid_price).abs
              }
            )
          end
        end

        signals
      end

      private

      def calculate_inventory_ratio
        return 0.0 if allocated_capital.zero?
        position_value = @positions.sum { |p| (p["quantity"] || 0).to_f * (p["current_price"] || current_price).to_f }
        (position_value / allocated_capital).clamp(0, 1)
      end

      def calculate_skew(inventory_ratio)
        neutral = 0.5
        deviation = inventory_ratio - neutral
        deviation * param("skew_intensity", 0.002)
      end

      def calculate_bid_confidence(inventory_ratio, current_spread, target_spread)
        spread_score = [current_spread / target_spread.to_f, 1.5].min / 1.5
        inventory_score = 1.0 - inventory_ratio
        (spread_score * 0.6 + inventory_score * 0.4).round(4)
      end

      def calculate_ask_confidence(inventory_ratio, current_spread, target_spread)
        spread_score = [current_spread / target_spread.to_f, 1.5].min / 1.5
        inventory_score = inventory_ratio
        (spread_score * 0.6 + inventory_score * 0.4).round(4)
      end
    end
  end
end
