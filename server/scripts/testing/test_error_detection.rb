# frozen_string_literal: true

# Test error detection with invalid model configuration

puts '🧪 Testing Error Detection with Invalid Model'
puts '=' * 80
puts ''

workflow = AiWorkflow.find('0199e138-d01a-7eaa-8764-91a499a0c6f6')
user = User.first

# Create a test run
run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: { 'topic' => 'Test Error Detection' },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "✓ Created run: #{run.run_id}"
puts ''

begin
  orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
  result = orchestrator.execute

  puts '❌ UNEXPECTED: Workflow completed without error'
  puts "Result: #{result.inspect[0..200]}"
rescue => e
  puts '✅ EXPECTED: Workflow failed with error'
  puts "Error Class: #{e.class.name}"
  puts "Error Message: #{e.message}"
  puts ''
end

puts ''
puts 'Test complete!'
