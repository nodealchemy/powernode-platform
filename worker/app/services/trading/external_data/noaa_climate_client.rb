# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Trading
  module ExternalData
    # NOAA NCEI (National Centers for Environmental Information) climate normals.
    # Provides 30-year historical averages (1991-2020) for base-rate anchoring.
    # Prevents overreaction to single forecasts by establishing climatological context.
    #
    # Requires a free NCEI CDO token: https://www.ncdc.noaa.gov/cdo-web/token
    # Set via ENV["NCEI_CDO_TOKEN"]. Returns nil gracefully when absent.
    class NoaaClimateClient < Base
      NCEI_BASE_URL = "https://www.ncei.noaa.gov/cdo-web/api/v2"

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
        604_800 # 7 days — climate normals are static 30-year averages
      end

      def fetch_for_market(market_question, metadata = {})
        token = ENV["NCEI_CDO_TOKEN"]
        return nil unless token

        location = metadata[:location] || metadata["location"]
        target_date = metadata[:date] || metadata["date"]
        return nil unless location

        coords = NoaaGeoResolver.resolve_coordinates(location)
        return nil unless coords

        # Cache key includes month-day for seasonal relevance
        date_key = target_date ? Date.parse(target_date.to_s).strftime("%m%d") : Date.today.strftime("%m%d")
        cache_key = "ncei:#{coords[:lat].round(1)}:#{coords[:lon].round(1)}:#{date_key}"

        cached_fetch(cache_key) do
          fetch_climate_normals(token, coords, location, target_date)
        end
      rescue => e
        log("NCEI climate fetch failed: #{e.message}", level: :error)
        nil
      end

      private

      def fetch_climate_normals(token, coords, location, target_date)
        fips = NoaaGeoResolver.fips_code(location)
        station = find_climate_station(token, coords, fips)
        return nil unless station

        target = target_date ? Date.parse(target_date.to_s) : Date.today
        month_day = target.strftime("%m-%d")

        normals = fetch_daily_normals(token, station, month_day)
        return nil unless normals

        # Calculate historical exceedance probability from normal distribution
        exceedance = calculate_historical_exceedance(normals, target)

        {
          station_id: station,
          normal_high_f: normals[:normal_high_f],
          normal_low_f: normals[:normal_low_f],
          normal_precip_in: normals[:normal_precip_in],
          historical_exceedance_prob: exceedance,
          climate_period: "1991-2020",
          target_month_day: month_day,
          source: "noaa_ncei",
          freshness_hours: 0.0 # Normals don't age
        }
      end

      def find_climate_station(token, coords, fips)
        # Try FIPS-based lookup first
        if fips
          url = "#{NCEI_BASE_URL}/stations?locationid=FIPS:#{fips}&datasetid=NORMAL_DLY&limit=1"
          data = ncei_get(url, token)
          station_id = data&.dig("results", 0, "id")
          return station_id if station_id
        end

        # Fallback: search by coordinates with extent box
        extent = "#{coords[:lat] - 0.5},#{coords[:lon] - 0.5},#{coords[:lat] + 0.5},#{coords[:lon] + 0.5}"
        url = "#{NCEI_BASE_URL}/stations?datasetid=NORMAL_DLY&extent=#{extent}&limit=1&sortfield=name"
        data = ncei_get(url, token)
        data&.dig("results", 0, "id")
      rescue => e
        log("NCEI station lookup failed: #{e.message}", level: :warn)
        nil
      end

      def fetch_daily_normals(token, station_id, month_day)
        # NCEI daily normals use date range within the normals dataset
        # The date format for normals is 2010-MM-DD (reference year)
        start_date = "2010-#{month_day}"
        end_date = start_date

        url = "#{NCEI_BASE_URL}/data?datasetid=NORMAL_DLY&stationid=#{station_id}" \
              "&startdate=#{start_date}&enddate=#{end_date}" \
              "&datatypeid=DLY-TMAX-NORMAL,DLY-TMIN-NORMAL,DLY-PRCP-PCTALL-GE001HI" \
              "&units=standard&limit=10"
        data = ncei_get(url, token)
        return nil unless data && data["results"]

        results = data["results"]
        high = results.find { |r| r["datatype"] == "DLY-TMAX-NORMAL" }
        low = results.find { |r| r["datatype"] == "DLY-TMIN-NORMAL" }
        precip = results.find { |r| r["datatype"] == "DLY-PRCP-PCTALL-GE001HI" }

        {
          normal_high_f: high ? high["value"].to_f / 10.0 : nil, # Tenths of degrees
          normal_low_f: low ? low["value"].to_f / 10.0 : nil,
          normal_precip_in: precip ? precip["value"].to_f / 10.0 : nil # Tenths of inches
        }
      rescue => e
        log("NCEI daily normals fetch failed: #{e.message}", level: :warn)
        nil
      end

      def calculate_historical_exceedance(normals, target)
        # Approximate exceedance using normal distribution assumption.
        # Standard deviation of daily temps is roughly 8-12°F depending on location/season.
        # This gives a rough base-rate probability.
        return nil unless normals[:normal_high_f]

        # Return the normal high as the expected value — evaluator uses this
        # to calculate how likely a threshold exceedance is historically.
        {
          expected_high_f: normals[:normal_high_f],
          expected_low_f: normals[:normal_low_f],
          daily_temp_std_f: 8.0 # Conservative estimate
        }
      end

      def ncei_get(url, token)
        http_get_json(url, headers: { "token" => token })
      end
    end
  end
end
