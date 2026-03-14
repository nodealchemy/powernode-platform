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

        # Check cached constraint pairs first (no LLM cost)
        cached_constraints = strategy_config["known_constraints"] || []
        cached_constraints.each do |cached|
          rel_pair = cached["pair"]
          rel_price = fetch_pair_price(rel_pair)
          next unless rel_price

          spread = case cached["direction"]
                   when "a_implies_b" then market_price - rel_price
                   when "b_implies_a" then rel_price - market_price
                   else 0
                   end
          min_spread = param("min_arb_spread_pct", 1.5) / 100.0
          next if spread <= 0
          next if spread < min_spread

          direction = determine_arb_direction(cached.symbolize_keys, market_price, rel_price)
          counter_side = direction == "long" ? "sell" : "buy"
          signals << build_signal(
            type: "entry", direction: direction,
            confidence: [cached["confidence"].to_f, 0.95].min,
            strength: (spread / 0.10).clamp(0.0, 1.0),
            reasoning: "Cached constraint: #{cached['reasoning']&.truncate(100)}. Spread: #{(spread * 100).round(2)}%",
            indicators: {
              related_pair: rel_pair, violation_spread: spread, direction: cached["direction"],
              market_price: market_price, related_price: rel_price, edge: spread,
              counter_leg: { pair: rel_pair, side: counter_side, price: rel_price },
              cached: true,
              legs: [
                { pair: strategy_pair, side: direction == "long" ? "buy" : "sell" },
                { pair: rel_pair, side: counter_side }
              ]
            }
          )
        end

        # Completeness constraint (Dutch book) — group-level check, no LLM needed.
        # If mutually exclusive outcomes sum > 100%, the group is overpriced.
        # Cache result per event_ticker per tick: tiered events always fail (>150%)
        # so skip redundant checks for the same event.
        my_event = @pair_registry.dig(strategy_pair, "event_ticker") ||
                   @pair_registry.dig(strategy_pair, :event_ticker)
        completeness_cache_key = "completeness:#{my_event}" if my_event

        skip_completeness = completeness_cache_key &&
                            @graph_cache&.key?(completeness_cache_key) &&
                            @graph_cache[completeness_cache_key] == :skip_tiered

        unless skip_completeness
          completeness_signals = check_completeness_constraint(market_price)
          signals.concat(completeness_signals)
        end

        # Respect scan interval cooldown (for the expensive pairwise LLM scan only)
        scan_interval = param("scan_interval_seconds", 180)
        last_scan = strategy_config["last_arb_scan_at"]
        if last_scan && Time.parse(last_scan) > (Time.current - scan_interval)
          return signals unless has_open_position?
        end

        # Find related markets via server (event-ticker + embedding).
        # Graph cache deduplicates by base ticker — YES/NO variants return identical results.
        graph_cache_key = strategy_pair.sub(%r{/(YES|NO)\z}, "")
        related = if @graph_cache&.key?(graph_cache_key)
                    @graph_cache[graph_cache_key]
                  else
                    result = @data_fetcher.market_graph_related(
                      pair: strategy_pair,
                      account_id: @strategy_data["account_id"],
                      agent_id: @agent_id,
                      similarity_threshold: param("similarity_threshold", 0.55)
                    )
                    @graph_cache[graph_cache_key] = result if @graph_cache
                    result
                  end

        event_count = related.count { |r| r["source"] == "event_ticker" }
        embedding_count = related.count { |r| r["source"] == "embedding" }
        log("#{strategy_pair}: found #{related.size} related markets (event: #{event_count}, embedding: #{embedding_count})")

        # Fallback to pair_registry when graph/embedding returns nothing
        if related.empty?
          related = find_related_from_pair_registry
          log("#{strategy_pair}: pair_registry fallback found #{related.size} candidates") if related.any?
        end

        return check_exit_conditions(signals) if related.empty?

        min_spread = param("min_arb_spread_pct", 3.0) / 100.0
        scan_limit = param("max_markets_to_scan", param("use_llm_validation", true) ? 5 : 50).to_i

        # Filter invalid comparisons
        base_ticker = strategy_pair.sub(%r{/(YES|NO)\z}, "")
        base_outcome = strategy_pair[%r{(YES|NO)\z}]
        venue_prefix = base_ticker[/\A(KL_|PM)/]
        filtered = related.reject do |r|
          rel_pair = r["pair"] || r[:pair]
          rel_ticker = rel_pair.sub(%r{/(YES|NO)\z}, "")
          rel_outcome = rel_pair[%r{(YES|NO)\z}]
          next true if rel_ticker == base_ticker
          # Skip cross-venue pairs (e.g., PM pairs when trading on Kalshi)
          next true if venue_prefix && !rel_ticker.start_with?(venue_prefix)
          false
        end

        # Pre-fetch prices and sort by divergence (largest first).
        # This prioritizes markets most likely to have exploitable constraint violations,
        # ensuring the scan_limit budget is spent on the best candidates.
        candidates = filtered.filter_map do |rel|
          rel_pair = rel["pair"] || rel[:pair]
          rel_price = fetch_pair_price(rel_pair)
          next nil unless rel_price
          rel.merge("_price" => rel_price, "_divergence" => (market_price - rel_price).abs)
        end
        candidates.sort_by! { |c| -c["_divergence"] }

        # Filter out pairs previously confirmed as "no implication" (cross-tick cache)
        negative_cache = load_negative_cache

        # Merge tick-scoped shared negatives from sibling (YES/NO share base ticker)
        tick_negatives_key = "negatives:#{graph_cache_key}"
        if @graph_cache&.key?(tick_negatives_key)
          negative_cache.merge(@graph_cache[tick_negatives_key])
        end

        if negative_cache.any?
          before = candidates.size
          candidates.reject! { |c| negative_cache.include?(c["pair"] || c[:pair]) }
          skipped = before - candidates.size
          log("#{strategy_pair}: negative cache skipped #{skipped} pairs") if skipped > 0
        end

        # Adaptive expansion: if negative cache thinned the pool below scan_limit,
        # widen the search radius to find genuinely new candidates
        min_pool_size = scan_limit * 2
        if candidates.size < min_pool_size
          expanded_threshold = param("similarity_threshold", 0.55) * param("expansion_threshold_factor", 0.6)
          expanded_cache_key = "#{graph_cache_key}__expanded"
          expanded = if @graph_cache&.key?(expanded_cache_key)
                       @graph_cache[expanded_cache_key]
                     else
                       result = @data_fetcher.market_graph_related(
                         pair: strategy_pair,
                         account_id: @strategy_data["account_id"],
                         agent_id: @agent_id,
                         similarity_threshold: expanded_threshold
                       )
                       @graph_cache[expanded_cache_key] = result if @graph_cache
                       result
                     end

          # Filter: remove already-seen pairs and negative-cached pairs
          seen_pairs = candidates.map { |c| c["pair"] || c[:pair] }.to_set
          base_ticker = strategy_pair.sub(%r{/(YES|NO)\z}, "")

          new_candidates = expanded.filter_map do |rel|
            rel_pair = rel["pair"] || rel[:pair]
            next if seen_pairs.include?(rel_pair)
            next if negative_cache.include?(rel_pair)
            rel_ticker = rel_pair.sub(%r{/(YES|NO)\z}, "")
            next if rel_ticker == base_ticker
            next if venue_prefix && !rel_ticker.start_with?(venue_prefix)

            rel_price = fetch_pair_price(rel_pair)
            next unless rel_price
            rel.merge("_price" => rel_price, "_divergence" => (market_price - rel_price).abs, "_expanded" => true)
          end

          if new_candidates.any?
            candidates.concat(new_candidates)
            candidates.sort_by! { |c| -c["_divergence"] }
            log("#{strategy_pair}: expanded search found #{new_candidates.size} additional candidates (threshold: #{expanded_threshold.round(2)})")
          end
        end

        pending_negative_pairs = []
        pending_positive_constraints = []
        llm_candidates = []

        candidates.first(scan_limit).each do |rel|
          rel_pair = rel["pair"] || rel[:pair]
          rel_price = rel["_price"]

          # Math-based constraint: if two YES markets from same event sum > 1.0, pure arbitrage.
          base_is_yes = strategy_pair.end_with?("/YES")
          rel_is_yes = rel_pair.to_s.end_with?("/YES")

          # Math-arb: only valid for MUTUALLY EXCLUSIVE outcomes (same contract, different outcomes).
          mutually_exclusive = base_is_yes && rel_is_yes && same_contract_different_outcome?(strategy_pair, rel_pair)
          if base_is_yes && rel_is_yes && !mutually_exclusive
            log("#{strategy_pair} vs #{rel_pair}: skipping math-arb (not mutually exclusive)")
          end

          if mutually_exclusive
            math_spread = market_price + rel_price - 1.0
            slippage = param("slippage_pct", 2.0) / 100.0
            net_spread = math_spread - slippage
            if net_spread > min_spread
              direction = market_price < rel_price ? "short" : "long"
              counter_side = direction == "long" ? "sell" : "buy"
              signals << build_signal(
                type: "entry", direction: direction,
                confidence: [net_spread / 0.10 + 0.4, 0.95].min,
                strength: (net_spread / 0.10).clamp(0.0, 1.0),
                reasoning: "Math arbitrage: #{strategy_pair} (#{(market_price * 100).round(1)}%) + #{rel_pair} (#{(rel_price * 100).round(1)}%) = #{((market_price + rel_price) * 100).round(1)}% > 100% (net after #{(slippage * 100).round(1)}% slippage: #{(net_spread * 100).round(1)}%)",
                indicators: {
                  related_pair: rel_pair, spread: math_spread, edge: net_spread, slippage: slippage,
                  market_price: market_price, related_price: rel_price,
                  counter_leg: { pair: rel_pair, side: counter_side, price: rel_price },
                  math_arb: true,
                  legs: [
                    { pair: strategy_pair, side: direction == "long" ? "buy" : "sell" },
                    { pair: rel_pair, side: counter_side }
                  ]
                }
              )
            end
            # Skip LLM for mutually exclusive pairs — handled by completeness check
            log("#{strategy_pair} vs #{rel_pair}: skipping LLM (mutually exclusive, handled by completeness check)")
            next
          end

          # Accumulate for batch LLM check
          llm_candidates << rel if param("use_llm_validation", true)
        end

        # Single batch LLM call for all remaining candidates (cached by base ticker for YES/NO dedup)
        if llm_candidates.any?
          constraint_cache_key = "constraints:#{graph_cache_key}"
          constraint_results = if @graph_cache&.key?(constraint_cache_key)
                                 log("#{strategy_pair}: reusing cached constraint results from sibling")
                                 @graph_cache[constraint_cache_key]
                               else
                                 results = batch_check_constraints(llm_candidates, market_price)
                                 @graph_cache[constraint_cache_key] = results if @graph_cache
                                 results
                               end

          llm_candidates.each do |rel|
            rel_pair = rel["pair"] || rel[:pair]
            rel_price = rel["_price"]
            constraint = constraint_results[rel_pair]

            # Skip pairs with no result (LLM client unavailable or batch parse error)
            next unless constraint.is_a?(Hash)

            unless constraint[:has_implication]
              # LLM confirmed no implication — cache for future ticks and share with sibling
              pending_negative_pairs << rel_pair
              next
            end

            next unless constraint[:violation]

            max_spread_pct = param("max_violation_spread_pct", 15.0) / 100.0
            spread = case constraint[:direction]
                     when "a_implies_b" then market_price - rel_price
                     when "b_implies_a" then rel_price - market_price
                     else (constraint[:violation_spread] || 0).to_f
                     end

            next if spread <= 0
            next if spread > max_spread_pct

            if spread > min_spread && (constraint[:confidence] || 0) >= param("confidence_threshold", 0.5)
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

              # Accumulate positive constraint for batch config write
              unless (strategy_config["known_constraints"] || []).any? { |c| c["pair"] == rel_pair }
                pending_positive_constraints << {
                  "pair" => rel_pair, "direction" => constraint[:direction],
                  "confidence" => constraint[:confidence], "reasoning" => constraint[:reasoning],
                  "discovered_at" => Time.current.iso8601
                }
              end
            end
          end
        end

        # Consolidated config write (single HTTP call instead of N+1)
        config_updates = { "last_arb_scan_at" => Time.current.iso8601 }

        if pending_negative_pairs.any?
          # Share negatives with sibling strategies within this tick via graph_cache
          if @graph_cache
            tick_negatives_key = "negatives:#{graph_cache_key}"
            existing_tick_set = @graph_cache[tick_negatives_key] || Set.new
            @graph_cache[tick_negatives_key] = existing_tick_set | pending_negative_pairs.to_set
          end

          existing = strategy_config["checked_no_implication"] || []
          existing_set = existing.map { |e| e["pair"] }.to_set
          new_entries = pending_negative_pairs.uniq
            .reject { |p| existing_set.include?(p) }
            .map { |p| { "pair" => p, "checked_at" => Time.current.iso8601 } }
          max_entries = param("negative_cache_max_entries", 100)
          config_updates["checked_no_implication"] = (existing + new_entries).last(max_entries)
        end

        if pending_positive_constraints.any?
          existing = strategy_config["known_constraints"] || []
          config_updates["known_constraints"] = (existing + pending_positive_constraints).last(20)
        end

        @data_fetcher.update_strategy_config(
          strategy_id: strategy_id,
          config_updates: config_updates
        )

        check_exit_conditions(signals)
        signals
      rescue StandardError => e
        log("Evaluation failed: #{e.message}", level: :warn)
        []
      end

      private

      # Dutch book check: for N mutually exclusive outcomes, SUM(YES prices) must = 100%.
      # A subset summing > 100% definitively proves overpricing. < 100% is inconclusive
      # (missing candidates may fill the gap) unless complete_outcome_set is flagged.
      def check_completeness_constraint(market_price)
        signals = []
        event_groups = group_by_event
        return signals if event_groups.empty?

        my_event = @pair_registry.dig(strategy_pair, "event_ticker") ||
                   @pair_registry.dig(strategy_pair, :event_ticker)
        return signals unless my_event

        group = event_groups[my_event]
        return signals unless group

        # Deduplicate to unique contracts (prefer YES over NO for same ticker)
        contracts = {}
        group.each do |pair, info|
          ticker = pair.sub(%r{/(YES|NO)\z}, "")
          outcome = pair[%r{(YES|NO)\z}]
          existing = contracts[ticker]
          if existing.nil? || outcome == "YES"
            contracts[ticker] = { pair: pair, outcome: outcome, info: info }
          end
        end

        return signals if contracts.size < 3

        # Fetch implied YES price for each contract
        my_ticker = strategy_pair.sub(%r{/(YES|NO)\z}, "")
        implied_yes = {}

        contracts.each do |ticker, entry|
          price = if ticker == my_ticker
                    market_price
                  else
                    fetch_pair_price(entry[:pair])
                  end
          next unless price

          implied_yes[ticker] = entry[:outcome] == "NO" ? 1.0 - price : price
        end

        return signals if implied_yes.size < 3

        total_sum = implied_yes.values.sum
        excess = total_sum - 1.0

        # Sanity check: if total_sum > 150%, outcomes are likely NOT mutually exclusive
        # (e.g., tiered date contracts "before Q1 2026", "before Q2 2026" where multiple
        # can resolve YES simultaneously). Dutch book only applies to exclusive outcomes.
        if total_sum > param("max_completeness_sum", 1.5)
          log("#{strategy_pair}: completeness sum #{(total_sum * 100).round(1)}% exceeds 150% — " \
              "outcomes likely NOT mutually exclusive (tiered/nested event), skipping")
          # Cache as :skip_tiered so sibling strategies skip this check entirely
          if @graph_cache && my_event
            @graph_cache["completeness:#{my_event}"] = :skip_tiered
          end
          return signals
        end

        slippage = param("slippage_pct", 2.0) / 100.0
        min_edge = param("min_completeness_edge_pct", 2.0) / 100.0
        my_implied_yes = implied_yes[my_ticker]
        return signals unless my_implied_yes

        my_is_no = strategy_pair.end_with?("/NO")

        log("#{strategy_pair}: completeness — #{implied_yes.size} outcomes sum=#{(total_sum * 100).round(1)}%, " \
            "excess=#{(excess * 100).round(1)}%, my_yes=#{(my_implied_yes * 100).round(1)}%")

        if excess > 0
          # Per-leg edge: this contract's share of the total overpricing
          per_leg_edge = my_implied_yes * excess / total_sum
          net_edge = per_leg_edge - slippage

          if net_edge > min_edge
            direction = my_is_no ? "long" : "short"
            signals << build_signal(
              type: "entry", direction: direction,
              confidence: [(net_edge / 0.10 + 0.4), 0.90].min,
              strength: (net_edge / 0.05).clamp(0.0, 1.0),
              reasoning: "Dutch book: #{implied_yes.size} exclusive outcomes sum to " \
                         "#{(total_sum * 100).round(1)}% (>100%). Per-leg edge: #{(per_leg_edge * 100).round(1)}%, " \
                         "net after slippage: #{(net_edge * 100).round(1)}%",
              indicators: {
                completeness_sum: total_sum, excess: excess, per_leg_edge: per_leg_edge,
                n_outcomes: implied_yes.size, edge: net_edge,
                market_price: market_price, my_implied_yes: my_implied_yes,
                dutch_book: true,
                outcome_prices: implied_yes.transform_values { |v| v.round(4) }
              }
            )
          elsif excess > min_edge
            # Total excess is meaningful but per-leg edge is thin after slippage.
            # Log for diagnostics but don't signal (not profitable for one leg).
            log("#{strategy_pair}: Dutch book excess #{(excess * 100).round(1)}% but per-leg net " \
                "#{(net_edge * 100).round(1)}% below threshold (slippage #{(slippage * 100).round(1)}%)")
          end
        end

        # Underpricing: only valid if we know we have ALL outcomes for this event
        if excess < 0 && param("complete_outcome_set", false)
          deficit = -excess
          per_leg_edge = my_implied_yes * deficit / (1.0 - deficit)
          net_edge = per_leg_edge - slippage

          if net_edge > min_edge
            direction = my_is_no ? "short" : "long"
            signals << build_signal(
              type: "entry", direction: direction,
              confidence: [(net_edge / 0.10 + 0.3), 0.85].min,
              strength: (net_edge / 0.05).clamp(0.0, 1.0),
              reasoning: "Reverse Dutch book: #{implied_yes.size} outcomes sum to " \
                         "#{(total_sum * 100).round(1)}% (<100%). Net edge: #{(net_edge * 100).round(1)}%",
              indicators: {
                completeness_sum: total_sum, deficit: deficit, per_leg_edge: per_leg_edge,
                n_outcomes: implied_yes.size, edge: net_edge,
                market_price: market_price, my_implied_yes: my_implied_yes,
                dutch_book: true, reverse: true,
                outcome_prices: implied_yes.transform_values { |v| v.round(4) }
              }
            )
          end
        end

        # Relative value: even when group sums to ~100%, detect individual outlier mispricing.
        # Only fire when we have enough candidates to compute a meaningful average.
        if excess.abs < min_edge && implied_yes.size >= 5
          avg_price = total_sum / implied_yes.size
          deviation = (my_implied_yes - avg_price).abs
          multiplier = param("relative_value_multiplier", 2.0)

          if deviation > avg_price * multiplier && deviation > slippage
            direction = if my_implied_yes > avg_price
                         my_is_no ? "long" : "short"
                        else
                         my_is_no ? "short" : "long"
                        end
            edge_est = deviation * 0.3 # Conservative: capture ~30% of deviation
            signals << build_signal(
              type: "entry", direction: direction,
              confidence: 0.45,
              strength: (edge_est / 0.05).clamp(0.0, 0.6),
              reasoning: "Relative value: #{(my_implied_yes * 100).round(1)}% vs group avg " \
                         "#{(avg_price * 100).round(1)}% (#{implied_yes.size} candidates, " \
                         "#{(deviation / avg_price * 100).round(0)}% deviation)",
              indicators: {
                my_implied_yes: my_implied_yes, avg_price: avg_price, deviation: deviation,
                edge: edge_est, market_price: market_price, relative_value: true
              }
            )
          end
        end

        signals
      end

      # Group pair_registry entries by event_ticker for completeness checks.
      def group_by_event
        groups = {}
        @pair_registry.each do |pair, info|
          event = info["event_ticker"] || info[:event_ticker]
          next unless event

          groups[event] ||= {}
          groups[event][pair] = info
        end
        groups
      end

      def find_related_from_pair_registry
        return [] if @pair_registry.empty?

        # Extract event ticker from current pair.
        # Kalshi format: "KL_KXEVENT123/YES" — event ticker is between KL_ and the contract suffix.
        # Only match pairs sharing the SAME event ticker (same parent event = potentially exclusive outcomes).
        base_ticker = strategy_pair.sub(%r{/[A-Z]+\z}, "") # e.g., "KL_KXAGICOCOMP29"
        base_event = @pair_registry.dig(strategy_pair, "event_ticker") ||
                     @pair_registry.dig(strategy_pair, :event_ticker)
        base_condition = @pair_registry.dig(strategy_pair, "condition_id") ||
                         @pair_registry.dig(strategy_pair, :condition_id)

        base_slug = @pair_registry.dig(strategy_pair, "slug") || @pair_registry.dig(strategy_pair, :slug)

        @pair_registry.filter_map do |pair, info|
          next if pair == strategy_pair
          rel_event = info["event_ticker"] || info[:event_ticker]

          # Require same event ticker for math-arb (mutually exclusive constraint)
          if base_event && rel_event
            next unless base_event == rel_event
          elsif base_slug.present?
            # Polymarket: slug groups markets from the same event
            rel_slug = info["slug"] || info[:slug]
            next unless rel_slug == base_slug
            # Skip same-condition complement (YES/NO of same binary = parity arb, not combinatorial)
            rel_condition = info["condition_id"] || info[:condition_id]
            next if rel_condition == base_condition
          elsif base_condition.present?
            # Polymarket fallback: condition_id grouping without slug
            rel_condition = info["condition_id"] || info[:condition_id]
            next if rel_condition == base_condition
            next unless rel_condition.present?
          else
            # Fallback: match by stripping trailing digits (e.g., KXAGICOCOMP29 → KXAGICOCOMP)
            base_stem = base_ticker.sub(/\d+\z/, "")
            rel_ticker = pair.sub(%r{/[A-Z]+\z}, "")
            rel_stem = rel_ticker.sub(/\d+\z/, "")
            next unless base_stem == rel_stem && base_stem.length > 5
          end

          { "pair" => pair, "source" => "pair_registry",
            "similarity" => 0.8, "question" => (info["question"] || info[:question]) }
        end
      end

      def fetch_pair_price(pair)
        venue_id = @strategy_data["venue_id"]
        return nil unless venue_id && @data_fetcher

        # Check tick price cache first (pre-warmed with batch fetch)
        if @price_cache
          cached = @price_cache.get(pair)
          if cached
            return (cached["last_price"] || cached[:last_price])&.to_f
          end
        end

        # Cache miss — fetch individually and cache for sibling strategies
        data = @data_fetcher.fetch_ticker(pair: pair, venue_id: venue_id)
        @price_cache&.set(pair, data) if data
        data && (data["last_price"] || data[:last_price])&.to_f
      rescue StandardError
        nil
      end

      def check_logical_constraint(pair_a, pair_b, price_a, price_b)
        return nil unless @llm_client && @provider_config

        question_a = @market_question || pair_a
        question_b = @pair_registry.dig(pair_b, "question") || @pair_registry.dig(pair_b, :question) || pair_b

        system_prompt = <<~PROMPT.strip
          Analyze logical relationships between prediction market questions.
          Types of relationships to check:
          1. IMPLICATION: A⊂B means if A is true then B must be true, so P(B)≥P(A). Example: "S&P above 5100" implies "S&P above 5000".
          2. MUTUAL EXCLUSIVITY: A and B cannot both be true. Example: two candidates for the same position. For mutually exclusive events, there is NO implication — set has_implication=false, direction=none, violation=false.
          3. INDEPENDENCE: No logical connection. Set has_implication=false, violation=false.

          CRITICAL: Mutually exclusive outcomes (e.g., different candidates for the same election) do NOT imply each other. "Candidate A wins" does NOT imply "Candidate B wins". Set violation=false for these.
          Only set violation=true when there is a genuine logical implication and prices violate it.
        PROMPT

        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          system_prompt += "\n\nPatterns from past trades:\n#{tc['compound_learnings'] || tc[:compound_learnings]}" if tc["compound_learnings"] || tc[:compound_learnings]
          system_prompt += "\n\nWarnings:\n#{tc['reflexion_warnings'] || tc[:reflexion_warnings]}" if tc["reflexion_warnings"] || tc[:reflexion_warnings]
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Question A (price: #{(price_a * 100).round(1)}%): #{question_a}\nQuestion B (price: #{(price_b * 100).round(1)}%): #{question_b}\n\nIs there a logical implication? If A implies B, then P(B) should be >= P(A). If A and B are mutually exclusive candidates/outcomes, there is no implication." }
          ],
          schema: {
            type: "object",
            properties: {
              has_implication: { type: "boolean", description: "True if there is a logical implication between A and B" },
              violation: { type: "boolean", description: "True if prices violate the logical constraint" },
              direction: { type: "string", enum: %w[a_implies_b b_implies_a none], description: "Direction of implication" },
              violation_spread: { type: "number", description: "Price discrepancy magnitude (0 if no violation)" },
              confidence: { type: "number", description: "Confidence in the constraint 0-1" },
              reasoning: { type: "string", description: "Explanation of the logical relationship" }
            },
            required: %w[has_implication violation direction violation_spread confidence reasoning],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost

        # Short-circuit: if LLM says no implication, don't process further
        return nil if response.is_a?(Hash) && response[:has_implication] == false

        response
      rescue StandardError => e
        log("Constraint check failed: #{e.message}", level: :warn)
        nil
      end

      def load_negative_cache
        entries = strategy_config["checked_no_implication"] || []
        ttl = param("negative_cache_ttl_seconds", 3600)
        cutoff = Time.current - ttl
        entries.each_with_object(Set.new) do |entry, set|
          next unless entry["checked_at"]
          next if Time.parse(entry["checked_at"]) < cutoff
          set << entry["pair"]
        end
      rescue StandardError
        Set.new
      end

      def batch_check_constraints(candidates_with_prices, market_price)
        return {} unless @llm_client && @provider_config
        return {} if candidates_with_prices.empty?

        question_a = @market_question || strategy_pair

        comparisons_text = candidates_with_prices.each_with_index.map do |c, i|
          rel_pair = c["pair"] || c[:pair]
          rel_price = c["_price"]
          question_b = @pair_registry.dig(rel_pair, "question") ||
                       @pair_registry.dig(rel_pair, :question) || rel_pair
          "Comparison #{i + 1}:\n  Question A (#{(market_price * 100).round(1)}%): #{question_a}\n  Question B (#{(rel_price * 100).round(1)}%): #{question_b}"
        end.join("\n\n")

        system_prompt = <<~PROMPT.strip
          Analyze logical relationships between prediction market questions.
          You will receive multiple comparisons. For EACH, determine:
          1. IMPLICATION: A⊂B means if A is true then B must be true, so P(B)≥P(A).
          2. MUTUAL EXCLUSIVITY: A and B cannot both be true. Set has_implication=false.
          3. INDEPENDENCE: No logical connection. Set has_implication=false.

          CRITICAL: Mutually exclusive outcomes do NOT imply each other.
          Only set violation=true when there is a genuine logical implication and prices violate it.
        PROMPT

        if @trading_context.is_a?(Hash)
          system_prompt += "\n\nPatterns:\n#{@trading_context['compound_learnings']}" if @trading_context["compound_learnings"]
          system_prompt += "\n\nWarnings:\n#{@trading_context['reflexion_warnings']}" if @trading_context["reflexion_warnings"]
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Analyze these #{candidates_with_prices.size} pair comparisons:\n\n#{comparisons_text}" }
          ],
          schema: {
            type: "object",
            properties: {
              results: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    comparison_index: { type: "integer", description: "1-based comparison number" },
                    has_implication: { type: "boolean" },
                    violation: { type: "boolean" },
                    direction: { type: "string", enum: %w[a_implies_b b_implies_a none] },
                    violation_spread: { type: "number" },
                    confidence: { type: "number" },
                    reasoning: { type: "string" }
                  },
                  required: %w[comparison_index has_implication violation direction violation_spread confidence reasoning],
                  additionalProperties: false
                }
              }
            },
            required: ["results"],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost

        # Map results by comparison index → candidate pair
        result_map = {}
        if response.is_a?(Hash) && response[:results].is_a?(Array)
          response[:results].each do |r|
            idx = (r[:comparison_index] || 0) - 1
            candidate = candidates_with_prices[idx]
            next unless candidate
            rel_pair = candidate["pair"] || candidate[:pair]
            result_map[rel_pair] = r
          end
        end
        result_map
      rescue StandardError => e
        log("Batch constraint check failed: #{e.message}, falling back to individual", level: :warn)
        result_map = {}
        candidates_with_prices.each do |c|
          rel_pair = c["pair"] || c[:pair]
          result_map[rel_pair] = check_logical_constraint(strategy_pair, rel_pair, market_price, c["_price"])
        end
        result_map
      end

      def determine_arb_direction(constraint, price_a, price_b)
        case constraint[:direction]
        when "a_implies_b" then price_a < price_b ? "long" : "short"
        when "b_implies_a" then price_a > price_b ? "long" : "short"
        else price_a < 0.5 ? "long" : "short"
        end
      end

      # Checks if two pairs are from the SAME contract but different outcome slots.
      # e.g., "KL_KXLLM126DEC31A/YES" vs "KL_KXLLM126DEC31B/YES" → same contract, different outcomes → exclusive
      # vs "KL_KXAGICOCOMP29/YES" vs "KL_KXAGICOCOMP30/YES" → different contracts → NOT exclusive
      def same_contract_different_outcome?(pair_a, pair_b)
        # Extract ticker portion: "KL_KXLLM126DEC31A" from "KL_KXLLM126DEC31A/YES"
        ticker_a = pair_a.sub(%r{/[A-Z]+\z}, "")
        ticker_b = pair_b.sub(%r{/[A-Z]+\z}, "")

        # Same ticker means YES vs NO of same contract — that's complementary, not arb
        return false if ticker_a == ticker_b

        # Check pair registry event_ticker — most reliable for multi-candidate events
        # (e.g., KXNEWPOPE-70-MZUP and KXNEWPOPE-70-PPAR share event_ticker "KXNEWPOPE-70")
        event_a = @pair_registry.dig(pair_a, "event_ticker") || @pair_registry.dig(pair_a, :event_ticker)
        event_b = @pair_registry.dig(pair_b, "event_ticker") || @pair_registry.dig(pair_b, :event_ticker)
        if event_a.present? && event_b.present? && event_a == event_b
          return true # Same event, different outcome contracts = mutually exclusive
        end

        # Polymarket: use condition_id from pair registry for mutual exclusivity
        if ticker_a.start_with?("PM") && ticker_b.start_with?("PM")
          cond_a = @pair_registry.dig(pair_a, "condition_id") || @pair_registry.dig(pair_a, :condition_id)
          cond_b = @pair_registry.dig(pair_b, "condition_id") || @pair_registry.dig(pair_b, :condition_id)
          return cond_a.present? && cond_b.present? && cond_a == cond_b
        end

        # Kalshi: letter-suffix convention for outcome slots
        # "KL_KXLLM126DEC31A" → "KL_KXLLM126DEC31" (base) + "A" (outcome)
        # "KL_KXAGICOCOMP29" → "KL_KXAGICOCOMP2" (base) + "9" (contract number) ← NOT an outcome letter
        # Only single trailing letters A-Z indicate outcome slots; trailing digits indicate contract numbers
        base_a = ticker_a.sub(/[A-Z]\z/, "")
        base_b = ticker_b.sub(/[A-Z]\z/, "")
        suffix_a = ticker_a[-1]
        suffix_b = ticker_b[-1]

        # Both must end in a letter (outcome slot), and share the same base
        return false unless suffix_a.match?(/[A-Z]/) && suffix_b.match?(/[A-Z]/)
        return false unless base_a == base_b && base_a.length > 5

        # Different outcome letters on same contract base = mutually exclusive
        suffix_a != suffix_b
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
