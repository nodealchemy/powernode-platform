# frozen_string_literal: true

# AI Data Sources Seed Data
# Creates default external data API sources for weather and financial data

puts "\n🌐 Creating AI Data Sources..."

admin_account = Account.find_by(name: "Powernode Admin")

unless admin_account
  puts "⚠️  Admin account not found, skipping data source seeding"
  return
end

puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"

def create_or_find_data_source(account, attrs)
  ds = account.ai_data_sources.find_by(slug: attrs[:slug])
  if ds
    puts "⏭️  Data source already exists: #{attrs[:name]}"
    return ds
  end

  puts "📡 Creating data source: #{attrs[:name]}"
  account.ai_data_sources.create!(attrs)
end

# =============================================================================
# 1. NOAA NCEI - Climate Data Online (CDO)
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "NOAA NCEI",
  slug: "noaa-ncei",
  source_type: "noaa_ncei",
  description: "NOAA National Centers for Environmental Information (NCEI) Climate Data Online. " \
               "Provides access to historical climate and weather data including daily summaries, " \
               "normals, and station metadata. Requires a free CDO API token.",
  api_base_url: "https://www.ncdc.noaa.gov/cdo-web/api/v2",
  requires_auth: true,
  is_active: true,
  priority_order: 100,
  documentation_url: "https://www.ncdc.noaa.gov/cdo-web/webservices/v2",
  capabilities: %w[
    historical_weather
    climate_normals
    station_metadata
    daily_summaries
    monthly_summaries
    annual_summaries
  ],
  rate_limits: {
    "requests_per_second" => 5,
    "requests_per_minute" => 300,
    "requests_per_day" => 10_000
  },
  default_parameters: {
    "units" => "metric",
    "limit" => 1000,
    "max_results" => 1000,
    "date_range_limit_years" => 10
  },
  configuration: {
    "auth_header" => "token",
    "auth_type" => "header_token",
    "response_format" => "json",
    "pagination" => "offset",
    "token_request_url" => "https://www.ncdc.noaa.gov/cdo-web/token",
    "available_datasets" => %w[GHCND GSOM GSOY NORMAL_DLY NORMAL_MLY NORMAL_ANN],
    "notes" => "Annual/monthly data limited to 10-year range; all other data limited to 1-year range per request"
  },
  metadata: {
    "provider" => "NOAA NCEI",
    "data_coverage" => "Global historical weather records (1763-present)",
    "update_frequency" => "Daily",
    "token_info" => "Free token from https://www.ncdc.noaa.gov/cdo-web/token — instant email delivery"
  }
})

# =============================================================================
# 2. NOAA GFS - Global Forecast System
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "NOAA GFS",
  slug: "noaa-gfs",
  source_type: "noaa_gfs",
  description: "NOAA Global Forecast System (GFS) via NOMADS. Provides global weather forecast " \
               "data at 0.25-degree resolution, running 4 times daily with forecasts out to 384 hours. " \
               "No authentication required.",
  api_base_url: "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl",
  requires_auth: false,
  is_active: true,
  priority_order: 200,
  documentation_url: "https://www.nco.ncep.noaa.gov/pmb/products/gfs/",
  capabilities: %w[
    weather_forecast
    global_model
    atmospheric_data
    surface_data
    pressure_levels
    ensemble_forecast
  ],
  rate_limits: {
    "requests_per_minute" => 60,
    "requests_per_hour" => 1800,
    "requests_per_day" => 20_000
  },
  default_parameters: {
    "resolution" => "0p25",
    "format" => "grib2",
    "model_cycle" => "00"
  },
  configuration: {
    "auth_type" => "none",
    "response_format" => "grib2",
    "model_runs" => %w[00 06 12 18],
    "forecast_hours" => 384,
    "ensemble_members" => 31,
    "grid_resolution_deg" => 0.25,
    "notes" => "GFS runs 4x daily. GEFS ensemble (31 members) available via NOMADS. No auth required but be respectful of server load."
  },
  metadata: {
    "provider" => "NOAA NCEP",
    "data_coverage" => "Global forecast 0.25-degree grid, 384-hour horizon",
    "update_frequency" => "Every 6 hours (00z, 06z, 12z, 18z)"
  }
})

# =============================================================================
# 3. NOAA Weather Observations (Weather.gov API)
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "NOAA Observations",
  slug: "noaa-observations",
  source_type: "noaa_observations",
  description: "NOAA Weather.gov API for real-time weather observations, forecasts, and alerts. " \
               "Provides current conditions from US weather stations, 7-day forecasts, and active " \
               "weather alerts. No authentication required but a User-Agent header is expected.",
  api_base_url: "https://api.weather.gov",
  requires_auth: false,
  is_active: true,
  priority_order: 300,
  documentation_url: "https://weather-gov.github.io/api/general-faqs",
  capabilities: %w[
    current_observations
    point_forecast
    hourly_forecast
    weather_alerts
    station_metadata
    gridpoint_data
  ],
  rate_limits: {
    "requests_per_second" => 1,
    "requests_per_minute" => 60,
    "requests_per_hour" => 3600
  },
  default_parameters: {
    "units" => "us"
  },
  configuration: {
    "auth_type" => "user_agent",
    "response_format" => "geojson",
    "required_headers" => {
      "User-Agent" => "(Powernode Trading Platform, +https://github.com/nodealchemy/powernode-platform)"
    },
    "key_endpoints" => {
      "points" => "/points/{lat},{lon}",
      "forecast" => "/gridpoints/{office}/{x},{y}/forecast",
      "hourly" => "/gridpoints/{office}/{x},{y}/forecast/hourly",
      "observations" => "/stations/{station}/observations/latest",
      "alerts" => "/alerts/active"
    },
    "notes" => "No API key required. User-Agent header is mandatory. Official recommendation: max 1 request/sec. Exact rate limit unpublished."
  },
  metadata: {
    "provider" => "NOAA NWS",
    "data_coverage" => "United States — real-time observations, 7-day forecasts, active alerts",
    "update_frequency" => "Observations hourly, forecasts every 1-6 hours"
  }
})

# =============================================================================
# 4. Open-Meteo - Free Weather API
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "Open-Meteo",
  slug: "open-meteo",
  source_type: "open_meteo",
  description: "Open-Meteo provides free weather forecast APIs with access to multiple weather " \
               "models including ECMWF, GFS, and regional models. Offers current weather, hourly " \
               "and daily forecasts, and historical data. No API key required for free tier.",
  api_base_url: "https://api.open-meteo.com/v1",
  requires_auth: false,
  is_active: true,
  priority_order: 400,
  documentation_url: "https://open-meteo.com/en/docs",
  capabilities: %w[
    weather_forecast
    historical_weather
    current_weather
    hourly_forecast
    daily_forecast
    ensemble_forecast
    marine_forecast
    air_quality
    geocoding
  ],
  rate_limits: {
    "requests_per_minute" => 600,
    "requests_per_hour" => 5_000,
    "requests_per_day" => 10_000
  },
  default_parameters: {
    "temperature_unit" => "celsius",
    "windspeed_unit" => "kmh",
    "precipitation_unit" => "mm",
    "timezone" => "auto"
  },
  configuration: {
    "auth_type" => "none",
    "response_format" => "json",
    "endpoints" => {
      "forecast" => "/forecast",
      "ensemble" => "/ensemble",
      "historical" => "/archive",
      "marine" => "/marine",
      "air_quality" => "/air-quality",
      "geocoding" => "https://geocoding-api.open-meteo.com/v1/search"
    },
    "ensemble_models" => %w[gfs_seamless icon_seamless gem_global ecmwf_ifs025],
    "notes" => "Free tier: 10K/day, 5K/hour, 600/min. Non-commercial only. Ensemble + historical require paid tier. CC BY 4.0 attribution required."
  },
  metadata: {
    "provider" => "Open-Meteo",
    "data_coverage" => "Global weather forecasts from GFS, ECMWF, ICON, GEM + regional models",
    "update_frequency" => "Hourly",
    "license" => "CC BY 4.0 (attribution required)",
    "paid_url" => "https://open-meteo.com/en/pricing"
  }
})

# =============================================================================
# 5. FRED - Federal Reserve Economic Data
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "FRED",
  slug: "fred",
  source_type: "fred",
  description: "Federal Reserve Economic Data (FRED) from the St. Louis Fed. " \
               "Provides access to 800,000+ economic time series including CPI, " \
               "Fed Funds Rate, GDP, unemployment, PCE, and producer prices. " \
               "Requires a free API key.",
  api_base_url: "https://api.stlouisfed.org/fred",
  requires_auth: true,
  is_active: true,
  priority_order: 500,
  documentation_url: "https://fred.stlouisfed.org/docs/api/fred/",
  capabilities: %w[
    economic_indicators
    release_calendar
    series_search
    observations
    categories
  ],
  rate_limits: {
    "requests_per_minute" => 120,
    "requests_per_day" => 10_000
  },
  default_parameters: {
    "file_type" => "json"
  },
  configuration: {
    "auth_type" => "query_param",
    "auth_param" => "api_key",
    "response_format" => "json",
    "key_series" => {
      "CPIAUCSL" => "CPI-U All Urban Consumers",
      "FEDFUNDS" => "Federal Funds Rate",
      "GDP" => "Gross Domestic Product",
      "UNRATE" => "Unemployment Rate",
      "PAYEMS" => "Non-Farm Payrolls",
      "PCEPI" => "PCE Price Index",
      "PPIACO" => "Producer Price Index"
    },
    "notes" => "Free API key from https://fred.stlouisfed.org/docs/api/api_key.html — instant delivery."
  },
  metadata: {
    "provider" => "Federal Reserve Bank of St. Louis",
    "data_coverage" => "800K+ US economic time series (1776-present)",
    "update_frequency" => "Varies by series (monthly, quarterly, etc.)",
    "license" => "Public domain"
  }
})

# =============================================================================
# 6. Yahoo Finance - Financial Spot Prices
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "Yahoo Finance",
  slug: "yahoo-finance",
  source_type: "yahoo_finance",
  description: "Yahoo Finance public API for real-time and historical financial data. " \
               "Provides spot prices, charts, and quotes for equities, commodities, " \
               "indices, and currencies. No API key required.",
  api_base_url: "https://query1.finance.yahoo.com/v8/finance",
  requires_auth: false,
  is_active: true,
  priority_order: 600,
  documentation_url: "https://finance.yahoo.com",
  capabilities: %w[
    spot_price
    quote
    chart
    historical_data
  ],
  rate_limits: {
    "requests_per_minute" => 60,
    "requests_per_hour" => 2000
  },
  default_parameters: {},
  configuration: {
    "auth_type" => "none",
    "response_format" => "json",
    "key_symbols" => {
      "WTI" => "CL=F",
      "SP500" => "^GSPC",
      "DOW" => "^DJI",
      "NASDAQ" => "^IXIC",
      "GOLD" => "GC=F",
      "SILVER" => "SI=F"
    },
    "notes" => "Public API, no key required. Rate limits are unofficial — be respectful."
  },
  metadata: {
    "provider" => "Yahoo Finance",
    "data_coverage" => "Global equities, commodities, indices, currencies",
    "update_frequency" => "Real-time during market hours, 15-min delay for some data"
  }
})

# =============================================================================
# 7. ESPN - Sports Data
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "ESPN",
  slug: "espn",
  source_type: "espn",
  description: "ESPN public API for US major sports leagues. Provides standings, " \
               "scores, schedules, and team statistics for NBA, NHL, MLB, and NFL. " \
               "No API key required.",
  api_base_url: "https://site.api.espn.com/apis/site/v2/sports",
  requires_auth: false,
  is_active: true,
  priority_order: 700,
  documentation_url: "https://site.api.espn.com",
  capabilities: %w[
    standings
    scores
    schedule
    team_stats
    player_stats
  ],
  rate_limits: {
    "requests_per_minute" => 30,
    "requests_per_hour" => 500
  },
  default_parameters: {},
  configuration: {
    "auth_type" => "none",
    "response_format" => "json",
    "leagues" => {
      "NBA" => "basketball/nba",
      "NHL" => "hockey/nhl",
      "MLB" => "baseball/mlb",
      "NFL" => "football/nfl"
    },
    "notes" => "Public API, no key required. Unofficial — endpoints may change."
  },
  metadata: {
    "provider" => "ESPN",
    "data_coverage" => "NBA, NHL, MLB, NFL — standings, scores, schedules",
    "update_frequency" => "Real-time during games"
  }
})

# =============================================================================
# 8. NewsAPI - News Headlines
# =============================================================================
create_or_find_data_source(admin_account, {
  name: "NewsAPI",
  slug: "newsapi",
  source_type: "newsapi",
  description: "NewsAPI provides real-time and historical news article search across " \
               "80,000+ sources worldwide. Useful for event-driven market analysis, " \
               "IPO tracking, and sentiment context. Requires a free API key.",
  api_base_url: "https://newsapi.org/v2",
  requires_auth: true,
  is_active: true,
  priority_order: 800,
  documentation_url: "https://newsapi.org/docs",
  capabilities: %w[
    top_headlines
    everything
    sources
  ],
  rate_limits: {
    "requests_per_day" => 100
  },
  default_parameters: {
    "language" => "en",
    "sortBy" => "publishedAt"
  },
  configuration: {
    "auth_type" => "header",
    "auth_header" => "X-Api-Key",
    "response_format" => "json",
    "notes" => "Free tier: 100 requests/day. Developer plan ($449/mo) for production use. Register at https://newsapi.org/register."
  },
  metadata: {
    "provider" => "NewsAPI",
    "data_coverage" => "80K+ global news sources, articles searchable by keyword/date/source",
    "update_frequency" => "Real-time",
    "license" => "Free for development, paid for production"
  }
})

puts "✅ AI Data Sources seeded: #{admin_account.ai_data_sources.count} total"
