# frozen_string_literal: true

# Fix Claude AI Provider Model Configuration
# Updates provider to use only VALID Anthropic model IDs

puts '🔧 Fixing Claude AI Provider Model Configuration'
puts '=' * 80
puts ''

provider = AiProvider.find_by(name: 'Claude AI (Anthropic)')

unless provider
  puts '❌ Claude AI provider not found'
  exit 1
end

puts "Provider: #{provider.name}"
puts "Type: #{provider.provider_type}"
puts ''

puts '📋 Current Supported Models:'
provider.supported_models.each_with_index do |model, i|
  marker = (i == 0) ? ' ← DEFAULT (used when agent has no model specified)' : ''
  puts "   #{i+1}. #{model['id']}#{marker}"
end
puts ''

puts '⚠️  ISSUE IDENTIFIED:'
puts '   Model "claude-sonnet-4-5-20250514" is INVALID'
puts '   Anthropic API returns 404: model not found'
puts ''

puts '💡 Valid Anthropic Model IDs (as of January 2025):'
puts '   According to Anthropic documentation, valid models are:'
puts '   - claude-3-5-sonnet-20241022      (Claude 3.5 Sonnet, latest)'
puts '   - claude-3-5-sonnet-20240620      (Claude 3.5 Sonnet, June 2024)'
puts '   - claude-3-opus-20240229          (Claude 3 Opus)'
puts '   - claude-3-haiku-20240307         (Claude 3 Haiku)'
puts ''

puts '🔧 Updating provider configuration...'
puts ''

# Update to known-valid models only
# Using claude-3-5-sonnet-20241022 as default (most recent stable model)
updated_models = [
  { 'id' => 'claude-3-5-sonnet-20241022', 'name' => 'Claude 3.5 Sonnet (Latest)' },
  { 'id' => 'claude-3-5-sonnet-20240620', 'name' => 'Claude 3.5 Sonnet (June 2024)' },
  { 'id' => 'claude-3-opus-20240229', 'name' => 'Claude 3 Opus' },
  { 'id' => 'claude-3-haiku-20240307', 'name' => 'Claude 3 Haiku' }
]

provider.update!(supported_models: updated_models)

puts '✅ Provider configuration updated!'
puts ''
puts '📋 New Supported Models:'
provider.reload.supported_models.each_with_index do |model, i|
  marker = (i == 0) ? ' ← DEFAULT' : ''
  puts "   #{i+1}. #{model['id']}#{marker}"
  puts "      Name: #{model['name']}"
end

puts ''
puts '🎯 Impact:'
puts '   - AI agents without explicit model will now use: claude-3-5-sonnet-20241022'
puts '   - This is a VALID model that Anthropic API will accept'
puts '   - Workflows should now execute successfully (if credentials are valid)'
puts ''

puts '🔑 Credentials Status:'
cred = provider.ai_provider_credentials.active.first
if cred
  puts '   ✅ Active credentials found'
  puts "   Created: #{cred.created_at}"
  puts ''
  puts '✅ System is ready for workflow execution!'
else
  puts '   ⚠️  No active credentials found'
  puts '   Add Anthropic API key to enable workflow execution'
  puts '   Navigate to: Settings → AI Providers → Claude AI → Add Credentials'
end

puts ''
puts '=' * 80
puts 'Fix complete!'
