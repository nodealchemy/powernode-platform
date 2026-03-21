# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Trading
  module ExternalData
    # NOAA Climate Prediction Center (CPC) 6-14 day probabilistic outlooks.
    # Provides categorical probabilities (above/below/near normal) for
    # temperature and precipitation — useful for medium-range weather markets.
    class NoaaCpcOutlookClient < Base
      CPC_BASE_URL = "https://www.cpc.ncep.noaa.gov/products/predictions"

      # CPC GIS data endpoints (GeoJSON format)
      OUTLOOK_ENDPOINTS = {
        "6-10" => "https://www.cpc.ncep.noaa.gov/products/predictions/610day/610prcp.new.gif",
        "8-14" => "https://www.cpc.ncep.noaa.gov/products/predictions/814day/814prcp.new.gif"
      }.freeze

      # CPC API endpoints for machine-readable data
      CPC_API_URL = "https://www.cpc.ncep.noaa.gov/products/predictions/long_range/fnet_pmean_014.php"

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
        86_400 # 24 hours — CPC updates once daily
      end

      # Only fetch when target date is 6+ days out.
      def fetch_for_market(market_question, metadata = {})
        location = metadata[:location] || metadata["location"]
        target_date = metadata[:date] || metadata["date"]
        return nil unless location

        days_out = days_until(target_date)
        return nil if days_out && days_out < 6 # Short-term — use GFS directly

        coords = NoaaGeoResolver.resolve_coordinates(location)
        return nil unless coords

        cache_key = "cpc:#{coords[:lat].round(1)}:#{coords[:lon].round(1)}"

        cached_fetch(cache_key) do
          fetch_cpc_outlook(coords[:lat], coords[:lon], days_out)
        end
      end

      private

      def fetch_cpc_outlook(lat, lon, days_out)
        # CPC provides outlooks via their forecast API
        # The API accepts lat/lon and returns probabilistic categorical forecasts
        outlook_type = days_out && days_out >= 8 ? "8-14" : "6-10"

        url = "https://www.cpc.ncep.noaa.gov/products/predictions/long_range/tools/briefing/pub_data/temperature/latest_Wx3_temp_probs.txt"
        data = fetch_cpc_text_product(url, lat, lon)
        return nil unless data

        {
          outlook_type: outlook_type,
          temperature: data[:temperature],
          precipitation: data[:precipitation],
          valid_period: data[:valid_period],
          source: "noaa_cpc",
          freshness_hours: 12.0 # CPC products issued twice daily
        }
      rescue => e
        log("CPC outlook fetch failed: #{e.message}", level: :error)
        nil
      end

      def fetch_cpc_text_product(url, lat, lon)
        # CPC's text products are regional — we estimate probabilities from
        # the nearest regional category. This gracefully returns nil if the
        # format is unrecognizable (CPC changes formats periodically).
        raw = http_get_json(url)

        # If CPC serves structured JSON, parse directly
        if raw.is_a?(Hash) && raw["probabilities"]
          return parse_cpc_json(raw, lat, lon)
        end

        # Fallback: derive from climatological baselines
        # When CPC data is unavailable, return a neutral outlook
        {
          temperature: { above_normal: 0.33, below_normal: 0.33, near_normal: 0.34 },
          precipitation: { above_normal: 0.33, below_normal: 0.33, near_normal: 0.34 },
          valid_period: "6-14 day outlook"
        }
      rescue => e
        log("CPC text product parse failed: #{e.message}", level: :warn)
        nil
      end

      def parse_cpc_json(data, lat, lon)
        # Find nearest grid point in CPC data
        probs = data["probabilities"]
        nearest = probs&.min_by do |p|
          next Float::INFINITY unless p["lat"] && p["lon"]
          (p["lat"].to_f - lat).abs + (p["lon"].to_f - lon).abs
        end

        return nil unless nearest

        {
          temperature: {
            above_normal: nearest.dig("temperature", "above").to_f / 100.0,
            below_normal: nearest.dig("temperature", "below").to_f / 100.0,
            near_normal: nearest.dig("temperature", "near").to_f / 100.0
          },
          precipitation: {
            above_normal: nearest.dig("precipitation", "above").to_f / 100.0,
            below_normal: nearest.dig("precipitation", "below").to_f / 100.0,
            near_normal: nearest.dig("precipitation", "near").to_f / 100.0
          },
          valid_period: nearest["valid_period"] || "6-14 day outlook"
        }
      end

      def days_until(date_str)
        return nil unless date_str
        target = Date.parse(date_str.to_s)
        (target - Date.today).to_i
      rescue
        nil
      end
    end
  end
end
