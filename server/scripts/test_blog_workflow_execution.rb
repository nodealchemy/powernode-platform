#!/usr/bin/env ruby
# frozen_string_literal: true

puts '═══════════════════════════════════════════════════════'
puts 'BLOG GENERATION PIPELINE - WORKFLOW EXECUTION TEST'
puts '═══════════════════════════════════════════════════════'
puts ''

# Get workflow and account
workflow = AiWorkflow.find_by(name: 'Blog Generation Pipeline')
account = Account.first
user = account.users.first

unless workflow
  puts '❌ Blog Generation Pipeline workflow not found'
  exit 1
end

puts '📋 WORKFLOW CONFIGURATION'
puts '─────────────────────────────────────────────────────'
puts ''
puts "Name: #{workflow.name}"
puts "Status: #{workflow.status}"
puts "Version: #{workflow.version}"
puts "Nodes: #{workflow.ai_workflow_nodes.count}"
puts "Edges: #{workflow.ai_workflow_edges.count}"
puts "Valid: #{workflow.valid? ? '✅' : '❌'}"
puts ''

# Check orchestrator
if workflow.configuration['orchestrator']
  orchestrator_id = workflow.configuration['orchestrator']['agent_id']
  orchestrator = AiAgent.find_by(id: orchestrator_id)

  puts "Orchestrator: #{orchestrator.name}"
  puts "  Strategy: #{workflow.configuration['orchestrator']['coordination_strategy']}"
  puts "  Error Recovery: #{workflow.configuration['orchestrator']['error_handling']['retry_failed_nodes'] ? 'Enabled' : 'Disabled'}"
  puts "  Checkpointing: #{workflow.configuration['orchestrator']['error_handling']['create_checkpoints'] ? 'Enabled' : 'Disabled'}"
  puts ''
else
  puts '⚠️  No orchestrator assigned'
  puts ''
end

# Display workflow structure
puts '📊 WORKFLOW STRUCTURE'
puts '─────────────────────────────────────────────────────'
puts ''

start_node = workflow.ai_workflow_nodes.find_by(is_start_node: true)
end_node = workflow.ai_workflow_nodes.find_by(is_end_node: true)

puts "Start Node: #{start_node&.name || 'Not found'}"
puts "End Node: #{end_node&.name || 'Not found'}"
puts ''

puts 'Execution Flow:'
workflow.ai_workflow_edges.order(:created_at).each do |edge|
  source = workflow.ai_workflow_nodes.find_by(node_id: edge.source_node_id)
  target = workflow.ai_workflow_nodes.find_by(node_id: edge.target_node_id)
  puts "  #{source.name} → #{target.name}"
end
puts ''

# Prepare test input
test_input = {
  'topic' => 'The Future of AI in Software Development',
  'target_audience' => 'software developers and tech professionals',
  'tone' => 'professional and informative',
  'word_count' => 1500,
  'keywords' => ['artificial intelligence', 'software development', 'automation', 'machine learning']
}

puts '📝 TEST INPUT'
puts '─────────────────────────────────────────────────────'
puts ''
puts "Topic: #{test_input['topic']}"
puts "Target Audience: #{test_input['target_audience']}"
puts "Tone: #{test_input['tone']}"
puts "Word Count: #{test_input['word_count']}"
puts "Keywords: #{test_input['keywords'].join(', ')}"
puts ''

# Create workflow run
puts '🚀 CREATING WORKFLOW RUN'
puts '─────────────────────────────────────────────────────'
puts ''

workflow_run = AiWorkflowRun.create!(
  ai_workflow: workflow,
  account: account,
  triggered_by_user_id: user.id,
  trigger_type: 'manual',
  status: 'initializing',
  input_variables: test_input,
  runtime_context: {
    'test_mode' => true,
    'created_at' => Time.current.iso8601
  }
)

puts "✅ Workflow Run Created"
puts "   ID: #{workflow_run.id}"
puts "   Status: #{workflow_run.status}"
puts ''

# Execute workflow using MCP Orchestrator
begin
  puts '🔧 INITIALIZING MCP WORKFLOW ORCHESTRATOR'
  puts '─────────────────────────────────────────────────────'
  puts ''

  # Check if MCP orchestrator exists
  unless defined?(Mcp::WorkflowOrchestrator)
    puts '❌ Mcp::WorkflowOrchestrator not found'
    puts ''
    puts '⚠️  MCP orchestration system is not available'
    exit 1
  end

  puts '✅ Mcp::WorkflowOrchestrator found'
  puts ''

  # Initialize MCP orchestrator
  orchestrator = Mcp::WorkflowOrchestrator.new(
    workflow_run: workflow_run,
    account: account,
    user: user
  )

  puts '   Orchestrator initialized'
  puts "   Workflow Run ID: #{workflow_run.id}"
  puts "   Initial Status: #{workflow_run.status}"
  puts ''

  puts '▶️  STARTING WORKFLOW EXECUTION'
  puts '─────────────────────────────────────────────────────'
  puts ''

  # Execute workflow synchronously
  start_time = Time.current
  result = orchestrator.execute
  execution_time = (Time.current - start_time).to_i

  puts ''
  puts "✅ Execution completed in #{execution_time}s"
  puts ''

    # Final status
    workflow_run.reload

    puts '📋 EXECUTION RESULTS'
    puts '─────────────────────────────────────────────────────'
    puts ''

    puts "Final Status: #{workflow_run.status}"
    puts "Progress: #{workflow_run.progress_percentage.to_i}%"
    puts "Duration: #{workflow_run.execution_duration_seconds.to_i}s" if workflow_run.execution_duration_seconds
    puts "Total Cost: $#{workflow_run.total_cost}" if workflow_run.total_cost
    puts ''

    # Node execution details
    puts 'Node Executions:'
    workflow_run.ai_workflow_node_executions.order(:created_at).each do |node_exec|
      node = workflow.ai_workflow_nodes.find_by(id: node_exec.ai_workflow_node_id)
      status_icon = case node_exec.status
                    when 'completed' then '✅'
                    when 'failed' then '❌'
                    when 'running' then '▶️'
                    else '⏸️'
                    end

      puts "  #{status_icon} #{node.name} (#{node_exec.status})"

      if node_exec.error_details.present? && node_exec.error_details['error_message']
        puts "     Error: #{node_exec.error_details['error_message']}"
      end
    end
    puts ''

    # Output
    if workflow_run.status == 'completed' && workflow_run.output_variables.present?
      puts '📄 WORKFLOW OUTPUT'
      puts '─────────────────────────────────────────────────────'
      puts ''

      if workflow_run.output_variables['blog_post']
        puts workflow_run.output_variables['blog_post']
      elsif workflow_run.output_variables['final_content']
        puts workflow_run.output_variables['final_content']
      elsif workflow_run.output_variables['variables']
        puts "Output variables: #{workflow_run.output_variables['variables'].inspect}"
      else
        puts "Output keys: #{workflow_run.output_variables.keys.join(', ')}"
      end
      puts ''
    end

    # Error details
    if workflow_run.status == 'failed'
      puts '❌ FAILURE DETAILS'
      puts '─────────────────────────────────────────────────────'
      puts ''

      if workflow_run.error_details
        puts "Error: #{workflow_run.error_details['error']}"
        puts "Message: #{workflow_run.error_details['message']}" if workflow_run.error_details['message']
      end
      puts ''
    end

    # Summary
    puts '═══════════════════════════════════════════════════════'
    puts 'TEST SUMMARY'
    puts '═══════════════════════════════════════════════════════'
    puts ''

    case workflow_run.status
    when 'completed'
      puts '✅ SUCCESS - Workflow executed successfully!'
      puts ''
      puts "✓ All #{workflow_run.ai_workflow_node_executions.where(status: 'completed').count} nodes completed"
      puts "✓ Output generated successfully"
      puts "✓ Orchestrator coordination working"
    when 'failed'
      puts '❌ FAILED - Workflow execution failed'
      puts ''
      failed_nodes = workflow_run.ai_workflow_node_executions.where(status: 'failed')
      puts "✗ #{failed_nodes.count} node(s) failed"
      puts "✗ Review error details above"
    else
      puts "⚠️  INCOMPLETE - Workflow status: #{workflow_run.status}"
      puts ''
      puts "✗ Execution timed out or was interrupted"
    end

rescue Mcp::WorkflowOrchestrator::WorkflowExecutionError => e
  puts "❌ WORKFLOW EXECUTION ERROR: #{e.message}"
  puts ''
  puts "Error Class: #{e.class.name}"
  puts "Workflow Run ID: #{workflow_run.id}" if workflow_run

rescue Mcp::WorkflowOrchestrator::StateTransitionError => e
  puts "❌ STATE TRANSITION ERROR: #{e.message}"
  puts ''
  puts "Error Class: #{e.class.name}"
  puts "Workflow Run ID: #{workflow_run.id}" if workflow_run

rescue => e
  puts "❌ ERROR: #{e.message}"
  puts ''
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
  puts ''
  puts "Workflow Run ID: #{workflow_run.id}" if workflow_run
end

puts ''
puts '═══════════════════════════════════════════════════════'
