# frozen_string_literal: true

module Trading
  module Evaluators
    class TailEndYield < Base
      register "tail_end_yield"

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price

        min_price = param("min_price", 0.95)
        max_price = param("max_price", 0.99)
        return check_exit_conditions(signals) unless market_price.between?(min_price, max_price)

        # Volume gate
        min_volume = param("min_volume_24h", 5000)
        vol_24h = (@market_data["volume_24h"] || @market_data[:volume_24h]).to_f
        return check_exit_conditions(signals) if vol_24h > 0 && vol_24h < min_volume

        # Time-to-expiry gate
        max_hours = param("max_time_to_expiry_hours", 168)
        expiry = market_expiry
        if expiry
          hours_to_expiry = (expiry - Time.current) / 3600.0
          return check_exit_conditions(signals) if hours_to_expiry > max_hours || hours_to_expiry < 0
        end

        # Calculate expected yield
        expected_yield = 1.0 - market_price
        min_yield = param("min_yield_pct", 0.5) / 100.0
        return check_exit_conditions(signals) if expected_yield < min_yield

        estimated_cost = spread_pct || 0.02 # Conservative 2% fallback when spread unknown
        net_yield = expected_yield - estimated_cost
        return check_exit_conditions(signals) if net_yield <= 0

        # Optional LLM confirmation
        confidence = base_confidence(market_price)
        if param("use_llm_confirmation", false) && @llm_client
          llm_check = confirm_resolution_likelihood
          if llm_check
            confidence = [confidence, llm_check[:confidence].to_f].min
            return check_exit_conditions(signals) if llm_check[:reversal_risk].to_f > 0.15
          end
        end

        if !has_open_position? && confidence >= param("confidence_threshold", 0.8)
          signals << build_signal(
            type: "entry", direction: "long",
            confidence: confidence,
            strength: (net_yield / 0.05).clamp(0.0, 1.0),
            reasoning: "Tail-end yield: #{(expected_yield * 100).round(2)}% gross yield (net #{(net_yield * 100).round(2)}% after costs) on near-settlement market at #{(market_price * 100).round(1)}%",
            indicators: {
              market_price: market_price, expected_yield: expected_yield,
              net_yield: net_yield, estimated_cost: estimated_cost,
              hours_to_expiry: expiry ? ((expiry - Time.current) / 3600.0).round(1) : nil,
              edge: expected_yield,
              limit_order: true,
              limit_price: market_price.round(4)
            }
          )
        end

        check_exit_conditions(signals)
        signals
      end

      private

      def base_confidence(market_price)
        (0.5 + market_price * 0.5).clamp(0.7, 0.98)
      end

      def confirm_resolution_likelihood
        question = @market_question
        return nil unless question

        @total_cost ||= 0.0
        response = llm_complete_structured(
          messages: [
            { role: "system", content: "You are assessing whether a prediction market is likely to resolve as expected. The market is currently priced above 95%, implying near-certainty. Evaluate if there's any realistic chance of reversal." },
            { role: "user", content: "Market question: #{question}\nCurrent price: #{(current_price * 100).round(1)}%\n\nIs this market likely to resolve YES as the price implies?" }
          ],
          schema: {
            type: "object",
            properties: {
              confidence: { type: "number", description: "Confidence that the market resolves as priced, 0-1" },
              reversal_risk: { type: "number", description: "Probability of last-minute reversal, 0-1" },
              reasoning: { type: "string", description: "Brief explanation" }
            },
            required: %w[confidence reversal_risk reasoning],
            additionalProperties: false
          },
          temperature: 0.2
        )
        @total_cost += last_llm_cost
        response
      rescue StandardError => e
        log("LLM confirmation failed: #{e.message}", level: :warn)
        nil
      end

      def check_exit_conditions(signals)
        return signals unless has_open_position?
        position = current_position
        return signals unless position

        reversal_threshold = param("reversal_exit_price", 0.90)
        if current_price < reversal_threshold
          signals << build_signal(
            type: "exit", direction: position["side"],
            confidence: 0.9, strength: 0.8,
            reasoning: "Price dropped to #{(current_price * 100).round(1)}% — potential reversal, exiting tail-end position",
            indicators: { current_price: current_price, reversal_threshold: reversal_threshold }
          )
        end
        signals
      end
    end
  end
end
