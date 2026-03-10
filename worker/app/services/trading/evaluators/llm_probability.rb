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
        return signals unless llm_result

        edge = llm_result[:probability] - market_price
        edge_threshold = param("edge_threshold_pct", 5.0) / 100.0
        exit_edge_mult = param("exit_edge_multiplier", 0.5)

        # Exit check (always runs, never gated by cooldown)
        if has_open_position?
          min_hold = param("min_hold_seconds", 60)
          position = current_position
          opened_at = position && position["opened_at"] ? Time.parse(position["opened_at"]) : nil
          if position && opened_at && opened_at < (Time.current - min_hold) && edge.abs < edge_threshold * exit_edge_mult
            signals << build_signal(
              type: "exit",
              direction: position["side"],
              confidence: 0.7,
              strength: 0.6,
              reasoning: "LLM edge collapsed to #{(edge * 100).round(2)}%, exiting position",
              indicators: { edge: edge, edge_pct: (edge * 100).round(2) }
            )
          end
        end

        # Cooldown gates entry signals
        if last_tick_at && last_tick_at > (Time.current - param("cooldown_seconds", 300).to_i)
          return signals
        end

        # Longshot bias correction for low-probability events
        adjusted_edge = edge
        if market_price < 0.15
          adjusted_edge = edge - longshot_bias_adjustment(market_price)
        end

        # Entry signal
        max_spread = param("max_spread_pct", 5.0) / 100.0
        min_confidence = param("confidence_threshold", 0.6)

        if adjusted_edge.abs > edge_threshold &&
           llm_result[:confidence] >= min_confidence &&
           !has_open_position? &&
           (spread_pct.nil? || spread_pct <= max_spread)

          direction = adjusted_edge > 0 ? "long" : "short"
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
              key_factors: llm_result[:key_factors]
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
          Be calibrated: use base rates, reference classes, and update on specific evidence.
          Consider multiple perspectives and potential failure modes.
          Current market price (implied probability): #{(market_price * 100).round(1)}%
        PROMPT

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

        if market_price < 0.05
          0.01
        elsif market_price < 0.10
          0.0075
        else
          0.005
        end
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
