# frozen_string_literal: true

# Test script for data mapping implementation
# Tests that workflow nodes properly receive and pass data between each other

puts "=" * 80
puts "Testing Data Mapping Implementation"
puts "=" * 80
puts ""

# Find the Simple Blog Generation workflow
workflow = AiWorkflow.find_by(name: 'Simple Blog Generation')

if workflow.nil?
  puts "❌ Simple Blog Generation workflow not found"
  exit 1
end

puts "✅ Found workflow:"
puts "   ID: #{workflow.id}"
puts "   Name: #{workflow.name}"
puts "   Nodes: #{workflow.ai_workflow_nodes.count}"
puts "   Edges: #{workflow.ai_workflow_edges.count}"
puts ""

# Find the account and user
account = workflow.account
user = account.users.first

puts "✅ Found account and user:"
puts "   Account: #{account.id}"
puts "   User: #{user.id}"
puts ""

# Execute the workflow with test data
puts "🚀 Starting workflow execution..."
puts ""

begin
  workflow_run = workflow.execute(
    input_variables: {
      'topic' => 'The Future of AI-Powered Workflow Automation',
      'post_length' => 'medium',
      'target_audience' => 'technical professionals'
    },
    user: user
  )

  puts "✅ Workflow execution started successfully!"
  puts "   Run ID: #{workflow_run.run_id}"
  puts "   Status: #{workflow_run.status}"
  puts ""
  puts "⏳ Waiting for workflow to complete..."

  # Wait up to 2 minutes for completion
  timeout = 120
  start_time = Time.current

  while workflow_run.status == 'initializing' || workflow_run.status == 'running'
    sleep 2
    workflow_run.reload
    elapsed = (Time.current - start_time).to_i

    if elapsed > timeout
      puts ""
      puts "⏰ Timeout reached after 2 minutes"
      puts "   Current status: #{workflow_run.status}"
      break
    end

    print "."
  end

  puts ""
  puts ""

  # Reload to get final state
  workflow_run.reload

  puts "📊 Workflow Execution Complete!"
  puts "   Final Status: #{workflow_run.status}"
  puts "   Duration: #{workflow_run.duration_ms}ms" if workflow_run.duration_ms
  puts ""

  # Check node executions
  node_executions = workflow_run.ai_workflow_node_executions.order(:started_at)
  puts "📝 Node Execution Summary:"
  puts ""

  node_executions.each do |ne|
    node = ne.ai_workflow_node
    puts "   #{node.name} (#{node.node_type}):"
    puts "      Status: #{ne.status}"
    puts "      Duration: #{ne.duration_ms}ms" if ne.duration_ms

    # Check if input data includes previous outputs
    input_keys = ne.input_data&.keys || []
    puts "      Input Keys: #{input_keys.join(', ')}" if input_keys.any?

    # Check output data
    output_keys = ne.output_data&.keys || []
    puts "      Output Keys: #{output_keys.join(', ')}" if output_keys.any?

    # For AI agent nodes, show if they received previous agent outputs
    if node.node_type == 'ai_agent'
      has_agent_output = ne.input_data&.key?('agent_output')
      has_any_previous_output = input_keys.any? { |k| k.include?('agent_output') || k.include?('_output') }
      puts "      Received Previous Outputs: #{has_any_previous_output ? '✅ Yes' : '❌ No'}"
    end

    puts ""
  end

  # Check the final output from End node
  puts "=" * 80
  puts "🎯 Final Workflow Result Analysis"
  puts "=" * 80
  puts ""

  end_node_execution = node_executions.find { |ne| ne.ai_workflow_node.node_type == 'end' }
  if end_node_execution
    final_output = end_node_execution.output_data&.dig('final_output')
    workflow_result = end_node_execution.output_data&.dig('workflow_result')

    if workflow_result
      all_outputs = workflow_result['all_node_outputs']
      primary_output = workflow_result['primary_output']
      summary = workflow_result['summary']

      puts "Consolidation Status:"
      puts "   Total Nodes Executed: #{summary&.dig('total_nodes_executed') || 'N/A'}"
      puts "   All Node Outputs Present: #{all_outputs&.any? ? '✅ Yes' : '❌ No'}"
      puts "   Primary Output Present: #{primary_output.present? ? '✅ Yes' : '❌ No'}"
      puts ""

      if all_outputs&.any?
        puts "Node Outputs Collected:"
        all_outputs.keys.each do |node_id|
          node_output = all_outputs[node_id]
          output_data = node_output[:output_data] || node_output['output_data']
          if output_data
            puts "   ✅ #{node_id}: #{output_data.keys.join(', ')}"
          end
        end
        puts ""
      end

      puts "Data Flow Assessment:"
      # Count how many AI agent nodes received previous outputs
      ai_agent_nodes = node_executions.select { |ne| ne.ai_workflow_node.node_type == 'ai_agent' }
      nodes_with_data = ai_agent_nodes.count do |ne|
        input_keys = ne.input_data&.keys || []
        input_keys.any? { |k| k.include?('agent_output') || k.include?('_output') }
      end

      total_ai_nodes = ai_agent_nodes.count
      data_flow_rate = total_ai_nodes > 1 ? ((nodes_with_data - 1).to_f / (total_ai_nodes - 1) * 100).round(1) : 0

      puts "   AI Agent nodes receiving data: #{nodes_with_data - 1}/#{total_ai_nodes - 1} (first doesn't count)"
      puts "   Data Flow Success Rate: #{data_flow_rate}%"
      puts ""

      if data_flow_rate >= 90
        puts "✅ Data mapping is working correctly!"
      elsif data_flow_rate >= 50
        puts "⚠️  Data mapping is partially working"
      else
        puts "❌ Data mapping is not working"
      end
    else
      puts "⚠️  No workflow_result in End node output"
    end
  else
    puts "❌ No End node execution found"
  end

  puts ""
  puts "=" * 80

rescue StandardError => e
  puts ""
  puts "❌ Workflow execution failed: #{e.message}"
  puts ""
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
end
