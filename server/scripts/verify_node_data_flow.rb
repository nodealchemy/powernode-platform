# frozen_string_literal: true

# Verification script for node output and context flow between workflow nodes
#
# This script tests that:
# 1. Node executors return v1.0 standard format (output, data, result, metadata)
# 2. Orchestrator properly stores results in @node_results
# 3. NodeExecutionContext auto-wires predecessor outputs
# 4. Subsequent nodes receive correct input data
# 5. Variables and context flow through the entire workflow

puts '🔍 Verifying Node Output and Context Flow'
puts '=' * 80
puts ''

# Find the workflow
workflow = AiWorkflow.find('0199e138-d01a-7eaa-8764-91a499a0c6f6')
user = User.first

puts "✓ Workflow: #{workflow.name}"
puts "  ID: #{workflow.id}"
puts "  Nodes: #{workflow.ai_workflow_nodes.count}"
puts ''

# Clean up old runs
puts 'Cleaning up old runs...'
AiWorkflowRun.where(ai_workflow_id: workflow.id).destroy_all
puts ''

# Create a test run with comprehensive input variables
run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: {
    'topic' => 'Testing Node Data Flow',
    'target_audience' => 'developers',
    'tone' => 'technical',
    'word_count_target' => 500,
    'primary_keyword' => 'workflow orchestration'
  },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "✓ Created workflow run: #{run.run_id}"
puts ''

# Execute workflow with data flow tracking
puts '🚀 Executing workflow with data flow tracking...'
puts ''

begin
  # Monkey-patch WorkflowOrchestrator to log data flow
  module Mcp
    class WorkflowOrchestrator
      alias_method :original_execute_node, :execute_node

      def execute_node(node)
        puts "  📝 Executing: #{node.name} (#{node.node_id})"

        # Show what data this node receives
        node_context = Mcp::NodeExecutionContext.new(
          node: node,
          workflow_run: @workflow_run,
          execution_context: @execution_context,
          previous_results: @node_results
        )

        puts "     Input keys: #{node_context.input_data.keys.join(', ')}"
        puts "     Variables: #{node_context.scoped_variables.select { |k,v| !k.start_with?('_') && !k.start_with?('node_') }.keys.join(', ')}"
        puts "     Previous results: #{@node_results.keys.join(', ')}" if @node_results.any?

        # Execute the node
        result = original_execute_node(node)

        # Show what data this node produced
        puts "     Output format: #{result.class.name}"
        puts "     Output keys: #{result.keys.join(', ')}" if result.is_a?(Hash)

        if result.is_a?(Hash)
          puts "     ✓ Has 'output': #{result.key?(:output)}"
          puts "     ✓ Has 'data': #{result.key?(:data)}"
          puts "     ✓ Has 'metadata': #{result.key?(:metadata)}"

          if result[:output].present?
            output_preview = result[:output].to_s[0..80]
            puts "     Output preview: #{output_preview}..."
          end

          if result[:data].present?
            puts "     Data keys: #{result[:data].keys.join(', ')}"
          end
        end

        puts ''

        result
      end
    end
  end

  # Execute workflow
  orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
  result = orchestrator.execute

  puts '=' * 80
  puts '✅ EXECUTION COMPLETED'
  puts '=' * 80
  puts ''

  # Reload and analyze results
  run.reload

  puts "📊 Workflow Run Summary:"
  puts "  Status: #{run.status}"
  puts "  Progress: #{run.progress_percentage}%"
  puts "  Completed Nodes: #{run.completed_nodes}/#{run.total_nodes}"
  puts "  Duration: #{run.duration_ms}ms"
  puts ''

  puts "📋 Node Execution Chain Analysis:"
  puts ''

  executions = run.ai_workflow_node_executions.includes(:ai_workflow_node).order(created_at: :asc)

  executions.each_with_index do |execution, index|
    node = execution.ai_workflow_node

    puts "  #{index + 1}. #{node.name} (#{node.node_id})"
    puts "     Status: #{execution.status}"
    puts "     Duration: #{execution.duration_ms}ms" if execution.duration_ms

    # Analyze input data
    if execution.input_data.present?
      input_keys = execution.input_data.keys
      puts "     Input received (#{input_keys.count} keys): #{input_keys.join(', ')}"

      # Check if received data from predecessor
      if index > 0 && input_keys.any? { |k| k.to_s.include?('output') || k.to_s.match?(/^[a-z_]+_output$/) }
        puts "     ✓ Received predecessor output"
      end
    else
      puts "     ⚠️  No input data recorded"
    end

    # Analyze output data
    if execution.output_data.present?
      output_keys = execution.output_data.keys
      puts "     Output produced (#{output_keys.count} keys): #{output_keys.join(', ')}"

      # Check standard format compliance
      has_output = output_keys.include?('output')
      has_data = output_keys.any? { |k| !['output', 'metadata', 'result'].include?(k) }

      puts "     ✓ Standard format: output=#{has_output}, data=#{has_data}"
    else
      puts "     ⚠️  No output data recorded"
    end

    puts ''
  end

  puts '=' * 80
  puts '📈 Data Flow Verification Results'
  puts '=' * 80
  puts ''

  # Verify data flow between consecutive nodes
  data_flow_successful = true

  executions.each_cons(2) do |prev_exec, curr_exec|
    prev_node = prev_exec.ai_workflow_node
    curr_node = curr_exec.ai_workflow_node

    # Check if current node received previous node's output
    if prev_exec.output_data.present? && curr_exec.input_data.present?
      # Look for predecessor output in current node's input
      has_predecessor_output = curr_exec.input_data.keys.any? do |key|
        key.to_s.include?(prev_node.node_id) || key.to_s == 'output'
      end

      if has_predecessor_output
        puts "✓ Data flow: #{prev_node.name} → #{curr_node.name}"
      else
        puts "⚠️  Missing data flow: #{prev_node.name} → #{curr_node.name}"
        puts "   Previous output keys: #{prev_exec.output_data.keys.join(', ')}"
        puts "   Current input keys: #{curr_exec.input_data.keys.join(', ')}"
        data_flow_successful = false
      end
    else
      if prev_exec.output_data.blank?
        puts "⚠️  #{prev_node.name} produced no output"
        data_flow_successful = false
      end
      if curr_exec.input_data.blank?
        puts "⚠️  #{curr_node.name} received no input"
        data_flow_successful = false
      end
    end
  end

  puts ''

  if data_flow_successful
    puts '✅ SUCCESS: Data flow verified through all nodes'
    puts '   All nodes received predecessor outputs correctly'
  else
    puts '❌ ISSUES FOUND: Some nodes did not receive predecessor data'
    puts '   Review output above for specific missing data flows'
  end

  puts ''
  puts '💡 Recommendations:'
  puts '   1. Check NodeExecutionContext.auto_wire_predecessor_outputs'
  puts '   2. Verify node executors return standard format'
  puts '   3. Ensure orchestrator calls build_output_for_context'
  puts '   4. Review node configuration for explicit input_mapping'

rescue => e
  puts '=' * 80
  puts '❌ EXECUTION FAILED'
  puts '=' * 80
  puts "  Error: #{e.message}"
  puts "  Class: #{e.class}"
  puts ''
  puts '  Backtrace:'
  e.backtrace.first(15).each { |line| puts "    #{line}" }
end
