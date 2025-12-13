# frozen_string_literal: true

# Fix End Node Output Mapping
# Update output_mapping to use correct {{}} syntax

puts "\n" + "=" * 80
puts "🔧 FIXING END NODE OUTPUT MAPPING"
puts "=" * 80
puts ""

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')
unless workflow
  puts "❌ Workflow not found"
  exit 1
end

end_node = workflow.ai_workflow_nodes.find_by(node_id: 'end')
unless end_node
  puts "❌ End node not found"
  exit 1
end

puts "✓ Found end node: #{end_node.name}"
puts ""

old_mapping = end_node.configuration['output_mapping']
puts "Current output_mapping (INCORRECT):"
puts JSON.pretty_generate(old_mapping)
puts ""

# SOLUTION: Since markdown_formatter returns JSON string in 'output' field,
# and that JSON contains markdown, metadata, seo_data, image_data, blog_content,
# we need to reference the output field and let the frontend parse the JSON.
#
# However, for better UX, we should parse the JSON here and extract fields.
# But the simplest fix is to return the whole JSON string in 'markdown' field.

new_mapping = {
  # Get the full JSON output from markdown_formatter
  # This contains: markdown, metadata, seo_data, image_data, blog_content
  'result' => '{{markdown_formatter.output}}',

  # Also include execution metadata
  'execution_metadata' => '{{markdown_formatter.metadata}}',

  # Include input variables for context
  'input_variables' => '{{input.topic}}'
}

end_node.configuration['output_mapping'] = new_mapping

if end_node.save
  puts "✅ Updated end node output_mapping"
  puts ""
  puts "New output_mapping:"
  puts JSON.pretty_generate(new_mapping)
  puts ""
  puts "=" * 80
  puts "✅ FIX COMPLETE"
  puts "=" * 80
  puts ""
  puts "Note: The 'result' field will contain the JSON string from markdown_formatter"
  puts "Frontend should parse this JSON to extract individual fields."
else
  puts "❌ Failed to save end node:"
  end_node.errors.full_messages.each do |error|
    puts "   - #{error}"
  end
end
