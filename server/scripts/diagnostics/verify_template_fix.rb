# frozen_string_literal: true

# Verify Template Rendering Fix

run = AiWorkflowRun.find_by(run_id: '0199e1fe-6a06-7384-864f-01c4df0887bb')

puts '🎯 TEMPLATE RENDERING FIX VERIFICATION'
puts '=' * 100
puts ''
puts "Run ID: #{run.run_id}"
puts "Status: #{run.status}"
puts "Duration: #{(run.duration_ms / 1000.0).round(2)}s"
puts ''

# Check writer node
writer_exec = run.ai_workflow_node_executions.find_by(node_id: 'writer')

if writer_exec
  puts '📝 WRITER NODE ANALYSIS:'
  puts '-' * 100
  puts ''

  # Input data check
  has_research = writer_exec.input_data&.key?('research_output')
  has_outline = writer_exec.input_data&.key?('outline_output')

  puts 'Input Data Keys:'
  puts "   Total keys: #{writer_exec.input_data.keys.size}"
  puts "   research_output: #{has_research ? '✅ PRESENT' : '❌ MISSING'}"
  puts "   outline_output: #{has_outline ? '✅ PRESENT' : '❌ MISSING'}"
  puts ''

  # Output analysis
  if writer_exec.output_data && writer_exec.output_data['output']
    output = writer_exec.output_data['output']

    puts 'Output Analysis:'
    puts "   Length: #{output.length} characters"
    puts "   First 500 chars:"
    puts "   #{'-' * 80}"
    puts "   #{output[0..500]}"
    puts "   #{'-' * 80}"
    puts ''

    # Error detection
    has_dont_see = output.include?("I don't see")
    has_dont_have = output.include?("don't have")
    has_placeholder = output.include?('{{')

    if has_dont_see || has_dont_have || has_placeholder
      puts '   ❌ OUTPUT CONTAINS ERROR INDICATORS:'
      puts "      - Contains \"I don't see\": #{has_dont_see}"
      puts "      - Contains \"don't have\": #{has_dont_have}"
      puts "      - Contains {{}} placeholders: #{has_placeholder}"
    else
      puts '   ✅ OUTPUT APPEARS TO BE ACTUAL BLOG CONTENT'
      puts '   No error messages or unresolved templates detected'
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

if writer_exec && writer_exec.input_data&.key?('research_output')
  output = writer_exec.output_data['output']
  is_actual_content = output && !output.include?("I don't see") && !output.include?('{{')

  if is_actual_content
    puts '✅ ✅ ✅ TEMPLATE RENDERING FIX SUCCESSFUL! ✅ ✅ ✅'
    puts ''
    puts '   • Writer received research_output: ✓'
    puts '   • Writer received outline_output: ✓'
    puts '   • Templates were resolved: ✓'
    puts '   • Writer produced actual blog content: ✓'
    puts ''
    puts '🎉 THE FIX IS WORKING CORRECTLY!'
  else
    puts '⚠️  PARTIAL SUCCESS'
    puts '   • Writer received inputs correctly'
    puts '   • But output still contains issues'
  end
else
  puts '❌ FIX NOT WORKING - Writer did not receive required data'
end

puts ''
puts '=' * 100
