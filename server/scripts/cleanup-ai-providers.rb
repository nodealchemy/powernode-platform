#!/usr/bin/env ruby

# Clean up complex AI providers and reseed with simple ones

require_relative '../config/environment'

puts "🧹 Cleaning up complex AI providers..."

# Remove complex providers
complex_slugs = [ 'multimodal-ai', 'local-code-assistant', 'ai-api-gateway' ]

complex_providers = AiProvider.where(slug: complex_slugs)

if complex_providers.any?
  puts "Found #{complex_providers.count} complex providers to remove:"
  complex_providers.each { |p| puts "  - #{p.name} (#{p.slug})" }

  # Remove them with SQL to avoid callback issues
  complex_providers.each do |provider|
    puts "Removing #{provider.name}..."

    # Remove associated records with raw SQL
    ActiveRecord::Base.connection.execute("DELETE FROM ai_provider_credentials WHERE ai_provider_id = '#{provider.id}'")
    ActiveRecord::Base.connection.execute("DELETE FROM ai_agent_executions WHERE ai_provider_id = '#{provider.id}'")
    ActiveRecord::Base.connection.execute("DELETE FROM ai_agents WHERE ai_provider_id = '#{provider.id}'")
    ActiveRecord::Base.connection.execute("DELETE FROM ai_providers WHERE id = '#{provider.id}'")
  end

  puts "✅ Removed complex providers"
else
  puts "No complex providers found"
end

puts "\n🌱 Reseeding with simple providers..."
load Rails.root.join('db/seeds/simple_ai_providers_seed.rb')

puts "\n📊 Current AI providers:"
AiProvider.all.each do |provider|
  puts "  ✓ #{provider.name} (#{provider.slug}) - #{provider.provider_type}"
end

puts "\n🎉 Cleanup complete!"
