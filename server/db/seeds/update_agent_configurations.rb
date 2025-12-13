# frozen_string_literal: true

# Update all existing agents with proper model configuration
puts "🔧 Updating AI Agent Configurations..."

updated_count = 0
failed_count = 0

AiAgent.find_each do |agent|
  begin
    # Determine appropriate model based on provider
    model = if agent.ai_provider&.provider_type == 'anthropic'
      'claude-sonnet-4-5-20250929'
    else
      'gpt-4-turbo-preview'
    end

    # Determine temperature based on agent type
    temperature = case agent.agent_type
    when 'monitor'
      0.1  # Precise monitoring
    when 'data_analyst'
      0.2  # Analytical
    when 'assistant'
      0.3  # Balanced
    when 'content_generator', 'image_generator'
      0.7  # Creative
    when 'code_assistant'
      0.2  # Precise code generation
    else
      0.5  # Default
    end

    # Preserve existing configuration but add/update model fields
    updated_config = agent.configuration.dup || {}
    updated_config['model'] = model
    updated_config['temperature'] = temperature
    updated_config['max_tokens'] = 4096

    # Set system_prompt if not already present
    if updated_config['system_prompt'].blank?
      updated_config['system_prompt'] = agent.description || "You are a helpful AI assistant specialized in #{agent.agent_type}."
    end

    agent.update!(configuration: updated_config)
    puts "✅ Updated #{agent.name}"
    puts "   Provider: #{agent.ai_provider&.name || 'None'}"
    puts "   Model: #{model}"
    puts "   Temperature: #{temperature}"
    updated_count += 1
  rescue StandardError => e
    puts "❌ Failed to update #{agent.name}: #{e.message}"
    failed_count += 1
  end
end

puts "\n📊 Update Summary:"
puts "   ✅ Successfully updated: #{updated_count} agents"
puts "   ❌ Failed: #{failed_count} agents" if failed_count > 0
puts "\n✅ Agent configuration update completed!"
