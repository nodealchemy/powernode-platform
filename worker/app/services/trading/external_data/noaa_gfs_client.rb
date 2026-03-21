# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Trading
  module ExternalData
    # NOAA NWS gridpoint forecast client.
    # Fetches raw quantitative gridpoint data (hourly value arrays) for
    # granular probability estimation instead of the human-readable 12-hour periods.
    class NoaaGfsClient < Base
      NWS_BASE_URL = "https://api.weather.gov"

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
        21_600 # 6 hours — matches GFS update cycle
      end

      def fetch_for_market(market_question, metadata = {})
        location = metadata[:location] || metadata["location"]
        return nil unless location

        grid = NoaaGeoResolver.resolve_grid_point(location)
        return nil unless grid

        cache_key = "noaa:#{grid[:office]}:#{grid[:x]}:#{grid[:y]}"

        forecast = cached_fetch(cache_key) do
          fetch_raw_gridpoint(grid[:office], grid[:x], grid[:y])
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

      # Calculate probability of a threshold being exceeded from raw gridpoint data.
      # Uses hourly value arrays (24+ points per day) for much finer granularity
      # than the old 12-hour period approach.
      def calculate_probability(forecast_data, metric:, threshold:, unit: "F", date: nil)
        return nil unless forecast_data && forecast_data[:forecast]

        props = forecast_data[:forecast]["properties"] || {}

        case metric&.downcase
        when "high_temperature", "temperature", "high"
          calculate_temperature_probability(props, threshold, unit, date)
        when "precipitation", "rain"
          calculate_precipitation_probability(props, date)
        when "wind_speed", "wind"
          calculate_wind_probability(props, threshold, unit, date)
        end
      end

      private

      def fetch_raw_gridpoint(office, x, y)
        url = "#{NWS_BASE_URL}/gridpoints/#{office}/#{x},#{y}"
        http_get_json(url)
      end

      def calculate_temperature_probability(props, threshold, unit, date)
        values = extract_values_for_date(props["maxTemperature"] || props["temperature"], date)
        return nil if values.empty?

        threshold_val = threshold.to_f
        # NWS raw gridpoint returns Celsius — convert threshold if needed
        value_unit = (props.dig("maxTemperature", "uom") || props.dig("temperature", "uom") || "").to_s
        if value_unit.include?("degC") && unit&.upcase == "F"
          threshold_val = (threshold_val - 32) * 5.0 / 9.0
        elsif !value_unit.include?("degC") && unit&.upcase == "C"
          threshold_val = threshold_val * 9.0 / 5.0 + 32
        end

        exceeding = values.count { |v| v >= threshold_val }
        exceeding.to_f / values.length
      end

      def calculate_precipitation_probability(props, date)
        values = extract_values_for_date(props["probabilityOfPrecipitation"], date)
        return nil if values.empty?

        # Values are already percentages (0-100)
        values.map { |v| v.to_f }.sum / values.length / 100.0
      end

      def calculate_wind_probability(props, threshold, unit, date)
        values = extract_values_for_date(props["windSpeed"], date)
        return nil if values.empty?

        threshold_val = threshold.to_f
        # NWS raw gridpoint returns km/h
        value_unit = (props.dig("windSpeed", "uom") || "").to_s
        if value_unit.include?("km") && (unit&.downcase == "mph")
          threshold_val = threshold_val * 1.60934
        elsif !value_unit.include?("km") && (unit&.downcase == "kph" || unit&.downcase == "km/h")
          threshold_val = threshold_val / 1.60934
        end

        exceeding = values.count { |v| v >= threshold_val }
        exceeding.to_f / values.length
      end

      # Extract numeric values from a NWS gridpoint property for a target date.
      # NWS raw gridpoint data uses ISO 8601 duration-tagged value arrays.
      def extract_values_for_date(property, date)
        return [] unless property.is_a?(Hash) && property["values"].is_a?(Array)

        target_date = date ? (Date.parse(date.to_s) rescue nil) : nil

        property["values"].filter_map do |entry|
          valid_time = entry["validTime"].to_s
          value = entry["value"]
          next unless value.is_a?(Numeric)

          if target_date
            period_date = Date.parse(valid_time.split("/").first) rescue nil
            next unless period_date == target_date
          end

          value
        end
      rescue
        []
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
