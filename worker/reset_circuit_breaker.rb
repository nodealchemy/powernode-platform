# frozen_string_literal: true

#!/usr/bin/env ruby

# Load the Rails environment
require_relative 'config/boot'

puts "=== Circuit Breaker Status Before Reset ==="
registry = CircuitBreakerRegistry.instance
puts registry.status

puts "\n=== Resetting Circuit Breaker ==="
registry.reset_breaker('backend_api')

puts "\n=== Circuit Breaker Status After Reset ==="
puts registry.status

puts "\nCircuit breaker reset completed!"