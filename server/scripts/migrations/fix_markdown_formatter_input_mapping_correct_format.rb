# frozen_string_literal: true

# Fix Markdown Formatter Input Mapping - Use Correct Expression Format
# The orchestrator requires @ prefix for node result references

puts '🔧 Fixing Markdown Formatter Input Mapping (Correct Format)'
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

puts '📋 Current input_mapping:'
puts JSON.pretty_generate(markdown_node.configuration['input_mapping'] || {})
puts

# Fix: Use @node_id.output format for node result references
# The orchestrator's resolve_expression method expects @ prefix
input_mapping = {
  'editor_output' => '@editor.output',     # Get editor node output
  'seo_output' => '@seo.output',           # Get SEO node output
  'image_output' => '@image.output'        # Get image node output
}

puts '📥 New Input Mapping (with correct @ prefix):'
puts JSON.pretty_generate(input_mapping)
puts

# Update the node configuration
markdown_node.update!(
  configuration: markdown_node.configuration.merge(
    'input_mapping' => input_mapping
  )
)

puts '✅ Markdown formatter input_mapping updated with correct format!'
puts

# Verify the update
markdown_node.reload
puts '📋 Verification - Current Configuration:'
puts "  Has input_mapping: #{markdown_node.configuration['input_mapping'].present?}"
puts "  Input mapping keys: #{markdown_node.configuration['input_mapping']&.keys&.join(', ')}"
puts "  Input mapping values: #{markdown_node.configuration['input_mapping']&.values&.join(', ')}"
puts

puts '=' * 80
puts '✅ Fix Complete!'
puts
puts '📝 Next Steps:'
puts '1. Run a new workflow execution to test the corrected format'
puts '2. Verify that markdown formatter receives actual node output content'
puts '3. Check that the final output contains complete markdown data'
