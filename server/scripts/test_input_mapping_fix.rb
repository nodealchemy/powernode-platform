# frozen_string_literal: true

# Test Input Mapping Fix - Execute new workflow to verify data continuity

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')
account = Account.find('0199e138-c1bd-7ae1-bc77-0d2d197ac6ff')
user = account.users.first

puts '🚀 Starting new workflow execution to test input_mapping fix'
puts "Workflow: #{workflow.name} (ID: #{workflow.id})"
puts "Account: #{account.name} (ID: #{account.id})"
puts

run = workflow.ai_workflow_runs.create!(
  account: account,
  triggered_by_user_id: user.id,
  status: 'initializing',
  trigger_type: 'manual',
  input_variables: {
    topic: 'Testing markdown formatter data continuity with input mapping',
    post_length: 'short',
    target_audience: 'developers'
  }
)

puts "✅ Workflow run created: #{run.run_id}"
puts "Status: #{run.status}"
puts

# Execute workflow
orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
puts '⚙️  Starting workflow execution...'
result = orchestrator.execute

run.reload
puts
puts '📊 Execution Complete!'
puts "Run ID: #{run.run_id}"
puts "Status: #{run.status}"
duration = run.completed_at - run.started_at if run.completed_at && run.started_at
puts "Duration: #{duration} seconds" if duration
puts
puts '🔍 Quick verification:'
puts "  Total nodes executed: #{run.ai_workflow_node_executions.count}"
puts "  Completed nodes: #{run.ai_workflow_node_executions.where(status: 'completed').count}"
puts "  Failed nodes: #{run.ai_workflow_node_executions.where(status: 'failed').count}"
