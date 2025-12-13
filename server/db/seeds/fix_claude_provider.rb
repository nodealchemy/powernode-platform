# frozen_string_literal: true

# Fix Claude Provider Configuration
# Updates the Claude provider to use correct model configuration

puts "🔧 Fixing Claude Provider Models Configuration..."

provider = AiProvider.find_by(provider_type: 'anthropic')
unless provider
  puts "❌ Claude provider not found"
  exit 1
end

# Extract model names and IDs from supported_models
model_names = provider.supported_models.map { |m| m['name'] }
model_ids = provider.supported_models.map { |m| m['id'] }

# Update the configuration_schema to include the models
updated_config_schema = {
  'api_key' => {
    'type' => 'string',
    'description' => 'Anthropic API key (required)',
    'required' => true,
    'sensitive' => true
  },
  'model' => {
    'type' => 'string',
    'description' => 'Claude model to use',
    'default' => 'claude-3-5-sonnet-20241022',
    'enum' => model_ids
  },
  'models' => model_names,
  'default_model' => 'claude-3.5-sonnet',
  'max_tokens' => {
    'type' => 'integer',
    'description' => 'Maximum tokens in response',
    'default' => 4096,
    'minimum' => 1,
    'maximum' => 8192
  },
  'temperature' => {
    'type' => 'number',
    'description' => 'Randomness in responses (0.0-1.0)',
    'default' => 0.7,
    'minimum' => 0.0,
    'maximum' => 1.0
  }
}

provider.update!(configuration_schema: updated_config_schema)
puts "✅ Updated configuration schema with models"

# Test model support again
puts "\n🧪 Testing model support:"
test_models = [ 'claude-3.5-sonnet', 'claude-3-5-sonnet-20241022', 'claude-3.5-haiku' ]
test_models.each do |model|
  if provider.supports_model?(model)
    puts "✅ Supports: #{model}"
  else
    puts "❌ Does not support: #{model}"
  end
end

puts "\n📊 Summary:"
puts "  Available models: #{provider.available_models.count}"
puts "  Supported models: #{provider.supported_models.count}"
puts "  Configuration valid: #{provider.configuration_schema.key?('api_key') && provider.configuration_schema.key?('model')}"

puts "\n🎯 Claude Provider Configuration Fix Complete"
