# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Provides order-book-aware price impact estimation.
      #
      # Included in Base so all evaluators benefit from depth-aware cost
      # estimation via the standard `estimate_signal_cost` interface.
      #
      # Fallback chain: order book walk → square-root impact model → spread proxy.
      module DepthAware
        # Walk the order book to calculate effective fill price and slippage.
        #
        # @param side [String] "buy" or "sell"
        # @param size_usd [Float] order size in USD
        # @param book [Hash] order book with :bids and :asks arrays of {price:, quantity:}
        # @return [Hash] { effective_price:, slippage_pct:, filled_usd:, levels_consumed: }
        def estimate_price_impact(side:, size_usd:, book: nil)
          book ||= @order_book_data
          levels = side == "buy" ? (book["asks"] || book[:asks] || []) : (book["bids"] || book[:bids] || [])

          return sqrt_fallback_impact(side, size_usd) if levels.empty?

          remaining = size_usd
          total_cost = 0.0
          total_qty = 0.0
          levels_consumed = 0

          levels.each do |level|
            price = (level["price"] || level[:price]).to_f
            qty = (level["quantity"] || level[:quantity]).to_f
            next if price <= 0 || qty <= 0

            level_value = price * qty
            fill_value = [remaining, level_value].min
            fill_qty = fill_value / price

            total_cost += fill_value
            total_qty += fill_qty
            remaining -= fill_value
            levels_consumed += 1

            break if remaining <= 0
          end

          return sqrt_fallback_impact(side, size_usd) if total_qty <= 0

          effective_price = total_cost / total_qty
          mid = current_price
          slippage_pct = mid > 0 ? ((effective_price - mid).abs / mid) : 0.0

          {
            effective_price: effective_price.round(6),
            slippage_pct: slippage_pct.round(6),
            filled_usd: (size_usd - remaining).round(4),
            levels_consumed: levels_consumed
          }
        end

        # Square-root impact model for CLOB venues (Kyle 1985, Almgren-Chriss 2001).
        #
        # Impact ∝ σ × √(Q / ADV) where:
        #   σ = realized volatility (approximated from spread)
        #   Q = order size in USD
        #   ADV = average daily volume
        #
        # @param size_usd [Float] order size in USD
        # @param current_price [Float] current market price (0-1 for prediction markets)
        # @param volume_24h [Float] 24-hour volume in USD
        # @param spread [Float] current bid-ask spread (absolute)
        # @return [Float] estimated slippage as a fraction (0.0-0.5)
        def sqrt_price_impact(size_usd:, current_price:, volume_24h:, spread: nil)
          return 0.0 if current_price <= 0 || size_usd <= 0

          # σ approximation: for prediction markets, sqrt(p*(1-p)) captures
          # the binary outcome variance. For non-PM prices, use spread as proxy.
          sigma = if current_price > 0 && current_price < 1.0
                    Math.sqrt([current_price * (1 - current_price), 0.001].max)
                  else
                    spread && spread > 0 ? spread * 0.5 : 0.01
                  end

          volume_ratio = size_usd / [volume_24h, 1.0].max
          slippage = sigma * Math.sqrt(volume_ratio)
          slippage.clamp(0.0, 0.5)
        end

        # Depth-aware signal cost estimation. Replaces Base#estimate_signal_cost.
        #
        # Fallback chain:
        # 1. Order book walk (most accurate — uses real liquidity data)
        # 2. Square-root impact model (Kyle 1985 — uses spread + volume)
        # 3. Spread proxy (original Base behavior)
        #
        # @param size_usd [Float, nil] estimated trade size (uses allocated_capital * 5% if nil)
        # @return [Float] estimated round-trip cost as a fraction
        def estimate_signal_cost(size_usd: nil)
          size = size_usd || @allocated_capital * 0.05
          size = [size, 1.0].max # minimum $1 to avoid zero-division

          # Flat fee cost as fraction of price (per-side × 2 for round-trip)
          price = [current_price, 0.01].max
          flat_fee_cost = (venue_flat_fee * 2.0) / price

          book = @order_book_data
          has_book = book.is_a?(Hash) && ((book["asks"] || book[:asks] || []).any? || (book["bids"] || book[:bids] || []).any?)

          if has_book
            # Walk both sides for round-trip cost
            buy_impact = estimate_price_impact(side: "buy", size_usd: size, book: book)
            sell_impact = estimate_price_impact(side: "sell", size_usd: size, book: book)
            round_trip = buy_impact[:slippage_pct] + sell_impact[:slippage_pct]
            return (round_trip + flat_fee_cost).clamp(0.0, 0.50)
          end

          # Square-root impact fallback (CLOB-appropriate)
          vol = (@market_data["volume_24h"] || @market_data[:volume_24h] || 0).to_f
          if vol > 0
            impact = sqrt_price_impact(size_usd: size, current_price: current_price,
                                       volume_24h: vol, spread: spread)
            round_trip = impact * 2.0
            return (round_trip + flat_fee_cost).clamp(0.0, 0.50)
          end

          # Original spread-based fallback.
          # On zero-fee venues with limit orders, actual spread cost is determined by
          # the evaluator's price placement, not market conditions. Use a lower default.
          spread_cost = spread_pct || (venue_flat_fee > 0 ? 0.005 : 0.001)
          round_trip = spread_cost * 2.0
          (round_trip + flat_fee_cost).clamp(0.0, 0.50)
        end

        private

        def sqrt_fallback_impact(side, size_usd)
          vol = (@market_data["volume_24h"] || @market_data[:volume_24h] || 0).to_f
          slippage = if vol > 0
                       sqrt_price_impact(size_usd: size_usd, current_price: current_price,
                                         volume_24h: vol, spread: spread)
                     else
                       (spread_pct || (venue_flat_fee > 0 ? 0.005 : 0.001))
                     end

          {
            effective_price: current_price * (1.0 + (side == "buy" ? slippage : -slippage)),
            slippage_pct: slippage.round(6),
            filled_usd: size_usd,
            levels_consumed: 0
          }
        end
      end
    end
  end
end
