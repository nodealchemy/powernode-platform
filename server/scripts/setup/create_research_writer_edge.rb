# frozen_string_literal: true

# Create research → writer edge

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

puts '🔧 Creating Missing Edge'
puts '=' * 80
puts ''

# Check current edges
puts 'Current edges to writer:'
workflow.ai_workflow_edges.where(target_node_id: 'writer').each do |e|
  puts "   #{e.source_node_id} → writer"
end
puts ''

# Verify nodes exist
research_node = workflow.ai_workflow_nodes.find_by(node_id: 'research')
writer_node = workflow.ai_workflow_nodes.find_by(node_id: 'writer')

puts 'Node verification:'
puts "   Research node exists: #{research_node ? '✓' : '✗'}"
puts "   Writer node exists: #{writer_node ? '✓' : '✗'}"
puts ''

if research_node && writer_node
  puts 'Creating edge...'

  begin
    edge = workflow.ai_workflow_edges.create!(
      edge_id: SecureRandom.uuid,
      source_node_id: 'research',
      target_node_id: 'writer',
      edge_type: 'success',
      condition: {},
      configuration: {},
      metadata: {},
      is_conditional: false,
      priority: 0
    )

    puts "   ✓ Edge created successfully!"
    puts "   Database ID: #{edge.id}"
    puts "   Edge ID: #{edge.edge_id}"
    puts ''

    # Verify it was saved
    workflow.reload
    saved_edge = workflow.ai_workflow_edges.find_by(
      source_node_id: 'research',
      target_node_id: 'writer'
    )

    if saved_edge
      puts '   ✓ Verified: Edge exists in database'
      puts ''
      puts 'All edges to writer now:'
      workflow.ai_workflow_edges.where(target_node_id: 'writer').each do |e|
        puts "   ✓ #{e.source_node_id} → writer (#{e.edge_type})"
      end
    else
      puts '   ✗ ERROR: Edge not found after creation!'
    end

  rescue => e
    puts "   ✗ Error creating edge: #{e.message}"
    puts "   Error class: #{e.class}"
    puts e.backtrace.first(5).join("\n")
  end
else
  puts '✗ Cannot create edge - one or both nodes missing'
end

puts ''
puts '=' * 80
puts 'Done!'
