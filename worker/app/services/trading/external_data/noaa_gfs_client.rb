# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Trading
  module ExternalData
    class NoaaGfsClient < Base
      NWS_BASE_URL = "https://api.weather.gov"
      USER_AGENT = "Powernode Trading Platform (contact@powernode.io)"

      # Common US city geocoding to NWS grid points
      CITY_GRID_POINTS = {
        "new york" => { office: "OKX", x: 33, y: 37 },
        "nyc" => { office: "OKX", x: 33, y: 37 },
        "los angeles" => { office: "LOX", x: 154, y: 44 },
        "la" => { office: "LOX", x: 154, y: 44 },
        "chicago" => { office: "LOT", x: 65, y: 76 },
        "houston" => { office: "HGX", x: 65, y: 97 },
        "phoenix" => { office: "PSR", x: 159, y: 57 },
        "miami" => { office: "MFL", x: 110, y: 65 },
        "denver" => { office: "BOU", x: 62, y: 60 },
        "seattle" => { office: "SEW", x: 124, y: 67 },
        "washington" => { office: "LWX", x: 97, y: 71 },
        "dc" => { office: "LWX", x: 97, y: 71 },
        "atlanta" => { office: "FFC", x: 50, y: 86 },
        "boston" => { office: "BOX", x: 71, y: 90 },
        "dallas" => { office: "FWD", x: 80, y: 103 },
        "san francisco" => { office: "MTR", x: 85, y: 105 },
        "sf" => { office: "MTR", x: 85, y: 105 }
      }.freeze

      WEATHER_KEYWORDS = %w[
        temperature rain snow precipitation wind hurricane tornado
        storm weather hot cold heat freeze frost drought flood
        celsius fahrenheit degree inches mph
      ].freeze

      def applicable?(question)
        q = question.to_s.downcase
        WEATHER_KEYWORDS.any? { |kw| q.include?(kw) }
      end

      def cache_ttl
        21_600  # 6 hours — matches GFS update cycle
      end

      # Fetch forecast for a parsed weather market
      # metadata: { location:, metric:, threshold:, unit:, date: }
      def fetch_for_market(market_question, metadata = {})
        location = metadata[:location] || metadata["location"]
        return nil unless location

        grid = resolve_grid_point(location)
        return nil unless grid

        cache_key = "noaa:#{grid[:office]}:#{grid[:x]}:#{grid[:y]}"

        forecast = cached_fetch(cache_key) do
          fetch_gridpoint_forecast(grid[:office], grid[:x], grid[:y])
        end

        return nil unless forecast

        {
          forecast: forecast,
          grid_point: grid,
          location: location,
          fetched_at: Time.now,
          model: "GFS",
          model_freshness_hours: calculate_model_age(forecast)
        }
      end

      # Calculate probability of a threshold being exceeded from forecast data
      def calculate_probability(forecast_data, metric:, threshold:, unit: "F", date: nil)
        return nil unless forecast_data && forecast_data[:forecast]

        periods = forecast_data[:forecast]["properties"]&.dig("periods") || []
        return nil if periods.empty?

        # Find relevant periods for the target date
        target_periods = if date
          target_date = Date.parse(date.to_s) rescue nil
          if target_date
            periods.select do |p|
              period_date = Date.parse(p["startTime"]) rescue nil
              period_date == target_date
            end
          else
            periods.first(2)  # Default to next 2 periods
          end
        else
          periods.first(2)
        end

        return nil if target_periods.empty?

        case metric&.downcase
        when "high_temperature", "temperature", "high"
          temps = target_periods.map { |p| p["temperature"] }.compact
          return nil if temps.empty?

          threshold_val = threshold.to_f
          # Convert if needed
          if unit&.upcase == "C" && target_periods.first["temperatureUnit"] == "F"
            threshold_val = threshold_val * 9.0 / 5.0 + 32
          end

          # Simple probability: fraction of periods exceeding threshold
          exceeding = temps.count { |t| t >= threshold_val }
          exceeding.to_f / temps.length

        when "precipitation", "rain"
          # Check precipitation probability from detailed forecast
          probs = target_periods.map do |p|
            p.dig("probabilityOfPrecipitation", "value")
          end.compact
          return nil if probs.empty?
          probs.sum / probs.length / 100.0

        else
          nil  # Unknown metric
        end
      end

      private

      def resolve_grid_point(location)
        normalized = location.to_s.downcase.strip
        CITY_GRID_POINTS[normalized]
      end

      def fetch_gridpoint_forecast(office, x, y)
        url = URI("#{NWS_BASE_URL}/gridpoints/#{office}/#{x},#{y}/forecast")

        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(url)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "application/geo+json"

        response = http.request(request)

        if response.code.to_i == 200
          JSON.parse(response.body)
        else
          log("NWS API error: #{response.code} for #{office}/#{x},#{y}", level: :warn)
          nil
        end
      rescue => e
        log("NWS API fetch failed: #{e.message}", level: :error)
        nil
      end

      def calculate_model_age(forecast)
        updated = forecast&.dig("properties", "updateTime") ||
                  forecast&.dig("properties", "generatedAt")
        return nil unless updated

        hours = (Time.now - Time.parse(updated)) / 3600.0
        hours.round(1)
      rescue
        nil
      end
    end
  end
end
