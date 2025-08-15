#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

begin
  puts "Testing admin settings API endpoint..."
  
  # First, login to get a token
  uri = URI('http://localhost:3000/api/v1/auth/login')
  http = Net::HTTP.new(uri.host, uri.port)
  
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json'
  request.body = {
    user: {
      email: 'admin@powernode.dev',
      password: 'AdminPassword123!'
    }
  }.to_json
  
  puts "Logging in as admin..."
  response = http.request(request)
  
  if response.code != '200'
    puts "❌ Login failed: #{response.code} - #{response.body}"
    exit 1
  end
  
  login_data = JSON.parse(response.body)
  token = login_data['data']['token']
  puts "✅ Login successful, got token"
  
  # Now test admin settings update
  uri = URI('http://localhost:3000/api/v1/admin_settings')
  http = Net::HTTP.new(uri.host, uri.port)
  
  request = Net::HTTP::Put.new(uri)
  request['Content-Type'] = 'application/json'
  request['Authorization'] = "Bearer #{token}"
  request.body = {
    admin_settings: {
      copyright_text: "© {year} Powernode Platform API Test #{Time.now.to_i}"
    }
  }.to_json
  
  puts "Testing admin settings update..."
  response = http.request(request)
  
  puts "Response code: #{response.code}"
  puts "Response body: #{response.body}"
  
  if response.code == '200'
    puts "✅ Admin settings update test: SUCCESS"
  else
    puts "❌ Admin settings update test: FAILED"
  end
  
rescue StandardError => e
  puts "❌ Test failed with error: #{e.class.name}: #{e.message}"
  puts e.backtrace.join("\n")
end