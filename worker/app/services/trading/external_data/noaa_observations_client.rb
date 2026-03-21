# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Trading
  module ExternalData
    # Real-time weather station observations from api.weather.gov.
    # Provides current conditions for calibrating forecast accuracy
    # and anchoring near-term weather markets.
    class NoaaObservationsClient < Base
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
        1800 # 30 minutes — observations update hourly
      end

      def fetch_for_market(market_question, metadata = {})
        location = metadata[:location] || metadata["location"]
        return nil unless location

        coords = NoaaGeoResolver.resolve_coordinates(location)
        return nil unless coords

        cache_key = "obs:#{coords[:lat]}:#{coords[:lon]}"

        cached_fetch(cache_key) do
          fetch_latest_observation(coords[:lat], coords[:lon])
        end
      end

      private

      def fetch_latest_observation(lat, lon)
        # Step 1: Find nearest station
        station_id = find_nearest_station(lat, lon)
        return nil unless station_id

        # Step 2: Get latest observation
        url = "#{NWS_BASE_URL}/stations/#{station_id}/observations/latest"
        data = http_get_json(url)
        return nil unless data

        props = data.dig("properties") || {}

        {
          station_id: station_id,
          observed_temperature_c: props.dig("temperature", "value"),
          observed_wind_speed_kmh: props.dig("windSpeed", "value"),
          observed_precip_mm: props.dig("precipitationLastHour", "value"),
          observed_humidity_pct: props.dig("relativeHumidity", "value"),
          observation_time: props["timestamp"],
          text_description: props["textDescription"],
          source: "noaa_observations",
          freshness_hours: calculate_freshness(props["timestamp"])
        }
      rescue => e
        log("Observation fetch failed: #{e.message}", level: :error)
        nil
      end

      def find_nearest_station(lat, lon)
        url = "#{NWS_BASE_URL}/points/#{lat.round(4)},#{lon.round(4)}/stations"
        data = http_get_json(url)
        return nil unless data

        stations = data.dig("features") || []
        return nil if stations.empty?

        # First station is nearest
        stations.first.dig("properties", "stationIdentifier")
      rescue => e
        log("Station lookup failed: #{e.message}", level: :warn)
        nil
      end

      def calculate_freshness(timestamp)
        return nil unless timestamp
        hours = (Time.now - Time.parse(timestamp)) / 3600.0
        hours.round(1)
      rescue
        nil
      end
    end
  end
end
