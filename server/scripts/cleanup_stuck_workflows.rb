# frozen_string_literal: true

# Cleanup Stuck Workflow Runs
# Finds and cancels workflow runs stuck in running/initializing states

puts '🧹 Cleaning Up Stuck Workflow Runs'
puts '=' * 80
puts ''

# Find all running or initializing workflow runs
stuck_runs = AiWorkflowRun.where(status: [ 'running', 'initializing' ])

if stuck_runs.empty?
  puts '✓ No stuck workflow runs found'
  exit 0
end

puts "Found #{stuck_runs.count} stuck workflow run(s):"
puts ''

stuck_runs.each do |run|
  puts "📋 Run: #{run.run_id}"
  puts "   Status: #{run.status}"
  puts "   Workflow: #{run.ai_workflow.name}"
  puts "   Started: #{run.created_at}"
  puts "   Topic: #{run.input_variables['topic']}" if run.input_variables['topic']

  # Count active node executions
  active_nodes = run.ai_workflow_node_executions.where(status: [ 'running', 'pending' ])
  puts "   Active nodes: #{active_nodes.count}"
  puts ''

  # Cancel all active node executions
  if active_nodes.any?
    puts "   Cancelling #{active_nodes.count} active node execution(s)..."
    active_nodes.each do |node_exec|
      begin
        node_exec.update!(
          status: 'cancelled',
          cancelled_at: Time.current,
          completed_at: Time.current,
          error_details: (node_exec.error_details || {}).merge({
            'cancellation_reason' => 'Manual cleanup - workflow stuck',
            'cancelled_at' => Time.current.iso8601
          })
        )
        puts "      ✓ Cancelled: #{node_exec.ai_workflow_node.name}"
      rescue => e
        puts "      ✗ Failed to cancel: #{node_exec.ai_workflow_node.name} - #{e.message}"
      end
    end
    puts ''
  end

  # Mark workflow as cancelled
  begin
    run.update!(
      status: 'cancelled',
      completed_at: Time.current,
      error_details: {
        'error_message' => "Workflow manually cancelled - was stuck in #{run.status} state",
        'cancelled_at' => Time.current.iso8601,
        'cancellation_reason' => 'Manual cleanup via script'
      }
    )
    puts "   ✓ Workflow marked as cancelled"
  rescue => e
    puts "   ✗ Failed to cancel workflow: #{e.message}"
  end

  puts ''
  puts '-' * 80
  puts ''
end

puts '✅ Cleanup complete!'
puts ''

# Show summary
remaining = AiWorkflowRun.where(status: [ 'running', 'initializing' ])
puts "Remaining stuck runs: #{remaining.count}"
