#!/usr/bin/env ruby
# frozen_string_literal: true

# Check what the status field contains in the API response

require_relative '../server/config/environment'

puts "🔍 Debugging PayPal Status Field in API Response"
puts "=" * 50

# Test the full API response structure
controller = Api::V1::PaymentGatewaysController.new
controller.define_singleton_method(:require_permission) { |perm| true }

puts "\n1️⃣ Full PayPal gateway status:"
status = controller.send(:gateway_status_for, 'paypal')
puts "Status object:"
puts JSON.pretty_generate(status)

puts "\n2️⃣ Full overview response structure:"
begin
  # Simulate the full API response structure
  overview = {
    gateways: {
      paypal: controller.send(:gateway_configuration_for, 'paypal')
    },
    status: {
      paypal: controller.send(:gateway_status_for, 'paypal')
    }
  }
  
  puts "Overview structure:"
  puts JSON.pretty_generate(overview)
  
  puts "\n🔍 Key analysis:"
  paypal_status = overview[:status][:paypal]
  paypal_config = overview[:gateways][:paypal]
  
  puts "Status.status: #{paypal_status[:status]}"
  puts "Config.client_id_present: #{paypal_config[:client_id_present]}"
  puts "Config.client_secret_present: #{paypal_config[:client_secret_present]}"
  
  puts "\nFrontend logic analysis:"
  is_configured = paypal_status[:status] != 'not_configured'
  puts "Frontend isConfigured = status.status !== 'not_configured': #{is_configured}"
  
  if is_configured && !paypal_config[:client_id_present]
    puts "❌ PROBLEM: Card shows configured but individual fields show not configured"
    puts "💡 SOLUTION: Need to fix the status calculation logic"
  elsif !is_configured && !paypal_config[:client_id_present] 
    puts "✅ Consistent: Both card and fields show not configured"
  end
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
end