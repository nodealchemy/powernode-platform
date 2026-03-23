# frozen_string_literal: true

module Trading
  module Evaluators
    class AgentEnsemble < Base
      include Concerns::DynamicKelly
      include Concerns::ConvergenceExit

      register "agent_ensemble"

      ANALYST_ROLES = %w[technical sentiment fundamentals news risk_manager].freeze
      TICK_BUDGET_SECONDS = 45       # Max wall-clock time for entire evaluate call [C2, #11]
      MIN_SYNTHESIS_TIMEOUT = 10     # Reserve at least this much time for synthesis

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price
        return signals unless @llm_client && @provider_config

        @budget_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TICK_BUDGET_SECONDS

        # Cooldown: prevent over-trading by spacing out entry evaluations (bypassed in training)
        unless training?
          cooldown = param("cooldown_seconds", 120)
          if !has_open_position? && last_tick_at && last_tick_at > (Time.current - cooldown)
            return signals
          end
        end

        # Max open positions guard
        open_count = @positions.count { |p| p["status"] == "open" }
        max_open = param("max_open_positions", 1)
        return signals if open_count >= max_open && !has_open_position?

        @llm_call_count = 0
        @max_llm_calls = param("max_llm_calls_per_tick", 8)
        @total_cost = 0.0

        analyses = collect_analyst_opinions(market_price)
        return signals if analyses.empty?

        if param("enable_bull_bear_debate", true) && can_make_llm_call?
          analyses = run_debate(analyses, market_price)
        end

        # Pre-compute consensus probability for the synthesizer prompt
        pre_consensus = calculate_consensus(analyses)
        @pre_consensus_prob = pre_consensus[:probability]

        decision = can_make_llm_call? ? synthesize_decision(analyses, market_price) : fallback_decision(analyses)
        return signals unless decision

        min_confidence = param("confidence_threshold", 0.65)
        consensus_threshold = param("consensus_threshold", 0.6)

        if decision[:direction] != "hold" && decision[:confidence] >= min_confidence && decision[:consensus] >= consensus_threshold
          # Dynamic Kelly sizing replaces LLM-generated position_size_modifier
          kelly = dynamic_kelly(
            estimated_prob: decision[:probability] || market_price,
            market_price: market_price
          )

          signals << build_signal(
            type: "entry", direction: decision[:direction],
            confidence: decision[:confidence].clamp(0.0, 1.0),
            strength: decision[:consensus].clamp(0.0, 1.0),
            reasoning: "Ensemble decision: #{decision[:reasoning]} (#{analyses.size} analysts, consensus: #{(decision[:consensus] * 100).round(0)}%)",
            indicators: {
              analyst_count: analyses.size, consensus: decision[:consensus],
              edge: decision[:edge] || 0, probability: decision[:probability],
              individual_views: analyses.map { |a| { role: a[:role], direction: a[:direction], confidence: a[:confidence], probability_estimate: a[:probability_estimate] } },
              kelly_fraction: kelly[:kelly_fraction],
              kelly_full: kelly[:kelly_full],
              edge_after_impact: kelly[:edge_after_impact],
              kelly_blend_source: kelly[:blend_source],
              position_sizing_method: "kelly",
              limit_order: true,
              limit_price: market_price.round(4)
            }
          )
        end

        if has_open_position?
          if decision[:direction] == "close"
            signals << build_signal(
              type: "exit", direction: current_position&.dig("side") || "long",
              confidence: decision[:confidence].clamp(0.0, 1.0), strength: 0.7,
              reasoning: "Ensemble consensus to exit: #{decision[:reasoning]}",
              indicators: { edge: 0 }
            )
          else
            # TP/SL exit check
            position = current_position
            if position
              entry_price = (position["entry_price"] || 0).to_f
              side = position["side"] || "long"
              pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0
              stop_loss = param("stop_loss_pct", 5.0)
              take_profit = param("take_profit_pct", 3.0)

              if pnl_pct <= -stop_loss
                signals << build_signal(
                  type: "exit", direction: side,
                  confidence: 0.9, strength: 0.9,
                  reasoning: "Ensemble stop-loss: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit",
                  indicators: { pnl_pct: pnl_pct, edge: 0 }
                )
              elsif pnl_pct >= take_profit
                signals << build_signal(
                  type: "exit", direction: side,
                  confidence: 0.85, strength: 0.8,
                  reasoning: "Ensemble take-profit: PnL #{pnl_pct.round(2)}% exceeds +#{take_profit}% target",
                  indicators: { pnl_pct: pnl_pct, edge: 0 }
                )
              else
                # Convergence exit: check if remaining edge has decayed below exit cost
                if market_expiry
                  hours_left = (market_expiry - Time.now) / 3600.0
                  conv_signal = convergence_exit_check(position, hours_left)
                  signals << build_signal(**conv_signal) if conv_signal
                end
              end
            end
          end
        end

        signals
      rescue StandardError => e
        log("Evaluation failed: #{e.message}", level: :warn)
        []
      end

      private

      def can_make_llm_call?
        @llm_call_count < @max_llm_calls
      end

      def track_llm_call!
        @llm_call_count += 1
      end

      def collect_analyst_opinions(market_price)
        roles = param("agent_roles", ANALYST_ROLES)
        analyst_roles = roles.reject { |r| r == "trader" }
        temperature = param("analyst_temperature", 0.7)

        # Parallel threads — each LLM call is I/O-bound
        threads = analyst_roles.first(@max_llm_calls).map do |role|
          Thread.new(role) do |r|
            Thread.current[:result] = call_analyst(r, market_price, temperature)
            Thread.current[:role] = r
          end
        end

        analyses = []
        threads.each do |t|
          configured_timeout = param("analyst_timeout_seconds", 30)
          effective_timeout = [configured_timeout, budget_remaining].min
          t.join(effective_timeout)
          if t.alive?
            t.kill
            t.join(1)
          end
          if t[:result]
            analyses << t[:result].merge(role: t[:role])
            track_llm_call!
          end
        end
        analyses
      end

      def call_analyst(role, market_price, temperature)
        system_prompt = analyst_system_prompt(role)

        # P0-2: Inject trading context to all relevant roles (was previously role-gated)
        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          learnings = tc["compound_learnings"] || tc[:compound_learnings]
          replays = tc["experience_replays"] || tc[:experience_replays]
          warnings = tc["reflexion_warnings"] || tc[:reflexion_warnings]

          # Historical patterns: universally relevant to all analyst roles
          system_prompt += "\n\nHistorical patterns:\n#{learnings}" if learnings
          # Past trade examples: relevant to roles that benefit from concrete examples
          system_prompt += "\n\nPast examples:\n#{replays}" if replays && %w[technical fundamentals risk_manager].include?(role)
          # Reflexion warnings: failure awareness for roles that assess risk and evidence
          system_prompt += "\n\nWarnings:\n#{warnings}" if warnings && %w[risk_manager fundamentals].include?(role)
        end

        question = @market_question || strategy_pair
        price_context = build_price_context(market_price)

        # P1-5: Enrich fundamentals analyst with settlement context
        user_content = "Analyze #{strategy_pair} at current price #{market_price}. Market question: #{question}\n\n#{price_context}"
        if role == "fundamentals"
          if market_expiry
            hours_left = ((market_expiry - Time.now) / 3600.0).round(1)
            user_content += "\n\nSettlement: #{market_expiry.strftime('%Y-%m-%d %H:%M UTC')} (#{hours_left}h remaining)"
          end
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_content }
          ],
          schema: analyst_schema,
          temperature: temperature
        )
        return nil unless response.is_a?(Hash) && response[:direction]

        @total_cost += last_llm_cost
        { direction: response[:direction], confidence: response[:confidence].to_f.clamp(0.0, 1.0),
          probability_estimate: response[:probability_estimate]&.to_f&.clamp(0.0, 1.0),
          reasoning: response[:reasoning].to_s, key_points: Array(response[:key_points]) }
      rescue StandardError => e
        log("Analyst #{role} failed: #{e.message}", level: :warn)
        nil
      end

      def run_debate(analyses, _market_price)
        rounds = param("debate_rounds", 2)
        return analyses if rounds.zero?

        bulls = analyses.select { |a| a[:direction] == "long" }
        bears = analyses.select { |a| a[:direction] == "short" }
        return analyses if bulls.empty? || bears.empty?

        bull_args = bulls.map { |b| "#{b[:role]}: #{b[:reasoning]}" }.join("\n")
        bear_args = bears.map { |b| "#{b[:role]}: #{b[:reasoning]}" }.join("\n")
        debate_temp = param("debate_temperature", 0.5)
        debate_schema = { type: "object", properties: { rebuttal: { type: "string" }, updated_confidence: { type: "number" } },
                          required: %w[rebuttal updated_confidence], additionalProperties: false }
        timeout = param("analyst_timeout_seconds", 30)

        rounds.times do |round|
          break unless @llm_call_count + 1 < @max_llm_calls
          break if budget_remaining < MIN_SYNTHESIS_TIMEOUT + 5  # Reserve time for synthesis [C2]

          bull_thread = Thread.new do
            Thread.current[:result] = llm_complete_structured(
              messages: [
                { role: "system", content: "You are the bull-case advocate in a structured debate. Your role is Bayesian updating, not blind advocacy. Steelman the strongest bear point before rebutting it. Introduce NEW evidence or reasoning — do not simply restate the bull case. If bear arguments genuinely weaken your case, lower your updated_confidence. Intellectual honesty improves the debate's value." },
                { role: "user", content: "Bull case:\n#{bull_args}\n\nBear case to rebut:\n#{bear_args}" }
              ],
              schema: debate_schema, temperature: debate_temp
            )
          rescue StandardError => e
            log("Bull rebuttal failed: #{e.message}", level: :warn)
          end

          bear_thread = Thread.new do
            Thread.current[:result] = llm_complete_structured(
              messages: [
                { role: "system", content: "You are the bear-case advocate in a structured debate. Your role is Bayesian updating, not blind opposition. Steelman the strongest bull point before rebutting it. Introduce NEW risk factors or counter-evidence — do not simply restate the bear case. If bull arguments genuinely strengthen the case, lower your updated_confidence. Intellectual honesty improves the debate's value." },
                { role: "user", content: "Bear case:\n#{bear_args}\n\nBull case to rebut:\n#{bull_args}" }
              ],
              schema: debate_schema, temperature: debate_temp
            )
          rescue StandardError => e
            log("Bear rebuttal failed: #{e.message}", level: :warn)
          end

          debate_timeout = [timeout, [budget_remaining - MIN_SYNTHESIS_TIMEOUT, 0].max].min
          bull_thread.join(debate_timeout)
          bear_thread.join(debate_timeout)
          [bull_thread, bear_thread].each { |t| t.kill if t.alive? }

          bull_rebuttal = bull_thread[:result]
          bear_rebuttal = bear_thread[:result]

          track_llm_call! if bull_rebuttal
          track_llm_call! if bear_rebuttal

          bull_args += "\nRebuttal #{round + 1}: #{bull_rebuttal[:rebuttal]}" if bull_rebuttal.is_a?(Hash)
          bear_args += "\nRebuttal #{round + 1}: #{bear_rebuttal[:rebuttal]}" if bear_rebuttal.is_a?(Hash)

          # Wire debate updated_confidence back into analyst analyses.
          # Without this, debate rounds waste LLM calls without affecting decisions.
          if bull_rebuttal.is_a?(Hash) && bull_rebuttal[:updated_confidence]
            bulls.each { |b| b[:confidence] = bull_rebuttal[:updated_confidence].to_f.clamp(0.0, 1.0) }
          end
          if bear_rebuttal.is_a?(Hash) && bear_rebuttal[:updated_confidence]
            bears.each { |b| b[:confidence] = bear_rebuttal[:updated_confidence].to_f.clamp(0.0, 1.0) }
          end

          break if bull_rebuttal.is_a?(Hash) && bull_rebuttal[:updated_confidence].to_f < 0.3 &&
                   bear_rebuttal.is_a?(Hash) && bear_rebuttal[:updated_confidence].to_f < 0.3
        end

        analyses
      rescue StandardError => e
        log("Debate failed: #{e.message}", level: :warn)
        analyses
      end

      def synthesize_decision(analyses, market_price)
        return nil if analyses.empty?
        summary = analyses.map { |a| "#{a[:role]} (#{a[:direction]}, conf: #{a[:confidence]}): #{a[:reasoning]}" }.join("\n")

        synthesizer_prompt = resolve_role_prompt("synthesizer")
        response = llm_complete_structured(
          messages: [
            { role: "system", content: synthesizer_prompt },
            { role: "user", content: "Market: #{strategy_pair} at #{market_price}\nHas open position: #{has_open_position?}\nConsensus probability: #{@pre_consensus_prob&.round(3)}\nEdge vs market: #{((@pre_consensus_prob || market_price) - market_price).round(3)}\n\nAnalyst opinions:\n#{summary}" }
          ],
          schema: trader_schema,
          temperature: param("trader_temperature", 0.3)
        )
        track_llm_call!

        return fallback_decision(analyses) unless response.is_a?(Hash)

        consensus = calculate_consensus(analyses)
        {
          direction: response[:direction] || consensus[:majority_direction],
          confidence: response[:confidence].to_f,
          reasoning: response[:reasoning].to_s,
          position_size_modifier: response[:position_size_modifier].to_f.clamp(0.1, 2.0),
          consensus: consensus[:score],
          probability: consensus[:probability],
          edge: consensus[:edge]
        }
      rescue StandardError => e
        log("Synthesis failed: #{e.message}", level: :warn)
        fallback_decision(analyses)
      end

      def fallback_decision(analyses)
        return nil if analyses.empty?
        consensus = calculate_consensus(analyses)
        avg_confidence = analyses.sum { |a| a[:confidence].to_f } / analyses.size
        { direction: consensus[:majority_direction], confidence: avg_confidence,
          reasoning: "Fallback consensus from #{analyses.size} analysts",
          position_size_modifier: 0.5, consensus: consensus[:score],
          probability: consensus[:probability], edge: consensus[:edge] }
      end

      def calculate_consensus(analyses)
        role_weights = param("role_weights", { "fundamentals" => 1.5, "risk_manager" => 1.3, "technical" => 1.2, "sentiment" => 1.0, "news" => 1.0 })

        # Probability-weighted averaging instead of vote-counting.
        # Each analyst's probability_estimate is weighted by their confidence and role weight.
        weighted_sum = 0.0
        weight_total = 0.0

        analyses.each do |a|
          role_weight = (role_weights[a[:role]] || 1.0).to_f
          prob = a[:probability_estimate] || (a[:direction] == "long" ? 0.6 : 0.4)
          confidence = (a[:confidence] || 0.5).to_f
          weight = confidence * role_weight
          weighted_sum += prob * weight
          weight_total += weight
        end

        return { majority_direction: "hold", score: 0.0, probability: nil, edge: 0.0 } if weight_total.zero?

        consensus_prob = weighted_sum / weight_total
        edge = (consensus_prob - current_price).abs
        min_edge = param("min_edge", 0.08)

        # E5: Echo chamber detection — penalize consensus when analyst probability
        # estimates have low variance. Data: 28/28 losses with unanimous consensus
        # = $1,165 lost to groupthink. When all analysts agree but are wrong,
        # variance is near zero. Require minimum disagreement for conviction.
        prob_estimates = analyses.map { |a| a[:probability_estimate] || (a[:direction] == "long" ? 0.6 : 0.4) }
        if prob_estimates.size >= 2
          mean_prob = prob_estimates.sum / prob_estimates.size
          variance = prob_estimates.sum { |p| (p - mean_prob)**2 } / prob_estimates.size
          std_dev = Math.sqrt(variance)
          disagreement_threshold = param("disagreement_threshold", 0.05)

          if std_dev < disagreement_threshold
            # Analysts suspiciously unanimous — discount the consensus score
            echo_penalty = param("echo_chamber_penalty", 1.0)
            return { majority_direction: "hold", score: 0.0, probability: consensus_prob,
                     edge: edge, echo_chamber: true, analyst_std_dev: std_dev } if echo_penalty >= 1.0
          end
        end

        if edge < min_edge
          { majority_direction: "hold", score: 0.0, probability: consensus_prob, edge: edge }
        else
          direction = consensus_prob > current_price ? "long" : "short"
          score = (edge * 2).clamp(0.3, 0.9)
          { majority_direction: direction, score: score, probability: consensus_prob, edge: edge }
        end
      end

      def build_price_context(market_price)
        parts = []
        parts << "Current implied probability: #{(market_price * 100).round(1)}%"
        parts << "Bid: #{bid_price.round(4)}, Ask: #{ask_price.round(4)}" if bid_price > 0 && ask_price > 0

        if price_history.size >= 3
          recent = price_history.last(5).map { |s| (s["close"] || s[:close]).to_f }
          trend = recent.last - recent.first
          parts << "Recent trend: #{trend > 0 ? '+' : ''}#{(trend * 100).round(2)}% over last #{recent.size} ticks"
        end

        if has_open_position?
          pos = current_position
          entry = (pos&.dig("entry_price") || 0).to_f
          side = pos&.dig("side") || "long"
          pnl = entry > 0 ? ((market_price - entry) / entry * 100 * (side == "short" ? -1 : 1)).round(2) : 0
          parts << "Open #{side} position from #{entry.round(4)}, P&L: #{pnl}%"
        end

        parts.join("\n")
      end

      # Resolve analyst system prompt: server context → hardcoded fallback.
      # Server-resolved prompts are the canonical source (from ENSEMBLE_ROLE_PROMPTS
      # in strategy_prompts.rb, with DB template override support). Hardcoded prompts
      # serve as backwards-compatible fallback when context is unavailable.
      def analyst_system_prompt(role)
        resolve_role_prompt(role)
      end

      # Resolve a role prompt from server context or hardcoded fallback.
      def resolve_role_prompt(role)
        # Prefer server-resolved prompts (single source of truth)
        if @ensemble_role_prompts
          prompts = @ensemble_role_prompts.is_a?(Hash) ? @ensemble_role_prompts : {}
          prompt = prompts[role] || prompts[role.to_s]
          return prompt if prompt.present?
        end

        # Fallback: hardcoded prompts (backwards compatibility)
        FALLBACK_ROLE_PROMPTS[role] || FALLBACK_ROLE_PROMPTS["fundamentals"]
      end

      FALLBACK_ROLE_PROMPTS = {
        "technical" => <<~PROMPT.strip,
          You are a Technical Analyst for a prediction market trading ensemble. Your domain is price action analysis: momentum indicators, support/resistance levels, order flow patterns, and volume profile interpretation.

          Analyze the price chart for directional signals. Look for trend confirmation (higher highs/higher lows or the reverse), volume-price divergences, and support/resistance levels relative to the current price. In prediction markets, prices are bounded at $0 and $1, so traditional technical patterns behave differently near extremes.

          Estimate the TRUE probability that this event will resolve YES based on what the price action tells you about market participant conviction and information flow. Form your own independent estimate — do NOT anchor on the current market price. Return your probability_estimate as a number between 0.0 and 1.0.

          Guard against recency bias (overweighting the last few price moves) and curve-fitting (seeing patterns in noise). Short price histories have low statistical significance.
        PROMPT
        "sentiment" => <<~PROMPT.strip,
          You are a Sentiment Analyst for a prediction market trading ensemble. Your domain is crowd psychology, contrarian indicators, fear/greed dynamics, and social signal interpretation.

          Assess the prevailing market sentiment toward this outcome. Consider whether the crowd is irrationally optimistic or pessimistic, look for contrarian indicators (extreme positioning often precedes reversals), and evaluate the quality of social signals (expert commentary vs. noise).

          Estimate the TRUE probability that this event will resolve YES based on your sentiment read, independent of the current price. Sentiment can diverge from price when markets are slow to incorporate qualitative information. Return your probability_estimate as a number between 0.0 and 1.0.

          Your magnitude reflects your confidence in the sentiment read, not the expected price move. A strong bullish sentiment read with high confidence means you are certain the crowd is bullish, not that the price will rise.
        PROMPT
        "fundamentals" => <<~PROMPT.strip,
          You are a Fundamentals Analyst for a prediction market trading ensemble. Your domain is real-world evidence evaluation, base rate analysis, reference class forecasting, and expert opinion synthesis. You carry the heaviest weight in the consensus calculation.

          Evaluate the underlying event probability using evidence-based reasoning. Start with base rates for similar events (reference class forecasting), then update based on specific evidence for or against. Synthesize expert opinions, official data, and structural factors that influence the outcome.

          Estimate the TRUE probability that this event will resolve YES. Your estimate must be grounded in evidence, not price action or sentiment. Form your independent view before considering what the market or other analysts think. Return your probability_estimate as a number between 0.0 and 1.0.

          This is the most important analyst role — your evidence-based probability anchors the entire ensemble's decision. Reason carefully from facts, not narratives.
        PROMPT
        "news" => <<~PROMPT.strip,
          You are a News Analyst for a prediction market trading ensemble. Your domain is recent developments, catalyst identification, information asymmetry assessment, and pricing-in dynamics.

          Assess recent news events and developments that could shift the probability of this outcome. Focus on genuinely new information — developments not yet reflected in the current price. Evaluate source credibility, information novelty, and potential for multi-hop effects (indirect impacts through related events).

          Estimate the TRUE probability that this event will resolve YES based on the latest information landscape. The key question is whether recent news represents a material update to the prior probability or is already priced in. Return your probability_estimate as a number between 0.0 and 1.0.

          Distinguish between news that changes the fundamental probability and news that merely generates attention or narrative momentum without new information content.
        PROMPT
        "risk_manager" => <<~PROMPT.strip,
          You are a Risk Manager for a prediction market trading ensemble. You have veto authority — your concerns can block trades that other analysts support. Your domain is downside scenario analysis, tail risk assessment, correlation exposure evaluation, and position sizing adequacy.

          Evaluate the downside risks of taking a position on this market. Consider: What is the worst-case scenario and its probability? Is there hidden correlation with existing positions? Is the position size appropriate for the confidence level? Are there upcoming events that could cause sudden price dislocation?

          Estimate the TRUE probability that this event will resolve YES, but with special attention to tail risks that other analysts may underweight. Return your probability_estimate as a number between 0.0 and 1.0.

          Flag overconfidence: If other analysts are likely to agree strongly, that itself is a risk signal — unanimous agreement with high confidence often precedes the worst losses. Challenge the consensus when conviction is high but evidence quality is low.
        PROMPT
        "synthesizer" => <<~PROMPT.strip,
          You are the Lead Trader synthesizing analyst opinions into a final trading decision. You have received independent probability estimates and directional views from multiple specialist analysts.

          Synthesis methodology: Weight analyst contributions by evidence quality, not just stated confidence. Fundamentals and risk management carry structurally higher weight. Apply an echo chamber penalty when analyst probability estimates have suspiciously low variance — unanimous agreement is a warning sign, not confirmation.

          Decision requirements: You MUST commit to a directional decision (long, short, or close). "Hold" is acceptable only when genuine uncertainty exists (consensus probability near 50% or analysts split evenly with good reasoning on both sides). Never hold simply to avoid risk — that is the risk manager's job, not yours.

          Position sizing: Your position_size_modifier reflects edge conviction. Scale it based on the gap between consensus probability and market price, analyst agreement quality (not just quantity), and the risk manager's assessment. A modifier of 1.0 is standard; above 1.0 signals exceptional edge; below 0.5 signals a marginal opportunity.
        PROMPT
      }.freeze

      def analyst_schema
        directions = param("force_directional", false) ? %w[long short close] : %w[long short hold close]
        { type: "object",
          properties: {
            direction: { type: "string", enum: directions, description: "Recommended direction" },
            probability_estimate: { type: "number", description: "Estimated true probability of YES outcome (0.0-1.0)" },
            confidence: { type: "number", description: "Confidence in your estimate 0-1" },
            reasoning: { type: "string", description: "Key reasoning" },
            key_points: { type: "array", items: { type: "string" }, description: "Key analysis points" }
          },
          required: %w[direction probability_estimate confidence reasoning key_points], additionalProperties: false }
      end

      def trader_schema
        directions = param("force_directional", false) ? %w[long short close] : %w[long short hold close]
        { type: "object",
          properties: {
            direction: { type: "string", enum: directions },
            confidence: { type: "number" },
            reasoning: { type: "string" },
            position_size_modifier: { type: "number", description: "Multiplier for default position size (0.1-2.0)" }
          },
          required: %w[direction confidence reasoning position_size_modifier], additionalProperties: false }
      end

      # Override health_report to include ensemble-specific data.
      def health_report
        base = super
        base.merge(
          analyst_count: param("agent_roles", ANALYST_ROLES).reject { |r| r == "trader" }.size,
          debate_rounds: param("debate_rounds", 2),
          llm_calls_per_tick: @llm_call_count || 0,
          max_llm_calls: param("max_llm_calls_per_tick", 8),
          consensus_quality: @pre_consensus_prob ? { probability: @pre_consensus_prob.round(4) } : nil
        )
      end

      # Seconds remaining in the tick budget. Returns Float::INFINITY if no deadline set.
      def budget_remaining
        return Float::INFINITY unless @budget_deadline
        [@budget_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
      end
    end
  end
end
