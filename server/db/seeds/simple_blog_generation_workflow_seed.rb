# frozen_string_literal: true

# Simple Blog Generation Workflow
# Demonstrates multi-stage AI agent workflow with research, writing, and editing
# Prerequisites: AI providers and agents must be seeded first

puts "\n" + "=" * 80
puts "📝 CREATING SIMPLE BLOG GENERATION WORKFLOW"
puts "=" * 80

# Use existing admin account and user
account = Account.find_by(subdomain: 'admin')
unless account
  puts "❌ Error: Admin account not found. Run main seeds first."
  return
end

user = account.users.find_by(email: 'admin@powernode.org')
unless user
  puts "❌ Error: Admin user not found. Run main seeds first."
  return
end

puts "✓ Using admin account: #{account.name} (#{user.email})"

# Find AI agents (created by enhanced_blog_generation_workflow_seed.rb)
research_agent = AiAgent.find_by(name: 'Blog Research Agent', account: account)
writer_agent = AiAgent.find_by(name: 'Blog Writer Agent', account: account)
editor_agent = AiAgent.find_by(name: 'Blog Editor Agent', account: account)

unless research_agent && writer_agent && editor_agent
  puts "⚠️  Warning: AI agents not found. This workflow requires:"
  puts "   - Blog Research Agent"
  puts "   - Blog Writer Agent"
  puts "   - Blog Editor Agent"
  puts "   Run enhanced_blog_generation_workflow_seed.rb first."
  puts ""
  puts "   Creating workflow anyway for structure demonstration..."
end

puts "✓ AI Agents found:" if research_agent && writer_agent && editor_agent
puts "   - Research Agent: #{research_agent.name}" if research_agent
puts "   - Writer Agent: #{writer_agent.name}" if writer_agent
puts "   - Editor Agent: #{editor_agent.name}" if editor_agent

# =============================================================================
# WORKFLOW
# =============================================================================

puts "\n🔄 Creating Simple Blog Generation Workflow..."

workflow = AiWorkflow.find_or_create_by!(
  account: account,
  name: 'Simple Blog Generation'
) do |wf|
  wf.description = 'Generate a blog post with research, writing, and editing stages'
  wf.creator = user
  wf.status = 'draft'  # Will activate after adding nodes and edges
  wf.version = '1.0.0'
  wf.visibility = 'private'
  wf.configuration = {
    execution_mode: 'sequential',
    timeout_seconds: 600,
    retry_policy: {
      max_retries: 2,
      retry_delay: 5
    },
    data_flow: {
      version: '1.0',
      mode: 'automatic',
      description: 'Data flows automatically between nodes without explicit configuration'
    }
  }
  wf.metadata = {
    category: 'content_generation',
    use_case: 'blog_creation',
    complexity: 'intermediate',
    estimated_duration: '3-5 minutes',
    data_flow_version: '1.0',
    data_flow_mode: 'automatic'
  }
end

puts "✓ Workflow created: #{workflow.name} (ID: #{workflow.id})"

# =============================================================================
# WORKFLOW NODES
# =============================================================================

puts "\n📋 Creating workflow nodes..."

# 1. Start Node
start_node = workflow.nodes.find_or_create_by!(
  node_id: 'start_1',
  node_type: 'start',
  name: 'Start'
) do |node|
  node.description = 'Workflow entry point - begins blog generation process'
  node.is_start_node = true
  node.is_end_node = false
  node.position = { x: 100, y: 100 }
  node.configuration = {
    start_type: 'manual',
    delay_seconds: 0,
    output_mapping: {
      data: 'start_data',
      output: 'start_data'
    }
  }
  node.metadata = {
    icon: 'play-circle',
    color: '#10b981',
    description: 'Workflow entry point'
  }
end

puts "  ✓ Start Node: #{start_node.name}"

# Only create AI agent nodes if agents exist
if research_agent && writer_agent && editor_agent
  # 2. Research Topic Node
  research_node = workflow.nodes.find_or_create_by!(
    node_id: 'research_1',
    node_type: 'ai_agent',
    name: 'Research Topic'
  ) do |node|
    node.description = 'Research blog topic, gather key facts, statistics, and insights from authoritative sources'
    node.is_start_node = false
    node.is_end_node = false
    node.position = { x: 300, y: 100 }
    node.configuration = {
      agent_id: research_agent.id,
      prompt: 'Research the following topic and provide key facts, statistics, and insights: {{topic}}. Focus on recent developments and authoritative sources.',
      max_tokens: 2000,
      temperature: 0.7,
      timeout: 90,
      output_mapping: {
        research_data: 'response'
      }
    }
    node.metadata = {
      icon: 'search',
      color: '#3b82f6',
      description: 'Research blog topic',
      requires_agent: true
    }
  end

  puts "  ✓ Research Node: #{research_node.name}"

  # 3. Write Blog Post Node
  writer_node = workflow.nodes.find_or_create_by!(
    node_id: 'writer_1',
    node_type: 'ai_agent',
    name: 'Write Blog Post'
  ) do |node|
    node.description = 'Write comprehensive, engaging, and SEO-friendly blog content based on research'
    node.is_start_node = false
    node.is_end_node = false
    node.position = { x: 500, y: 100 }
    node.configuration = {
      agent_id: writer_agent.id,
      prompt: 'Write a comprehensive blog post about {{topic}}. Use this research data: {{research_data}}. Make it engaging, informative, and SEO-friendly. Include an introduction, main points, and conclusion.',
      max_tokens: 3000,
      temperature: 0.8,
      timeout: 120,
      output_mapping: {
        blog_draft: 'response'
      }
    }
    node.metadata = {
      icon: 'edit',
      color: '#ec4899',
      description: 'Write blog content',
      requires_agent: true
    }
  end

  puts "  ✓ Writer Node: #{writer_node.name}"

  # 4. Edit & Polish Node
  editor_node = workflow.nodes.find_or_create_by!(
    node_id: 'editor_1',
    node_type: 'ai_agent',
    name: 'Edit & Polish'
  ) do |node|
    node.description = 'Edit and refine blog content for grammar, clarity, readability, and proper structure'
    node.is_start_node = false
    node.is_end_node = false
    node.position = { x: 700, y: 100 }
    node.configuration = {
      agent_id: editor_agent.id,
      prompt: 'Review and improve this blog post: {{blog_draft}}. Fix grammar, improve clarity, enhance readability, and ensure proper structure. Return the final polished version.',
      max_tokens: 3000,
      temperature: 0.3,
      timeout: 120,
      output_mapping: {
        final_blog: 'response'
      }
    }
    node.metadata = {
      icon: 'check-square',
      color: '#06b6d4',
      description: 'Edit and refine content',
      requires_agent: true
    }
  end

  puts "  ✓ Editor Node: #{editor_node.name}"
else
  puts "  ⚠️  Skipping AI agent nodes (agents not found)"
  research_node = nil
  writer_node = nil
  editor_node = nil
end

# 5. End Node
end_node = workflow.nodes.find_or_create_by!(
  node_id: 'end_1',
  node_type: 'end',
  name: 'End'
) do |node|
  node.description = 'Workflow completion - outputs final blog post and research summary'
  node.is_start_node = false
  node.is_end_node = true
  node.position = { x: 900, y: 100 }
  node.configuration = {
    output_mapping: {
      final_output: 'final_blog',
      research_summary: 'research_data'
    }
  }
  node.metadata = {
    icon: 'check-circle',
    color: '#10b981',
    description: 'Workflow completion'
  }
end

puts "  ✓ End Node: #{end_node.name}"

puts "✓ Created #{workflow.nodes.count} workflow nodes"

# =============================================================================
# WORKFLOW EDGES (Connections)
# =============================================================================

puts "\n🔗 Creating workflow edges..."

if research_agent && writer_agent && editor_agent
  # Edge 1: Start → Research Topic
  edge1 = workflow.edges.find_or_create_by!(
    edge_id: 'edge_1',
    source_node_id: start_node.node_id,
    target_node_id: research_node.node_id
  ) do |edge|
    edge.edge_type = 'default'
    edge.source_handle = nil
    edge.target_handle = nil
    edge.is_conditional = false
    edge.condition = {}
    edge.configuration = {
      label: 'Start Research',
      description: 'Begin research phase',
      style: 'solid',
      color: '#6b7280'
    }
    edge.metadata = {}
    edge.priority = 0
  end

  puts "  ✓ Edge 1: #{start_node.name} → #{research_node.name}"

  # Edge 2: Research Topic → Write Blog Post
  # DATA FLOW STANDARD (v1.0): Data flows automatically without explicit mapping
  # The writer node will automatically receive all outputs from the research node
  # This includes: output, data.agent_id, data.agent_name, metadata, etc.
  #
  # Optional: Explicit data mapping can be added for clarity or renaming:
  # data_mapping: {
  #   "{{research_1.output}}" => "research_findings",
  #   "{{input.topic}}" => "topic"
  # }
  edge2 = workflow.edges.find_or_create_by!(
    edge_id: 'edge_2',
    source_node_id: research_node.node_id,
    target_node_id: writer_node.node_id
  ) do |edge|
    edge.edge_type = 'success'
    edge.source_handle = nil
    edge.target_handle = nil
    edge.is_conditional = false
    edge.condition = {}
    edge.configuration = {
      label: 'Research Complete',
      description: 'Proceed to writing phase - research data flows automatically',
      style: 'solid',
      color: '#10b981',
      # Optional explicit data mapping (commented out - not needed with automatic flow)
      # data_mapping: {
      #   "{{research_1.agent_output}}" => "research_data"
      # }
    }
    edge.metadata = {
      automatic_data_flow: true,
      data_flow_version: '1.0'
    }
    edge.priority = 0
  end

  puts "  ✓ Edge 2: #{research_node.name} → #{writer_node.name} (automatic data flow)"

  # Edge 3: Write Blog Post → Edit & Polish
  edge3 = workflow.edges.find_or_create_by!(
    edge_id: 'edge_3',
    source_node_id: writer_node.node_id,
    target_node_id: editor_node.node_id
  ) do |edge|
    edge.edge_type = 'success'
    edge.source_handle = nil
    edge.target_handle = nil
    edge.is_conditional = false
    edge.condition = {}
    edge.configuration = {
      label: 'Draft Complete',
      description: 'Proceed to editing phase',
      style: 'solid',
      color: '#10b981'
    }
    edge.metadata = {}
    edge.priority = 0
  end

  puts "  ✓ Edge 3: #{writer_node.name} → #{editor_node.name}"

  # Edge 4: Edit & Polish → End
  edge4 = workflow.edges.find_or_create_by!(
    edge_id: 'edge_4',
    source_node_id: editor_node.node_id,
    target_node_id: end_node.node_id
  ) do |edge|
    edge.edge_type = 'success'
    edge.source_handle = nil
    edge.target_handle = nil
    edge.is_conditional = false
    edge.condition = {}
    edge.configuration = {
      label: 'Editing Complete',
      description: 'Finalize blog post',
      style: 'solid',
      color: '#10b981'
    }
    edge.metadata = {}
    edge.priority = 0
  end

  puts "  ✓ Edge 4: #{editor_node.name} → #{end_node.name}"
else
  # Simple edge from start to end when agents don't exist
  edge1 = workflow.edges.find_or_create_by!(
    edge_id: 'edge_1',
    source_node_id: start_node.node_id,
    target_node_id: end_node.node_id
  ) do |edge|
    edge.edge_type = 'default'
    edge.source_handle = nil
    edge.target_handle = nil
    edge.is_conditional = false
    edge.condition = {}
    edge.configuration = {
      label: 'Direct to End',
      description: 'Workflow structure only (agents not configured)',
      style: 'dashed',
      color: '#6b7280'
    }
    edge.metadata = {}
    edge.priority = 0
  end

  puts "  ✓ Edge 1: #{start_node.name} → #{end_node.name} (structure only)"
end

puts "✓ Created #{workflow.edges.count} workflow edges"

# =============================================================================
# WORKFLOW VARIABLES
# =============================================================================

puts "\n📊 Creating workflow variables..."

# Input variable
workflow.variables.find_or_create_by!(name: 'topic') do |var|
  var.variable_type = 'string'
  var.default_value = nil
  var.description = 'Blog topic or title (input)'
  var.is_required = true
  var.is_input = true
  var.is_output = false
  var.metadata = { example: 'The Future of AI in Healthcare' }
end

# Intermediate variables
workflow.variables.find_or_create_by!(name: 'research_data') do |var|
  var.variable_type = 'json'
  var.default_value = nil
  var.description = 'Research findings (intermediate)'
  var.is_required = false
  var.is_input = false
  var.is_output = false
  var.metadata = {}
end

workflow.variables.find_or_create_by!(name: 'blog_draft') do |var|
  var.variable_type = 'string'
  var.default_value = nil
  var.description = 'Draft blog post (intermediate)'
  var.is_required = false
  var.is_input = false
  var.is_output = false
  var.metadata = {}
end

# Output variable
workflow.variables.find_or_create_by!(name: 'final_blog') do |var|
  var.variable_type = 'string'
  var.default_value = nil
  var.description = 'Final polished blog post (output)'
  var.is_required = false
  var.is_input = false
  var.is_output = true
  var.metadata = {}
end

puts "✓ Created #{workflow.variables.count} workflow variables"

# Activate workflow if agents exist
if research_agent && writer_agent && editor_agent
  workflow.update!(status: 'active')
  puts "\n✅ Simple Blog Generation Workflow created and activated successfully!"
else
  puts "\n⚠️  Workflow created but NOT activated (missing AI agents)"
  puts "   Run enhanced_blog_generation_workflow_seed.rb to create agents"
  puts "   Then manually activate this workflow"
end

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + "=" * 80
puts "✅ SIMPLE BLOG GENERATION WORKFLOW CREATION COMPLETE"
puts "=" * 80
puts "\n📊 Summary:"
puts "   Workflow: #{workflow.name}"
puts "   Workflow ID: #{workflow.id}"
puts "   Status: #{workflow.status}"
puts "   Nodes: #{workflow.nodes.count}"
puts "   Edges: #{workflow.edges.count}"
puts "   Variables: #{workflow.variables.count}"
puts "\n📝 Workflow Flow:"
puts "   Start → Research Topic → Write Blog Post → Edit & Polish → End"
puts "\n🎯 Purpose:"
puts "   • Multi-stage content generation"
puts "   • AI agent collaboration"
puts "   • Research-driven writing"
puts "   • Automated editing and refinement"
puts "\n🚀 Usage:"
puts "   Input: { \"topic\": \"Your blog topic\" }"
puts "   Output: { \"final_blog\": \"Polished blog post content\" }"
puts "\n💡 Dependencies:"
puts "   Requires AI agents: Blog Research Agent, Blog Writer Agent, Blog Editor Agent"
puts "   Create with: rails db:seed:enhanced_blog_generation_workflow_seed"
puts "\n" + "=" * 80
