# frozen_string_literal: true

module Trading
  module Evaluators
    class PredictionMarketMaking < Base
      register "prediction_market_making"

      def evaluate
        signals = []
        price = current_price
        return signals unless price && price > 0 && price < 1

        # Settlement proximity check — stop quoting near settlement
        halt_hours = param("settlement_halt_hours", 6)
        widen_hours = param("settlement_widen_hours", 24)

        if market_expiry
          hours_left = (market_expiry - Time.now) / 3600.0
          return signals if hours_left < halt_hours

          # Generate aggressive exit signals for remaining inventory before halt
          if hours_left < halt_hours * 2 && has_open_position?
            signals << build_exit_signal("Settlement approaching (#{hours_left.round(1)}h remaining), unwinding inventory")
            return signals
          end
        else
          hours_left = nil
        end

        # Volatility halt — pause in extreme volatility
        if @price_history.length >= 5
          recent_returns = @price_history.last(5).each_cons(2).map do |a, b|
            prev_close = (a["close"] || a[:close] || 0).to_f
            curr_close = (b["close"] || b[:close] || 0).to_f
            prev_close > 0 ? ((curr_close - prev_close) / prev_close).abs : 0
          end
          avg_volatility = recent_returns.sum / recent_returns.length
          if avg_volatility > param("volatility_halt_pct", 5.0) / 100.0
            return signals
          end
        end

        # Estimate fair value
        fair_value = estimate_fair_value(price)

        # Calculate Stoikov optimal spread
        sigma = calculate_binary_sigma(price)
        gamma = calculate_risk_aversion(hours_left)
        t_remaining = hours_left ? [hours_left / 24.0, 0.01].max : 1.0
        kappa = estimate_arrival_rate

        # Stoikov reservation price and spread
        # r = s - q * gamma * sigma^2 * T  (inventory-adjusted mid)
        inventory = calculate_net_inventory
        max_inventory_pct = param("max_inventory_pct", 20.0) / 100.0
        inventory_ratio = @allocated_capital > 0 ? inventory.abs / @allocated_capital : 0

        reservation_price = fair_value - inventory * gamma * (sigma**2) * t_remaining

        # Optimal spread: delta = gamma * sigma^2 * T + (2/gamma) * ln(1 + gamma/kappa)
        spread_component = gamma * (sigma**2) * t_remaining
        arrival_component = gamma > 0 && kappa > 0 ? (2.0 / gamma) * Math.log(1 + gamma / kappa) : 0.02
        optimal_spread = spread_component + arrival_component

        # Apply settlement widening
        if hours_left && hours_left < widen_hours
          widen_factor = 1.0 + (widen_hours - hours_left) / widen_hours
          optimal_spread *= widen_factor
        end

        # Enforce minimum spread
        min_spread = param("min_spread_cents", 3) / 100.0
        optimal_spread = [optimal_spread, min_spread].max

        # Calculate bid and ask prices
        bid_price = [reservation_price - optimal_spread / 2.0, 0.01].max
        ask_price_calc = [reservation_price + optimal_spread / 2.0, 0.99].min

        # Skip if inventory limit reached (only quote on reducing side)
        skip_bid = inventory_ratio > max_inventory_pct && inventory > 0
        skip_ask = inventory_ratio > max_inventory_pct && inventory < 0

        quote_confidence = calculate_quote_confidence(optimal_spread, sigma, inventory_ratio)

        # Generate bid signal (buying YES = going long)
        unless skip_bid
          signals << build_signal(
            type: "entry",
            direction: "long",
            confidence: quote_confidence,
            strength: classify_spread_strength(optimal_spread),
            reasoning: "Market making bid: fair=#{(fair_value * 100).round(1)}¢, bid=#{(bid_price * 100).round(1)}¢, spread=#{(optimal_spread * 100).round(1)}¢, inventory=#{inventory.round(2)}",
            indicators: {
              edge: optimal_spread / 2.0,
              edge_pct: (optimal_spread / 2.0 / fair_value * 100).round(2),
              market_price: price,
              fair_value: fair_value,
              reservation_price: reservation_price,
              limit_order: true,
              limit_price: bid_price.round(2),
              spread: optimal_spread,
              spread_cents: (optimal_spread * 100).round(1),
              inventory: inventory,
              inventory_ratio: inventory_ratio,
              sigma: sigma,
              gamma: gamma,
              quote_side: "bid",
              hours_to_expiry: hours_left,
              position_sizing_method: "percent_equity"
            }
          )
        end

        # Generate ask signal (selling YES = going short)
        unless skip_ask
          signals << build_signal(
            type: "entry",
            direction: "short",
            confidence: quote_confidence,
            strength: classify_spread_strength(optimal_spread),
            reasoning: "Market making ask: fair=#{(fair_value * 100).round(1)}¢, ask=#{(ask_price_calc * 100).round(1)}¢, spread=#{(optimal_spread * 100).round(1)}¢, inventory=#{inventory.round(2)}",
            indicators: {
              edge: optimal_spread / 2.0,
              edge_pct: (optimal_spread / 2.0 / fair_value * 100).round(2),
              market_price: price,
              fair_value: fair_value,
              reservation_price: reservation_price,
              limit_order: true,
              limit_price: ask_price_calc.round(2),
              spread: optimal_spread,
              spread_cents: (optimal_spread * 100).round(1),
              inventory: inventory,
              inventory_ratio: inventory_ratio,
              sigma: sigma,
              gamma: gamma,
              quote_side: "ask",
              hours_to_expiry: hours_left,
              position_sizing_method: "percent_equity"
            }
          )
        end

        signals
      end

      def tick_cost_usd
        0.0 # No LLM calls — pure quantitative model
      end

      private

      def estimate_fair_value(price)
        # Blend: parity data + price history + current mid
        parity_fair = nil
        if @parity_data && @parity_data["yes_price"] && @parity_data["no_price"]
          yes_p = @parity_data["yes_price"].to_f
          no_p = @parity_data["no_price"].to_f
          total = yes_p + no_p
          parity_fair = yes_p / total if total > 0
        end

        history_fair = nil
        if @price_history.length >= 10
          recent = @price_history.last(10).map { |c| (c["close"] || c[:close] || 0).to_f }
          history_fair = recent.sum / recent.length
        end

        mid = bid_price && ask_price ? (bid_price + ask_price) / 2.0 : price

        values = [parity_fair, history_fair, mid].compact
        values.empty? ? price : values.sum / values.length
      end

      def calculate_binary_sigma(price)
        # Binary outcome: sigma bounded by sqrt(p * (1-p))
        theoretical_max = Math.sqrt(price * (1 - price))

        if @price_history.length >= 5
          returns = @price_history.last(20).each_cons(2).map do |a, b|
            prev = (a["close"] || a[:close] || 0).to_f
            curr = (b["close"] || b[:close] || 0).to_f
            prev > 0 ? (curr - prev) / prev : 0
          end
          realized = returns.empty? ? 0 : Math.sqrt(returns.map { |r| r**2 }.sum / returns.length)
          [realized, theoretical_max].min
        else
          theoretical_max * 0.5 # Conservative estimate
        end
      end

      def calculate_risk_aversion(hours_left)
        base_gamma = param("risk_aversion_gamma", 0.1)
        return base_gamma unless hours_left

        # Exponentially increase risk aversion as settlement approaches
        if hours_left < 24
          base_gamma * (24.0 / [hours_left, 1.0].max)
        else
          base_gamma
        end
      end

      def estimate_arrival_rate
        # From recent volume / time period
        if @market_data && @market_data["volume_24h"]
          vol = @market_data["volume_24h"].to_f
          vol / 24.0 / 60.0 # Orders per minute estimate
        else
          1.0 # Default: 1 order per minute
        end
      end

      def calculate_net_inventory
        @positions.select { |p| p["status"] == "open" }.sum do |pos|
          qty = (pos["quantity"] || pos["current_quantity"] || 0).to_f
          side = pos["side"]
          side == "long" ? qty : -qty
        end
      end

      def calculate_quote_confidence(spread, sigma, inventory_ratio)
        base = 0.5

        # Wider spread -> higher confidence (more buffer)
        spread_bonus = [spread * 5, 0.2].min

        # Lower volatility -> higher confidence
        vol_bonus = sigma < 0.1 ? 0.1 : 0.0

        # Lower inventory -> higher confidence
        inventory_penalty = [inventory_ratio * 0.3, 0.15].min

        [base + spread_bonus + vol_bonus - inventory_penalty, 0.9].min.clamp(0.2, 0.9)
      end

      def classify_spread_strength(spread)
        case spread
        when (0.10..) then "very_strong"
        when (0.06..0.10) then "strong"
        when (0.03..0.06) then "moderate"
        else "weak"
        end
      end

      def build_exit_signal(reason)
        build_signal(
          type: "exit",
          direction: "close",
          confidence: 0.9,
          strength: "strong",
          reasoning: reason,
          indicators: {
            edge: 0,
            market_price: current_price,
            exit_reason: "settlement_proximity"
          }
        )
      end

      # Override base bid/ask to avoid naming conflict
      def bid_price
        (@market_data["bid"] || @market_data[:bid] || 0).to_f
      end

      def ask_price
        (@market_data["ask"] || @market_data[:ask] || 0).to_f
      end
    end
  end
end
