# frozen_string_literal: true

# Test script to verify activities API returns real endpoint data
# Run with: rails runner db/test_activities_api.rb

require 'net/http'
require 'json'

puts "=== Testing Activities API ==="
puts "Time: #{Time.current}"
puts

# Get worker and user for testing
worker = Worker.first
user = User.first

if worker.nil? || user.nil?
  puts "❌ Missing worker or user for testing"
  exit 1
end

puts "🔧 Testing with worker: #{worker.name}"
puts "🔧 Testing with user: #{user.email}"
puts

# Generate JWT token for API access
token = JWT.encode(
  {
    user_id: user.id,
    account_id: user.account_id,
    iat: Time.current.to_i,
    exp: (Time.current + 1.hour).to_i
  },
  Rails.application.config.jwt_secret_key,
  'HS256'
)

# Make API request
uri = URI("http://localhost:3000/api/v1/workers/#{worker.id}/activities")
http = Net::HTTP.new(uri.host, uri.port)
request = Net::HTTP::Get.new(uri)
request['Authorization'] = "Bearer #{token}"
request['Accept'] = 'application/json'
request['Content-Type'] = 'application/json'

begin
  response = http.request(request)

  puts "📡 API Response:"
  puts "   Status: #{response.code}"
  puts "   Success: #{response.code == '200'}"

  if response.code == '200'
    data = JSON.parse(response.body)

    if data['success'] && data['data'] && data['data']['summary']
      summary = data['data']['summary']

      puts
      puts "📊 Summary Statistics:"
      puts "   Total Recent: #{summary['total_recent']}"
      puts "   Successful: #{summary['successful_recent']}"
      puts "   Failed: #{summary['failed_recent']}"
      puts "   Success Rate: #{summary['success_rate']}%"
      puts "   Avg Response Time: #{summary['avg_response_time']}ms"

      puts
      puts "🔗 Top Endpoints from API:"
      if summary['top_endpoints'] && summary['top_endpoints'].any?
        summary['top_endpoints'].each_with_index do |endpoint_data, index|
          puts "   #{index + 1}. #{endpoint_data['endpoint']} - #{endpoint_data['count']} requests"
        end
      else
        puts "   No endpoints found in API response"
      end

      puts
      puts "✅ SUCCESS: API is returning real endpoint data!"

    else
      puts "❌ API response structure is invalid"
      puts "   Response: #{data.inspect}"
    end

  else
    puts "❌ API request failed"
    puts "   Error: #{response.body}"
  end

rescue => e
  puts "❌ API request error: #{e.message}"
end

puts
puts "✨ Activities API test completed!"
