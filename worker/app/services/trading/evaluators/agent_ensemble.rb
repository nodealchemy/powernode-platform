# frozen_string_literal: true

module Trading
  module Evaluators
    class AgentEnsemble < Base
      register "agent_ensemble"

      ANALYST_ROLES = %w[technical sentiment fundamentals news risk_manager].freeze

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price
        return signals unless @llm_client && @provider_config

        @llm_call_count = 0
        @max_llm_calls = param("max_llm_calls_per_tick", 8)
        @total_cost = 0.0

        analyses = collect_analyst_opinions(market_price)
        return signals if analyses.empty?

        if param("enable_bull_bear_debate", true) && can_make_llm_call?
          analyses = run_debate(analyses, market_price)
        end

        decision = can_make_llm_call? ? synthesize_decision(analyses, market_price) : fallback_decision(analyses)
        return signals unless decision

        min_confidence = param("confidence_threshold", 0.65)
        consensus_threshold = param("consensus_threshold", 0.6)

        if decision[:direction] != "hold" && decision[:confidence] >= min_confidence && decision[:consensus] >= consensus_threshold
          signals << build_signal(
            type: "entry", direction: decision[:direction],
            confidence: decision[:confidence].clamp(0.0, 1.0),
            strength: decision[:consensus].clamp(0.0, 1.0),
            reasoning: "Ensemble decision: #{decision[:reasoning]} (#{analyses.size} analysts, consensus: #{(decision[:consensus] * 100).round(0)}%)",
            indicators: {
              analyst_count: analyses.size, consensus: decision[:consensus],
              individual_views: analyses.map { |a| { role: a[:role], direction: a[:direction], confidence: a[:confidence] } },
              position_size_modifier: decision[:position_size_modifier]
            }
          )
        end

        if has_open_position? && decision[:direction] == "close"
          signals << build_signal(
            type: "exit", direction: current_position&.dig("side") || "long",
            confidence: decision[:confidence].clamp(0.0, 1.0), strength: 0.7,
            reasoning: "Ensemble consensus to exit: #{decision[:reasoning]}"
          )
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
        temperature = param("analyst_temperature", 0.5)

        # Parallel threads — each LLM call is I/O-bound
        threads = analyst_roles.first(@max_llm_calls).map do |role|
          Thread.new(role) do |r|
            Thread.current[:result] = call_analyst(r, market_price, temperature)
            Thread.current[:role] = r
          end
        end

        analyses = []
        threads.each do |t|
          t.join(param("analyst_timeout_seconds", 30))
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

        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          system_prompt += "\n\nHistorical patterns:\n#{tc["compound_learnings"] || tc[:compound_learnings]}" if (tc["compound_learnings"] || tc[:compound_learnings]) && %w[technical fundamentals].include?(role)
          system_prompt += "\n\nPast examples:\n#{tc["experience_replays"] || tc[:experience_replays]}" if (tc["experience_replays"] || tc[:experience_replays]) && role == "technical"
          system_prompt += "\n\nWarnings:\n#{tc["reflexion_warnings"] || tc[:reflexion_warnings]}" if (tc["reflexion_warnings"] || tc[:reflexion_warnings]) && role == "risk_manager"
        end

        question = @market_question || strategy_pair
        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Analyze #{strategy_pair} at current price #{market_price}. Market question: #{question}" }
          ],
          schema: analyst_schema,
          temperature: temperature
        )
        return nil unless response.is_a?(Hash) && response[:direction]

        @total_cost += last_llm_cost
        { direction: response[:direction], confidence: response[:confidence].to_f.clamp(0.0, 1.0),
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
        debate_temp = param("debate_temperature", 0.6)
        debate_schema = { type: "object", properties: { rebuttal: { type: "string" }, updated_confidence: { type: "number" } },
                          required: %w[rebuttal updated_confidence], additionalProperties: false }
        timeout = param("analyst_timeout_seconds", 30)

        rounds.times do |round|
          break unless @llm_call_count + 1 < @max_llm_calls

          bull_thread = Thread.new do
            Thread.current[:result] = llm_complete_structured(
              messages: [
                { role: "system", content: "You are a bull analyst. Counter the bear arguments with evidence." },
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
                { role: "system", content: "You are a bear analyst. Counter the bull arguments with evidence and risk analysis." },
                { role: "user", content: "Bear case:\n#{bear_args}\n\nBull case to rebut:\n#{bull_args}" }
              ],
              schema: debate_schema, temperature: debate_temp
            )
          rescue StandardError => e
            log("Bear rebuttal failed: #{e.message}", level: :warn)
          end

          bull_thread.join(timeout)
          bear_thread.join(timeout)
          [bull_thread, bear_thread].each { |t| t.kill if t.alive? }

          bull_rebuttal = bull_thread[:result]
          bear_rebuttal = bear_thread[:result]

          track_llm_call! if bull_rebuttal
          track_llm_call! if bear_rebuttal

          bull_args += "\nRebuttal #{round + 1}: #{bull_rebuttal[:rebuttal]}" if bull_rebuttal.is_a?(Hash)
          bear_args += "\nRebuttal #{round + 1}: #{bear_rebuttal[:rebuttal]}" if bear_rebuttal.is_a?(Hash)

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

        response = llm_complete_structured(
          messages: [
            { role: "system", content: "You are the Lead Trader. Synthesize analyst opinions into a final trading decision. Consider risk, consensus, and confidence levels." },
            { role: "user", content: "Market: #{strategy_pair} at #{market_price}\nHas open position: #{has_open_position?}\n\nAnalyst opinions:\n#{summary}" }
          ],
          schema: trader_schema,
          temperature: param("trader_temperature", 0.2)
        )
        track_llm_call!

        return fallback_decision(analyses) unless response.is_a?(Hash)

        consensus = calculate_consensus(analyses)
        {
          direction: response[:direction] || consensus[:majority_direction],
          confidence: response[:confidence].to_f,
          reasoning: response[:reasoning].to_s,
          position_size_modifier: response[:position_size_modifier].to_f.clamp(0.1, 2.0),
          consensus: consensus[:score]
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
          position_size_modifier: 0.5, consensus: consensus[:score] }
      end

      def calculate_consensus(analyses)
        role_weights = param("role_weights", { "fundamentals" => 1.5, "risk_manager" => 1.3, "technical" => 1.2, "sentiment" => 1.0, "news" => 0.8 })
        weighted_votes = Hash.new(0.0)
        total_weight = 0.0

        analyses.each do |a|
          weight = (role_weights[a[:role]] || 1.0).to_f
          weighted_votes[a[:direction]] += weight
          total_weight += weight
        end

        majority_direction = weighted_votes.max_by { |_, v| v }&.first || "hold"
        score = total_weight > 0 ? weighted_votes[majority_direction] / total_weight : 0.0
        { majority_direction: majority_direction, score: score }
      end

      def analyst_system_prompt(role)
        prompts = {
          "technical" => "You are a Technical Analyst. Analyze price action, momentum, volume patterns, and support/resistance levels for prediction markets.",
          "sentiment" => "You are a Sentiment Analyst. Assess market sentiment, social signals, and crowd psychology around this market.",
          "fundamentals" => "You are a Fundamentals Analyst. Evaluate the underlying event probability based on real-world evidence, news, and expert opinions.",
          "news" => "You are a News Analyst. Assess recent news events and their impact on this market's outcome probability.",
          "risk_manager" => "You are a Risk Manager. Evaluate position sizing, downside risk, correlation risk, and whether the risk/reward is favorable."
        }
        prompts[role] || "You are a Market Analyst. Provide your assessment of this market."
      end

      def analyst_schema
        directions = param("force_directional", false) ? %w[long short close] : %w[long short hold close]
        { type: "object",
          properties: {
            direction: { type: "string", enum: directions, description: "Recommended direction" },
            confidence: { type: "number", description: "Confidence 0-1" },
            reasoning: { type: "string", description: "Key reasoning" },
            key_points: { type: "array", items: { type: "string" }, description: "Key analysis points" }
          },
          required: %w[direction confidence reasoning key_points], additionalProperties: false }
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
    end
  end
end
