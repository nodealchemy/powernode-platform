# frozen_string_literal: true

module Trading
  module ExternalData
    # Single source of truth for NOAA location resolution.
    # All NOAA clients use this module instead of maintaining their own city maps.
    module NoaaGeoResolver
      NWS_POINTS_URL = "https://api.weather.gov/points"

      # City coordinates with NWS grid points pre-resolved.
      # lat/lon for observations + NCEI; office/x/y for GFS gridpoint forecasts.
      CITY_COORDINATES = {
        "new york"      => { lat: 40.7128, lon: -74.0060, office: "OKX", x: 33, y: 37, fips: "36061" },
        "los angeles"   => { lat: 34.0522, lon: -118.2437, office: "LOX", x: 154, y: 44, fips: "06037" },
        "chicago"       => { lat: 41.8781, lon: -87.6298, office: "LOT", x: 65, y: 76, fips: "17031" },
        "houston"       => { lat: 29.7604, lon: -95.3698, office: "HGX", x: 65, y: 97, fips: "48201" },
        "phoenix"       => { lat: 33.4484, lon: -112.0740, office: "PSR", x: 159, y: 57, fips: "04013" },
        "miami"         => { lat: 25.7617, lon: -80.1918, office: "MFL", x: 110, y: 65, fips: "12086" },
        "denver"        => { lat: 39.7392, lon: -104.9903, office: "BOU", x: 62, y: 60, fips: "08031" },
        "seattle"       => { lat: 47.6062, lon: -122.3321, office: "SEW", x: 124, y: 67, fips: "53033" },
        "washington"    => { lat: 38.9072, lon: -77.0369, office: "LWX", x: 97, y: 71, fips: "11001" },
        "atlanta"       => { lat: 33.7490, lon: -84.3880, office: "FFC", x: 50, y: 86, fips: "13121" },
        "boston"         => { lat: 42.3601, lon: -71.0589, office: "BOX", x: 71, y: 90, fips: "25025" },
        "dallas"        => { lat: 32.7767, lon: -96.7970, office: "FWD", x: 80, y: 103, fips: "48113" },
        "san francisco" => { lat: 37.7749, lon: -122.4194, office: "MTR", x: 85, y: 105, fips: "06075" },
        "las vegas"     => { lat: 36.1699, lon: -115.1398, office: "VEF", x: 126, y: 97, fips: "32003" },
        "minneapolis"   => { lat: 44.9778, lon: -93.2650, office: "MPX", x: 107, y: 71, fips: "27053" },
        "detroit"       => { lat: 42.3314, lon: -83.0458, office: "DTX", x: 65, y: 33, fips: "26163" }
      }.freeze

      # Common aliases — map to canonical city names
      ALIASES = {
        "nyc" => "new york", "ny" => "new york",
        "la" => "los angeles",
        "sf" => "san francisco", "san fran" => "san francisco",
        "dc" => "washington", "d.c." => "washington", "washington dc" => "washington",
        "phx" => "phoenix",
        "atl" => "atlanta",
        "bos" => "boston",
        "sea" => "seattle",
        "lv" => "las vegas",
        "mpls" => "minneapolis"
      }.freeze

      module_function

      def normalize_location(location)
        normalized = location.to_s.downcase.strip
        ALIASES[normalized] || normalized
      end

      def resolve_coordinates(location)
        city = CITY_COORDINATES[normalize_location(location)]
        return { lat: city[:lat], lon: city[:lon] } if city

        # Fallback: geocode via NWS points API
        geocode_via_nws(location)
      end

      def resolve_grid_point(location)
        city = CITY_COORDINATES[normalize_location(location)]
        return { office: city[:office], x: city[:x], y: city[:y] } if city

        nil # Unknown city — GFS requires pre-mapped grid points
      end

      def known_location?(location)
        CITY_COORDINATES.key?(normalize_location(location))
      end

      def fips_code(location)
        CITY_COORDINATES.dig(normalize_location(location), :fips)
      end

      def geocode_via_nws(location)
        # NWS points API requires lat,lon — we can't geocode from city name alone.
        # This is a placeholder for when callers provide raw coordinates.
        nil
      end
    end
  end
end
