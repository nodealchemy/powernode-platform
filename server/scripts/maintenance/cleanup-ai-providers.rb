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

    # Remove associated records using parameterized queries
    Ai::ProviderCredential.where(ai_provider_id: provider.id).delete_all
    Ai::AgentExecution.where(ai_provider_id: provider.id).delete_all
    Ai::Agent.where(ai_provider_id: provider.id).delete_all
    provider.destroy!
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
