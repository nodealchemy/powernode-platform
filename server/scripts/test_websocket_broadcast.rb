# frozen_string_literal: true

# Test script to execute a workflow and trigger WebSocket broadcasts

workflow = AiWorkflow.find('0199cbf8-0619-71ff-8b8b-baf62908142a')
user = User.first

# Create workflow run
run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: { input_text: 'Testing WebSocket routing' },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "✓ Created workflow run: #{run.run_id}"
puts "  Watch for WebSocket broadcasts in backend logs..."
puts "  Check browser console for: [WebSocket] Message received"
puts ""

# Execute the workflow
orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
result = orchestrator.execute

puts "✓ Execution completed"
puts "  Final status: #{run.reload.status}"
puts "  Run ID: #{run.run_id}"
