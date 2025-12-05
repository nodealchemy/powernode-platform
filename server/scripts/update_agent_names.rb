# frozen_string_literal: true

# Update Agent Names in Complete Blog Generation Workflow

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts '❌ Workflow not found'
  exit 1
end

puts '🔧 Updating Agent Names in Workflow Nodes'
puts '=' * 80
puts ''

# Map of node_id to suggested agent name
agent_names = {
  'research' => 'Blog Research Agent',
  'outline' => 'Outline Generator Agent',
  'writer' => 'Content Writer Agent',
  'editor' => 'Content Editor Agent',
  'seo' => 'SEO Optimizer Agent',
  'image' => 'Image Suggestion Agent'
}

workflow.ai_workflow_nodes.where(node_type: 'ai_agent').each do |node|
  agent_name = agent_names[node.node_id]
  if agent_name && node.configuration
    # Update configuration with agent name
    node.configuration['agent_name'] = agent_name
    node.save!
    puts "✅ Updated #{node.node_id}: #{agent_name}"
  end
end

puts ''
puts '=' * 80
puts '✅ Agent names updated successfully!'
puts ''

# Verify updates
puts 'VERIFICATION:'
puts '-' * 80
workflow.reload
workflow.ai_workflow_nodes.where(node_type: 'ai_agent').order(:created_at).each do |node|
  puts "  • #{node.node_id.ljust(15)} → #{node.configuration['agent_name'] || 'NOT SET'}"
end
