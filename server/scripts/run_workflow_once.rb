#!/usr/bin/env ruby
# frozen_string_literal: true

workflow = AiWorkflow.find_by(name: 'Blog Generation Pipeline')
account = Account.first
user = account.users.first

puts '🚀 BLOG GENERATION PIPELINE - SINGLE EXECUTION TEST'
puts '═══════════════════════════════════════════════════════'
puts ''

# Check for existing runs before starting
existing_runs_before = workflow.ai_workflow_runs.count
puts '📊 Pre-execution Status:'
puts "   Existing runs: #{existing_runs_before}"
puts ''

# Create test input
test_input = {
  'topic' => 'The Impact of AI on Modern Software Engineering',
  'target_audience' => 'senior software engineers and technical leads',
  'tone' => 'technical and analytical',
  'word_count' => 2000,
  'keywords' => [ 'AI', 'software engineering', 'development tools', 'productivity' ]
}

puts '📝 TEST INPUT:'
puts "   Topic: #{test_input['topic']}"
puts "   Audience: #{test_input['target_audience']}"
puts "   Tone: #{test_input['tone']}"
puts "   Word Count: #{test_input['word_count']}"
puts "   Keywords: #{test_input['keywords'].join(', ')}"
puts ''

# Create workflow run
puts '🔨 CREATING WORKFLOW RUN...'
workflow_run = AiWorkflowRun.create!(
  ai_workflow: workflow,
  account: account,
  triggered_by_user_id: user.id,
  trigger_type: 'manual',
  status: 'initializing',
  input_variables: test_input,
  runtime_context: {
    'test_mode' => true,
    'execution_timestamp' => Time.current.iso8601
  }
)

puts '✅ Workflow Run Created'
puts "   Run ID: #{workflow_run.run_id}"
puts "   Database ID: #{workflow_run.id}"
puts ''

# Check for duplicate creation
existing_runs_after_create = workflow.ai_workflow_runs.count
if existing_runs_after_create > existing_runs_before + 1
  puts "⚠️  WARNING: Multiple runs created! Expected 1, got #{existing_runs_after_create - existing_runs_before}"
  puts ''
end

# Initialize orchestrator
puts '🎭 INITIALIZING ORCHESTRATOR...'
orchestrator = Mcp::WorkflowOrchestrator.new(
  workflow_run: workflow_run,
  account: account,
  user: user
)
puts '✅ Orchestrator initialized'
puts ''

# Execute workflow
puts '▶️  STARTING EXECUTION...'
puts '═══════════════════════════════════════════════════════'
puts ''

start_time = Time.current
result = orchestrator.execute
execution_time = (Time.current - start_time).round(2)

puts ''
puts '═══════════════════════════════════════════════════════'
puts '📊 EXECUTION COMPLETE'
puts '═══════════════════════════════════════════════════════'
puts ''

# Reload to get updated data
workflow_run.reload

puts "⏱️  Execution Time: #{execution_time}s"
puts "📈 Final Status: #{workflow_run.status}"
puts "💰 Total Cost: $#{workflow_run.total_cost}"
puts "📊 Progress: #{workflow_run.progress_percentage.to_i}%"
puts ''

# Check for duplicate runs after execution
existing_runs_final = workflow.ai_workflow_runs.count
if existing_runs_final > existing_runs_after_create
  puts '⚠️  WARNING: Additional runs created during execution!'
  puts "   Expected: #{existing_runs_after_create}, Found: #{existing_runs_final}"
  puts "   Duplicate runs: #{existing_runs_final - existing_runs_after_create}"
  puts ''
end

# Get all node executions
node_executions = workflow_run.ai_workflow_node_executions.order(:created_at)

puts '📋 NODE EXECUTION SUMMARY:'
puts '─────────────────────────────────────────────────────'
puts ''

node_executions.each_with_index do |node_exec, index|
  node = workflow.ai_workflow_nodes.find_by(id: node_exec.ai_workflow_node_id)

  status_icon = case node_exec.status
  when 'completed' then '✅'
  when 'failed' then '❌'
  when 'running' then '▶️'
  else '⏸️'
  end

  duration = node_exec.duration_ms ? "#{node_exec.duration_ms}ms" : 'N/A'
  cost = node_exec.cost ? "$#{node_exec.cost}" : '$0.00'

  puts "#{index + 1}. #{status_icon} #{node.name}"
  puts "   Type: #{node.node_type}"
  puts "   Status: #{node_exec.status}"
  puts "   Duration: #{duration}"
  puts "   Cost: #{cost}"

  if node_exec.error_details.present? && node_exec.error_details['error_message']
    puts "   ❌ Error: #{node_exec.error_details['error_message']}"
  end

  if node_exec.output_data.present? && node_exec.output_data.keys.any?
    puts "   📤 Output Keys: #{node_exec.output_data.keys.first(3).join(', ')}"
  end

  puts ''
end

puts '═══════════════════════════════════════════════════════'
puts '📊 FINAL SUMMARY'
puts '═══════════════════════════════════════════════════════'
puts ''

completed_nodes = node_executions.where(status: 'completed').count
failed_nodes = node_executions.where(status: 'failed').count
total_nodes = node_executions.count

puts "✅ Completed Nodes: #{completed_nodes}/#{total_nodes}"
puts "❌ Failed Nodes: #{failed_nodes}/#{total_nodes}"
puts "⏱️  Total Duration: #{execution_time}s"
puts "💰 Total Cost: $#{workflow_run.total_cost}"
puts ''

# Duplicate run check summary
puts '🔍 DUPLICATE RUN CHECK:'
puts "   Runs before execution: #{existing_runs_before}"
puts "   Runs after creation: #{existing_runs_after_create}"
puts "   Runs after execution: #{existing_runs_final}"
puts "   Expected: #{existing_runs_before + 1}"
puts "   Actual: #{existing_runs_final}"

if existing_runs_final == existing_runs_before + 1
  puts '   ✅ No duplicate runs detected'
else
  puts "   ⚠️  Duplicate runs detected: #{existing_runs_final - existing_runs_before - 1}"
end
puts ''

# Overall result
if workflow_run.status == 'completed' && completed_nodes == total_nodes
  puts '🎉 SUCCESS - Workflow executed successfully!'
  puts '   ✓ All nodes completed'
  puts '   ✓ No errors encountered'
  puts '   ✓ Output generated'
elsif workflow_run.status == 'failed'
  puts '❌ FAILURE - Workflow execution failed'
  puts "   ✗ #{failed_nodes} node(s) failed"
  puts "   ✗ #{total_nodes - completed_nodes - failed_nodes} node(s) incomplete"
else
  puts "⚠️  PARTIAL - Workflow status: #{workflow_run.status}"
  puts "   ✓ #{completed_nodes} completed"
  puts "   ✗ #{failed_nodes} failed"
end

puts ''
puts '═══════════════════════════════════════════════════════'
