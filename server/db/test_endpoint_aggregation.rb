# frozen_string_literal: true

# Test script to verify endpoint aggregation functionality
# Run with: rails runner db/test_endpoint_aggregation.rb

puts "=== Testing Endpoint Aggregation ==="
puts "Time: #{Time.current}"
puts

worker = Worker.first
if worker.nil?
  puts "❌ No worker found."
  exit 1
end

puts "🔧 Testing with worker: #{worker.name}"

# Get recent activities
recent_activities = worker.worker_activities.where('performed_at > ?', 24.hours.ago)
puts "📊 Recent activities (24h): #{recent_activities.count}"
puts

# Test the endpoint aggregation logic
def get_top_endpoints(activities, limit = 10)
  endpoint_counts = {}
  
  # Aggregate endpoint usage from activities
  activities.each do |activity|
    details = activity.details || {}
    
    # Check for endpoint in different possible fields
    endpoint = details['endpoint'] || details['request_path']
    next unless endpoint
    
    # Clean up endpoint (remove query parameters)
    clean_endpoint = endpoint.split('?').first
    endpoint_counts[clean_endpoint] = (endpoint_counts[clean_endpoint] || 0) + 1
  end
  
  # Sort by count and return top endpoints
  endpoint_counts
    .sort_by { |endpoint, count| -count }
    .first(limit)
    .map { |endpoint, count| { endpoint: endpoint, count: count } }
end

# Test endpoint aggregation
top_endpoints = get_top_endpoints(recent_activities)

puts "🔗 Top API Endpoints:"
if top_endpoints.any?
  top_endpoints.each_with_index do |data, index|
    puts "   #{index + 1}. #{data[:endpoint]} - #{data[:count]} requests"
  end
else
  puts "   No endpoints found in activity data"
end

puts
puts "🔍 Sample activity details:"
recent_activities.limit(5).each do |activity|
  details = activity.details || {}
  endpoint = details['endpoint'] || details['request_path']
  puts "   Action: #{activity.action}, Endpoint: #{endpoint || 'N/A'}"
end

puts
puts "✨ Endpoint aggregation test completed!"