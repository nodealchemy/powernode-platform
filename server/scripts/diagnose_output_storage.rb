# frozen_string_literal: true

# Diagnostic script to identify why node output key is not being stored

puts '🔬 Diagnosing Node Output Storage Issue'
puts '=' * 80
puts ''

workflow = AiWorkflow.find('0199e138-d01a-7eaa-8764-91a499a0c6f6')
user = User.first

# Clean up
AiWorkflowRun.where(ai_workflow_id: workflow.id).destroy_all

run = workflow.ai_workflow_runs.create!(
  account_id: user.account_id,
  triggered_by_user_id: user.id,
  input_variables: { 'topic' => 'Test Output Storage' },
  status: 'initializing',
  trigger_type: 'manual'
)

puts "Created run: #{run.run_id}"
puts ''

# Monkey-patch to inspect data at key points
module Mcp
  class WorkflowOrchestrator
    alias_method :original_build_output_for_context, :build_output_for_context

    def build_output_for_context(result)
      puts "  🔍 build_output_for_context called"
      puts "     result keys: #{result.keys.join(', ')}"
      puts "     result[:output].present?: #{result[:output].present?}"
      puts "     result[:output] class: #{result[:output].class}"
      puts "     result[:output] value: #{result[:output].inspect[0..100]}"
      puts "     result[:data] keys: #{result[:data].keys.join(', ')}" if result[:data].is_a?(Hash)
      puts ''

      output_data = original_build_output_for_context(result)

      puts "  📦 build_output_for_context result:"
      puts "     output_data keys: #{output_data.keys.join(', ')}"
      puts "     output_data['output'].present?: #{output_data['output'].present?}"
      puts "     output_data.inspect: #{output_data.inspect[0..200]}"
      puts ''

      output_data
    end

    alias_method :original_handle_node_success, :handle_node_success

    def handle_node_success(node, node_execution, result, node_context)
      puts "  ✅ handle_node_success called for: #{node.name}"
      puts "     Node result keys: #{result.keys.join(', ')}"
      puts ''

      original_handle_node_success(node, node_execution, result, node_context)
    end
  end
end

# Patch node execution complete_execution! to see what's being stored
class AiWorkflowNodeExecution
  alias_method :original_complete_execution!, :complete_execution!

  def complete_execution!(output_data_hash = {}, execution_cost = 0)
    puts "  💾 complete_execution! called"
    puts "     output_data_hash keys: #{output_data_hash.keys.join(', ')}"
    puts "     output_data_hash['output'].present?: #{output_data_hash['output'].present?}"
    puts "     output_data_hash.inspect: #{output_data_hash.inspect[0..200]}"
    puts "     Current output_data before merge: #{output_data.keys.join(', ')}"
    puts ''

    result = original_complete_execution!(output_data_hash, execution_cost)

    reload
    puts "  📊 After save - output_data keys in database: #{output_data.keys.join(', ')}"
    puts "     output_data['output'].present?: #{output_data['output'].present?}"
    puts ''

    result
  end
end

puts '🚀 Executing workflow...'
puts ''

orchestrator = Mcp::WorkflowOrchestrator.new(workflow_run: run)
orchestrator.execute

puts '=' * 80
puts '✅ EXECUTION COMPLETED'
puts '=' * 80
puts ''

# Verify results
run.reload
executions = run.ai_workflow_node_executions.includes(:ai_workflow_node).order(created_at: :asc)

puts '📋 Final Storage Analysis:'
puts ''

executions.each do |execution|
  node = execution.ai_workflow_node
  next if node.node_type == 'trigger' || node.node_type == 'start' || node.node_type == 'end'

  puts "Node: #{node.name}"
  puts "  Stored output_data keys: #{execution.output_data.keys.join(', ')}"
  puts "  Has 'output' key: #{execution.output_data.key?('output')}"

  if execution.output_data.key?('output')
    puts "  output value: #{execution.output_data['output'].to_s[0..80]}"
  else
    puts "  ⚠️  'output' key MISSING!"
  end

  puts ''
end
