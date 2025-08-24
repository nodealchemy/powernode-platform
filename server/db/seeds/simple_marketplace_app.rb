# Simple Sample Marketplace App - Skipping complex validations

puts "🚀 Creating Simple Sample Marketplace App..."

# Find or create account
account = Account.first
unless account
  puts "❌ No accounts found. Please create an account first."
  return
end

puts "📋 Using account: #{account.name}"

# Create simple app if it doesn't exist
app = App.find_by(slug: "simple-weather-api")
unless app
  app = App.create!(
    account_id: account.id,
    name: "Simple Weather API",
    slug: "simple-weather-api",
    description: "A simple weather API for testing the marketplace",
    long_description: "# Simple Weather API\n\nGet weather data for any location worldwide.\n\n## Features\n- Current weather\n- 5-day forecast\n- Weather alerts\n\n## Easy to Use\nJust sign up, get your API key, and start making requests!",
    category: "weather",
    version: "1.0.0",
    status: "published",
    published_at: 1.week.ago,
    metadata: {
      "author" => "Weather Corp",
      "license" => "Commercial"
    },
    configuration: {
      "api_version" => "v1",
      "rate_limit" => "1000/hour"
    }
  )
  puts "✅ Created app: #{app.name}"
else
  puts "📱 Found existing app: #{app.name}"
end

# Create marketplace listing if it doesn't exist
listing = MarketplaceListing.find_by(app_id: app.id)
unless listing
  listing = MarketplaceListing.create!(
    app_id: app.id,
    title: "Simple Weather API - Get Weather Data Instantly",
    short_description: "Easy-to-use weather API with current conditions and forecasts for any location worldwide.",
    long_description: app.long_description,
    category: "weather",
    tags: ["weather", "forecast", "api", "simple"],
    documentation_url: "https://docs.example.com",
    support_url: "https://support.example.com",
    homepage_url: "https://weather-api.example.com",
    featured: false,
    review_status: "approved",
    published_at: 1.week.ago
  )
  puts "✅ Created marketplace listing"
else
  puts "📋 Found existing marketplace listing"
end

puts ""
puts "🎉 Simple Sample Marketplace App Created Successfully!"
puts ""
puts "📊 Summary:"
puts "   App: #{app.name} (#{app.slug})"
puts "   Status: #{app.status.humanize}"
puts "   Category: #{app.category}"
puts ""
puts "🔗 You can now:"
puts "   1. View the app in the marketplace at /app/marketplace"
puts "   2. Browse marketplace listings to see the sample app"
puts "   3. Access app management at /app/marketplace/apps/#{app.id}"
puts ""