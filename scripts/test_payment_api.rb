#!/usr/bin/env ruby

# Test payment gateways API directly
user = User.find_by(email: 'manager@powernode.org')

if user
  puts "User: #{user.email}"
  puts "Has admin.settings.payment: #{user.has_permission?('admin.settings.payment')}"
  
  # Generate a token for testing
  tokens = JwtService.generate_tokens(user)
  puts "Access token generated: #{tokens[:access_token][0..20]}..."
  
  # Test what the API would return
  puts "\nTesting controller logic..."
  begin
    # We can't easily test the full controller without Rails request context,
    # but we can test if the underlying data exists
    
    # Check if GatewayConfiguration model exists
    if defined?(GatewayConfiguration)
      puts "GatewayConfiguration model exists"
    else  
      puts "GatewayConfiguration model NOT found"
    end
    
    # Check if Payment model exists
    if defined?(Payment)
      puts "Payment model exists"
    else
      puts "Payment model NOT found"
    end
  rescue => e
    puts "Error testing: #{e.message}"
  end
else
  puts "User not found"
end