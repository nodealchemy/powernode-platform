/**
 * Source type display name mapping.
 * Used across DataSourceCard, DataSourceDetailModal, DataSourceFilters, and CreateDataSourceModal.
 */
export const SOURCE_TYPE_LABELS: Record<string, string> = {
  noaa_ncei: 'NOAA Climate (NCEI)',
  noaa_gfs: 'NOAA GFS Forecasts',
  noaa_observations: 'NOAA Observations',
  open_meteo: 'Open-Meteo',
  custom: 'Custom API',
};

/**
 * All available source types for select dropdowns.
 */
export const SOURCE_TYPE_OPTIONS = Object.entries(SOURCE_TYPE_LABELS).map(([value, label]) => ({
  value,
  label,
}));

/**
 * Presets for each source type — pre-fills the creation form with accurate
 * API endpoints, rate limits, capabilities, and configuration.
 * Rate limits are based on documented API policies as of April 2026.
 */
export interface SourceTypePreset {
  description: string;
  api_base_url: string;
  documentation_url: string;
  requires_auth: boolean;
  auth_instructions?: string;
  capabilities: string[];
  rate_limits: { requests_per_minute?: number; requests_per_hour?: number; requests_per_day?: number };
}

export const SOURCE_TYPE_PRESETS: Record<string, SourceTypePreset> = {
  noaa_ncei: {
    description: 'NOAA Climate Data Online — historical climate data, 30-year normals, daily/monthly summaries. Global coverage from 1763 to present.',
    api_base_url: 'https://www.ncei.noaa.gov/cdo-web/api/v2',
    documentation_url: 'https://www.ncdc.noaa.gov/cdo-web/webservices/v2',
    requires_auth: true,
    auth_instructions: 'Free token from https://www.ncdc.noaa.gov/cdo-web/token — delivered via email instantly. Enter token as the API Key in credentials.',
    capabilities: ['historical_weather', 'climate_normals', 'station_metadata', 'daily_summaries', 'monthly_summaries'],
    rate_limits: { requests_per_minute: 300, requests_per_hour: 10000, requests_per_day: 10000 },
  },
  noaa_gfs: {
    description: 'NOAA Global Forecast System — global weather forecasts at 0.25° resolution. Runs 4x daily (00z/06z/12z/18z), 384-hour horizon, 31-member ensemble.',
    api_base_url: 'https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl',
    documentation_url: 'https://www.nco.ncep.noaa.gov/pmb/products/gfs/',
    requires_auth: false,
    capabilities: ['weather_forecast', 'global_model', 'ensemble_forecast', 'atmospheric_data', 'surface_data'],
    rate_limits: { requests_per_minute: 60, requests_per_hour: 1800, requests_per_day: 20000 },
  },
  noaa_observations: {
    description: 'NOAA Weather.gov API — real-time observations, 7-day forecasts, and active alerts for US locations. Requires User-Agent header.',
    api_base_url: 'https://api.weather.gov',
    documentation_url: 'https://weather-gov.github.io/api/general-faqs',
    requires_auth: false,
    auth_instructions: 'No API key needed. A User-Agent header is required and auto-configured.',
    capabilities: ['current_observations', 'point_forecast', 'hourly_forecast', 'weather_alerts', 'gridpoint_data'],
    rate_limits: { requests_per_minute: 60, requests_per_hour: 3600, requests_per_day: 50000 },
  },
  open_meteo: {
    description: 'Open-Meteo — free global weather API with GFS, ECMWF, ICON, and GEM models. Hourly/daily forecasts, ensemble data, air quality, and marine.',
    api_base_url: 'https://api.open-meteo.com/v1',
    documentation_url: 'https://open-meteo.com/en/docs',
    requires_auth: false,
    auth_instructions: 'Free tier: no key needed (non-commercial use, CC BY 4.0). Paid tier uses API key for higher limits.',
    capabilities: ['weather_forecast', 'ensemble_forecast', 'historical_weather', 'current_weather', 'air_quality', 'marine_forecast'],
    rate_limits: { requests_per_minute: 600, requests_per_hour: 5000, requests_per_day: 10000 },
  },
  custom: {
    description: '',
    api_base_url: '',
    documentation_url: '',
    requires_auth: false,
    capabilities: [],
    rate_limits: {},
  },
};
