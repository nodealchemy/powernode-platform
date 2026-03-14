# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Provides order-book-aware price impact estimation.
      #
      # Included in Base so all evaluators benefit from depth-aware cost
      # estimation via the standard `estimate_signal_cost` interface.
      #
      # Fallback chain: order book walk → LMSR model → spread proxy.
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

          return lmsr_fallback_impact(side, size_usd) if levels.empty?

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

          return lmsr_fallback_impact(side, size_usd) if total_qty <= 0

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

        # Fit an effective LMSR `b` parameter from observed spread and volume.
        #
        # In LMSR, spread ≈ 1/(2b) for equal-weight binary markets.
        # Volume scales b (higher volume → deeper book → higher b).
        #
        # @param spread [Float] current bid-ask spread (absolute, not %)
        # @param volume_24h [Float] 24-hour volume in USD
        # @return [Float] estimated LMSR b parameter
        def lmsr_effective_b(spread:, volume_24h:)
          # From LMSR theory: spread ≈ 1/(2b) → b ≈ 1/(2*spread)
          b_from_spread = spread > 0.001 ? (1.0 / (2.0 * spread)) : 100.0

          # Volume-based: CLOB markets replenish depth continuously.
          # Use sqrt(volume) to capture that a 100x volume market is ~10x deeper,
          # not 100x deeper (liquidity scales sub-linearly with volume).
          b_from_volume = volume_24h > 0 ? Math.sqrt(volume_24h) : 50.0

          # Blend: weight volume more heavily since it captures real-world
          # depth better than spread-inferred static LMSR depth.
          ((b_from_spread * 0.3) + (b_from_volume * 0.7)).clamp(1.0, 10_000.0)
        end

        # LMSR-based slippage estimate (analytical fallback when no book data).
        #
        # LMSR-based slippage estimate for binary markets.
        #
        # Uses exact LMSR cost formula: C(Δq) = b * ln(p * e^(Δq/b) + (1-p))
        # rather than the quadratic approximation (which diverges for large Δq/b).
        #
        # @param size_usd [Float] order size in USD
        # @param current_price [Float] current market price (0-1 for prediction markets)
        # @param b [Float] LMSR b parameter
        # @return [Float] estimated slippage as a fraction (0.0-1.0)
        def lmsr_price_impact(size_usd:, current_price:, b:)
          return 0.0 if b <= 0 || current_price <= 0 || current_price >= 1.0

          # Convert USD size to contract quantity
          contracts = size_usd / current_price
          return 0.0 if contracts <= 0

          p = current_price
          ratio = contracts / b

          if ratio > 20.0
            # Very large order: slippage saturates at (1-p)/p
            return [((1.0 - p) / p) * 0.5, 0.5].min
          end

          # Exact LMSR: cost = b * ln(p * e^(dq/b) + (1-p))
          cost = b * Math.log(p * Math.exp(ratio) + (1.0 - p))
          effective_price = cost / contracts
          slippage = ((effective_price - p) / p).abs
          slippage.clamp(0.0, 0.5)
        end

        # Depth-aware signal cost estimation. Replaces Base#estimate_signal_cost.
        #
        # Fallback chain:
        # 1. Order book walk (most accurate — uses real liquidity data)
        # 2. LMSR model (analytical — uses spread + volume to fit b parameter)
        # 3. Spread proxy (original Base behavior)
        #
        # @param size_usd [Float, nil] estimated trade size (uses allocated_capital * 5% if nil)
        # @return [Float] estimated round-trip cost as a fraction
        def estimate_signal_cost(size_usd: nil)
          size = size_usd || @allocated_capital * 0.05
          size = [size, 1.0].max # minimum $1 to avoid zero-division

          book = @order_book_data
          has_book = book.is_a?(Hash) && ((book["asks"] || book[:asks] || []).any? || (book["bids"] || book[:bids] || []).any?)

          if has_book
            # Walk both sides for round-trip cost
            buy_impact = estimate_price_impact(side: "buy", size_usd: size, book: book)
            sell_impact = estimate_price_impact(side: "sell", size_usd: size, book: book)
            round_trip = buy_impact[:slippage_pct] + sell_impact[:slippage_pct]
            return round_trip.clamp(0.0, 0.08)
          end

          # LMSR fallback
          sp = spread
          vol = (@market_data["volume_24h"] || @market_data[:volume_24h] || 0).to_f
          if sp && sp > 0.001 && vol > 0
            b = lmsr_effective_b(spread: sp, volume_24h: vol)
            impact = lmsr_price_impact(size_usd: size, current_price: current_price, b: b)
            round_trip = impact * 2.0
            return round_trip.clamp(0.0, 0.08)
          end

          # Original spread-based fallback
          spread_cost = spread_pct || 0.005
          round_trip = spread_cost * 2.0
          [round_trip, 0.08].min
        end

        private

        def lmsr_fallback_impact(side, size_usd)
          sp = spread
          vol = (@market_data["volume_24h"] || @market_data[:volume_24h] || 0).to_f
          if sp && sp > 0.001 && vol > 0
            b = lmsr_effective_b(spread: sp, volume_24h: vol)
            slippage = lmsr_price_impact(size_usd: size_usd, current_price: current_price, b: b)
          else
            slippage = (spread_pct || 0.005)
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
