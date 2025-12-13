# frozen_string_literal: true

# Migrate all existing workflows to conform to new mandatory data flow standard
# This script updates workflow metadata and documentation to reflect that data
# now flows automatically between nodes without explicit configuration.

puts "=" * 80
puts "Migrating Workflows to New Data Flow Standard"
puts "=" * 80
puts ""

# Statistics
total_workflows = 0
updated_workflows = 0
skipped_workflows = 0

# Process all workflows
AiWorkflow.find_each do |workflow|
  total_workflows += 1

  begin
    puts "Processing workflow: #{workflow.name} (#{workflow.id})"

    # Check if workflow has nodes
    nodes_count = workflow.ai_workflow_nodes.count
    edges_count = workflow.ai_workflow_edges.count

    puts "  Nodes: #{nodes_count}, Edges: #{edges_count}"

    if nodes_count == 0
      puts "  ⚠️  Skipping - no nodes"
      skipped_workflows += 1
      next
    end

    # Update workflow metadata to indicate new data flow standard
    metadata = workflow.metadata || {}

    # Add data flow version marker
    metadata['data_flow_version'] = '1.0'
    metadata['data_flow_mode'] = 'automatic'
    metadata['updated_for_standard'] = true
    metadata['migration_date'] = Time.current.iso8601

    # Update workflow description if it doesn't mention data flow
    if workflow.description.present? && !workflow.description.include?('Data flows automatically')
      workflow.description = "#{workflow.description}\n\nData flows automatically between nodes - no configuration required."
    end

    # Update configuration to mark as migrated
    config = workflow.configuration || {}
    config['data_flow'] = {
      'version' => '1.0',
      'mode' => 'automatic',
      'description' => 'All nodes automatically receive outputs from predecessor nodes'
    }

    # Save updates
    workflow.update!(
      metadata: metadata,
      configuration: config
    )

    puts "  ✅ Updated workflow metadata and configuration"
    updated_workflows += 1

    # Check nodes for potential issues
    nodes_without_incoming = workflow.ai_workflow_nodes.reject { |n| n.node_type == 'start' }.select do |node|
      workflow.ai_workflow_edges.where(target_node_id: node.node_id).empty?
    end

    if nodes_without_incoming.any?
      puts "  ⚠️  Warning: #{nodes_without_incoming.count} nodes have no incoming edges:"
      nodes_without_incoming.each do |node|
        puts "     - #{node.name} (#{node.node_type})"
      end
    end

  rescue StandardError => e
    puts "  ❌ Error updating workflow: #{e.message}"
    skipped_workflows += 1
  end

  puts ""
end

# Summary
puts "=" * 80
puts "Migration Summary"
puts "=" * 80
puts ""
puts "Total workflows: #{total_workflows}"
puts "Updated workflows: #{updated_workflows}"
puts "Skipped workflows: #{skipped_workflows}"
puts ""

# Update system configuration to mark migration as complete
if updated_workflows > 0
  puts "✅ Migration completed successfully!"
  puts ""
  puts "All workflows now use automatic data flow:"
  puts "  - Nodes automatically receive outputs from predecessors"
  puts "  - No explicit configuration required"
  puts "  - Optional explicit mapping still supported for advanced use cases"
else
  puts "⚠️  No workflows were updated"
end

puts ""
puts "=" * 80
