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

        # E3: Adverse selection detector — halt quoting when per-market win rate
        # drops below threshold. Data: 2/3 markets had 0% win rate (60+ fills each,
        # -$5,300 per market) while 1 market was profitable.
        @adverse_selection_tracker ||= {}
        pair_key = strategy_pair
        as_tracker = @adverse_selection_tracker[pair_key] ||= { wins: 0, losses: 0 }
        min_fills_to_judge = param("adverse_selection_min_fills", 10)
        min_win_rate = param("adverse_selection_min_win_rate", 0.08)
        total_fills = as_tracker[:wins] + as_tracker[:losses]

        if !has_open_position? && total_fills >= min_fills_to_judge
          win_rate = as_tracker[:wins].to_f / total_fills
          if win_rate < min_win_rate
            return signals # halt quoting on this pair — getting picked off
          end
        end

        # Settlement halt: stop quoting near market expiry (skip in training — ticks are compressed)
        unless training?
          halt_hours = param("settlement_halt_hours", 2)
          if market_expiry
            hours_left = (market_expiry - Time.now) / 3600.0
            return has_open_position? ? check_tp_sl(signals) : signals if hours_left < halt_hours
          end
        end

        # Volatility halt: pause in extreme price swings
        if price_history&.size.to_i >= 5
          recent_returns = price_history.last(5).each_cons(2).map { |a, b|
            prev_close = (a["close"] || a[:close] || 0).to_f
            curr_close = (b["close"] || b[:close] || 0).to_f
            prev_close > 0 ? ((curr_close - prev_close) / prev_close).abs : 0
          }
          max_swing = recent_returns.max || 0
          if max_swing > param("volatility_halt_threshold", 0.15)
            return has_open_position? ? check_tp_sl(signals) : signals
          end
        end

        bid = bid_price
        ask = ask_price
        return signals unless bid > 0 && ask > 0

        mid_price = (bid + ask) / 2.0
        pm_mode = param("pm_mode", false) || mid_price.between?(0.01, 0.99)

        if pm_mode
          spread_cents = ((ask - bid) * 100).round(2)
          min_cents = param("min_spread_cents", 2)
          return signals if spread_cents < min_cents
          target_spread = param("target_spread_cents", 3) / 100.0
        else
          current_spread = ((ask - bid) / mid_price * 10_000).round(2)
          return signals if current_spread < min_spread_bps
          target_spread = spread_bps / 10_000.0
        end

        inventory_ratio = calculate_inventory_ratio
        skew_factor = inventory_skew ? calculate_skew(inventory_ratio) : 0

        half_spread = target_spread / 2.0
        bid_p = [mid_price - half_spread - skew_factor, 0.01].max
        display_spread = pm_mode ? "#{spread_cents}c" : "#{current_spread}bps"
        bid_confidence = calculate_bid_confidence(inventory_ratio, pm_mode ? spread_cents : current_spread, pm_mode ? param("target_spread_cents", 3) : spread_bps)

        if bid_confidence > param("confidence_threshold", 0.3) && inventory_ratio < max_inventory_ratio
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: bid_confidence,
            strength: pm_mode ? [spread_cents / 6.0, 1.0].min : [current_spread / (spread_bps * 2.0), 1.0].min,
            reasoning: "Market making bid: #{bid_p.round(4)} (spread: #{display_spread}, inventory: #{(inventory_ratio * 100).round(1)}%)",
            indicators: {
              bid_price: bid_p, mid_price: mid_price,
              spread_bps: pm_mode ? (spread_cents * 100).round(0) : current_spread,
              inventory_ratio: inventory_ratio, skew_factor: skew_factor,
              limit_order: true,
              limit_price: bid_p.round(4),
              edge: half_spread
            }
          )
        end

        if has_open_position? || pm_mode
          ask_p = [mid_price + half_spread + skew_factor, 0.99].min
          ask_confidence = calculate_ask_confidence(inventory_ratio, pm_mode ? spread_cents : current_spread, pm_mode ? param("target_spread_cents", 3) : spread_bps)
          if ask_confidence > param("confidence_threshold", 0.3)
            signals << build_signal(
              type: has_open_position? ? "exit" : "entry",
              direction: has_open_position? ? "long" : "short",
              confidence: ask_confidence,
              strength: pm_mode ? [spread_cents / 6.0, 1.0].min : [current_spread / (spread_bps * 2.0), 1.0].min,
              reasoning: "Market making ask: #{ask_p.round(4)} (spread: #{display_spread})",
              indicators: {
                ask_price: ask_p, mid_price: mid_price,
                spread_bps: pm_mode ? (spread_cents * 100).round(0) : current_spread,
                inventory_ratio: inventory_ratio,
                limit_order: true,
                limit_price: ask_p.round(4),
                edge: half_spread
              }
            )
          end
        end

        # TP/SL exits for open positions
        check_tp_sl(signals) if has_open_position?

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
        # Wider spread = more profit per trade but spread width shouldn't inflate confidence.
        # Use spread ratio for sizing, and base confidence on inventory room + market conditions.
        spread_efficiency = [current_spread / [target_spread.to_f, 0.01].max, 2.0].min / 2.0
        inventory_room = 1.0 - inventory_ratio
        (spread_efficiency * 0.4 + inventory_room * 0.6).clamp(0.2, 0.85).round(4)
      end

      def calculate_ask_confidence(inventory_ratio, current_spread, target_spread)
        spread_efficiency = [current_spread / [target_spread.to_f, 0.01].max, 2.0].min / 2.0
        # Higher inventory = more urgency to sell, so higher ask confidence
        inventory_urgency = inventory_ratio
        (spread_efficiency * 0.4 + inventory_urgency * 0.6).clamp(0.2, 0.85).round(4)
      end

      def check_tp_sl(signals)
        position = current_position
        return signals unless position

        entry_price = (position["entry_price"] || 0).to_f
        side = position["side"] || "long"
        pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
        stop_loss = param("stop_loss_pct", 3.0)
        take_profit = param("take_profit_pct", 2.0)

        if pnl_pct <= -stop_loss
          # E3: Track as adverse selection loss
          as_tracker = (@adverse_selection_tracker ||= {})[strategy_pair] ||= { wins: 0, losses: 0 }
          as_tracker[:losses] += 1
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.9, strength: 0.9,
            reasoning: "MM stop-loss: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit (adverse: #{as_tracker[:losses]}L/#{as_tracker[:wins]}W)",
            indicators: { pnl_pct: pnl_pct, edge: 0, adverse_selection_losses: as_tracker[:losses] }
          )
        elsif pnl_pct >= take_profit
          # E3: Track as win
          as_tracker = (@adverse_selection_tracker ||= {})[strategy_pair] ||= { wins: 0, losses: 0 }
          as_tracker[:wins] += 1
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.85, strength: 0.8,
            reasoning: "MM take-profit: PnL #{pnl_pct.round(2)}% exceeds +#{take_profit}% target",
            indicators: { pnl_pct: pnl_pct, edge: 0 }
          )
        end
        signals
      end
    end
  end
end
