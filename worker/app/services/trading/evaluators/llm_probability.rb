# frozen_string_literal: true

module Trading
  module Evaluators
    # Worker-side LLM Probability evaluator.
    #
    # Mirrors Trading::Strategies::LlmProbability but runs entirely on the worker:
    # - Fetches market question from the evaluation context (no API call)
    # - Calls the AI provider directly via LlmProxyClient (no server round-trip)
    # - Returns signal hashes for the server to process into orders
    class LlmProbability < Base
      include Concerns::DynamicKelly
      include Concerns::ConvergenceExit

      register "llm_probability"

      def evaluate
        signals = []
        market_price = current_price
        @total_cost = 0.0

        min_prob = param("min_probability", 0.01)
        max_prob = param("max_probability", 0.99)
        return signals unless market_price.between?(min_prob, max_prob)

        question = @market_question
        return signals unless question

        llm_result = estimate_probability(question, market_price)
        unless llm_result
          log("#{strategy_pair}: LLM estimate returned nil (price: #{market_price})")
          return signals
        end

        edge = llm_result[:probability] - market_price
        edge_threshold = param("edge_threshold_pct", 5.0) / 100.0
        exit_edge_mult = param("exit_edge_multiplier", 0.5)
        log("#{strategy_pair}: LLM=#{(llm_result[:probability] * 100).round(1)}% mkt=#{(market_price * 100).round(1)}% edge=#{(edge * 100).round(1)}% conf=#{llm_result[:confidence].round(2)} thresh=#{(edge_threshold * 100).round(1)}%")

        # Exit check (always runs, never gated by cooldown)
        if has_open_position?
          min_hold = param("min_hold_seconds", 60)
          position = current_position
          opened_at = position && position["opened_at"] ? Time.parse(position["opened_at"]) : nil
          entry_price = (position&.dig("entry_price") || 0).to_f
          side = position&.dig("side") || "long"
          pnl_pct = entry_price > 0 ? ((market_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
          stop_loss = param("stop_loss_pct", 8.0)

          if position && opened_at && opened_at < (Time.current - min_hold) && edge.abs < edge_threshold * exit_edge_mult
            signals << build_signal(
              type: "exit",
              direction: side,
              confidence: 0.7,
              strength: 0.6,
              reasoning: "LLM edge collapsed to #{(edge * 100).round(2)}%, exiting position",
              indicators: { edge: edge, edge_pct: (edge * 100).round(2),
                            limit_order: true, limit_price: market_price.round(2) }
            )
          elsif pnl_pct <= -stop_loss
            signals << build_signal(
              type: "exit",
              direction: side,
              confidence: 0.9,
              strength: 0.9,
              reasoning: "LLM stop-loss: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit",
              indicators: { pnl_pct: pnl_pct, edge: 0 }
            )
          else
            # Convergence exit: check if remaining edge has decayed below exit cost
            if market_expiry && position
              hours_left = (market_expiry - Time.now) / 3600.0
              conv_signal = convergence_exit_check(position, hours_left)
              signals << build_signal(**conv_signal) if conv_signal
            end
          end
        end

        # Cooldown gates entry signals (bypassed in training — tick intervals are too fast)
        unless training?
          cooldown = param("cooldown_seconds", 300).to_i
          if last_tick_at && last_tick_at > (Time.current - cooldown)
            log("#{strategy_pair}: cooldown active (#{cooldown}s, last_tick: #{last_tick_at})")
            return signals
          end
        end

        # Longshot bias correction for low-probability events
        adjusted_edge = edge
        if market_price < 0.15
          adjusted_edge = edge - longshot_bias_adjustment(market_price)
        end

        # Entry signal
        max_spread = param("max_spread_pct", 5.0) / 100.0
        min_confidence = param("confidence_threshold", 0.6)

        entry_ok = adjusted_edge.abs > edge_threshold &&
                   llm_result[:confidence] >= min_confidence &&
                   !has_open_position? &&
                   (spread_pct.nil? || spread_pct <= max_spread)

        unless entry_ok
          reasons = []
          reasons << "edge #{(adjusted_edge.abs * 100).round(1)}% < #{(edge_threshold * 100).round(1)}%" unless adjusted_edge.abs > edge_threshold
          reasons << "conf #{llm_result[:confidence].round(2)} < #{min_confidence}" unless llm_result[:confidence] >= min_confidence
          reasons << "has_position" if has_open_position?
          reasons << "spread #{(spread_pct.to_f * 100).round(1)}% > #{(max_spread * 100).round(1)}%" if spread_pct && spread_pct > max_spread
          log("#{strategy_pair}: entry rejected — #{reasons.join(', ')}")
        end

        if entry_ok
          direction = adjusted_edge > 0 ? "long" : "short"

          # Use limit orders to avoid adverse spread costs.
          # For long: buy at current price (mid); for short: sell at current price.
          limit_price = market_price.round(2)

          # Dynamic Kelly sizing based on edge + historical performance
          kelly = dynamic_kelly(estimated_prob: llm_result[:probability], market_price: market_price)

          signals << build_signal(
            type: "entry",
            direction: direction,
            confidence: [llm_result[:confidence], adjusted_edge.abs / 0.10].min.clamp(0.0, 1.0),
            strength: (adjusted_edge.abs / 0.075).clamp(0.0, 1.0),
            reasoning: "LLM probability estimate: #{(llm_result[:probability] * 100).round(1)}% vs market #{(market_price * 100).round(1)}% (edge: #{(adjusted_edge * 100).round(1)}%#{market_price < 0.15 ? ', longshot-adjusted' : ''}). #{llm_result[:reasoning]}",
            indicators: {
              market_price: market_price,
              llm_probability: llm_result[:probability],
              llm_confidence: llm_result[:confidence],
              edge: adjusted_edge,
              edge_pct: (adjusted_edge * 100).round(2),
              raw_edge: edge,
              longshot_adjusted: market_price < 0.15,
              key_factors: llm_result[:key_factors],
              kelly_fraction: kelly[:kelly_fraction],
              kelly_full: kelly[:kelly_full],
              edge_after_impact: kelly[:edge_after_impact],
              kelly_blend_source: kelly[:blend_source],
              position_sizing_method: "kelly",
              limit_order: true,
              limit_price: limit_price
            }
          )
        end

        signals
      end

      private

      def estimate_probability(question, market_price)
        messages = build_messages(question, market_price)

        response = llm_complete_structured(
          messages: messages,
          schema: llm_schema,
          temperature: param("temperature", 0.3)
        )
        return nil unless response

        @total_cost += last_llm_cost

        result = response.is_a?(Hash) && response.key?(:probability) ? response : parse_structured_response(response)
        return nil unless result.is_a?(Hash) && result[:probability]

        {
          probability: result[:probability].to_f.clamp(0.01, 0.99),
          reasoning: result[:reasoning].to_s,
          confidence: result[:confidence].to_f.clamp(0.0, 1.0),
          key_factors: Array(result[:key_factors])
        }
      rescue StandardError => e
        log("Estimation failed: #{e.message}", level: :warn)
        nil
      end

      def build_messages(question, market_price)
        system_prompt = <<~PROMPT
          You are an expert superforecaster. Estimate the probability of the following prediction market question resolving YES.
          Be calibrated but do NOT anchor on the current market price. The market may be inefficient.
          Use base rates, reference classes, and update on specific evidence.
          Consider multiple perspectives and potential failure modes.
          Current market price (implied probability): #{(market_price * 100).round(1)}%
        PROMPT

        # Add price trend context if available
        if price_history.size >= 3
          recent = price_history.last(5).map { |s| (s["close"] || s[:close]).to_f }
          trend = recent.last - recent.first
          system_prompt += "\nRecent price trend: #{trend > 0 ? '+' : ''}#{(trend * 100).round(2)}% over last #{recent.size} ticks"
        end

        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          system_prompt += "\n\nRelevant patterns from past trades:\n#{tc["compound_learnings"] || tc[:compound_learnings]}" if tc["compound_learnings"] || tc[:compound_learnings]
          system_prompt += "\n\nPast trade examples:\n#{tc["experience_replays"] || tc[:experience_replays]}" if tc["experience_replays"] || tc[:experience_replays]
          system_prompt += "\n\nWarnings from past failures:\n#{tc["reflexion_warnings"] || tc[:reflexion_warnings]}" if tc["reflexion_warnings"] || tc[:reflexion_warnings]
        end

        [
          { role: "system", content: system_prompt },
          { role: "user", content: "Question: #{question}" }
        ]
      end

      def longshot_bias_adjustment(market_price)
        return 0.0 unless market_price > 0 && market_price < 0.15

        # Configurable bias factor: 1.0 = full correction (original R2 levels),
        # 0.5 = half correction (better for venues where LLM calibration is accurate),
        # 0.0 = no correction. Defaults to 0.5 per training analysis showing
        # full correction removes genuine edge on Polymarket.
        factor = param("longshot_bias_factor", 0.5)

        raw = if market_price < 0.05
                0.015
              elsif market_price < 0.10
                0.010
              else
                0.007
              end

        raw * factor
      end

      def llm_schema
        {
          type: "object",
          properties: {
            probability: { type: "number", description: "Estimated probability 0-1" },
            reasoning: { type: "string", description: "Key reasoning for estimate" },
            confidence: { type: "number", description: "Confidence in estimate 0-1" },
            key_factors: { type: "array", items: { type: "string" }, description: "Key factors considered" }
          },
          required: %w[probability reasoning confidence key_factors],
          additionalProperties: false
        }
      end
    end
  end
end
