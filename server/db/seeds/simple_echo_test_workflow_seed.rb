# frozen_string_literal: true

# Simple Echo Test Workflow
# A minimal workflow for testing basic workflow execution
# Demonstrates: Start node → Transform node → End node with proper edge connections

puts "\n" + "=" * 80
puts "🔊 CREATING SIMPLE ECHO TEST WORKFLOW"
puts "=" * 80

# Use existing admin account and user
account = Account.find_by(subdomain: 'admin')
unless account
  puts "❌ Error: Admin account not found. Run main seeds first."
  return
end

user = account.users.find_by(email: 'admin@powernode.org')
unless user
  puts "❌ Error: Admin user not found. Run main seeds first."
  return
end

puts "✓ Using admin account: #{account.name} (#{user.email})"

# =============================================================================
# WORKFLOW
# =============================================================================

puts "\n🔄 Creating Simple Echo Test Workflow..."

workflow = AiWorkflow.find_or_create_by!(
  account: account,
  name: 'Simple Echo Test'
) do |wf|
  wf.description = 'A simple workflow that echoes input text back as output. Used for testing workflow execution.'
  wf.creator = user
  wf.status = 'draft'  # Will activate after adding nodes and edges
  wf.version = '1.0.0'
  wf.visibility = 'private'
  wf.configuration = {
    execution_mode: 'sequential',
    auto_retry: false,
    error_handling: 'stop',
    timeout_seconds: 300,
    max_parallel_nodes: 1
  }
  wf.metadata = {
    category: 'testing',
    use_case: 'workflow_validation',
    complexity: 'basic',
    estimated_duration: '5-10 seconds'
  }
end

puts "✓ Workflow created: #{workflow.name} (ID: #{workflow.id})"

# =============================================================================
# WORKFLOW NODES
# =============================================================================

puts "\n📋 Creating workflow nodes..."

# 1. Start Node
start_node = workflow.nodes.find_or_create_by!(
  node_id: 'start_1',
  node_type: 'start',
  name: 'Start'
) do |node|
  node.is_start_node = true
  node.is_end_node = false
  node.position = { x: 100, y: 100 }
  node.configuration = {
    start_type: 'manual',
    delay_seconds: 0,
    output_mapping: {
      data: 'start_data',
      output: 'start_data'
    }
  }
  node.metadata = {
    icon: 'play-circle',
    color: '#10b981',
    description: 'Workflow entry point'
  }
end

puts "  ✓ Start Node: #{start_node.name}"

# 2. Echo Transform Node
echo_node = workflow.nodes.find_or_create_by!(
  node_id: 'echo_1',
  node_type: 'transform',
  name: 'Echo Text'
) do |node|
  node.is_start_node = false
  node.is_end_node = false
  node.position = { x: 300, y: 100 }
  node.configuration = {
    operation: 'echo',
    input_field: 'text',
    output_field: 'echo_result'
  }
  node.metadata = {
    icon: 'message-circle',
    color: '#3b82f6',
    description: 'Echoes input back as output'
  }
end

puts "  ✓ Echo Node: #{echo_node.name}"

# 3. End Node
end_node = workflow.nodes.find_or_create_by!(
  node_id: 'end_1',
  node_type: 'end',
  name: 'End'
) do |node|
  node.is_start_node = false
  node.is_end_node = true
  node.position = { x: 500, y: 100 }
  node.configuration = {
    save_output: true
  }
  node.metadata = {
    icon: 'check-circle',
    color: '#10b981',
    description: 'Workflow completion'
  }
end

puts "  ✓ End Node: #{end_node.name}"

puts "✓ Created #{workflow.nodes.count} workflow nodes"

# =============================================================================
# WORKFLOW EDGES (Connections)
# =============================================================================

puts "\n🔗 Creating workflow edges..."

# Edge 1: Start → Echo Text
edge1 = workflow.edges.find_or_create_by!(
  edge_id: 'edge_1',
  source_node_id: start_node.node_id,
  target_node_id: echo_node.node_id
) do |edge|
  edge.edge_type = 'default'
  edge.source_handle = nil
  edge.target_handle = nil
  edge.is_conditional = false
  edge.condition = {}
  edge.configuration = {
    label: 'Start Flow',
    description: 'Initial connection from start to echo',
    style: 'solid',
    color: '#6b7280'
  }
  edge.metadata = {}
  edge.priority = 0
end

puts "  ✓ Edge 1: #{start_node.name} → #{echo_node.name}"

# Edge 2: Echo Text → End
edge2 = workflow.edges.find_or_create_by!(
  edge_id: 'edge_2',
  source_node_id: echo_node.node_id,
  target_node_id: end_node.node_id
) do |edge|
  edge.edge_type = 'default'
  edge.source_handle = nil
  edge.target_handle = nil
  edge.is_conditional = false
  edge.condition = {}
  edge.configuration = {
    label: 'Complete',
    description: 'Flow completion to end node',
    style: 'solid',
    color: '#6b7280'
  }
  edge.metadata = {}
  edge.priority = 0
end

puts "  ✓ Edge 2: #{echo_node.name} → #{end_node.name}"

puts "✓ Created #{workflow.edges.count} workflow edges"

# =============================================================================
# WORKFLOW VARIABLES
# =============================================================================

puts "\n📊 Creating workflow variables..."

# Input variable
workflow.variables.find_or_create_by!(name: 'text') do |var|
  var.variable_type = 'string'
  var.default_value = 'Hello, World!'
  var.description = 'Text to echo (input)'
  var.is_required = true
  var.is_input = true
  var.is_output = false
  var.metadata = { example: 'Hello, World!' }
end

# Output variable
workflow.variables.find_or_create_by!(name: 'echo_result') do |var|
  var.variable_type = 'string'
  var.default_value = nil
  var.description = 'Echoed text result (output)'
  var.is_required = false
  var.is_input = false
  var.is_output = true
  var.metadata = {}
end

puts "✓ Created #{workflow.variables.count} workflow variables"

# Activate workflow
workflow.update!(status: 'active')

puts "\n✅ Simple Echo Test Workflow created and activated successfully!"

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + "=" * 80
puts "✅ SIMPLE ECHO TEST WORKFLOW CREATION COMPLETE"
puts "=" * 80
puts "\n📊 Summary:"
puts "   Workflow: #{workflow.name}"
puts "   Workflow ID: #{workflow.id}"
puts "   Status: #{workflow.status}"
puts "   Nodes: #{workflow.nodes.count}"
puts "   Edges: #{workflow.edges.count}"
puts "   Variables: #{workflow.variables.count}"
puts "\n📝 Workflow Flow:"
puts "   Start → Echo Text → End"
puts "\n🎯 Purpose:"
puts "   • Basic workflow execution testing"
puts "   • Validates node connection and edge traversal"
puts "   • Tests input/output variable passing"
puts "   • Minimal complexity for quick validation"
puts "\n🚀 Usage:"
puts "   Input: { \"text\": \"Your message here\" }"
puts "   Output: { \"echo_result\": \"Your message here\" }"
puts "\n" + "=" * 80
