# frozen_string_literal: true

# Execute and Monitor Complete Blog Generation Workflow

puts '🎬 Executing and Monitoring Workflow'
puts '=' * 100
puts ''

# Find workflow
workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts '❌ Workflow not found'
  exit 1
end

puts "Workflow: #{workflow.name}"
puts "Workflow ID: #{workflow.id}"
puts ''

# Verify edge configuration
puts '📋 Pre-Flight Check:'
edges_to_writer = workflow.ai_workflow_edges.where(target_node_id: 'writer')
puts "   Edges to writer node: #{edges_to_writer.count}"
edges_to_writer.each do |edge|
  puts "      ✓ #{edge.source_node_id} → writer (#{edge.edge_type})"
end
puts ''

# Get user and account
user = User.first
account = user.account

# Create workflow run
puts '🚀 Creating New Workflow Run...'
input_variables = {
  'topic' => 'The Future of Artificial Intelligence in Healthcare',
  'target_audience' => 'healthcare professionals',
  'post_length' => 'medium'
}

puts "   Topic: #{input_variables['topic']}"
puts "   Target Audience: #{input_variables['target_audience']}"
puts "   Post Length: #{input_variables['post_length']}"
puts ''

run = workflow.execute(
  input_variables: input_variables,
  user: user,
  trigger_type: 'manual',
  trigger_context: { initiated_by: 'monitoring_script' }
)

puts "✓ Workflow run created: #{run.run_id}"
puts "   Status: #{run.status}"
puts "   Created: #{run.created_at}"
puts ''

# Monitor execution
puts '⏳ Monitoring Execution...'
puts '   (Waiting for worker to process job...)'
puts ''

# Wait for execution to complete
max_wait = 120 # 2 minutes
start_time = Time.current
last_status = run.status

loop do
  sleep 2
  run.reload

  elapsed = Time.current - start_time

  if run.status != last_status
    puts "   Status changed: #{last_status} → #{run.status} (#{elapsed.round(1)}s elapsed)"
    last_status = run.status
  end

  break if %w[completed failed cancelled].include?(run.status)

  if elapsed > max_wait
    puts "   ⚠️  Timeout: Execution exceeded #{max_wait}s"
    break
  end
end

puts ''
puts '=' * 100
puts '📊 EXECUTION RESULTS'
puts '=' * 100
puts ''

# Reload to get final state
run.reload

puts "Final Status: #{run.status}"
puts "Total Duration: #{run.duration_ms}ms (#{(run.duration_ms / 1000.0).round(2)}s)"
puts "Nodes Executed: #{run.completed_nodes} / #{run.total_nodes}"
puts ''

# Analyze each node execution
puts '🔍 NODE-BY-NODE ANALYSIS:'
puts '-' * 100
puts ''

node_executions = run.ai_workflow_node_executions.order(:created_at)

node_executions.each_with_index do |exec, i|
  # Get node name from the workflow
  node = workflow.ai_workflow_nodes.find_by(node_id: exec.node_id)
  node_name = node&.name || exec.node_id

  puts "#{i + 1}. #{node_name} (#{exec.node_id})"
  puts "   Type: #{exec.node_type}"
  puts "   Status: #{exec.status}"
  puts "   Duration: #{exec.duration_ms}ms" if exec.duration_ms
  puts ''

  # Input Data Analysis
  if exec.input_data.present?
    puts "   📥 INPUT DATA (#{exec.input_data.keys.size} keys):"
    exec.input_data.each do |key, value|
      value_preview = if value.is_a?(String)
        value.length > 80 ? "#{value[0..80]}... (#{value.length} chars)" : value
      else
        value.inspect
      end
      puts "      • #{key}: #{value_preview}"
    end
    puts ''
  end

  # Output Data Analysis
  if exec.output_data.present?
    puts "   📤 OUTPUT DATA (#{exec.output_data.keys.size} keys):"

    # Show output key specially
    if exec.output_data['output']
      output = exec.output_data['output']
      output_preview = output.is_a?(String) ?
        (output.length > 150 ? "#{output[0..150]}... (#{output.length} chars total)" : output) :
        output.inspect

      puts "      • output: #{output_preview}"

      # Check if it looks like an error
      if output.is_a?(String) && (output.include?("I don't see") || output.include?("don't have"))
        puts "         ⚠️  WARNING: Output appears to be an error message"
      end
    end

    # Show other keys
    exec.output_data.except('output').each do |key, value|
      value_preview = value.is_a?(String) && value.length > 50 ? "#{value[0..50]}..." : value.inspect
      puts "      • #{key}: #{value_preview}"
    end
    puts ''
  end

  # Error Analysis
  if exec.error_details.present? && !exec.error_details.empty?
    puts "   ❌ ERROR:"
    error_msg = exec.error_details.is_a?(Hash) ? exec.error_details['message'] || exec.error_details.inspect : exec.error_details
    puts "      #{error_msg}"
    puts ''
  end

  puts '-' * 100
  puts ''
end

# Summary Analysis
puts '📈 SUMMARY ANALYSIS:'
puts ''

success_count = node_executions.count { |e| e.status == 'completed' }
failure_count = node_executions.count { |e| e.status == 'failed' }

puts "Successful Nodes: #{success_count} / #{node_executions.count}"
puts "Failed Nodes: #{failure_count} / #{node_executions.count}"
puts ''

# Check writer node specifically
writer_exec = node_executions.find { |e| e.node_id == 'writer' }

if writer_exec
  puts '🎯 WRITER NODE EVALUATION:'
  puts ''

  # Check for research_output
  has_research = writer_exec.input_data&.key?('research_output')
  has_outline = writer_exec.input_data&.key?('outline_output')

  puts "   Input Variables:"
  puts "      • research_output: #{has_research ? '✓ PRESENT' : '✗ MISSING'}"
  puts "      • outline_output: #{has_outline ? '✓ PRESENT' : '✗ MISSING'}"
  puts ''

  # Evaluate output quality
  if writer_exec.output_data && writer_exec.output_data['output']
    output = writer_exec.output_data['output']

    is_error_message = output.include?("I don't see") ||
                       output.include?("don't have") ||
                       output.include?("{{")

    puts "   Output Evaluation:"
    if is_error_message
      puts "      ✗ Output is an error message or contains unresolved templates"
      puts "      Issue: #{output[0..200]}"
    else
      puts "      ✓ Output appears to be actual blog content"
      puts "      Length: #{output.length} characters"
      puts "      Preview: #{output[0..150]}..."
    end
  else
    puts "   ✗ No output produced"
  end
  puts ''
end

# Final verdict
puts '=' * 100
puts '🏁 FINAL VERDICT:'
puts '=' * 100
puts ''

if run.status == 'completed' && success_count == node_executions.count
  if writer_exec && writer_exec.input_data&.key?('research_output')
    puts '✅ SUCCESS: Workflow completed with all nodes successful'
    puts '✅ VERIFICATION: Writer node received research_output'
    puts '✅ FIX CONFIRMED: The research → writer edge is working correctly!'
  else
    puts '⚠️  PARTIAL SUCCESS: Workflow completed but writer node missing research_output'
    puts '   This may indicate the edge wasn\'t used or data flow issue persists'
  end
elsif run.status == 'failed'
  puts '❌ FAILURE: Workflow execution failed'
  puts "   Failed nodes: #{failure_count}"
else
  puts "⏸️  INCOMPLETE: Workflow status is #{run.status}"
end

puts ''
puts '=' * 100
puts "Monitoring complete! Run ID: #{run.run_id}"
puts '=' * 100
