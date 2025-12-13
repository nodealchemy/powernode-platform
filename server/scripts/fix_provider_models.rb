# frozen_string_literal: true

# Fix AI Provider Model Configuration
# Updates Claude AI provider to use valid models only

puts '🔧 Fixing AI Provider Model Configuration'
puts '=' * 80
puts ''

provider = AiProvider.find_by(name: 'Claude AI (Anthropic)')

unless provider
  puts '❌ Claude AI provider not found'
  exit 1
end

puts 'Current supported_models (first 5):'
provider.supported_models.first(5).each_with_index do |model, i|
  puts "  #{i+1}. #{model['id']} - #{model['name']}"
end
puts ''

# Update to valid models only (removed invalid claude-opus-4-5-20250514)
updated_models = [
  { 'id' => 'claude-sonnet-4-5-20250514', 'name' => 'Claude Sonnet 4.5' },
  { 'id' => 'claude-sonnet-4-1-20250329', 'name' => 'Claude Sonnet 4.1' },
  { 'id' => 'claude-sonnet-3-5-20241022', 'name' => 'Claude 3.5 Sonnet' },
  { 'id' => 'claude-3-5-sonnet-20241022', 'name' => 'Claude 3.5 Sonnet (Legacy)' },
  { 'id' => 'claude-3-5-sonnet-20240620', 'name' => 'Claude 3.5 Sonnet (June)' }
]

provider.update!(supported_models: updated_models)

puts '✅ Updated supported_models:'
provider.reload.supported_models.first(5).each_with_index do |model, i|
  puts "  #{i+1}. #{model['id']} - #{model['name']}"
end
puts ''

puts '✓ Provider configuration fixed!'
puts "  First model (fallback): #{provider.supported_models.first['id']}"
puts ''
puts '🎯 AI agents without explicit model config will now use: claude-sonnet-4-5-20250514'
