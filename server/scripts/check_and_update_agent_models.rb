#!/usr/bin/env ruby
# frozen_string_literal: true

puts '🔍 CHECKING AI AGENT MODEL ASSIGNMENTS'
puts '═══════════════════════════════════════════════════════'
puts ''

workflow = AiWorkflow.find_by(name: 'Blog Generation Pipeline')
agents_used = []

# Get all AI agent nodes
workflow.ai_workflow_nodes.where(node_type: 'ai_agent').each do |node|
  agent_id = node.configuration['agent_id']
  agent = AiAgent.find_by(id: agent_id)

  if agent
    agents_used << {
      node_name: node.name,
      agent: agent,
      agent_name: agent.name,
      agent_type: agent.agent_type,
      provider: agent.ai_provider.name,
      current_model: agent.configuration['model'],
      task_hint: node.name
    }
  end
end

# Display current assignments
puts '📋 CURRENT MODEL ASSIGNMENTS:'
puts '─────────────────────────────────────────────────────'
puts ''

agents_used.each_with_index do |info, idx|
  puts "#{idx + 1}. #{info[:node_name]}"
  puts "   Agent: #{info[:agent_name]} (#{info[:agent_type]})"
  puts "   Provider: #{info[:provider]}"
  puts "   Current Model: #{info[:current_model] || 'NOT SET'}"
  puts ''
end

# Get available models
provider = AiProvider.find_by(slug: 'anthropic-claude')
if provider
  puts '📚 AVAILABLE ANTHROPIC MODELS:'
  puts '─────────────────────────────────────────────────────'
  puts ''

  provider.supported_models.each_with_index do |model, idx|
    puts "#{idx + 1}. #{model['name']} (#{model['id']})"
    puts "   Context: #{model['context_length'].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"
    puts "   Max Output: #{model['max_output_tokens'].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"
    puts ''
  end
end

puts '💡 RECOMMENDED MODEL ASSIGNMENTS:'
puts '─────────────────────────────────────────────────────'
puts ''
puts 'For Blog Generation Pipeline tasks:'
puts ''
puts '• Research/Analysis Tasks (high quality needed):'
puts '  → Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)'
puts '  → Best for: Topic Research, Fact Checking'
puts ''
puts '• Content Creation Tasks (balanced):'
puts '  → Claude Sonnet 4 (claude-sonnet-4-20250514)'
puts '  → Best for: Outline, Writing, Editing, SEO'
puts ''
puts '• Quick Tasks (speed/cost optimized):'
puts '  → Claude Haiku 3.5 (claude-3-5-haiku-20241022)'
puts '  → Best for: Quality checks, simple transforms'
puts ''

# Update models based on task type
puts '🔧 UPDATING AGENT MODELS...'
puts '─────────────────────────────────────────────────────'
puts ''

updates_made = 0

# Model mapping
model_names = {
  'claude-sonnet-4-5-20250929' => 'Claude Sonnet 4.5',
  'claude-sonnet-4-20250514' => 'Claude Sonnet 4',
  'claude-3-5-haiku-20241022' => 'Claude Haiku 3.5'
}

agents_used.each do |info|
  agent = info[:agent]
  task_name = info[:node_name].downcase

  # Determine appropriate model based on task
  new_model = if task_name.include?('research') || task_name.include?('fact')
                'claude-sonnet-4-5-20250929'  # Sonnet 4.5 for research/analysis
              elsif task_name.include?('quality') || task_name.include?('check')
                'claude-3-5-haiku-20241022'   # Haiku for quick checks
              else
                'claude-sonnet-4-20250514'    # Sonnet 4 for content creation
              end

  current_model = agent.configuration['model']

  if current_model != new_model
    agent.configuration['model'] = new_model
    agent.save!

    model_name = model_names[new_model] || new_model

    puts "✅ Updated: #{info[:agent_name]}"
    puts "   #{current_model || 'none'} → #{new_model}"
    puts "   Model: #{model_name}"
    puts ''

    updates_made += 1
  else
    puts "✓ No change: #{info[:agent_name]} (already using #{new_model})"
    puts ''
  end
end

puts '═══════════════════════════════════════════════════════'
puts '📊 UPDATE SUMMARY'
puts '═══════════════════════════════════════════════════════'
puts ''
puts "Total Agents: #{agents_used.count}"
puts "Updated: #{updates_made}"
puts "Unchanged: #{agents_used.count - updates_made}"
puts ''

if updates_made > 0
  puts '✅ Agent models have been optimized for their tasks!'
else
  puts '✅ All agents already using appropriate models!'
end
puts ''
