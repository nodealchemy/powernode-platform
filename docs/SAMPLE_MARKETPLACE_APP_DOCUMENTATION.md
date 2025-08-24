# Sample Marketplace App Documentation

## Overview

This documentation covers the **Simple Weather API** sample marketplace app that demonstrates the complete marketplace functionality in the Powernode platform.

## App Details

- **Name**: Simple Weather API
- **Slug**: `simple-weather-api`
- **ID**: `efb0390f-e9e7-4e54-b777-d5060520836e`
- **Category**: Weather
- **Status**: Published
- **Created**: Sample seed data

## Marketplace Listing

### Basic Information
- **Title**: "Simple Weather API - Get Weather Data Instantly"
- **Short Description**: "Easy-to-use weather API with current conditions and forecasts for any location worldwide."
- **Category**: `weather`
- **Tags**: `["weather", "forecast", "api", "simple"]`
- **Review Status**: Approved
- **Featured**: No
- **Published**: Yes

### URLs
- **Documentation**: https://docs.example.com
- **Support**: https://support.example.com  
- **Homepage**: https://weather-api.example.com

### Screenshots
1. `https://cdn.weathertech.example.com/screenshots/dashboard.png`
2. `https://cdn.weathertech.example.com/screenshots/api-response.png`
3. `https://cdn.weathertech.example.com/screenshots/analytics.png`

## App Plans

The sample app includes two pricing tiers for subscription testing:

### 1. Free Tier
- **Price**: $0.00 (Free)
- **Billing**: Monthly
- **Description**: "Basic weather data access with limited requests"
- **Features**: `["basic_weather"]`
- **Permissions**: `["weather.read"]`
- **Limits**:
  - `requests_per_day`: 100
  - `locations`: 5
- **Popular**: No

### 2. Standard Plan
- **Price**: $29.00/month
- **Billing**: Monthly  
- **Description**: "Enhanced weather data with more requests and features"
- **Features**: `["basic_weather"]`
- **Permissions**: `["weather.read"]`
- **Limits**:
  - `requests_per_day`: 5,000
  - `locations`: 50
- **Popular**: Yes (recommended)

## API Endpoints

### Public Marketplace Access
```bash
# Get all marketplace listings (includes sample app)
GET http://localhost:3000/api/v1/marketplace_listings

# Response includes app plans:
{
  "success": true,
  "data": [{
    "title": "Simple Weather API - Get Weather Data Instantly",
    "app": {
      "slug": "simple-weather-api",
      "app_plans": [
        {
          "name": "Free Tier",
          "formatted_price": "Free",
          "billing_interval": "monthly"
        },
        {
          "name": "Standard Plan", 
          "formatted_price": "$29.0/month",
          "billing_interval": "monthly"
        }
      ]
    }
  }]
}
```

### Authentication Required Endpoints
```bash
# Get app details (requires authentication)
GET http://localhost:3000/api/v1/apps/{app_id}

# Create app subscription (requires authentication)
POST http://localhost:3000/api/v1/app_subscriptions
{
  "app_id": "efb0390f-e9e7-4e54-b777-d5060520836e",
  "app_plan_id": "{plan_id}"
}
```

## Testing Workflow

### 1. Frontend Marketplace Display
1. Navigate to `http://localhost:3001/app/marketplace`
2. Verify "Simple Weather API" appears in listings
3. Check app shows pricing plans
4. Verify screenshots and app details display correctly

### 2. App Installation/Subscription Flow
1. Click on the sample app in marketplace
2. View app details page with pricing plans
3. Select a pricing plan (Free Tier or Standard)
4. Complete subscription process
5. Verify subscription appears in user's installed apps

### 3. API Verification
```bash
# Test marketplace API
curl -s "http://localhost:3000/api/v1/marketplace_listings" | jq '.data[] | select(.app.slug == "simple-weather-api")'

# Test app plans included
curl -s "http://localhost:3000/api/v1/marketplace_listings" | jq '.data[] | select(.app.slug == "simple-weather-api") | .app.app_plans'
```

## Database Verification

```ruby
# Rails console verification
app = App.find_by(slug: 'simple-weather-api')
puts "App: #{app.name}"
puts "Status: #{app.status}"
puts "Plans: #{app.app_plans.count}"
puts "Listing: #{app.marketplace_listing&.title}"
puts "Published: #{app.marketplace_listing&.published_at ? 'Yes' : 'No'}"
```

## Seed Scripts Used

1. **Main App Creation**: `db/seeds/simple_marketplace_app.rb`
   - Creates basic app with marketplace listing
   - Sets up screenshots and app metadata
   
2. **App Plans Creation**: `db/seeds/simple_app_plans.rb`
   - Adds Free Tier and Standard Plan
   - Configures pricing, features, and limits

## Frontend Integration

The sample app demonstrates:
- **Marketplace browsing**: App appears in public marketplace listings
- **App details view**: Individual app page with plans and information  
- **Subscription flow**: Users can subscribe to different pricing tiers
- **Plan comparison**: Side-by-side pricing comparison
- **Installation tracking**: Subscription management interface

## Key Features Demonstrated

### Backend
- ✅ App model with published status
- ✅ MarketplaceListing with approved status  
- ✅ AppPlan with multiple pricing tiers
- ✅ Public API endpoints for marketplace browsing
- ✅ Authentication-protected subscription endpoints
- ✅ Screenshot URL handling fix
- ✅ Tab scrollbar hiding improvements

### Frontend  
- ✅ Marketplace page displays sample apps
- ✅ App detail pages with pricing information
- ✅ Plan selection and subscription workflow
- ✅ Responsive design with theme support
- ✅ Hidden scrollbars on tab navigation

## Usage for Development

This sample app serves as:
1. **Testing data** for marketplace functionality
2. **Reference implementation** for app structure
3. **Demo content** for showcasing platform capabilities
4. **Integration testing** baseline for subscription workflows

## Maintenance Notes

- Sample data is preserved across database resets
- Seed scripts are idempotent (can run multiple times safely)
- App IDs are generated, so reference by slug for consistency
- Plans can be modified for testing different pricing scenarios

---

**Created**: Sample marketplace app implementation  
**Last Updated**: Tab scrollbar improvements and screenshot URL fixes
**Status**: Complete and ready for demonstration