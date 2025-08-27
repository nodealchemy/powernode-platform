#!/usr/bin/env ruby

# Test payment gateway API with admin user
require 'net/http'
require 'uri'
require 'json'

# Find admin user (try multiple possibilities)
admin_candidates = ['admin@powernode.org', 'manager@powernode.org', 'test@example.com']
admin_user = nil

admin_candidates.each do |email|
  user = User.find_by(email: email)
  if user
    admin_user = user
    puts "Found user: #{email}"
    break
  end
end

if admin_user.nil?
  puts "No admin user found. Available users:"
  User.all.each { |u| puts "  - #{u.email}" }
  exit 1
end

# Generate proper JWT tokens using the application's JwtService
tokens = JwtService.generate_tokens(admin_user)
token = tokens[:access_token]

puts "Generated JWT token for #{admin_user.email}"
puts "User roles: #{admin_user.roles.pluck(:name).join(', ')}"
puts "User permissions: #{admin_user.permissions.pluck(:name).join(', ')}"
puts

# Test the payment gateways API
uri = URI('http://localhost:3000/api/v1/payment_gateways')
http = Net::HTTP.new(uri.host, uri.port)

request = Net::HTTP::Get.new(uri)
request['Content-Type'] = 'application/json'
request['Authorization'] = "Bearer #{token}"

puts "Making API request to #{uri}"
response = http.request(request)

puts "Response Status: #{response.code}"
puts "Response Headers:"
response.each_header { |key, value| puts "  #{key}: #{value}" }
puts
puts "Response Body:"
puts response.body
puts

if response.code == '200'
  begin
    data = JSON.parse(response.body)
    puts "API Response Structure:"
    puts "  Success: #{data['success']}"
    if data['data']
      puts "  Data keys: #{data['data'].keys.join(', ')}"
      if data['data']['gateways']
        puts "  Gateways: #{data['data']['gateways'].keys.join(', ')}"
      end
      if data['data']['status']
        puts "  Status: #{data['data']['status'].keys.join(', ')}"
      end
    end
  rescue JSON::ParserError => e
    puts "Failed to parse JSON response: #{e.message}"
  end
else
  puts "API request failed with status #{response.code}"
end