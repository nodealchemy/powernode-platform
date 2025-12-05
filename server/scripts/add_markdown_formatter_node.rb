# frozen_string_literal: true

# Add Markdown Formatter Node to Complete Blog Generation Workflow

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts '❌ Workflow not found'
  exit 1
end

puts '🔧 Adding Markdown Formatter Node to Workflow'
puts '=' * 80
puts ''

# Find existing nodes
seo_node = workflow.ai_workflow_nodes.find_by(node_id: 'seo')
image_node = workflow.ai_workflow_nodes.find_by(node_id: 'image')
end_node = workflow.ai_workflow_nodes.find_by(node_id: 'end')

unless seo_node && image_node && end_node
  puts '❌ Required nodes not found'
  exit 1
end

# Find the Claude Content Creator agent
content_creator = AiAgent.find_by(name: 'Claude Content Creator')
unless content_creator
  puts '❌ Claude Content Creator agent not found'
  exit 1
end

# Create the markdown formatter node
markdown_node = workflow.ai_workflow_nodes.create!(
  node_id: 'markdown_formatter',
  node_type: 'ai_agent',
  name: 'Format as Markdown',
  description: 'Convert the final blog content into properly formatted markdown',
  configuration: {
    agent_id: content_creator.id,
    agent_name: 'Markdown Formatter Agent',
    prompt_template: <<~PROMPT.strip,
      Convert the following blog content into properly formatted markdown.

      Blog Content:
      {{editor_output}}

      SEO Optimizations:
      {{seo_output}}

      Image Suggestions:
      {{image_output}}

      Format the content with:
      - Proper markdown headers (# for title, ## for sections, ### for subsections)
      - Emphasis with *italic* and **bold** where appropriate
      - Bulleted or numbered lists for key points
      - Code blocks with ``` for any code examples
      - Links in [text](url) format
      - Image placeholders with ![alt text](image_url) format
      - Proper spacing and line breaks for readability
      - Table formatting if there are tabular data

      Output the complete blog post in markdown format, ready for publishing.
    PROMPT
    max_tokens: 4000,
    temperature: 0.3
  },
  position: {
    x: seo_node.position['x'].to_i + 150,
    y: ((seo_node.position['y'].to_i + image_node.position['y'].to_i) / 2)
  },
  metadata: {
    created_by: 'system',
    purpose: 'markdown_formatting',
    dependencies: ['editor', 'seo', 'image']
  }
)

puts "✅ Created markdown formatter node: #{markdown_node.node_id}"
puts ''

# Remove old edges from seo/image to end
old_edges = workflow.ai_workflow_edges.where(
  source_node_id: [seo_node.node_id, image_node.node_id],
  target_node_id: end_node.node_id
)

puts "🔧 Removing #{old_edges.count} old edges..."
old_edges.destroy_all
puts ''

# Create new edges: seo → markdown_formatter, image → markdown_formatter
seo_to_markdown = workflow.ai_workflow_edges.create!(
  edge_id: "#{seo_node.node_id}_to_#{markdown_node.node_id}",
  source_node_id: seo_node.node_id,
  target_node_id: markdown_node.node_id,
  edge_type: 'default',
  configuration: {
    output_mapping: {
      'seo_output' => 'output'
    }
  }
)

image_to_markdown = workflow.ai_workflow_edges.create!(
  edge_id: "#{image_node.node_id}_to_#{markdown_node.node_id}",
  source_node_id: image_node.node_id,
  target_node_id: markdown_node.node_id,
  edge_type: 'default',
  configuration: {
    output_mapping: {
      'image_output' => 'output'
    }
  }
)

# Create edge: markdown_formatter → end
markdown_to_end = workflow.ai_workflow_edges.create!(
  edge_id: "#{markdown_node.node_id}_to_#{end_node.node_id}",
  source_node_id: markdown_node.node_id,
  target_node_id: end_node.node_id,
  edge_type: 'default',
  configuration: {
    output_mapping: {
      'final_markdown' => 'output'
    }
  }
)

puts "✅ Created new edges:"
puts "   • #{seo_to_markdown.source_node_id} → #{seo_to_markdown.target_node_id}"
puts "   • #{image_to_markdown.source_node_id} → #{image_to_markdown.target_node_id}"
puts "   • #{markdown_to_end.source_node_id} → #{markdown_to_end.target_node_id}"
puts ''

# Touch updated_at without changing version
workflow.touch

puts '=' * 80
puts '✅ Markdown formatter node added successfully!'
puts "📊 Workflow version: #{workflow.version}"
puts ''

# Display updated workflow structure
puts 'UPDATED WORKFLOW STRUCTURE:'
puts '-' * 80
workflow.reload
workflow.ai_workflow_nodes.order(:created_at).each do |node|
  puts "  • #{node.node_id.ljust(20)} (#{node.node_type}) - #{node.name}"
end
puts ''
puts 'EDGES:'
puts '-' * 80
workflow.ai_workflow_edges.order(:created_at).each do |edge|
  puts "  • #{edge.source_node_id} → #{edge.target_node_id} (#{edge.edge_type})"
end
