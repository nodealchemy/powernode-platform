# frozen_string_literal: true

# Test script to verify the trigger node type fix

puts '🧪 Testing Workflow Execution After Trigger Node Fix'
puts '=' * 80
puts ''

# Get the workflow
workflow = AiWorkflow.find('0199e138-d01a-7eaa-8764-91a499a0c6f6')
user = User.first

puts "✓ Workflow: #{workflow.name}"
puts "  ID: #{workflow.id}"
puts "  Start node type: #{workflow.ai_workflow_nodes.find_by(is_start_node: true).node_type}"
puts ''

# Create a test run
run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: {
    topic: 'Testing Trigger Node Type Fix',
    target_audience: 'developers',
    tone: 'technical',
    word_count_target: 500,
    primary_keyword: 'workflow orchestration'
  },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "✓ Created workflow run: #{run.run_id}"
puts "  Status: #{run.status}"
puts ''

# Execute using MCP WorkflowOrchestrator with correct syntax
begin
  puts '📋 Initializing orchestrator with keyword argument...'
  orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)

  puts '✓ Orchestrator initialized'
  puts '🚀 Executing workflow...'
  puts ''

  result = orchestrator.execute

  run.reload
  puts '=' * 80
  puts '✅ EXECUTION COMPLETED'
  puts '=' * 80
  puts "  Final Status: #{run.status}"
  puts "  Progress: #{run.progress_percentage}%"
  puts "  Completed Nodes: #{run.completed_nodes}/#{run.total_nodes}"
  puts "  Duration: #{run.duration_ms}ms" if run.duration_ms
  puts ''

  if run.status == 'failed'
    puts '❌ EXECUTION FAILED'
    puts "  Error: #{run.error_details}"
  elsif run.completed_nodes > 0
    puts '✅ SUCCESS: Start node executed without "Unknown node type" error!'
  end

rescue => e
  puts '=' * 80
  puts '❌ EXECUTION FAILED'
  puts '=' * 80
  puts "  Error: #{e.message}"
  puts "  Class: #{e.class}"
  puts ''
  puts '  Backtrace:'
  e.backtrace.first(10).each { |line| puts "    #{line}" }
end
