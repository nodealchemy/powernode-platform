# Add plans to Simple Weather API for subscription testing

puts "🔧 Adding plans to Simple Weather API..."

# Find the app
app = App.find_by(slug: "simple-weather-api")
unless app
  puts "❌ Simple Weather API not found. Run simple_marketplace_app.rb first."
  return
end

puts "📱 Found app: #{app.name}"

# Create basic plans if they don't exist
plans_data = [
  {
    name: "Free Tier",
    slug: "free",
    price_cents: 0,
    billing_interval: "monthly",
    description: "Basic weather data access with limited requests",
    features: ["basic_weather"],
    permissions: ["weather.read"],
    limits: {
      "requests_per_day" => 100,
      "locations" => 5,
      "historical_data_days" => 7
    },
    metadata: {
      "popular" => false,
      "recommended" => false
    },
    is_active: true,
    is_public: true
  },
  {
    name: "Standard Plan",
    slug: "standard",
    price_cents: 2900, # $29.00
    billing_interval: "monthly",
    description: "Enhanced weather data with more requests and features",
    features: ["basic_weather", "extended_forecast", "weather_alerts"],
    permissions: ["weather.read", "weather.forecast", "weather.alerts"],
    limits: {
      "requests_per_day" => 5000,
      "locations" => 50,
      "historical_data_days" => 30,
      "forecast_days" => 14
    },
    metadata: {
      "popular" => true,
      "recommended" => true
    },
    is_active: true,
    is_public: true
  },
  {
    name: "Professional Plan",
    slug: "professional",
    price_cents: 9900, # $99.00
    billing_interval: "monthly",
    description: "Advanced weather data for professional applications",
    features: ["basic_weather", "extended_forecast", "weather_alerts", "historical_data", "weather_analytics"],
    permissions: ["weather.read", "weather.forecast", "weather.alerts", "weather.analytics"],
    limits: {
      "requests_per_day" => 25000,
      "locations" => 500,
      "historical_data_days" => 365,
      "forecast_days" => 30,
      "api_keys" => 10
    },
    metadata: {
      "popular" => false,
      "recommended" => false,
      "enterprise" => true
    },
    is_active: true,
    is_public: true
  }
]

created_count = 0
plans_data.each do |plan_data|
  existing_plan = app.app_plans.find_by(slug: plan_data[:slug])
  
  if existing_plan
    puts "📋 Plan already exists: #{plan_data[:name]}"
  else
    plan = app.app_plans.create!(plan_data)
    puts "✅ Created plan: #{plan.name} (#{plan.formatted_price})"
    created_count += 1
  end
end

puts ""
puts "🎉 Sample App Plans Setup Complete!"
puts ""
puts "📊 Summary:"
puts "   Plans created: #{created_count}"
puts "   Total plans: #{app.app_plans.count}"
puts ""
puts "🔗 You can now:"
puts "   1. View app plans in the marketplace"
puts "   2. Test subscription workflow"
puts "   3. Subscribe to different pricing tiers"
puts ""