# frozen_string_literal: true

# Fix Markdown Formatter Node to Preserve Original Data
# The node should add markdown output while preserving SEO and image data

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts '❌ Workflow not found'
  exit 1
end

puts '🔧 Updating Markdown Formatter Node to Preserve Data'
puts '=' * 80
puts ''

markdown_node = workflow.ai_workflow_nodes.find_by(node_id: 'markdown_formatter')
unless markdown_node
  puts '❌ Markdown formatter node not found'
  exit 1
end

# Update the prompt to instruct returning structured JSON with all data
updated_prompt = <<~PROMPT.strip
  You are formatting blog content into markdown while preserving all metadata.

  Blog Content:
  {{editor_output}}

  SEO Optimizations:
  {{seo_output}}

  Image Suggestions:
  {{image_output}}

  Your task:
  1. Format the blog content as clean, professional markdown with:
     - Proper headers (# for title, ## for sections, ### for subsections)
     - Emphasis with *italic* and **bold** where appropriate
     - Bulleted or numbered lists for key points
     - Code blocks with ``` for any code examples
     - Links in [text](url) format
     - Image placeholders with ![alt text](image_url) format
     - Proper spacing and line breaks for readability

  2. Return a JSON object with ALL data preserved:
  {
    "markdown": "your formatted markdown content here",
    "blog_content": {{editor_output}},
    "seo_data": {{seo_output}},
    "image_data": {{image_output}},
    "metadata": {
      "formatted_at": "current timestamp",
      "format": "markdown",
      "version": "1.0"
    }
  }

  CRITICAL: Return ONLY the JSON object. Do not include any explanation or additional text.
PROMPT

# Update the node configuration
markdown_node.update!(
  configuration: markdown_node.configuration.merge(
    'prompt_template' => updated_prompt,
    'response_format' => 'json',
    'preserve_data' => true
  )
)

puts '✅ Updated markdown formatter prompt to preserve all data'
puts ''

# Check if we need to update the End node to handle the new structure
end_node = workflow.ai_workflow_nodes.find_by(node_id: 'end')

# Update End node configuration to extract all data properly
if end_node
  end_config = end_node.configuration || {}
  end_config['output_mapping'] = {
    'markdown' => 'markdown_formatter.markdown',
    'blog_content' => 'markdown_formatter.blog_content',
    'seo_data' => 'markdown_formatter.seo_data',
    'image_data' => 'markdown_formatter.image_data',
    'metadata' => 'markdown_formatter.metadata'
  }

  end_node.update!(configuration: end_config)
  puts '✅ Updated End node output mapping to extract all fields'
  puts ''
end

# Display updated configuration
puts 'UPDATED CONFIGURATION:'
puts '-' * 80
puts 'Markdown Formatter Node:'
puts "  • Prompt Template: #{updated_prompt.lines.first(3).join.strip}..."
puts "  • Response Format: json"
puts "  • Preserve Data: true"
puts ''
puts 'End Node Output Mapping:'
end_node.configuration['output_mapping']&.each do |key, value|
  puts "  • #{key} ← #{value}"
end
puts ''

puts '=' * 80
puts '✅ Markdown formatter updated to preserve all data!'
puts ''
puts 'Next workflow run will output:'
puts '  • markdown: Formatted markdown content'
puts '  • blog_content: Original blog content from editor'
puts '  • seo_data: SEO optimizations'
puts '  • image_data: Image suggestions'
puts '  • metadata: Formatting metadata'
