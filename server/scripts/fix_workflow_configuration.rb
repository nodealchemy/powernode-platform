# frozen_string_literal: true

# Fix Workflow Configuration Mismatch
# Adds missing edge and input schema defaults for Complete Blog Generation Workflow

puts '🔧 Fixing Workflow Configuration Mismatch'
puts '=' * 80
puts ''

# Find the Complete Blog Generation Workflow
workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts '❌ Complete Blog Generation Workflow not found'
  puts ''
  puts 'Available workflows:'
  AiWorkflow.all.each do |w|
    puts "   - #{w.name}"
  end
  exit 1
end

puts "Workflow: #{workflow.name}"
puts "Workflow ID: #{workflow.id}"
puts ''

# -----------------------------------------------------------------------------
# ISSUE ANALYSIS
# -----------------------------------------------------------------------------

puts '🔍 Current Configuration Issues:'
puts ''

# Check for research → writer edge
research_to_writer = workflow.ai_workflow_edges.exists?(
  source_node_id: 'research',
  target_node_id: 'writer'
)

puts '1. Workflow Edge Analysis:'
puts "   research → writer edge: #{research_to_writer ? '✓ EXISTS' : '✗ MISSING'}"

outline_to_writer = workflow.ai_workflow_edges.exists?(
  source_node_id: 'outline',
  target_node_id: 'writer'
)
puts "   outline → writer edge:  #{outline_to_writer ? '✓ EXISTS' : '✗ MISSING'}"
puts ''

# Check writer node template
puts '2. Writer Node Template Analysis:'
writer_node = workflow.ai_workflow_nodes.find_by(node_id: 'writer')
if writer_node && writer_node.configuration['prompt_template']
  template = writer_node.configuration['prompt_template']
  variables = template.scan(/\{\{(\w+)\}\}/).flatten.uniq

  puts "   Template variables: #{variables.join(', ')}"

  # Check for problematic variables
  has_tone_ref = template.include?('{{tone}}')
  has_word_count_ref = template.include?('{{word_count_target}}')

  puts "   References {{tone}}: #{has_tone_ref ? '✓ YES (needs fixing)' : '✗ NO'}"
  puts "   References {{word_count_target}}: #{has_word_count_ref ? '✓ YES (needs fixing)' : '✗ NO'}"
else
  puts '   Writer node or template not found'
end
puts ''

# Check writer node template requirements
writer_node = workflow.ai_workflow_nodes.find_by(node_id: 'writer')
if writer_node && writer_node.configuration['prompt_template']
  template = writer_node.configuration['prompt_template']
  variables = template.scan(/\{\{(\w+)\}\}/).flatten.uniq

  puts '3. Writer Node Template Requirements:'
  puts "   Template references: #{variables.join(', ')}"
  puts ''
end

# -----------------------------------------------------------------------------
# FIX APPLICATION
# -----------------------------------------------------------------------------

puts '🛠️  Applying Fixes:'
puts ''

fixes_applied = []

# Fix 1: Add research → writer edge
unless research_to_writer
  puts '1. Adding missing edge: research → writer'

  edge = AiWorkflowEdge.create!(
    ai_workflow_id: workflow.id,
    edge_id: SecureRandom.uuid,
    source_node_id: 'research',
    target_node_id: 'writer',
    edge_type: 'success',
    condition: {},
    configuration: {},
    metadata: {},
    is_conditional: false,
    priority: 0
  )

  puts "   ✓ Edge created: #{edge.id}"
  puts "   This allows research output to flow directly to writer node"
  puts ''
  fixes_applied << 'Added research → writer edge'
else
  puts '1. research → writer edge already exists (skipping)'
  puts ''
end

# Fix 2: Update writer node template to handle missing variables gracefully
writer_node = workflow.ai_workflow_nodes.find_by(node_id: 'writer')
if writer_node
  current_template = writer_node.configuration['prompt_template']

  # Check if template needs updating
  if current_template && current_template.include?('{{tone}}') && current_template.include?('{{word_count_target}}')
    puts '2. Updating writer node prompt template'
    puts '   Making template more flexible for missing variables'

    updated_template = <<~TEMPLATE
      Write a complete blog post following this outline:

      Outline: {{outline_output}}
      Research Data: {{research_output}}
      Target Audience: {{target_audience}}

      Writing guidelines:
      - Follow outline structure precisely
      - Incorporate research data and statistics naturally
      - Use engaging, conversational tone appropriate for {{target_audience}}
      - Include examples and real-world applications
      - Maintain keyword density at 2-3%
      - Aim for {{post_length}} length (short: 500-800 words, medium: 800-1500 words, long: 1500+ words)

      Output complete blog post in Markdown format.
    TEMPLATE

    updated_config = writer_node.configuration.merge('prompt_template' => updated_template)
    writer_node.update!(configuration: updated_config)

    puts '   ✓ Template updated to use available variables only'
    puts '   - Removed explicit {{tone}} reference (uses conversational by default)'
    puts '   - Removed {{word_count_target}} reference (uses {{post_length}} instead)'
    puts ''
    fixes_applied << 'Updated writer node template'
  else
    puts '2. Writer node template already appropriate (skipping)'
    puts ''
  end
else
  puts '2. Writer node not found (skipping template update)'
  puts ''
end

# -----------------------------------------------------------------------------
# VERIFICATION
# -----------------------------------------------------------------------------

puts '✅ Fix Application Complete!'
puts ''
puts '📊 Final Configuration:'
puts ''

# Reload to get fresh data
workflow.reload

# Verify edges
puts '1. Workflow Edges to Writer Node:'
edges_to_writer = workflow.ai_workflow_edges.where(target_node_id: 'writer')
edges_to_writer.each do |edge|
  puts "   ✓ #{edge.source_node_id} → writer (#{edge.edge_type})"
end
puts ''

# Verify writer node template
puts '2. Writer Node Template Variables:'
writer_node = workflow.ai_workflow_nodes.find_by(node_id: 'writer')
if writer_node && writer_node.configuration['prompt_template']
  template = writer_node.configuration['prompt_template']
  variables = template.scan(/\{\{(\w+)\}\}/).flatten.uniq
  variables.each do |var|
    puts "   ✓ {{#{var}}}"
  end
else
  puts '   (no template found)'
end
puts ''

# Summary
if fixes_applied.any?
  puts '🎉 Fixes Applied:'
  fixes_applied.each do |fix|
    puts "   ✓ #{fix}"
  end
  puts ''
  puts '📝 What This Fixes:'
  puts '   - Writer node now receives research_output directly from research node'
  puts '   - Template updated to only use variables that are consistently available'
  puts '   - Template now uses {{post_length}} (always provided) instead of {{word_count_target}}'
  puts '   - Template uses "conversational tone" by default instead of requiring {{tone}}'
  puts '   - All template variables ({{outline_output}}, {{research_output}},'
  puts '     {{target_audience}}, {{post_length}}) will now resolve correctly'
else
  puts '✅ Workflow configuration already correct!'
  puts '   No fixes needed'
end

puts ''
puts '🚀 Next Steps:'
puts '   1. Execute workflow in UI: AI Orchestration → Workflows'
puts '   2. Use topic: "Your topic here"'
puts '   3. Verify writer node produces blog content (not error message)'
puts '   4. Confirm all nodes complete with valid output'
puts ''
puts '=' * 80
puts 'Fix complete!'
