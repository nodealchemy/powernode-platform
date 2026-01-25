# frozen_string_literal: true

# Add Image Generation node to Complete Blog Generation Workflow
# Inserts between Image Suggestions and Format as Markdown

puts "\n" + "=" * 80
puts "🖼️  ADDING IMAGE GENERATION NODE"
puts "=" * 80
puts ""

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')
unless workflow
  puts "❌ Workflow not found"
  exit 1
end

# Find reference nodes
image_suggestions_node = workflow.ai_workflow_nodes.find_by(node_id: 'image')
markdown_node = workflow.ai_workflow_nodes.find_by(node_id: 'markdown_formatter')

unless image_suggestions_node && markdown_node
  puts "❌ Required nodes not found"
  exit 1
end

# Position between image suggestions and markdown
new_x = image_suggestions_node.position['x'].to_i + 200
new_y = image_suggestions_node.position['y'].to_i

# Find an AI agent to use
sample_agent = workflow.ai_workflow_nodes.where(node_type: 'ai_agent').first
agent_id = sample_agent&.configuration&.dig('agent_id')

# Create the new node
image_gen_node = workflow.ai_workflow_nodes.create!(
  node_id: 'image_generator',
  node_type: 'ai_agent',
  name: 'Generate Images',
  description: 'Generate actual images using AI based on the suggestions - creates visual content with DALL-E or similar',
  is_start_node: false,
  is_end_node: false,
  position: { x: new_x, y: new_y },
  configuration: {
    agent_id: agent_id,
    prompt: 'Based on these image suggestions: {{image_suggestions}}, generate detailed prompts for AI image generation. For each suggested image, create a DALL-E prompt that captures the visual concept. Return a JSON array with: [{"description": "image description", "prompt": "DALL-E prompt", "placement": "where in blog"}]',
    max_tokens: 2000,
    temperature: 0.8,
    timeout: 120,
    output_mapping: {
      generated_images: 'response'
    }
  },
  metadata: {
    icon: 'image',
    color: '#f59e0b',
    description: 'Generate AI images',
    requires_agent: true,
    image_generation: true
  }
)

puts "✅ Created node: Generate Images"
puts "   Node ID: #{image_gen_node.node_id}"
puts "   Position: (#{new_x}, #{new_y})"
puts ""

# Update edges: Remove Image → Markdown, add Image → Generate Images → Markdown
puts "🔗 Updating workflow edges..."
puts ""

old_edge = workflow.ai_workflow_edges.find_by(
  source_node_id: 'image',
  target_node_id: 'markdown_formatter'
)

if old_edge
  puts "❌ Removing: Image Suggestions → Format as Markdown"
  old_edge.destroy!
end

# Create new edge: Image Suggestions → Generate Images
edge1 = workflow.ai_workflow_edges.create!(
  edge_id: 'edge_image_to_gen',
  source_node_id: 'image',
  target_node_id: 'image_generator',
  edge_type: 'success',
  source_handle: nil,
  target_handle: nil,
  is_conditional: false,
  condition: {},
  configuration: {
    label: 'Suggestions Ready',
    description: 'Generate actual images from suggestions',
    style: 'solid',
    color: '#10b981'
  },
  metadata: {},
  priority: 0
)

puts "✅ Added: Image Suggestions → Generate Images"

# Create new edge: Generate Images → Format as Markdown
edge2 = workflow.ai_workflow_edges.create!(
  edge_id: 'edge_gen_to_markdown',
  source_node_id: 'image_generator',
  target_node_id: 'markdown_formatter',
  edge_type: 'success',
  source_handle: nil,
  target_handle: nil,
  is_conditional: false,
  condition: {},
  configuration: {
    label: 'Images Generated',
    description: 'Format blog with generated images',
    style: 'solid',
    color: '#10b981'
  },
  metadata: {},
  priority: 0
)

puts "✅ Added: Generate Images → Format as Markdown"
puts ""

puts "=" * 80
puts "📊 UPDATED WORKFLOW STRUCTURE"
puts "=" * 80
puts ""
puts "🔗 All Edges:"
puts "-" * 80
workflow.ai_workflow_edges.reload.order(:created_at).each do |edge|
  source = workflow.ai_workflow_nodes.find_by(node_id: edge.source_node_id)
  target = workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
  puts "  #{source.name.ljust(25)} → #{target.name.ljust(25)} (#{edge.edge_type})"
end
puts ""
puts "🎨 New Parallel Path:"
puts "  Edit & Refine"
puts "    ├─→ SEO Optimization → Format as Markdown"
puts "    └─→ Image Suggestions → Generate Images → Format as Markdown"
puts ""
puts "=" * 80
