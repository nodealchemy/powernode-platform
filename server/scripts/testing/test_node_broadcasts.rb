# frozen_string_literal: true

# Test script to diagnose node execution broadcasts

puts '🔍 Testing Node Execution Broadcast System'
puts '=' * 80
puts ''

# Find the workflow
workflow = AiWorkflow.find('0199e138-d01a-7eaa-8764-91a499a0c6f6')
user = User.first

# Clean up
puts 'Cleaning up old runs...'
AiWorkflowRun.destroy_all
puts ''

# Create new run
run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: { topic: 'Testing Node Broadcasts' },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "✓ Created run: #{run.run_id}"
puts "  Account ID: #{run.account_id}"
puts ''

# Subscribe to check if broadcasts are sent
require 'action_cable/subscription_adapter/test'

puts '📡 Executing workflow and monitoring broadcasts...'
puts ''

# Execute with logging
orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)

# Patch the broadcast method to log all broadcasts
original_broadcast = ActionCable.server.method(:broadcast)
ActionCable.server.define_singleton_method(:broadcast) do |stream, message|
  if stream.include?('ai_orchestration') && message[:event]&.include?('node')
    puts "  🔔 NODE BROADCAST: #{stream}"
    puts "     Event: #{message[:event]}"
    puts "     Node: #{message.dig(:payload, :node_execution, :node, :name)}"
    puts "     Status: #{message.dig(:payload, :node_execution, :status)}"
    puts ''
  end
  original_broadcast.call(stream, message)
end

# Execute
orchestrator.execute

puts ''
puts '✓ Execution complete'
puts ''

# Check what broadcasts should have happened
puts '📊 Node Execution Summary:'
puts ''
run.reload
run.ai_workflow_node_executions.order(created_at: :asc).each_with_index do |execution, index|
  puts "  #{index + 1}. #{execution.ai_workflow_node.name}"
  puts "     Status: #{execution.status}"
  puts "     Started: #{execution.started_at&.strftime('%H:%M:%S')}"
  puts "     Completed: #{execution.completed_at&.strftime('%H:%M:%S')}"
  puts "     Duration: #{execution.duration_ms}ms" if execution.duration_ms
  puts ''
end

puts ''
puts '❓ Expected Broadcasts:'
puts "   - #{run.ai_workflow_node_executions.count * 2} node broadcasts (start + complete for each)"
puts ''
puts '🔍 Check above for actual broadcasts that occurred'
