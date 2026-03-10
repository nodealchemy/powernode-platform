# frozen_string_literal: true

module Trading
  module Evaluators
    class NewsReactive < Base
      register "news_reactive"

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price
        return signals unless @llm_client && @provider_config

        @total_cost = 0.0

        # Fetch new documents since last tick
        new_docs = fetch_new_documents
        return check_exit_conditions(signals) if new_docs.empty?

        # Classify each document's impact
        events = []
        new_docs.each do |doc|
          event = classify_event(doc)
          events << event.merge(document: doc) if event && event[:impact_magnitude].to_f > param("impact_threshold", 0.5)
        end

        return check_exit_conditions(signals) if events.empty?

        # Match events to our pair
        matched = events.select { |e| event_matches_pair?(e) }
        return check_exit_conditions(signals) if matched.empty?

        # Build signal from strongest matching event
        strongest = matched.max_by { |e| e[:impact_magnitude].to_f * time_weight(e) }
        return check_exit_conditions(signals) if strongest.nil?

        direction = strongest[:impact_direction] == "positive" ? "long" : "short"
        weight = time_weight(strongest)
        lag_bonus = news_lag_bonus(strongest)
        confidence = (strongest[:confidence].to_f * weight * lag_bonus).clamp(0.0, 1.0)

        if !has_open_position? && confidence >= param("confidence_threshold", 0.6)
          signals << build_signal(
            type: "entry",
            direction: direction,
            confidence: confidence,
            strength: strongest[:impact_magnitude].to_f.clamp(0.0, 1.0),
            reasoning: "News event: #{strongest[:event_type]} — #{strongest[:reasoning] || 'impact detected'}. Magnitude: #{strongest[:impact_magnitude]}, Recency weight: #{weight.round(2)}",
            indicators: {
              event_type: strongest[:event_type],
              impact_direction: strongest[:impact_direction],
              impact_magnitude: strongest[:impact_magnitude],
              confidence: strongest[:confidence],
              time_weight: weight,
              lag_bonus: lag_bonus,
              in_lag_window: lag_bonus > 1.0,
              events_found: matched.size,
              edge: strongest[:impact_magnitude].to_f * weight * 0.5
            }
          )
        end

        check_exit_conditions(signals)
        signals
      rescue StandardError => e
        log("Evaluation failed: #{e.message}", level: :warn)
        []
      end

      private

      def fetch_new_documents
        return [] unless @data_fetcher

        since = last_tick_at || (Time.current - 3600)
        max_age = param("max_age_minutes", 30).to_i * 60
        cutoff = [since, Time.current - max_age].max

        question = @market_question || strategy_pair
        chunks = @data_fetcher.rag_query(
          account_id: account_id,
          query: question,
          kb_name: "trading_news",
          top_k: param("rag_top_k", 10)
        )

        chunks.select do |c|
          created = c["created_at"] || c[:created_at]
          if created
            (Time.parse(created.to_s) > cutoff rescue true)
          else
            true
          end
        end.map do |c|
          timestamp = c["created_at"] || c[:created_at]
          {
            id: c["id"] || c[:id],
            content: c["content"] || c[:content],
            timestamp: timestamp ? (Time.parse(timestamp.to_s) rescue Time.current) : Time.current
          }
        end
      rescue StandardError => e
        log("Document fetch failed: #{e.message}", level: :warn)
        []
      end

      def classify_event(doc)
        system_prompt = "Classify this news/document for its impact on prediction markets. Determine the event type, which markets it affects, the direction and magnitude of impact."

        if @trading_context
          tc = @trading_context.is_a?(Hash) ? @trading_context : {}
          system_prompt += "\n\nPatterns from past trades:\n#{tc["compound_learnings"] || tc[:compound_learnings]}" if tc["compound_learnings"] || tc[:compound_learnings]
          system_prompt += "\n\nWarnings from past failures:\n#{tc["reflexion_warnings"] || tc[:reflexion_warnings]}" if tc["reflexion_warnings"] || tc[:reflexion_warnings]
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: doc[:content].to_s[0, 3000] }
          ],
          schema: {
            type: "object",
            properties: {
              event_type: { type: "string", description: "Type: breaking_news, policy_change, economic_data, market_event, other" },
              affected_markets: { type: "array", items: { type: "string" }, description: "Market topics affected" },
              impact_direction: { type: "string", enum: %w[positive negative neutral] },
              impact_magnitude: { type: "number", description: "Impact strength 0-1" },
              confidence: { type: "number", description: "Classification confidence 0-1" },
              reasoning: { type: "string" }
            },
            required: %w[event_type affected_markets impact_direction impact_magnitude confidence reasoning],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost
        return nil unless response.is_a?(Hash)

        {
          event_type: response[:event_type],
          affected_markets: Array(response[:affected_markets]),
          impact_direction: response[:impact_direction],
          impact_magnitude: response[:impact_magnitude].to_f,
          confidence: response[:confidence].to_f,
          reasoning: response[:reasoning]
        }
      rescue StandardError => e
        log("Event classification failed: #{e.message}", level: :warn)
        nil
      end

      def event_matches_pair?(event)
        question = @market_question
        return true unless question

        topics = event[:affected_markets] || []
        return true if topics.empty?

        question_words = question.downcase.split(/\W+/)
        topics.any? do |topic|
          topic_words = topic.downcase.split(/\W+/)
          (question_words & topic_words).size >= 2
        end
      end

      def time_weight(event)
        doc = event[:document] || {}
        timestamp = doc[:timestamp] || Time.current
        age_seconds = [(Time.current - timestamp), 1].max

        half_life = param("news_half_life_seconds", 1800).to_f
        Math.exp(-age_seconds * Math.log(2) / half_life).clamp(0.1, 1.0)
      end

      def news_lag_bonus(event)
        lag_window = param("news_lag_window_seconds", 600).to_f
        bonus_mult = param("lag_bonus_multiplier", 1.3).to_f

        doc = event[:document] || {}
        timestamp = doc[:timestamp] || Time.current
        age_seconds = (Time.current - timestamp).abs

        age_seconds <= lag_window ? bonus_mult : 1.0
      end

      def check_exit_conditions(signals)
        return signals unless has_open_position?

        position = current_position
        return signals unless position

        opened_at = position["opened_at"] ? Time.parse(position["opened_at"]) : nil
        max_age = param("max_age_minutes", 30).to_i * 60

        if opened_at && opened_at < (Time.current - max_age)
          signals << build_signal(
            type: "exit",
            direction: position["side"],
            confidence: 0.6,
            strength: 0.5,
            reasoning: "News impact window expired (#{param('max_age_minutes', 30)} minutes)",
            indicators: { position_age_minutes: ((Time.current - opened_at) / 60).round(1) }
          )
        end

        signals
      end
    end
  end
end
