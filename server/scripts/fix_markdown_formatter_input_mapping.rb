# frozen_string_literal: true

# Fix Markdown Formatter Input Mapping - Ensure Data Continuity
# This script adds the missing input_mapping configuration to the markdown formatter node
# so it can receive data from editor, SEO, and image nodes

puts '🔧 Fixing Markdown Formatter Input Mapping'
puts '=' * 80

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts '❌ Workflow not found'
  exit 1
end

markdown_node = workflow.ai_workflow_nodes.find_by(node_id: 'markdown_formatter')

unless markdown_node
  puts '❌ Markdown formatter node not found'
  exit 1
end

puts "✅ Found markdown formatter node: #{markdown_node.name}"
puts

# Add input_mapping to tell the orchestrator where to get the data
input_mapping = {
  'editor_output' => 'editor.output',  # Get the edited blog content from editor node
  'seo_output' => 'seo.output',       # Get SEO optimizations from SEO node
  'image_output' => 'image.output'    # Get image suggestions from image node
}

puts '📥 Adding Input Mapping:'
puts JSON.pretty_generate(input_mapping)
puts

# Update the node configuration
markdown_node.update!(
  configuration: markdown_node.configuration.merge(
    'input_mapping' => input_mapping
  )
)

puts '✅ Markdown formatter input_mapping updated successfully!'
puts

# Verify the update
markdown_node.reload
puts '📋 Verification - Current Configuration:'
puts "  Has input_mapping: #{markdown_node.configuration['input_mapping'].present?}"
puts "  Input mapping keys: #{markdown_node.configuration['input_mapping']&.keys&.join(', ')}"
puts

puts '=' * 80
puts '✅ Fix Complete!'
puts
puts '📝 Next Steps:'
puts '1. Run a new workflow execution to test the fix'
puts '2. Verify that markdown formatter receives the correct input data'
puts '3. Check that the final output contains all preserved data'
