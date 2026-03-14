# frozen_string_literal: true

require "digest"

module Trading
  module Evaluators
    class SentimentAnalysis < Base
      register "sentiment_analysis"

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price
        return signals unless @llm_client && @provider_config

        @total_cost = 0.0

        # Cooldown: prevent consecutive trades after recent entry evaluation (bypassed in training)
        unless training?
          cooldown = param("cooldown_seconds", 60)
          if !has_open_position? && last_tick_at && last_tick_at > (Time.current - cooldown)
            return signals
          end
        end

        # Warm-up gate: don't trade on first ticks with zero price history
        tick_count = price_history&.size || 0
        warm_up = param("warm_up_ticks", 3)
        return signals if tick_count < warm_up && !has_open_position?

        # Fetch and score RAG chunks via server
        scored_chunks = fetch_and_score_chunks

        # LLM fallback when RAG returns insufficient data
        if scored_chunks.size < param("min_sources", 1) && @llm_client && @provider_config
          llm_sentiment = estimate_sentiment_via_llm
          scored_chunks = [llm_sentiment] if llm_sentiment
        end
        return signals if scored_chunks.empty?

        # Aggregate with temporal decay
        decay = param("decay_factor", 0.9)
        current_sentiment = aggregate_sentiment(scored_chunks, decay)

        # Get rolling average for shift detection
        rolling = load_rolling_sentiment
        shift = detect_shift(current_sentiment, rolling)

        # Store current sentiment for future rolling average
        store_sentiment(current_sentiment)

        # Generate signal on significant sentiment shift (warm-up gate prevents first-tick noise)
        threshold = param("sentiment_shift_threshold", 0.3)

        if shift && shift[:shift_magnitude] > threshold
          direction = shift[:shift_direction] == "bullish" ? "long" : "short"

          unless has_open_position?
            signals << build_signal(
              type: "entry",
              direction: direction,
              confidence: ([shift[:shift_magnitude] * 1.5, 0.3].max * current_sentiment[:magnitude]).clamp(0.3, 0.90),
              strength: current_sentiment[:magnitude],
              reasoning: "Sentiment shift detected: #{shift[:shift_direction]} (#{shift[:shift_magnitude].round(3)}). Current: #{current_sentiment[:score].round(3)}, Rolling: #{(rolling&.dig(:score) || 0).round(3)}",
              indicators: {
                sentiment_score: current_sentiment[:score],
                sentiment_magnitude: current_sentiment[:magnitude],
                sentiment_direction: current_sentiment[:direction],
                shift_magnitude: shift[:shift_magnitude],
                source_count: current_sentiment[:source_count]
              }
            )
          end
        end

        # Exit on TP/SL or high-confidence reversal
        if has_open_position?
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
                reasoning: "Sentiment stop-loss: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit",
                indicators: { pnl_pct: pnl_pct, sentiment_score: current_sentiment[:score], edge: 0 }
              )
              return signals
            elsif pnl_pct >= take_profit
              signals << build_signal(
                type: "exit", direction: side,
                confidence: 0.85, strength: 0.8,
                reasoning: "Sentiment take-profit: PnL #{pnl_pct.round(2)}% exceeds +#{take_profit}% target",
                indicators: { pnl_pct: pnl_pct, sentiment_score: current_sentiment[:score], edge: 0 }
              )
              return signals
            end

            position_direction = position["side"] == "long" ? "bullish" : "bearish"
            sentiment_reversed = current_sentiment[:direction] != "neutral" && current_sentiment[:direction] != position_direction
            high_confidence_reversal = sentiment_reversed && current_sentiment[:magnitude].to_f > 0.5
            opened_at = position["opened_at"] ? Time.parse(position["opened_at"]) : nil
            max_hold_expired = opened_at && opened_at < (Time.current - param("max_hold_seconds", 3600).to_i)

            if high_confidence_reversal
              signals << build_signal(
                type: "exit",
                direction: position["side"],
                confidence: (current_sentiment[:magnitude].to_f * 0.9).clamp(0.5, 0.95),
                strength: current_sentiment[:magnitude],
                reasoning: "Sentiment reversed against position: #{current_sentiment[:direction]} with magnitude #{current_sentiment[:magnitude].to_f.round(3)}",
                indicators: { sentiment_score: current_sentiment[:score], sentiment_magnitude: current_sentiment[:magnitude] }
              )
            elsif max_hold_expired
              signals << build_signal(
                type: "exit",
                direction: position["side"],
                confidence: 0.6,
                strength: 0.5,
                reasoning: "Max hold time expired (score: #{current_sentiment[:score].round(3)})",
                indicators: { sentiment_score: current_sentiment[:score] }
              )
            end
          end
        end

        signals
      rescue StandardError => e
        log("Evaluation failed: #{e.message}", level: :warn)
        []
      end

      private

      def estimate_sentiment_via_llm
        question = @market_question || strategy_pair

        price_context = if price_history&.size.to_i > 3
          recent = price_history.last(5).map { |s| (s["close"] || s[:close]).to_f }
          "Recent prices: #{recent.map { |p| "#{(p * 100).round(1)}%" }.join(', ')}"
        else
          "Insufficient price history for trend analysis."
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: "You are a sentiment analyst. Assess the current market sentiment for the given prediction market question. Consider public opinion, news, and social signals. Use the price context to inform your assessment." },
            { role: "user", content: "What is the current sentiment around: #{question}\nCurrent price: #{(current_price * 100).round(1)}%\n#{price_context}" }
          ],
          schema: {
            type: "object",
            properties: {
              sentiment: { type: "number", description: "Sentiment score -1 (bearish) to 1 (bullish)" },
              magnitude: { type: "number", description: "Confidence/strength 0 to 1" },
              reasoning: { type: "string", description: "Brief reasoning" }
            },
            required: %w[sentiment magnitude reasoning],
            additionalProperties: false
          },
          temperature: 0.3
        )
        return nil unless response.is_a?(Hash) && response[:sentiment]

        @total_cost += last_llm_cost
        { sentiment: response[:sentiment].to_f.clamp(-1.0, 1.0),
          magnitude: response[:magnitude].to_f.clamp(0.0, 1.0),
          timestamp: Time.current }
      rescue StandardError => e
        log("LLM sentiment fallback failed: #{e.message}", level: :warn)
        nil
      end

      def fetch_and_score_chunks
        return [] unless @data_fetcher

        question = @market_question || strategy_pair
        chunks = @data_fetcher.rag_query(
          account_id: account_id,
          query: question,
          kb_name: "Trading Market Intelligence",
          top_k: param("rag_top_k", 10)
        )
        return [] if chunks.empty?

        # Deduplicate by content prefix
        seen = Set.new
        unique = chunks.select do |c|
          content = (c["content"] || c[:content]).to_s
          prefix_hash = Digest::SHA256.hexdigest(content[0, 200])[0, 16]
          seen.add?(prefix_hash)
        end

        # Batch classify all chunks in a single LLM call
        batch_classify_sentiment(unique)
      end

      def batch_classify_sentiment(chunks)
        return [] if chunks.empty?

        system_prompt = <<~PROMPT
          Classify the sentiment of each numbered text regarding prediction market outcomes.
          For each text, return a sentiment score from -1 (very bearish/negative) to 1 (very bullish/positive) and a magnitude from 0 (low confidence) to 1 (high confidence).
        PROMPT

        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          system_prompt += "\n\nPatterns from past trades:\n#{tc["compound_learnings"] || tc[:compound_learnings]}" if tc["compound_learnings"] || tc[:compound_learnings]
          system_prompt += "\n\nWarnings:\n#{tc["reflexion_warnings"] || tc[:reflexion_warnings]}" if tc["reflexion_warnings"] || tc[:reflexion_warnings]
        end

        text_list = chunks.each_with_index.map do |c, i|
          content = (c["content"] || c[:content]).to_s[0, 500]
          "[#{i + 1}] #{content}"
        end.join("\n\n")

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: text_list }
          ],
          schema: {
            type: "object",
            properties: {
              results: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    index: { type: "integer", description: "1-based text index" },
                    sentiment: { type: "number", description: "Sentiment score -1 to 1" },
                    magnitude: { type: "number", description: "Confidence/strength 0 to 1" }
                  },
                  required: %w[index sentiment magnitude],
                  additionalProperties: false
                }
              }
            },
            required: %w[results],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost
        return [] unless response.is_a?(Hash) && response[:results].is_a?(Array)

        response[:results].filter_map do |r|
          idx = r[:index].to_i - 1
          next unless idx >= 0 && idx < chunks.size

          chunk = chunks[idx]
          timestamp = chunk["created_at"] || chunk[:created_at]
          {
            sentiment: r[:sentiment].to_f.clamp(-1.0, 1.0),
            magnitude: r[:magnitude].to_f.clamp(0.0, 1.0),
            timestamp: timestamp ? (Time.parse(timestamp.to_s) rescue Time.current) : Time.current
          }
        end
      rescue StandardError => e
        log("Batch classification failed: #{e.message}", level: :warn)
        []
      end

      def aggregate_sentiment(scored_chunks, decay_factor)
        return { score: 0, magnitude: 0, direction: "neutral", source_count: 0 } if scored_chunks.empty?

        now = Time.current
        weighted_sum = 0.0
        magnitude_sum = 0.0
        total_weight = 0.0

        scored_chunks.sort_by { |c| c[:timestamp] || now }.each_with_index do |chunk, i|
          age_factor = decay_factor**(scored_chunks.size - 1 - i)
          weight = age_factor * chunk[:magnitude]
          weighted_sum += chunk[:sentiment] * weight
          magnitude_sum += chunk[:magnitude] * age_factor
          total_weight += weight
        end

        score = total_weight > 0 ? weighted_sum / total_weight : 0.0
        avg_magnitude = scored_chunks.size > 0 ? magnitude_sum / scored_chunks.size : 0.0
        direction = if score > 0.1
                      "bullish"
                    elsif score < -0.1
                      "bearish"
                    else
                      "neutral"
                    end

        { score: score, magnitude: avg_magnitude, direction: direction, source_count: scored_chunks.size }
      end

      def detect_shift(current, rolling)
        return nil unless rolling && rolling[:count].to_i > 0

        shift_magnitude = (current[:score] - rolling[:score]).abs
        shift_direction = current[:score] > rolling[:score] ? "bullish" : "bearish"

        { shift_magnitude: shift_magnitude, shift_direction: shift_direction }
      end

      def store_sentiment(sentiment)
        return unless @data_fetcher

        history = strategy_config["sentiment_history"] || []
        history << sentiment.merge(timestamp: Time.current.iso8601)

        window_hours = param("rolling_window_hours", 24)
        cutoff = Time.current - (window_hours * 3600)
        history = history.select do |h|
          ts = h[:timestamp] || h["timestamp"]
          ts ? (Time.parse(ts.to_s) > cutoff rescue true) : true
        end

        @data_fetcher.update_strategy_config(
          strategy_id: strategy_id,
          config_updates: { "sentiment_history" => history.last(100) }
        )
      rescue StandardError => e
        log("Failed to store sentiment: #{e.message}", level: :warn)
      end

      def load_rolling_sentiment
        history = strategy_config["sentiment_history"] || []
        return nil if history.empty?

        scores = history.map { |h| (h[:score] || h["score"]).to_f }
        magnitudes = history.map { |h| (h[:magnitude] || h["magnitude"]).to_f }

        {
          score: scores.sum / scores.size,
          magnitude: magnitudes.sum / magnitudes.size,
          count: history.size
        }
      end
    end
  end
end
