# frozen_string_literal: true

# Analyze completed workflow run

run_id = '0199e1f8-79a1-7131-ac77-588db4cdb613'
run = AiWorkflowRun.find_by(run_id: run_id)

puts '📊 COMPLETE WORKFLOW ANALYSIS'
puts '=' * 100
puts ''
puts "Run ID: #{run.run_id}"
puts "Status: #{run.status}"
puts "Duration: #{run.duration_ms}ms (#{(run.duration_ms / 1000.0).round(2)}s)"
puts "Nodes: #{run.completed_nodes} / #{run.total_nodes}"
puts ''
puts '=' * 100
puts ''

# Get all node executions in order
executions = run.ai_workflow_node_executions.order(:created_at)

executions.each_with_index do |exec, i|
  puts "#{i + 1}. #{exec.node_id.upcase} (#{exec.node_type})"
  puts "   Status: #{exec.status}"
  puts "   Duration: #{exec.duration_ms}ms"
  puts ''

  # Input data
  if exec.input_data.present?
    puts "   📥 INPUT (#{exec.input_data.keys.size} keys):"
    exec.input_data.keys.sort.each do |key|
      value = exec.input_data[key]
      preview = if value.is_a?(String)
        value.length > 100 ? "#{value[0..100]}... [#{value.length} chars]" : value
      elsif value.is_a?(Hash)
        "[Hash with #{value.keys.size} keys]"
      else
        value.inspect
      end
      puts "      • #{key}: #{preview}"
    end
    puts ''
  end

  # Output data
  if exec.output_data.present?
    puts "   📤 OUTPUT (#{exec.output_data.keys.size} keys):"

    if exec.output_data['output']
      output = exec.output_data['output']
      if output.is_a?(String)
        preview = output[0..200]
        puts "      • output: #{preview}... [#{output.length} chars total]"

        # Check for error patterns
        has_error = output.include?("I don't see") || output.include?("don't have") || output.include?('{{')
        if has_error
          puts "         ⚠️  WARNING: Output may be an error or has unresolved templates"
        end
      else
        puts "      • output: [#{output.class}]"
      end
    end

    exec.output_data.except('output').keys.sort.first(5).each do |key|
      value = exec.output_data[key]
      preview = value.is_a?(String) && value.length > 50 ? "#{value[0..50]}..." : value.inspect[0..50]
      puts "      • #{key}: #{preview}"
    end
    puts ''
  end

  puts '-' * 100
  puts ''
end

# CRITICAL ANALYSIS: Writer Node
puts '🎯 CRITICAL EVALUATION: WRITER NODE'
puts '=' * 100
puts ''

writer_exec = executions.find { |e| e.node_id == 'writer' }

if writer_exec
  puts 'Input Data Keys:'
  writer_exec.input_data.keys.sort.each do |key|
    puts "   • #{key}"
  end
  puts ''

  # Check critical variables
  has_research = writer_exec.input_data.key?('research_output')
  has_outline = writer_exec.input_data.key?('outline_output')
  has_topic = writer_exec.input_data.key?('topic')
  has_audience = writer_exec.input_data.key?('target_audience')
  has_length = writer_exec.input_data.key?('post_length')

  puts 'Critical Variables Check:'
  puts "   research_output: #{has_research ? '✅ PRESENT' : '❌ MISSING'}"
  puts "   outline_output: #{has_outline ? '✅ PRESENT' : '❌ MISSING'}"
  puts "   topic: #{has_topic ? '✅ PRESENT' : '❌ MISSING'}"
  puts "   target_audience: #{has_audience ? '✅ PRESENT' : '❌ MISSING'}"
  puts "   post_length: #{has_length ? '✅ PRESENT' : '❌ MISSING'}"
  puts ''

  # Analyze output
  if writer_exec.output_data && writer_exec.output_data['output']
    output = writer_exec.output_data['output']

    puts 'Output Analysis:'
    puts "   Length: #{output.length} characters"
    puts "   Preview (first 300 chars):"
    puts "   #{'-' * 80}"
    puts "   #{output[0..300]}"
    puts "   #{'-' * 80}"
    puts ''

    # Error detection
    has_dont_see = output.include?("I don't see")
    has_dont_have = output.include?("don't have")
    has_curly_braces = output.include?('{{')
    has_could_you = output.include?('Could you please provide')

    if has_dont_see || has_dont_have || has_curly_braces || has_could_you
      puts '   ❌ OUTPUT EVALUATION: ERROR MESSAGE DETECTED'
      puts '   The output appears to be an error/request message, not actual content'
    else
      puts '   ✅ OUTPUT EVALUATION: ACTUAL CONTENT PRODUCED'
      puts '   The output appears to be genuine blog post content'
    end
  else
    puts '   ❌ No output produced'
  end
else
  puts '❌ Writer node execution not found!'
end

puts ''
puts '=' * 100
puts '🏁 FINAL VERDICT'
puts '=' * 100
puts ''

if run.status == 'completed' && writer_exec
  has_research_output = writer_exec.input_data.key?('research_output')
  output_data = writer_exec.output_data['output']
  is_actual_content = output_data && !output_data.include?("I don't see")

  if has_research_output && is_actual_content
    puts '✅ ✅ ✅ COMPLETE SUCCESS ✅ ✅ ✅'
    puts ''
    puts '   • Workflow completed: ✓'
    puts '   • Writer received research_output: ✓'
    puts '   • Writer received outline_output: ✓'
    puts '   • Writer produced actual content: ✓'
    puts ''
    puts '🎉 THE FIX IS WORKING CORRECTLY!'
  elsif has_research_output
    puts '⚠️  PARTIAL SUCCESS'
    puts '   • Writer received research_output: ✓'
    puts '   • But output still contains errors'
  else
    puts '❌ FIX NOT WORKING'
    puts '   • Writer did NOT receive research_output'
  end
else
  puts "❌ Workflow status: #{run.status}"
end

puts ''
puts '=' * 100
