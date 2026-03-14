# frozen_string_literal: true

module Trading
  module Evaluators
    class WeatherModelAlpha < Base
      include Concerns::DynamicKelly

      register "weather_model_alpha"

      def evaluate
        signals = []
        price = current_price
        return signals unless price && price > 0 && price < 1

        # Must have a market question to parse
        return signals unless @market_question && !@market_question.empty?

        # Check concurrent position limits
        max_concurrent = param("max_concurrent_positions", 3)
        open_count = @positions.count { |p| p["status"] == "open" }
        return signals if open_count >= max_concurrent

        # Initialize NOAA client
        noaa = Trading::ExternalData::NoaaGfsClient.new

        # Check if this is a weather market
        return signals unless noaa.applicable?(@market_question)

        # Parse market question into structured params via LLM
        parsed = parse_weather_question(@market_question)
        return signals unless parsed

        # Fetch forecast data
        forecast_data = noaa.fetch_for_market(@market_question, parsed)
        return signals unless forecast_data

        record_external_data("noaa_gfs")

        # Check model freshness
        max_age = param("max_model_age_hours", 12)
        model_age = forecast_data[:model_freshness_hours]
        if model_age && model_age > max_age
          log("GFS model too stale: #{model_age}h old (max #{max_age}h)")
          return signals
        end

        # Calculate model probability
        model_prob = noaa.calculate_probability(
          forecast_data,
          metric: parsed[:metric],
          threshold: parsed[:threshold],
          unit: parsed[:unit],
          date: parsed[:date]
        )
        return signals unless model_prob

        # Calculate edge
        edge = (model_prob - price).abs
        min_edge = param("min_edge_pct", 8.0) / 100.0
        return signals unless edge >= min_edge

        # Determine direction
        direction = model_prob > price ? "long" : "short"

        # Confidence based on model agreement and edge size
        confidence = calculate_weather_confidence(edge, model_age, parsed)

        # Dynamic Kelly sizing from edge + historical performance
        kelly = dynamic_kelly(estimated_prob: model_prob, market_price: price)

        signals << build_signal(
          type: "entry",
          direction: direction,
          confidence: confidence,
          strength: classify_weather_strength(edge),
          reasoning: "Weather model alpha: GFS model probability #{(model_prob * 100).round(1)}% vs market #{(price * 100).round(1)}¢. Edge: #{(edge * 100).round(1)}%. #{parsed[:metric]} #{parsed[:threshold]}#{parsed[:unit]} in #{parsed[:location]} on #{parsed[:date]}.",
          indicators: {
            edge: edge,
            edge_pct: (edge * 100).round(2),
            market_price: price,
            model_probability: model_prob,
            model_source: "NOAA GFS",
            model_age_hours: model_age,
            location: parsed[:location],
            metric: parsed[:metric],
            threshold: parsed[:threshold],
            unit: parsed[:unit],
            target_date: parsed[:date],
            kelly_fraction: kelly[:kelly_fraction],
            kelly_full: kelly[:kelly_full],
            edge_after_impact: kelly[:edge_after_impact],
            kelly_blend_source: kelly[:blend_source],
            position_sizing_method: "kelly"
          }
        )

        # Exit signals for existing positions if model flipped
        @positions.select { |p| p["status"] == "open" }.each do |pos|
          pos_direction = pos["side"]
          # If model now disagrees with position direction
          model_direction = model_prob > price ? "long" : "short"
          if pos_direction != model_direction && edge >= min_edge
            signals << build_signal(
              type: "exit",
              direction: "close",
              confidence: 0.8,
              strength: 0.6,
              reasoning: "Weather model reversal: was #{pos_direction}, model now indicates #{model_direction}. Model prob: #{(model_prob * 100).round(1)}%",
              indicators: {
                edge: 0,
                market_price: price,
                model_probability: model_prob,
                exit_reason: "model_reversal"
              }
            )
          end
        end

        signals
      end

      private

      def parse_weather_question(question)
        messages = [
          {
            role: "system",
            content: "Extract structured weather market parameters from the question. Return JSON with: location (city name), metric (high_temperature, precipitation, wind_speed), threshold (numeric value), unit (F, C, inches, mph), date (YYYY-MM-DD). If you cannot parse, return null for all fields."
          },
          {
            role: "user",
            content: question
          }
        ]

        schema = {
          type: "object",
          properties: {
            location: { type: ["string", "null"] },
            metric: { type: ["string", "null"] },
            threshold: { type: ["number", "null"] },
            unit: { type: ["string", "null"] },
            date: { type: ["string", "null"] }
          },
          required: %w[location metric threshold unit date]
        }

        begin
          response = llm_complete_structured(messages: messages, schema: schema, temperature: 0.1)
          @total_cost = (@total_cost || 0.0) + last_llm_cost

          return nil unless response && response[:location] && response[:metric] && response[:threshold]
          response
        rescue => e
          log("Failed to parse weather question: #{e.message}", level: :warn)
          nil
        end
      end

      def calculate_weather_confidence(edge, model_age, parsed)
        base = 0.5

        # Larger edge → higher confidence
        edge_bonus = [edge * 3, 0.25].min

        # Fresher model → higher confidence
        age_bonus = if model_age && model_age < 3
                      0.15
                    elsif model_age && model_age < 6
                      0.10
                    elsif model_age && model_age < 12
                      0.05
                    else
                      0.0
                    end

        # Known locations → higher confidence
        location_bonus = Trading::ExternalData::NoaaGfsClient::CITY_GRID_POINTS.key?(
          parsed[:location].to_s.downcase.strip
        ) ? 0.1 : 0.0

        [base + edge_bonus + age_bonus + location_bonus, 0.95].min.clamp(0.3, 0.95)
      end

      def classify_weather_strength(edge)
        case edge
        when (0.20..) then 0.95
        when (0.15..0.20) then 0.8
        when (0.10..0.15) then 0.6
        else 0.4
        end
      end
    end
  end
end
