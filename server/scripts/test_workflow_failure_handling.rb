# frozen_string_literal: true

# Test Workflow Failure Handling
# Verifies that when a workflow fails:
# 1. All active nodes are cancelled
# 2. Final status updates are broadcast
# 3. Auto-updates stop after failure

puts '🧪 Testing Workflow Failure Handling'
puts '=' * 80
puts ''

# Find a workflow to test
workflow = AiWorkflow.find('0199e138-d01a-7eaa-8764-91a499a0c6f6')
user = User.first

unless workflow && user
  puts '❌ Test prerequisites not met (workflow or user not found)'
  exit 1
end

puts "✓ Testing workflow: #{workflow.name}"
puts "✓ Test user: #{user.email}"
puts ''

# Create a test run
run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: { 'topic' => 'Test Failure Handling' },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "✓ Created test run: #{run.run_id}"
puts ''

# Monkey-patch to track broadcasts
module BroadcastTracker
  @broadcasts = []

  class << self
    attr_accessor :broadcasts

    def track(event_type, data)
      @broadcasts << { event_type: event_type, data: data, timestamp: Time.current }
      puts "   📡 Broadcast sent: #{event_type}"

      if event_type == 'node.execution.updated'
        puts "      Node: #{data[:node_id]}"
        puts "      Status: #{data[:status]}"
      elsif event_type == 'workflow.failed'
        puts "      Error: #{data.dig(:error, :message)}"
      end
    end

    def reset
      @broadcasts = []
    end

    def node_broadcasts
      @broadcasts.select { |b| b[:event_type] == 'node.execution.updated' }
    end

    def failure_broadcasts
      @broadcasts.select { |b| b[:event_type] == 'workflow.failed' }
    end
  end
end

# Patch AiWorkflowNodeExecution to track broadcasts
AiWorkflowNodeExecution.class_eval do
  alias_method :original_broadcast_node_status_change, :broadcast_node_status_change

  def broadcast_node_status_change
    result = original_broadcast_node_status_change

    BroadcastTracker.track('node.execution.updated', {
      node_id: node_id,
      status: status,
      execution_id: id
    })

    result
  end
end

# Patch WorkflowOrchestrator to track failure broadcast
Mcp::WorkflowOrchestrator.class_eval do
  alias_method :original_broadcast_failure, :broadcast_failure

  def broadcast_failure(error)
    result = original_broadcast_failure(error)

    BroadcastTracker.track('workflow.failed', {
      error: { message: error.message, class: error.class.name }
    })

    result
  end
end

puts '🔧 Monkey-patches applied to track broadcasts'
puts ''

# Force an early failure by creating invalid configuration
# We'll modify the first AI agent node to reference a non-existent agent
begin
  orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)

  # Patch execute_node to force failure on second node
  def orchestrator.execute_node(node)
    if node.position == 2
      raise Mcp::WorkflowOrchestrator::NodeExecutionError, "Simulated node failure for testing"
    end

    super
  end

  puts '📊 Starting workflow execution...'
  puts ''

  # Track node states before execution
  puts '📋 Initial state:'
  run.ai_workflow_node_executions.joins(:ai_workflow_node).order('ai_workflow_nodes.position').each do |ne|
    puts "   #{ne.ai_workflow_node.position}. #{ne.ai_workflow_node.name}: #{ne.status}"
  end
  puts ''

  BroadcastTracker.reset

  # Execute and expect failure
  result = orchestrator.execute

  puts '❌ UNEXPECTED: Workflow completed without error'
  puts "   Result: #{result.inspect[0..200]}"

rescue Mcp::WorkflowOrchestrator::NodeExecutionError => e
  puts '✅ EXPECTED: Workflow failed with node execution error'
  puts "   Error: #{e.message}"
  puts ''

  # Give callbacks time to complete
  sleep 0.5

  puts '📊 Analysis of Failure Handling:'
  puts ''

  # Check workflow run status
  run.reload
  puts '1️⃣ Workflow Run Status:'
  puts "   Status: #{run.status}"
  puts "   Completed at: #{run.completed_at}"
  puts "   Error details: #{run.error_details&.dig('error_message')}"

  if run.status == 'failed'
    puts '   ✅ Workflow correctly marked as failed'
  else
    puts "   ❌ Workflow status is '#{run.status}' instead of 'failed'"
  end
  puts ''

  # Check node execution states
  puts '2️⃣ Node Execution States (after failure):'
  node_executions = run.ai_workflow_node_executions.joins(:ai_workflow_node).order('ai_workflow_nodes.position')

  active_count = 0
  cancelled_count = 0
  completed_count = 0
  failed_count = 0
  pending_count = 0

  node_executions.each do |ne|
    status_symbol = case ne.status
    when 'cancelled' then '🚫'
    when 'failed' then '❌'
    when 'completed' then '✅'
    when 'running' then '▶️'
    when 'pending' then '⏸️'
    else '❓'
    end

    puts "   #{status_symbol} #{ne.ai_workflow_node.position}. #{ne.ai_workflow_node.name}: #{ne.status}"

    case ne.status
    when 'cancelled' then cancelled_count += 1
    when 'completed' then completed_count += 1
    when 'failed' then failed_count += 1
    when 'running' then active_count += 1
    when 'pending' then pending_count += 1
    end
  end
  puts ''

  puts '   Summary:'
  puts "   - Cancelled: #{cancelled_count}"
  puts "   - Failed: #{failed_count}"
  puts "   - Completed: #{completed_count}"
  puts "   - Still running: #{active_count}"
  puts "   - Still pending: #{pending_count}"
  puts ''

  if active_count == 0 && pending_count == 0
    puts '   ✅ All active nodes were properly cancelled'
  else
    puts "   ❌ Found #{active_count + pending_count} nodes still in active/pending state"
  end
  puts ''

  # Check broadcasts
  puts '3️⃣ Broadcast Analysis:'
  node_broadcasts = BroadcastTracker.node_broadcasts
  failure_broadcasts = BroadcastTracker.failure_broadcasts

  puts "   Node status broadcasts: #{node_broadcasts.count}"
  puts "   Workflow failure broadcasts: #{failure_broadcasts.count}"
  puts ''

  if node_broadcasts.any?
    puts '   Node status changes broadcast:'
    node_broadcasts.each do |broadcast|
      node_exec = node_executions.find { |ne| ne.node_id == broadcast[:data][:node_id] }
      node_name = node_exec&.ai_workflow_node&.name || 'Unknown'
      puts "   - #{node_name}: #{broadcast[:data][:status]}"
    end
    puts ''
  end

  # Check if cancelled nodes were broadcast
  cancelled_nodes = node_executions.select { |ne| ne.status == 'cancelled' }
  cancelled_broadcasts = node_broadcasts.select { |b| b[:data][:status] == 'cancelled' }

  puts "   Cancelled nodes: #{cancelled_nodes.count}"
  puts "   Cancellation broadcasts: #{cancelled_broadcasts.count}"

  if cancelled_nodes.count == cancelled_broadcasts.count
    puts '   ✅ All cancellations were broadcast'
  else
    puts "   ⚠️  Mismatch: #{cancelled_nodes.count} cancelled but only #{cancelled_broadcasts.count} broadcasts"
  end
  puts ''

  if failure_broadcasts.any?
    puts '   ✅ Workflow failure was broadcast'
  else
    puts '   ❌ Workflow failure was NOT broadcast'
  end
  puts ''

rescue => e
  puts "❌ Unexpected error: #{e.class.name}"
  puts "   #{e.message}"
  puts "   #{e.backtrace.first(5).join("\n   ")}"
end

puts ''
puts '=' * 80
puts '📋 Test Summary'
puts ''

# Reload and show final state
run.reload
node_executions = run.ai_workflow_node_executions.joins(:ai_workflow_node).order('ai_workflow_nodes.position')

puts "Workflow Status: #{run.status}"
puts "Node States:"
node_executions.each do |ne|
  puts "  - #{ne.ai_workflow_node.name}: #{ne.status}"
end
puts ''

puts "Total Broadcasts: #{BroadcastTracker.broadcasts.count}"
puts "  - Node updates: #{BroadcastTracker.node_broadcasts.count}"
puts "  - Workflow failures: #{BroadcastTracker.failure_broadcasts.count}"
puts ''

# Determine if behavior is correct
all_nodes_finalized = node_executions.all? { |ne| ne.status.in?(%w[completed failed cancelled]) }
workflow_failed = run.status == 'failed'
broadcasts_sent = BroadcastTracker.broadcasts.any?

if all_nodes_finalized && workflow_failed && broadcasts_sent
  puts '✅ SUCCESS: Workflow failure handling is working correctly'
  puts '   - All nodes were finalized (completed/failed/cancelled)'
  puts '   - Workflow was marked as failed'
  puts '   - Status updates were broadcast'
  puts ''
  puts '💡 Expected behavior after failure:'
  puts '   - Frontend receives final status broadcasts'
  puts '   - Auto-updates should stop (no more running nodes)'
  puts '   - UI should show workflow and node failure states'
else
  puts '❌ FAILURE: Issues detected in workflow failure handling'
  puts "   - All nodes finalized: #{all_nodes_finalized}"
  puts "   - Workflow failed: #{workflow_failed}"
  puts "   - Broadcasts sent: #{broadcasts_sent}"
end

puts ''
puts 'Test complete!'
