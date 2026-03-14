# frozen_string_literal: true

module Trading
  module Evaluators
    class Momentum < Base
      register "momentum"

      def evaluate
        signals = []
        lookback = param("lookback_periods", 20)
        entry_threshold = param("entry_threshold", 0.02)
        exit_threshold = param("exit_threshold", -0.01)

        # E1: Whipsaw circuit breaker — halt entries after consecutive stop-outs
        # on the same pair. Data: 30/30 losses on one market = $456 lost to whipsaw.
        @whipsaw_tracker ||= {}
        pair_key = strategy_pair
        tracker = @whipsaw_tracker[pair_key] ||= { consecutive_losses: 0, last_loss_at: nil }
        max_consecutive = param("whipsaw_max_consecutive_losses", 3)
        cooldown_after_whipsaw = param("whipsaw_cooldown_seconds", 900)

        if !has_open_position? && tracker[:consecutive_losses] >= max_consecutive
          if tracker[:last_loss_at] && (Time.now - tracker[:last_loss_at]) < cooldown_after_whipsaw
            return signals
          else
            tracker[:consecutive_losses] = 0 # cooldown expired, reset
          end
        end

        return signals if price_history.size < lookback

        prices = price_history.last(lookback).map { |s| (s["close"] || s[:close]).to_f }
        return signals if prices.any?(&:zero?)

        # Volatility gate: skip low-volatility markets where momentum signals are noise.
        # For prediction market prices (0.01-0.99 range), use coefficient of variation
        # (relative volatility) instead of absolute std_dev, since PM prices have
        # inherently small absolute volatility.
        mean_price = prices.sum / prices.size
        price_std = Math.sqrt(prices.map { |p| (p - mean_price)**2 }.sum / prices.size)
        min_vol = param("min_volatility", 0.005)
        is_pm_price = mean_price.between?(0.01, 0.99)
        effective_vol = if is_pm_price && mean_price > 0
                          price_std / mean_price # coefficient of variation
                        else
                          price_std
                        end
        if effective_vol < min_vol && !has_open_position?
          return signals
        end

        # Price boundary check: reject extreme-probability markets where percentage
        # returns are dominated by noise. At $0.95, a 1-cent move = 1.05% log return
        # which easily triggers entry thresholds but has no real edge.
        price_floor = param("price_floor", 0.10)
        price_ceil = param("price_ceil", 0.90)
        if is_pm_price && (mean_price < price_floor || mean_price > price_ceil)
          return has_open_position? ? check_pm_exit(signals) : signals
        end

        # Log returns with median filtering for spike resistance
        # For PM prices (0-1 range), use wider filter to avoid killing all signals
        log_returns = prices.each_cons(2).map { |a, b| Math.log(b / a) }
        sorted_returns = log_returns.sort
        median_return = sorted_returns[sorted_returns.size / 2] || 0
        filter_width = current_price.between?(0.01, 0.99) ? 0.05 : (median_return.abs * 3 + 0.01)
        momentum = log_returns.select { |r| (r - median_return).abs < filter_width }.sum

        volumes = price_history.last(lookback).map { |s| (s["volume"] || s[:volume] || 0).to_f }
        avg_volume = volumes.sum / volumes.size
        volume_ratio = (volumes.last || 0).to_f / [avg_volume, 0.001].max

        volume_boost = if volume_ratio > 1.5 then 0.15
                       elsif volume_ratio > 1.0 then 0.05
                       else -0.10
                       end

        # Minimum edge filter: don't enter if momentum edge is too small vs fees.
        # On Kalshi, round-trip cost ~$0.02/contract ($0.01 each side). For a $0.50
        # contract that's 4% round-trip; for $0.10 it's 20%. Scale threshold accordingly.
        min_edge_pct = param("min_edge_pct", 3.0) / 100.0
        fee_adjusted_threshold = [entry_threshold, min_edge_pct].max

        if !has_open_position? && momentum > fee_adjusted_threshold
          base_confidence = (momentum / fee_adjusted_threshold * 0.5).clamp(0.3, 0.85)
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: (base_confidence + volume_boost).clamp(0.3, 0.95),
            strength: momentum.abs.clamp(0.0, 1.0),
            reasoning: "Bullish momentum #{(momentum * 100).round(2)}% over #{lookback} periods exceeds threshold #{(entry_threshold * 100).round(2)}%",
            indicators: { momentum: momentum, volume_ratio: volume_ratio, volume_boost: volume_boost, lookback: lookback,
                          limit_order: true, limit_price: current_price.round(4), edge: momentum.abs }
          )
        elsif !has_open_position? && momentum < -fee_adjusted_threshold
          base_confidence = (momentum.abs / fee_adjusted_threshold * 0.5).clamp(0.3, 0.85)
          signals << build_signal(
            type: "entry", direction: "short",
            confidence: (base_confidence + volume_boost).clamp(0.3, 0.95),
            strength: momentum.abs.clamp(0.0, 1.0),
            reasoning: "Bearish momentum #{(momentum * 100).round(2)}% over #{lookback} periods",
            indicators: { momentum: momentum, volume_ratio: volume_ratio, lookback: lookback,
                          limit_order: true, limit_price: current_price.round(4), edge: momentum.abs }
          )
        elsif has_open_position?
          position = current_position
          entry_price = (position&.dig("entry_price") || 0).to_f
          pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100) : 0

          stop_loss = param("stop_loss_pct", 5.0)
          take_profit = param("take_profit_pct", 5.0)

          if momentum < exit_threshold
            signals << build_signal(
              type: "exit", direction: position&.dig("side") || "long",
              confidence: (exit_threshold.abs / [momentum.abs, 0.001].max).clamp(0.5, 0.95),
              strength: momentum.abs.clamp(0.0, 1.0),
              reasoning: "Momentum reversed to #{(momentum * 100).round(2)}%, below exit threshold #{(exit_threshold * 100).round(2)}%",
              indicators: { momentum: momentum, edge: momentum.abs }
            )
          elsif pnl_pct <= -stop_loss
            # E1: Track stop-loss as consecutive loss for whipsaw detection
            tracker[:consecutive_losses] += 1
            tracker[:last_loss_at] = Time.now
            signals << build_signal(
              type: "exit", direction: position&.dig("side") || "long",
              confidence: 0.9, strength: 0.9,
              reasoning: "Stop-loss triggered: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit (whipsaw count: #{tracker[:consecutive_losses]}/#{max_consecutive})",
              indicators: { pnl_pct: pnl_pct, edge: 0, whipsaw_count: tracker[:consecutive_losses] }
            )
          elsif pnl_pct >= take_profit
            # E1: Reset whipsaw counter on profitable exit
            tracker[:consecutive_losses] = 0
            signals << build_signal(
              type: "exit", direction: position&.dig("side") || "long",
              confidence: 0.85, strength: 0.8,
              reasoning: "Take-profit triggered: PnL #{pnl_pct.round(2)}% exceeds +#{take_profit}% target",
              indicators: { pnl_pct: pnl_pct, edge: 0 }
            )
          end
        end

        signals
      end

      private

      # Exit check for positions stuck in extreme-probability zones
      def check_pm_exit(signals)
        return signals unless has_open_position?
        position = current_position
        return signals unless position

        entry_price = (position.dig("entry_price") || 0).to_f
        pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100) : 0
        stop_loss = param("stop_loss_pct", 5.0)

        if pnl_pct <= -stop_loss || pnl_pct >= param("take_profit_pct", 5.0)
          signals << build_signal(
            type: "exit", direction: position.dig("side") || "long",
            confidence: 0.9, strength: 0.9,
            reasoning: "Extreme probability zone exit: PnL #{pnl_pct.round(2)}%",
            indicators: { pnl_pct: pnl_pct, edge: 0 }
          )
        end
        signals
      end
    end
  end
end
