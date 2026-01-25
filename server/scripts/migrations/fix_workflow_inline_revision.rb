#!/usr/bin/env ruby
# frozen_string_literal: true

workflow = AiWorkflow.first

# Step 1: Delete the incorrect edges
edge1 = workflow.ai_workflow_edges.find_by(source_node_id: 'quality_gate_1', target_node_id: 'revision_1')
edge2 = workflow.ai_workflow_edges.find_by(source_node_id: 'revision_1', target_node_id: 'quality_gate_1')
edge3 = workflow.ai_workflow_edges.find_by(source_node_id: 'seo_1', target_node_id: 'quality_gate_1')

edge1&.destroy
edge2&.destroy
edge3&.destroy

puts '✅ Deleted incorrect edges'

# Step 2: Create correct inline flow: SEO → Revision → Quality
AiWorkflowEdge.create!(
  ai_workflow: workflow,
  edge_id: 'edge_seo_to_revision',
  source_node_id: 'seo_1',
  target_node_id: 'revision_1',
  edge_type: 'default',
  priority: 0,
  metadata: { created_by: 'workflow_fix' }
)

AiWorkflowEdge.create!(
  ai_workflow: workflow,
  edge_id: 'edge_revision_to_quality',
  source_node_id: 'revision_1',
  target_node_id: 'quality_gate_1',
  edge_type: 'default',
  priority: 0,
  metadata: { created_by: 'workflow_fix' }
)

puts '✅ Created inline flow: SEO → Revision → Quality'
puts ''
puts 'New workflow structure:'
workflow.reload.ai_workflow_edges.order(:created_at).each do |edge|
  source = workflow.ai_workflow_nodes.find_by(node_id: edge.source_node_id)
  target = workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
  puts "  #{source.name} → #{target.name} (#{edge.edge_type})"
end
