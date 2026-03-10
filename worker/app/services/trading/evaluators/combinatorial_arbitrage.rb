# frozen_string_literal: true

module Trading
  module Evaluators
    class CombinatorialArbitrage < Base
      register "combinatorial_arbitrage"

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price&.between?(0.01, 0.99)
        return signals unless @data_fetcher

        @total_cost = 0.0

        # Respect scan interval cooldown
        scan_interval = param("scan_interval_seconds", 180)
        last_scan = strategy_config["last_arb_scan_at"]
        if last_scan && Time.parse(last_scan) > (Time.current - scan_interval)
          return signals unless has_open_position?
        end

        # Find related markets via server (event-ticker + embedding)
        related = @data_fetcher.market_graph_related(
          pair: strategy_pair,
          account_id: @strategy_data["account_id"],
          agent_id: @agent_id,
          similarity_threshold: param("similarity_threshold", 0.55)
        )

        event_count = related.count { |r| r["source"] == "event_ticker" }
        embedding_count = related.count { |r| r["source"] == "embedding" }
        log("#{strategy_pair}: found #{related.size} related markets (event: #{event_count}, embedding: #{embedding_count})")

        return check_exit_conditions(signals) if related.empty?

        min_spread = param("min_arb_spread_pct", 3.0) / 100.0
        scan_limit = param("max_markets_to_scan", param("use_llm_validation", true) ? 5 : 50).to_i

        # Filter invalid comparisons
        base_ticker = strategy_pair.sub(%r{/(YES|NO)\z}, "")
        base_outcome = strategy_pair[%r{(YES|NO)\z}]
        filtered = related.reject do |r|
          rel_pair = r["pair"] || r[:pair]
          rel_ticker = rel_pair.sub(%r{/(YES|NO)\z}, "")
          rel_outcome = rel_pair[%r{(YES|NO)\z}]
          next true if rel_ticker == base_ticker
          next true if (r["source"] || r[:source]) == "event_ticker" && rel_outcome != base_outcome
          false
        end

        filtered.first(scan_limit).each do |rel|
          rel_pair = rel["pair"] || rel[:pair]
          rel_price = fetch_pair_price(rel_pair)
          next unless rel_price

          if param("use_llm_validation", true)
            constraint = check_logical_constraint(strategy_pair, rel_pair, market_price, rel_price)
            next unless constraint.is_a?(Hash) && constraint[:violation]

            max_spread_pct = param("max_violation_spread_pct", 15.0) / 100.0
            spread = case constraint[:direction]
                     when "a_implies_b" then market_price - rel_price
                     when "b_implies_a" then rel_price - market_price
                     else (constraint[:violation_spread] || 0).to_f
                     end

            next if spread <= 0
            next if spread > max_spread_pct

            if spread > min_spread && (constraint[:confidence] || 0) >= param("confidence_threshold", 0.7)
              direction = determine_arb_direction(constraint, market_price, rel_price)
              counter_side = direction == "long" ? "sell" : "buy"
              signals << build_signal(
                type: "entry", direction: direction,
                confidence: constraint[:confidence].to_f.clamp(0.0, 1.0),
                strength: (spread / 0.10).clamp(0.0, 1.0),
                reasoning: "Combinatorial arbitrage: #{constraint[:reasoning]}. Spread: #{(spread * 100).round(2)}%",
                indicators: {
                  related_pair: rel_pair, similarity: (rel["similarity"] || rel[:similarity]).to_f,
                  violation_spread: spread, direction: constraint[:direction],
                  market_price: market_price, related_price: rel_price, edge: spread,
                  counter_leg: { pair: rel_pair, side: counter_side, price: rel_price },
                  multi_leg: param("use_multi_leg", false),
                  legs: [
                    { pair: strategy_pair, side: direction == "long" ? "buy" : "sell" },
                    { pair: rel_pair, side: counter_side }
                  ]
                }
              )
            end
          else
            # Heuristic mode without LLM
            spread = (market_price - rel_price).abs
            if spread > min_spread
              direction = market_price < rel_price ? "long" : "short"
              signals << build_signal(
                type: "entry", direction: direction,
                confidence: ((rel["similarity"] || rel[:similarity]).to_f * 0.8).clamp(0.0, 1.0),
                strength: (spread / 0.10).clamp(0.0, 1.0),
                reasoning: "Heuristic arb: #{strategy_pair} at #{(market_price * 100).round(1)}% vs #{rel_pair} at #{(rel_price * 100).round(1)}%",
                indicators: { related_pair: rel_pair, similarity: (rel["similarity"] || rel[:similarity]).to_f, spread: spread }
              )
            end
          end
        end

        # Update scan timestamp
        @data_fetcher.update_strategy_config(
          strategy_id: strategy_id,
          config_updates: { "last_arb_scan_at" => Time.current.iso8601 }
        )

        check_exit_conditions(signals)
        signals
      rescue StandardError => e
        log("Evaluation failed: #{e.message}", level: :warn)
        []
      end

      private

      def fetch_pair_price(pair)
        venue_id = @strategy_data["venue_id"]
        return nil unless venue_id && @data_fetcher
        data = @data_fetcher.fetch_ticker(pair: pair, venue_id: venue_id)
        data && (data["last_price"] || data[:last_price])&.to_f
      rescue StandardError
        nil
      end

      def check_logical_constraint(pair_a, pair_b, price_a, price_b)
        return nil unless @llm_client && @provider_config

        question_a = @market_question || pair_a
        question_b = @pair_registry.dig(pair_b, "question") || @pair_registry.dig(pair_b, :question) || pair_b

        tc_prompt = ""
        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          tc_prompt = "\n\nPatterns: #{tc["compound_learnings"] || tc[:compound_learnings]}" if tc["compound_learnings"] || tc[:compound_learnings]
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: "You are a logic expert analyzing prediction market relationships. Determine if there is a logical implication between two markets, and if so, whether their prices violate that implication.#{tc_prompt}" },
            { role: "user", content: "Market A: #{question_a} (price: #{(price_a * 100).round(1)}%)\nMarket B: #{question_b} (price: #{(price_b * 100).round(1)}%)\n\nIs there a logical implication (A implies B or B implies A)? If so, do the current prices violate it?" }
          ],
          schema: {
            type: "object",
            properties: {
              violation: { type: "boolean", description: "True if prices violate logical constraint" },
              direction: { type: "string", enum: %w[a_implies_b b_implies_a none], description: "Direction of implication" },
              violation_spread: { type: "number", description: "Price discrepancy magnitude" },
              confidence: { type: "number", description: "Confidence in the constraint 0-1" },
              reasoning: { type: "string", description: "Explanation of the logical relationship" }
            },
            required: %w[violation direction confidence reasoning],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost
        response
      rescue StandardError => e
        log("Constraint check failed: #{e.message}", level: :warn)
        nil
      end

      def determine_arb_direction(constraint, price_a, price_b)
        case constraint[:direction]
        when "a_implies_b" then price_a < price_b ? "long" : "short"
        when "b_implies_a" then price_a > price_b ? "long" : "short"
        else price_a < 0.5 ? "long" : "short"
        end
      end

      def check_exit_conditions(signals)
        return signals unless has_open_position?
        position = current_position
        return signals unless position

        original_spread = (last_entry_indicators["violation_spread"] || last_entry_indicators["spread"] || 0).to_f
        opened_at = position["opened_at"] ? Time.parse(position["opened_at"]) : nil

        if original_spread > 0 && opened_at && opened_at < (Time.current - 60)
          entry_price = position["entry_price"].to_f
          quantity = position["quantity"].to_f
          pnl_pct = entry_price > 0 ? position["unrealized_pnl_usd"].to_f / [entry_price * quantity, 0.01].max * 100 : 0
          min_arb = param("min_arb_spread_pct", 3.0)

          if pnl_pct > min_arb * 0.5 || pnl_pct < -min_arb
            signals << build_signal(
              type: "exit", direction: position["side"],
              confidence: 0.7, strength: 0.6,
              reasoning: "Arbitrage spread target reached or stop hit (P&L: #{pnl_pct.round(2)}%)",
              indicators: { pnl_pct: pnl_pct }
            )
          end
        end
        signals
      end
    end
  end
end
