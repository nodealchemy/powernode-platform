# frozen_string_literal: true

module Trading
  module Evaluators
    class WeatherModelAlpha < Base
      include Concerns::DynamicKelly
      include Concerns::BayesianBelief
      include Concerns::WeatherEnsemble

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

        # Build ensemble from additional sources
        source_estimates = [
          { source: "noaa_gfs", probability: model_prob, confidence: 0.9, freshness_hours: model_age || 0 }
        ]

        # Fetch observations for real-time calibration
        obs_estimate = fetch_observations(parsed)
        source_estimates << obs_estimate if obs_estimate

        # Fetch CPC outlooks for medium-range markets
        cpc_estimate = fetch_cpc_outlook(parsed)
        source_estimates << cpc_estimate if cpc_estimate

        # Fetch climate normals for base-rate anchoring
        climate_estimate = fetch_climate_normals(parsed, model_prob)
        source_estimates << climate_estimate if climate_estimate

        # Blend sources
        ensemble = blend_weather_sources(source_estimates)
        blended_prob = if ensemble && ensemble[:source_count] > 1
                         ensemble[:blended_probability]
                       else
                         model_prob
                       end

        # Update Bayesian belief with model evidence and market price movements
        if @price_history.length >= 2
          prev = (@price_history[-2]["close"] || @price_history[-2][:close]).to_f
          update_belief_from_price(previous_price: prev, current_price: price) if prev > 0
        end
        update_belief(
          evidence_up: blended_prob,
          evidence_down: 1.0 - blended_prob,
          weight: model_age && model_age < max_age ? (1.0 - model_age.to_f / max_age) : 0.5
        )

        # Blend ensemble probability with Bayesian posterior
        blended_prob = bayesian_blend(blended_prob)

        # Calculate edge using blended probability
        edge = (blended_prob - price).abs
        min_edge = param("min_edge_pct", 8.0) / 100.0
        return signals unless edge >= min_edge

        # Determine direction from blended estimate
        direction = blended_prob > price ? "long" : "short"

        # Confidence based on model agreement and edge size
        source_count = ensemble ? ensemble[:source_count] : 1
        confidence = calculate_weather_confidence(edge, model_age, parsed, source_count)

        # Dynamic Kelly sizing from blended probability + historical performance
        kelly = dynamic_kelly(estimated_prob: blended_prob, market_price: price)

        # Build indicators hash
        indicators = {
          edge: edge,
          edge_pct: (edge * 100).round(2),
          market_price: price,
          model_probability: model_prob,
          blended_probability: blended_prob,
          model_source: source_count > 1 ? "NOAA Ensemble" : "NOAA GFS",
          source_count: source_count,
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

        if ensemble && ensemble[:source_count] > 1
          indicators[:source_details] = ensemble[:source_details]
          indicators[:ensemble_spread] = ensemble[:spread]
        end

        signals << build_signal(
          type: "entry",
          direction: direction,
          confidence: confidence,
          strength: classify_weather_strength(edge),
          reasoning: "Weather model alpha: #{indicators[:model_source]} probability #{(model_prob * 100).round(1)}% (blended: #{(blended_prob * 100).round(1)}%) vs market #{(price * 100).round(1)}¢. Edge: #{(edge * 100).round(1)}%. #{parsed[:metric]} #{parsed[:threshold]}#{parsed[:unit]} in #{parsed[:location]} on #{parsed[:date]}. Sources: #{source_count}.",
          indicators: indicators
        )

        # Exit signals for existing positions if model flipped
        @positions.each do |pos|
          pos_direction = pos["side"]
          model_direction = blended_prob > price ? "long" : "short"
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

      def fetch_observations(parsed)
        return nil unless param("enable_observations", true)

        obs_client = Trading::ExternalData::NoaaObservationsClient.new
        obs_data = obs_client.fetch_for_market("", parsed)
        return nil unless obs_data

        record_external_data("noaa_observations")

        # Convert observation to a probability estimate based on current conditions
        obs_prob = observation_to_probability(obs_data, parsed)
        return nil unless obs_prob

        {
          source: "noaa_observations",
          probability: obs_prob,
          confidence: 0.7,
          freshness_hours: obs_data[:freshness_hours] || 1.0
        }
      rescue => e
        log("Observation fetch failed (non-fatal): #{e.message}", level: :warn)
        nil
      end

      def fetch_cpc_outlook(parsed)
        return nil unless param("enable_cpc_outlook", true)

        days_out = days_to_target(parsed[:date])
        return nil if days_out && days_out < 6

        cpc_client = Trading::ExternalData::NoaaCpcOutlookClient.new
        cpc_data = cpc_client.fetch_for_market("", parsed)
        return nil unless cpc_data

        record_external_data("noaa_cpc")

        # Convert CPC categorical outlook to a probability
        cpc_prob = cpc_outlook_to_probability(cpc_data, parsed)
        return nil unless cpc_prob

        {
          source: "noaa_cpc",
          probability: cpc_prob,
          confidence: 0.75,
          freshness_hours: cpc_data[:freshness_hours] || 12.0
        }
      rescue => e
        log("CPC outlook fetch failed (non-fatal): #{e.message}", level: :warn)
        nil
      end

      def fetch_climate_normals(parsed, model_prob)
        return nil unless param("enable_climate_normals", true)

        climate_client = Trading::ExternalData::NoaaClimateClient.new
        climate_data = climate_client.fetch_for_market("", parsed)
        return nil unless climate_data

        record_external_data("noaa_ncei")

        # Convert climate normals to a base-rate probability
        climate_prob = climate_to_probability(climate_data, parsed)
        return nil unless climate_prob

        {
          source: "noaa_ncei",
          probability: climate_prob,
          confidence: 0.6,
          freshness_hours: 0.0
        }
      rescue => e
        log("Climate normals fetch failed (non-fatal): #{e.message}", level: :warn)
        nil
      end

      def observation_to_probability(obs_data, parsed)
        return nil unless parsed[:metric] && parsed[:threshold]

        case parsed[:metric].downcase
        when "high_temperature", "temperature", "high"
          current_temp_c = obs_data[:observed_temperature_c]
          return nil unless current_temp_c

          threshold_c = if parsed[:unit]&.upcase == "F"
                          (parsed[:threshold].to_f - 32) * 5.0 / 9.0
                        else
                          parsed[:threshold].to_f
                        end

          # If current temp is already near/above threshold, high probability
          diff = threshold_c - current_temp_c
          if diff <= 0
            0.85 # Already exceeding
          elsif diff < 3
            0.7
          elsif diff < 6
            0.5
          elsif diff < 10
            0.3
          else
            0.15
          end

        when "precipitation", "rain"
          # If currently precipitating, higher probability
          if obs_data[:text_description]&.downcase&.match?(/rain|snow|drizzle|shower/)
            0.75
          else
            0.35
          end

        when "wind_speed", "wind"
          current_wind = obs_data[:observed_wind_speed_kmh]
          return nil unless current_wind

          threshold_kmh = if parsed[:unit]&.downcase == "mph"
                            parsed[:threshold].to_f * 1.60934
                          else
                            parsed[:threshold].to_f
                          end

          ratio = current_wind / [threshold_kmh, 0.1].max
          if ratio >= 1.0
            0.8
          elsif ratio >= 0.7
            0.6
          elsif ratio >= 0.4
            0.4
          else
            0.2
          end
        end
      end

      def cpc_outlook_to_probability(cpc_data, parsed)
        return nil unless cpc_data[:temperature]

        case parsed[:metric]&.downcase
        when "high_temperature", "temperature", "high"
          # Above-normal probability maps to threshold exceedance likelihood
          above_prob = cpc_data[:temperature][:above_normal] || 0.33
          # Scale: if threshold is high relative to normals, above_normal matters more
          above_prob.clamp(0.1, 0.9)

        when "precipitation", "rain"
          above_prob = cpc_data.dig(:precipitation, :above_normal) || 0.33
          above_prob.clamp(0.1, 0.9)

        else
          nil
        end
      end

      def climate_to_probability(climate_data, parsed)
        return nil unless climate_data[:historical_exceedance_prob]

        exceedance = climate_data[:historical_exceedance_prob]
        return nil unless exceedance.is_a?(Hash) && exceedance[:expected_high_f]

        case parsed[:metric]&.downcase
        when "high_temperature", "temperature", "high"
          expected = exceedance[:expected_high_f]
          std = exceedance[:daily_temp_std_f] || 8.0
          threshold_f = if parsed[:unit]&.upcase == "C"
                          parsed[:threshold].to_f * 9.0 / 5.0 + 32
                        else
                          parsed[:threshold].to_f
                        end

          # Z-score based probability (normal distribution approximation)
          z = (threshold_f - expected) / std
          # Approximate 1 - CDF using logistic function
          prob = 1.0 / (1.0 + Math.exp(1.7 * z))
          prob.clamp(0.01, 0.99)

        when "precipitation", "rain"
          # Use normal precipitation probability as base rate
          (climate_data[:normal_precip_in] || 0).to_f > 0.01 ? 0.4 : 0.2

        else
          nil
        end
      end

      def days_to_target(date_str)
        return nil unless date_str
        target = Date.parse(date_str.to_s)
        (target - Date.today).to_i
      rescue
        nil
      end

      def calculate_weather_confidence(edge, model_age, parsed, source_count = 1)
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
        location_bonus = NoaaGeoResolver.known_location?(parsed[:location].to_s) ? 0.1 : 0.0

        # Multiple sources → higher confidence
        source_bonus = if source_count >= 3
                         0.10
                       elsif source_count >= 2
                         0.05
                       else
                         0.0
                       end

        [base + edge_bonus + age_bonus + location_bonus + source_bonus, 0.95].min.clamp(0.3, 0.95)
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
