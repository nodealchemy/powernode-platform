# Sample Marketplace App Seed Data
# Creates a comprehensive sample app for the Powernode Marketplace

puts "🚀 Creating Sample Marketplace App..."

# Find or create a sample account (use existing admin account)
account = Account.find_by(name: "Powernode Platform") || Account.first
unless account
  puts "❌ No accounts found. Please create an account first."
  return
end

puts "📋 Using account: #{account.name}"

# Create the sample app
app = App.find_or_initialize_by(slug: "weather-insights-api") do |a|
  a.account_id = account.id
  a.name = "Weather Insights API"
  a.description = "Professional weather data API with forecasts, alerts, and historical data"
  a.long_description = <<~DESC
    # Weather Insights API

    Get access to comprehensive weather data for your applications with our professional Weather Insights API.#{' '}
    Perfect for businesses, developers, and researchers who need reliable weather information.

    ## Key Features
    - **Real-time Weather Data**: Current conditions for any location worldwide
    - **7-Day Forecasts**: Detailed predictions with hourly breakdowns
    - **Weather Alerts**: Severe weather warnings and notifications
    - **Historical Data**: Access to weather history and trends
    - **Multiple Data Formats**: JSON, XML, and CSV support
    - **Global Coverage**: 200+ countries and territories

    ## Use Cases
    - **E-commerce**: Weather-based product recommendations
    - **Logistics**: Route optimization based on weather conditions
    - **Agriculture**: Crop planning and irrigation management
    - **Events**: Outdoor event planning and management
    - **Tourism**: Travel recommendations and planning
    - **Construction**: Project scheduling and safety planning

    ## Data Quality
    Our weather data is sourced from over 40,000 weather stations, satellites, and weather models worldwide.#{' '}
    We provide enterprise-grade reliability with 99.9% uptime SLA and data accuracy guarantees.

    ## Getting Started
    1. Subscribe to a plan
    2. Get your API key from the dashboard
    3. Start making requests to our endpoints
    4. Monitor your usage and analytics

    ## Support
    - 24/7 technical support for Pro and Enterprise plans
    - Comprehensive documentation and code examples
    - Active developer community and forums
    - Professional services for custom integrations
  DESC
  a.category = "data-apis"
  a.version = "2.1.0"
  a.status = "published"
  a.published_at = 2.months.ago
  a.metadata = {
    "author" => "WeatherTech Solutions",
    "website" => "https://weathertech.example.com",
    "license" => "Commercial",
    "supported_regions" => [ "global" ],
    "data_retention" => "5 years",
    "update_frequency" => "Every 15 minutes",
    "accuracy_sla" => "98.5%",
    "uptime_sla" => "99.9%"
  }
  a.configuration = {
    "api_version" => "v2",
    "base_url" => "https://api.weathertech.example.com/v2",
    "rate_limits" => {
      "default" => "1000 requests/hour",
      "burst" => "100 requests/minute"
    },
    "supported_formats" => [ "json", "xml", "csv" ],
    "authentication" => {
      "type" => "api_key",
      "header" => "X-API-Key"
    },
    "caching" => {
      "enabled" => true,
      "ttl" => 900
    }
  }
end

if app.persisted?
  puts "📱 Found existing app: #{app.name}"
else
  app.save!
  puts "✅ Created sample app: #{app.name} (#{app.id})"
end

# Create marketplace listing
listing = MarketplaceListing.find_or_initialize_by(app_id: app.id) do |l|
  l.title = "Weather Insights API - Professional Weather Data"
  l.short_description = "Comprehensive weather API with real-time data, forecasts, alerts, and historical information for 200+ countries worldwide."
  l.long_description = app.long_description
  l.category = "data-apis"
  l.tags = [
    "weather", "forecast", "api", "data", "analytics", "alerts", "climate",
    "meteorology", "real-time", "historical", "global", "professional"
  ]
  l.screenshots = [
    "https://cdn.weathertech.example.com/screenshots/dashboard.png",
    "https://cdn.weathertech.example.com/screenshots/api-response.png",
    "https://cdn.weathertech.example.com/screenshots/analytics.png"
  ]
  l.documentation_url = "https://docs.weathertech.example.com/api"
  l.support_url = "https://support.weathertech.example.com"
  l.homepage_url = "https://weathertech.example.com"
  l.featured = true
  l.review_status = "approved"
  l.published_at = 2.months.ago
end

if listing.persisted?
  puts "📋 Found existing marketplace listing"
else
  listing.save!
  puts "✅ Created marketplace listing"
end

# Create app endpoints
endpoints_data = [
  {
    name: "Current Weather",
    slug: "current-weather",
    description: "Get current weather conditions for any location",
    http_method: "GET",
    path: "/current",
    request_schema: {
      type: "object",
      properties: {
        location: { type: "string", description: "City name, coordinates, or location ID" },
        units: { type: "string", enum: [ "metric", "imperial", "kelvin" ], default: "metric" },
        lang: { type: "string", description: "Language for weather descriptions", default: "en" }
      },
      required: [ "location" ]
    }.to_json,
    response_schema: {
      type: "object",
      properties: {
        location: {
          type: "object",
          properties: {
            name: { type: "string" },
            country: { type: "string" },
            coordinates: {
              type: "object",
              properties: {
                lat: { type: "number" },
                lon: { type: "number" }
              }
            }
          }
        },
        weather: {
          type: "object",
          properties: {
            temperature: { type: "number" },
            feels_like: { type: "number" },
            humidity: { type: "integer" },
            pressure: { type: "number" },
            visibility: { type: "number" },
            uv_index: { type: "number" },
            condition: { type: "string" },
            description: { type: "string" },
            wind: {
              type: "object",
              properties: {
                speed: { type: "number" },
                direction: { type: "integer" },
                gust: { type: "number" }
              }
            }
          }
        },
        timestamp: { type: "string", format: "date-time" }
      }
    }.to_json,
    parameters: {
      "location" => {
        "type" => "string",
        "required" => true,
        "description" => "Location to get weather for (city, coordinates, etc.)"
      },
      "units" => {
        "type" => "string",
        "required" => false,
        "description" => "Temperature units (metric, imperial, kelvin)"
      }
    },
    rate_limits: { "requests_per_minute" => 60, "requests_per_hour" => 1000 },
    is_public: true,
    is_active: true
  },
  {
    name: "7-Day Forecast",
    slug: "forecast",
    description: "Get detailed 7-day weather forecast",
    http_method: "GET",
    path: "/forecast",
    request_schema: {
      type: "object",
      properties: {
        location: { type: "string", description: "Location identifier" },
        days: { type: "integer", minimum: 1, maximum: 7, default: 7 },
        hourly: { type: "boolean", default: false },
        units: { type: "string", enum: [ "metric", "imperial" ], default: "metric" }
      },
      required: [ "location" ]
    }.to_json,
    response_schema: {
      type: "object",
      properties: {
        location: { type: "object" },
        forecast: {
          type: "array",
          items: {
            type: "object",
            properties: {
              date: { type: "string", format: "date" },
              temperature: {
                type: "object",
                properties: {
                  min: { type: "number" },
                  max: { type: "number" }
                }
              },
              condition: { type: "string" },
              precipitation: { type: "number" },
              wind: { type: "object" }
            }
          }
        }
      }
    }.to_json,
    rate_limits: { "requests_per_minute" => 30, "requests_per_hour" => 500 },
    is_active: true
  },
  {
    name: "Weather Alerts",
    slug: "alerts",
    description: "Get severe weather alerts and warnings",
    http_method: "GET",
    path: "/alerts",
    request_schema: {
      type: "object",
      properties: {
        location: { type: "string" },
        severity: { type: "string", enum: [ "minor", "moderate", "severe", "extreme" ] },
        active_only: { type: "boolean", default: true }
      },
      required: [ "location" ]
    }.to_json,
    response_schema: {
      type: "object",
      properties: {
        alerts: {
          type: "array",
          items: {
            type: "object",
            properties: {
              id: { type: "string" },
              title: { type: "string" },
              description: { type: "string" },
              severity: { type: "string" },
              start_time: { type: "string", format: "date-time" },
              end_time: { type: "string", format: "date-time" },
              areas: { type: "array", items: { type: "string" } }
            }
          }
        }
      }
    }.to_json,
    rate_limits: { "requests_per_minute" => 20, "requests_per_hour" => 300 },
    is_active: true
  },
  {
    name: "Historical Weather",
    slug: "historical",
    description: "Access historical weather data",
    http_method: "GET",
    path: "/historical",
    request_schema: {
      type: "object",
      properties: {
        location: { type: "string" },
        start_date: { type: "string", format: "date" },
        end_date: { type: "string", format: "date" },
        aggregation: { type: "string", enum: [ "daily", "monthly", "yearly" ], default: "daily" }
      },
      required: [ "location", "start_date", "end_date" ]
    }.to_json,
    response_schema: {
      type: "object",
      properties: {
        location: { type: "object" },
        data: {
          type: "array",
          items: {
            type: "object",
            properties: {
              date: { type: "string", format: "date" },
              temperature: { type: "object" },
              precipitation: { type: "number" },
              conditions: { type: "array" }
            }
          }
        }
      }
    }.to_json,
    rate_limits: { "requests_per_minute" => 10, "requests_per_hour" => 100 },
    requires_auth: true,
    is_active: true
  }
]

endpoints_data.each do |endpoint_data|
  endpoint = AppEndpoint.find_or_initialize_by(
    app_id: app.id,
    slug: endpoint_data[:slug]
  ) do |e|
    e.name = endpoint_data[:name]
    e.description = endpoint_data[:description]
    e.http_method = endpoint_data[:http_method]
    e.path = endpoint_data[:path]
    e.request_schema = endpoint_data[:request_schema]
    e.response_schema = endpoint_data[:response_schema]
    e.parameters = endpoint_data[:parameters] || {}
    e.rate_limits = endpoint_data[:rate_limits] || {}
    e.requires_auth = endpoint_data.fetch(:requires_auth, true)
    e.is_public = endpoint_data.fetch(:is_public, false)
    e.is_active = endpoint_data.fetch(:is_active, true)
    e.version = "v2"
  end

  if endpoint.persisted?
    puts "🔌 Found existing endpoint: #{endpoint.name}"
  else
    endpoint.save!
    puts "✅ Created endpoint: #{endpoint.name}"
  end
end

# Create webhooks
webhooks_data = [
  {
    name: "Weather Alert Notifications",
    slug: "weather-alerts",
    description: "Receive notifications when severe weather alerts are issued",
    event_type: "weather.alert.issued",
    is_active: true,
    url: "https://api.example.com/webhooks/weather-alerts",
    payload_template: {
      "event_type" => "weather.alert.issued",
      "alert" => {
        "id" => "{{alert.id}}",
        "location" => "{{alert.location}}",
        "severity" => "{{alert.severity}}",
        "title" => "{{alert.title}}",
        "description" => "{{alert.description}}",
        "start_time" => "{{alert.start_time}}",
        "end_time" => "{{alert.end_time}}"
      },
      "timestamp" => "{{timestamp}}"
    },
    retry_config: { "max_attempts" => 5, "backoff_factor" => 2 }
  },
  {
    name: "Daily Weather Summary",
    slug: "daily-summary",
    description: "Daily weather summary for subscribed locations",
    event_type: "weather.daily_summary",
    is_active: true,
    url: "https://api.example.com/webhooks/daily-summary",
    payload_template: {
      "event_type" => "weather.daily_summary",
      "location" => "{{location}}",
      "date" => "{{date}}",
      "summary" => {
        "temperature" => "{{summary.temperature}}",
        "conditions" => "{{summary.conditions}}",
        "precipitation" => "{{summary.precipitation}}",
        "notable_events" => "{{summary.notable_events}}"
      }
    },
    retry_config: { "max_attempts" => 3, "backoff_factor" => 1.5 }
  },
  {
    name: "API Usage Threshold",
    slug: "usage-threshold",
    description: "Notification when API usage reaches specified thresholds",
    event_type: "usage.threshold_reached",
    is_active: true,
    url: "https://api.example.com/webhooks/usage-threshold",
    payload_template: {
      "event_type" => "usage.threshold_reached",
      "subscription_id" => "{{subscription_id}}",
      "threshold_percentage" => "{{threshold_percentage}}",
      "current_usage" => "{{current_usage}}",
      "plan_limit" => "{{plan_limit}}",
      "reset_date" => "{{reset_date}}"
    },
    retry_config: { "max_attempts" => 3, "backoff_factor" => 2 }
  }
]

webhooks_data.each do |webhook_data|
  webhook = AppWebhook.find_or_initialize_by(
    app_id: app.id,
    slug: webhook_data[:slug]
  ) do |w|
    w.name = webhook_data[:name]
    w.description = webhook_data[:description]
    w.event_type = webhook_data[:event_type]
    w.url = webhook_data[:url]
    w.payload_template = webhook_data[:payload_template]
    w.is_active = webhook_data[:is_active]
    w.retry_config = webhook_data[:retry_config] || {}
    w.timeout_seconds = 30
    w.max_retries = 5
    w.content_type = "application/json"
    w.metadata = {
      "delivery_method" => "http_post",
      "timeout_seconds" => 30
    }
  end

  if webhook.persisted?
    puts "📡 Found existing webhook: #{webhook.name}"
  else
    webhook.save!
    puts "✅ Created webhook: #{webhook.name}"
  end
end

# Create app plans
plans_data = [
  {
    name: "Starter",
    slug: "starter",
    description: "Perfect for personal projects and small applications",
    price_cents: 0,
    billing_interval: "monthly",
    is_active: true,
    features: [
      "current_weather",
      "basic_forecasts",
      "community_support"
    ],
    permissions: [
      "weather.current.read",
      "weather.forecast.basic"
    ],
    limits: {
      "requests_per_month" => 1000,
      "locations_tracked" => 5,
      "webhook_endpoints" => 0,
      "data_retention_days" => 30,
      "concurrent_requests" => 1
    },
    metadata: {
      "popular" => false,
      "recommended_for" => [ "hobbyists", "students", "small projects" ],
      "setup_time" => "5 minutes",
      "support_channel" => "community"
    }
  },
  {
    name: "Professional",
    slug: "professional",
    description: "Ideal for growing businesses and production applications",
    price_cents: 4900, # $49/month
    billing_interval: "monthly",
    is_active: true,
    features: [
      "current_weather",
      "extended_forecasts",
      "historical_data",
      "weather_alerts",
      "webhook_notifications",
      "email_support",
      "data_exports"
    ],
    permissions: [
      "weather.current.read",
      "weather.forecast.extended",
      "weather.historical.read",
      "weather.alerts.read",
      "webhooks.manage"
    ],
    limits: {
      "requests_per_month" => 50000,
      "locations_tracked" => 100,
      "webhook_endpoints" => 5,
      "data_retention_days" => 365,
      "concurrent_requests" => 10
    },
    metadata: {
      "popular" => true,
      "recommended_for" => [ "small businesses", "developers", "SaaS applications" ],
      "setup_time" => "10 minutes",
      "support_channel" => "email"
    }
  },
  {
    name: "Enterprise",
    slug: "enterprise",
    description: "For large-scale applications with advanced requirements",
    price_cents: 19900, # $199/month
    billing_interval: "monthly",
    is_active: true,
    features: [
      "current_weather",
      "extended_forecasts",
      "advanced_forecasts",
      "historical_data",
      "weather_alerts",
      "unlimited_webhooks",
      "priority_support",
      "data_exports",
      "custom_integrations",
      "dedicated_support",
      "sla_guarantee"
    ],
    permissions: [
      "weather.current.read",
      "weather.forecast.extended",
      "weather.forecast.advanced",
      "weather.historical.read",
      "weather.historical.export",
      "weather.alerts.read",
      "weather.alerts.manage",
      "webhooks.manage",
      "webhooks.unlimited",
      "support.priority"
    ],
    limits: {
      "requests_per_month" => 500000,
      "locations_tracked" => -1,
      "webhook_endpoints" => -1,
      "data_retention_days" => 1825, # 5 years
      "concurrent_connections" => 100,
      "dedicated_support" => true
    },
    metadata: {
      "popular" => false,
      "recommended_for" => [ "enterprises", "high-traffic applications", "mission-critical systems" ],
      "setup_time" => "24 hours",
      "custom_onboarding" => true,
      "support_channel" => "priority"
    }
  }
]

plans_data.each do |plan_data|
  plan = AppPlan.find_or_initialize_by(
    app_id: app.id,
    slug: plan_data[:slug]
  ) do |p|
    p.name = plan_data[:name]
    p.description = plan_data[:description]
    p.price_cents = plan_data[:price_cents]
    p.billing_interval = plan_data[:billing_interval]
    p.is_active = plan_data[:is_active]
    p.features = plan_data[:features]
    p.permissions = plan_data[:permissions]
    p.limits = plan_data[:limits]
    p.metadata = plan_data[:metadata]
  end

  if plan.persisted?
    puts "💳 Found existing plan: #{plan.name}"
  else
    plan.save!
    puts "✅ Created plan: #{plan.name} ($#{plan.price_cents/100}/month)"
  end
end

# Create app features
features_data = [
  {
    name: "Real-time Data",
    slug: "real-time-data",
    description: "Access to current weather conditions updated every 15 minutes",
    feature_type: "data_access",
    default_enabled: true,
    configuration: {
      "update_interval" => "15 minutes",
      "data_sources" => [ "weather_stations", "satellites" ],
      "accuracy" => "high"
    }
  },
  {
    name: "Historical Analytics",
    slug: "historical-analytics",
    description: "Access to historical weather data and trend analysis",
    feature_type: "analytics",
    default_enabled: false,
    configuration: {
      "data_range" => "5 years",
      "aggregation_levels" => [ "daily", "monthly", "yearly" ],
      "analysis_types" => [ "trends", "anomalies", "comparisons" ]
    },
    dependencies: [ "historical_data_access" ]
  },
  {
    name: "Alert System",
    slug: "alert-system",
    description: "Severe weather alerts and custom threshold notifications",
    feature_type: "notifications",
    default_enabled: false,
    configuration: {
      "alert_types" => [ "severe_weather", "temperature_threshold", "precipitation_threshold" ],
      "delivery_methods" => [ "webhook", "email" ],
      "priority_levels" => [ "low", "medium", "high", "critical" ]
    }
  },
  {
    name: "Advanced Forecasting",
    slug: "advanced-forecasting",
    description: "Extended forecasts with hourly breakdowns and confidence intervals",
    feature_type: "forecasting",
    default_enabled: false,
    configuration: {
      "forecast_range" => "14 days",
      "hourly_detail" => true,
      "confidence_intervals" => true,
      "model_ensemble" => [ "gfs", "ecmwf", "nam" ]
    }
  }
]

features_data.each do |feature_data|
  feature = AppFeature.find_or_initialize_by(
    app_id: app.id,
    slug: feature_data[:slug]
  ) do |f|
    f.name = feature_data[:name]
    f.description = feature_data[:description]
    f.feature_type = feature_data[:feature_type]
    f.default_enabled = feature_data[:default_enabled]
    f.configuration = feature_data[:configuration]
    f.dependencies = feature_data[:dependencies] || []
  end

  if feature.persisted?
    puts "⚡ Found existing feature: #{feature.name}"
  else
    feature.save!
    puts "✅ Created feature: #{feature.name}"
  end
end

puts ""
puts "🎉 Sample Marketplace App Created Successfully!"
puts ""
puts "📊 Summary:"
puts "   App: #{app.name} (#{app.slug})"
puts "   Status: #{app.status.humanize}"
puts "   Endpoints: #{app.app_endpoints.count}"
puts "   Webhooks: #{app.app_webhooks.count}"
puts "   Plans: #{app.app_plans.count}"
puts "   Features: #{app.app_features.count}"
puts ""
puts "🔗 You can now:"
puts "   1. View the app in the marketplace at /app/marketplace"
puts "   2. Subscribe to the app to test the subscription flow"
puts "   3. Access the app management at /app/marketplace/apps/#{app.id}"
puts "   4. Test the API endpoints and webhooks"
puts ""
puts "💡 Next steps:"
puts "   - Customize the app details and features"
puts "   - Test the subscription and billing flow"
puts "   - Set up webhook endpoints for notifications"
puts "   - Monitor usage and analytics"
