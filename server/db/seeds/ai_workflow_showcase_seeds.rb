# frozen_string_literal: true

# AI Workflow Showcase Seeds
# Creates 3 realistic example workflows that demonstrate platform capabilities:
# 1. Content Generation Pipeline - Multi-agent AI orchestration with KB integration
# 2. Customer Onboarding Flow - Human approval, notifications, and conditional logic
# 3. Data Integration Pipeline - API calls, transforms, and database operations

puts "\n" + '=' * 80
puts 'AI WORKFLOW SHOWCASE - Creating Example Workflows'
puts '=' * 80

# Find admin account and user
account = Account.find_by(subdomain: 'admin')
unless account
  puts '❌ Error: Admin account not found. Run main seeds first.'
  return
end

user = account.users.find_by(email: 'admin@powernode.org')
unless user
  puts '❌ Error: Admin user not found. Run main seeds first.'
  return
end

puts "✓ Using admin account: #{account.name} (#{user.email})"

# Find or create AI Provider
provider = account.ai_providers.find_by(provider_type: 'anthropic') ||
           account.ai_providers.find_by(provider_type: 'openai') ||
           account.ai_providers.first

unless provider
  puts '⚠️  No AI providers found - creating placeholder provider'
  provider = Ai::Provider.find_or_create_by!(
    account: account,
    name: 'Claude AI',
    provider_type: 'anthropic'
  ) do |p|
    p.is_active = true
    p.api_endpoint = 'https://api.anthropic.com/v1'
    p.supported_models = [ { 'name' => 'claude-sonnet-4-5', 'id' => 'claude-sonnet-4-5-20250929' } ]
  end
end

default_model = case provider.provider_type
when 'anthropic' then 'claude-sonnet-4-5-20250929'
when 'openai' then 'gpt-4o'
else provider.supported_models&.first&.dig('id') || 'default'
end

puts "✓ Using AI Provider: #{provider.name}"

# =============================================================================
# HELPER METHODS
# =============================================================================

def create_agent(account:, user:, provider:, name:, type:, description:, prompt:, model:)
  Ai::Agent.find_or_create_by!(account: account, name: name) do |agent|
    agent.agent_type = type
    agent.description = description
    agent.creator = user
    agent.provider = provider
    agent.status = 'active'
    agent.version = '1.0.0'
    # Set realistic capabilities based on agent type
    agent.mcp_capabilities = case type
    when 'content_generator'
      %w[text_generation markdown_formatting blog_writing seo_optimization]
    when 'code_assistant'
      %w[code_generation code_review git_operations test_execution]
    when 'data_analyst'
      %w[database_queries csv_processing data_aggregation report_generation]
    when 'monitor'
      %w[http_health_checks log_analysis metric_collection alerting]
    else
      %w[text_generation summarization document_analysis]
    end
    agent.mcp_metadata = {
      'system_prompt' => prompt,
      'model' => model,
      'temperature' => 0.7,
      'max_tokens' => 2000
    }
  end
end

# =============================================================================
# WORKFLOW 1: CONTENT GENERATION PIPELINE
# Demonstrates: Multi-agent AI, parallel execution, KB integration, quality gates
# =============================================================================

puts "\n" + '-' * 60
puts '1. CONTENT GENERATION PIPELINE'
puts '-' * 60

# Create specialized agents for content generation
research_agent = create_agent(
  account: account, user: user, provider: provider, model: default_model,
  name: 'Content Research Agent',
  type: 'data_analyst',
  description: 'Researches topics and gathers supporting data',
  prompt: <<~PROMPT
    Research the given topic comprehensively. Gather key themes, statistics,
    examples, and credible sources. Output structured JSON with research findings.
  PROMPT
)

writer_agent = create_agent(
  account: account, user: user, provider: provider, model: default_model,
  name: 'Content Writer Agent',
  type: 'content_generator',
  description: 'Creates engaging written content from research',
  prompt: <<~PROMPT
    Write compelling content based on the provided research and outline.
    Use engaging tone, incorporate data naturally, and structure for readability.
  PROMPT
)

editor_agent = create_agent(
  account: account, user: user, provider: provider, model: default_model,
  name: 'Content Editor Agent',
  type: 'content_generator',
  description: 'Refines content for quality and clarity',
  prompt: <<~PROMPT
    Edit content for grammar, clarity, flow, and engagement.
    Verify facts, improve readability, and ensure consistent tone.
  PROMPT
)

seo_agent = create_agent(
  account: account, user: user, provider: provider, model: default_model,
  name: 'SEO Optimizer Agent',
  type: 'content_generator',
  description: 'Optimizes content for search engines',
  prompt: <<~PROMPT
    Optimize content for SEO: meta tags, keyword placement, headings,
    schema markup, and linking suggestions.
  PROMPT
)

puts "✓ Created content generation agents"

# Create workflow
content_workflow = Ai::Workflow.find_or_create_by!(
  account: account,
  name: 'Content Generation Pipeline'
) do |wf|
  wf.description = 'AI-powered content creation with research, writing, editing, and SEO optimization'
  wf.creator = user
  wf.status = 'active'
  wf.version = '1.0.0'
  wf.mcp_input_schema = {
    'type' => 'object',
    'properties' => {
      'topic' => { 'type' => 'string', 'description' => 'The topic to write about' },
      'audience' => { 'type' => 'string', 'description' => 'Target audience for the content', 'default' => 'general' },
      'tone' => { 'type' => 'string', 'description' => 'Writing tone', 'enum' => %w[professional casual technical friendly], 'default' => 'professional' }
    },
    'required' => [ 'topic' ]
  }
  wf.configuration = {
    'execution_mode' => 'sequential',
    'enable_checkpointing' => true,
    'timeout_seconds' => 600
  }
  wf.metadata = {
    'category' => 'Content Creation',
    'complexity' => 'intermediate',
    'estimated_duration' => '3-5 minutes'
  }
end

# Clear existing nodes/edges for clean recreation
content_workflow.workflow_edges.destroy_all
content_workflow.workflow_nodes.destroy_all

# Create nodes
# Layout: Vertical flow with condition branches
# - Main flow: start → research → write → edit → seo → quality_check
# - True path (right): quality_check → kb_create → end
# - False path (left): quality_check → needs_revision → end
nodes_data = [
  # Vertical flow (x=400 centered, 150px vertical spacing)
  { id: 'start', type: 'start', name: 'Start', x: 400, y: 50, is_start: true,
    config: { 'input_schema' => { 'topic' => 'string', 'audience' => 'string', 'tone' => 'string' } } },
  { id: 'research', type: 'ai_agent', name: 'Research Topic', x: 400, y: 200,
    config: { 'agent_id' => research_agent.id, 'prompt_template' => 'Research: {{topic}} for {{audience}}' } },
  { id: 'write', type: 'ai_agent', name: 'Write Content', x: 400, y: 350,
    config: { 'agent_id' => writer_agent.id, 'prompt_template' => 'Write about {{topic}} using research: {{research_output}}' } },
  { id: 'edit', type: 'ai_agent', name: 'Edit & Refine', x: 400, y: 500,
    config: { 'agent_id' => editor_agent.id, 'prompt_template' => 'Edit: {{writer_output}}' } },
  { id: 'seo', type: 'ai_agent', name: 'SEO Optimization', x: 400, y: 650,
    config: { 'agent_id' => seo_agent.id, 'prompt_template' => 'Optimize for SEO: {{editor_output}}. Output JSON with seo_title, meta_description, keywords, and quality_score (0-100).' } },
  { id: 'quality_check', type: 'condition', name: 'Quality Check', x: 400, y: 800,
    config: { 'conditions' => [ { 'field' => 'seo.quality_score', 'operator' => '>=', 'value' => 80 } ] } },
  # True path offset right (x=550) to align with condition's True handle (bottom-right)
  { id: 'kb_create', type: 'kb_article', name: 'Create KB Article', x: 550, y: 950,
    config: { 'action' => 'create', 'title' => '{{seo.seo_title}}', 'content' => '{{edit.output}}', 'status' => 'published' } },
  # False path offset left (x=250) for manual revision notification
  { id: 'needs_revision', type: 'notification', name: 'Needs Revision', x: 250, y: 950,
    config: { 'channel' => 'email', 'message' => 'Content for "{{topic}}" scored {{seo.quality_score}}/100 and needs manual revision.' } },
  { id: 'end', type: 'end', name: 'Complete', x: 400, y: 1100, is_end: true,
    config: { 'output_mapping' => { 'content' => '{{edit.output}}', 'seo_data' => '{{seo}}', 'article_id' => '{{kb_create.id}}', 'needs_revision' => '{{quality_check.result == false}}' } } }
]

nodes_data.each do |n|
  content_workflow.workflow_nodes.create!(
    node_id: n[:id],
    node_type: n[:type],
    name: n[:name],
    position: { 'x' => n[:x], 'y' => n[:y] },
    is_start_node: n[:is_start] || false,
    is_end_node: n[:is_end] || false,
    configuration: n[:config]
  )
end

# Create edges with proper handle IDs and edge_type
# Note: False path from quality_check goes to a revision node that then connects to end
# (feedback loop to edit would create infinite loop - instead we notify for manual revision)
edges_data = [
  { source: 'start', target: 'research', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'research', target: 'write', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'write', target: 'edit', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'edit', target: 'seo', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'seo', target: 'quality_check', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  # Condition node outputs: path determined by source_handle ('true'/'false'), not by condition expression
  { source: 'quality_check', target: 'kb_create', source_handle: 'true', target_handle: 'input', edge_type: 'default' },
  { source: 'quality_check', target: 'needs_revision', source_handle: 'false', target_handle: 'input', edge_type: 'default' },
  { source: 'kb_create', target: 'end', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'needs_revision', target: 'end', source_handle: 'output', target_handle: 'input', edge_type: 'default' }
]

edges_data.each_with_index do |e, i|
  content_workflow.workflow_edges.create!(
    edge_id: "edge_#{i + 1}",
    source_node_id: e[:source],
    target_node_id: e[:target],
    source_handle: e[:source_handle],
    target_handle: e[:target_handle],
    edge_type: e[:edge_type],
    # is_conditional is false for condition node outputs - path is determined by source_handle
    is_conditional: false,
    condition: {}
  )
end

puts "✓ Created Content Generation Pipeline (#{content_workflow.workflow_nodes.count} nodes, #{content_workflow.workflow_edges.count} edges)"

# =============================================================================
# WORKFLOW 2: CUSTOMER ONBOARDING FLOW
# Demonstrates: Human approval, email notifications, delays, webhooks
# =============================================================================

puts "\n" + '-' * 60
puts '2. CUSTOMER ONBOARDING FLOW'
puts '-' * 60

onboarding_workflow = Ai::Workflow.find_or_create_by!(
  account: account,
  name: 'Customer Onboarding Flow'
) do |wf|
  wf.description = 'Automated customer onboarding with approval gates, notifications, and integrations'
  wf.creator = user
  wf.status = 'active'
  wf.version = '1.0.0'
  wf.mcp_input_schema = {
    'type' => 'object',
    'properties' => {
      'customer_name' => { 'type' => 'string', 'description' => 'Name of the new customer' },
      'customer_email' => { 'type' => 'string', 'format' => 'email', 'description' => 'Customer email address' },
      'company' => { 'type' => 'string', 'description' => 'Company name' },
      'plan' => { 'type' => 'string', 'enum' => %w[starter professional enterprise], 'description' => 'Selected subscription plan' }
    },
    'required' => %w[customer_name customer_email company plan]
  }
  wf.configuration = {
    'execution_mode' => 'sequential',
    'enable_compensation' => true,
    'timeout_seconds' => 86400
  }
  wf.metadata = {
    'category' => 'Business Process',
    'complexity' => 'intermediate',
    'estimated_duration' => '1-3 days (includes approval wait)'
  }
end

# Clear existing nodes/edges
onboarding_workflow.workflow_edges.destroy_all
onboarding_workflow.workflow_nodes.destroy_all

# Create nodes
# Layout: Vertical flow with condition branches (False=left x=200, True=right x=600)
# Consistent 120px vertical spacing
onboarding_nodes = [
  { id: 'trigger', type: 'trigger', name: 'New Customer Signup', x: 400, y: 50, is_start: true,
    config: { 'trigger_type' => 'webhook', 'webhook_path' => '/api/webhooks/new-customer' } },
  { id: 'validate', type: 'validator', name: 'Validate Customer Data', x: 400, y: 170,
    config: { 'rules' => [ { 'field' => 'email', 'rule' => 'required|email' }, { 'field' => 'company', 'rule' => 'required' } ] } },
  { id: 'check_tier', type: 'condition', name: 'Check Account Tier', x: 400, y: 290,
    config: { 'conditions' => [ { 'field' => 'plan', 'operator' => '==', 'value' => 'enterprise' } ] } },
  # Condition branches: False=left, True=right
  { id: 'auto_approve', type: 'transform', name: 'Auto-Approve Standard', x: 200, y: 410,
    config: { 'operation' => 'set', 'fields' => { 'approval_status' => 'approved', 'approved_by' => 'system' } } },
  { id: 'approval', type: 'human_approval', name: 'Manager Approval', x: 600, y: 410,
    config: { 'approval_type' => 'single', 'timeout_hours' => 48, 'approvers' => [ 'sales_manager' ] } },
  # Continue main flow (merge point)
  { id: 'create_account', type: 'api_call', name: 'Create Account', x: 400, y: 530,
    config: { 'method' => 'POST', 'url' => '/api/v1/accounts', 'body' => { 'customer' => '{{customer_data}}' } } },
  { id: 'send_welcome', type: 'email', name: 'Send Welcome Email', x: 400, y: 650,
    config: { 'template' => 'customer_welcome', 'to' => '{{customer.email}}', 'subject' => 'Welcome to Powernode!' } },
  { id: 'schedule_call', type: 'scheduler', name: 'Schedule Onboarding Call', x: 400, y: 770,
    config: { 'schedule_type' => 'delay', 'delay_hours' => 24, 'action' => 'create_calendar_event' } },
  { id: 'notify_team', type: 'notification', name: 'Notify Success Team', x: 400, y: 890,
    config: { 'channel' => 'slack', 'message' => 'New customer {{customer.company}} onboarded!' } },
  { id: 'end', type: 'end', name: 'Onboarding Complete', x: 400, y: 1010, is_end: true,
    config: { 'output_mapping' => { 'account_id' => '{{account.id}}', 'status' => 'completed' } } }
]

onboarding_nodes.each do |n|
  onboarding_workflow.workflow_nodes.create!(
    node_id: n[:id],
    node_type: n[:type],
    name: n[:name],
    position: { 'x' => n[:x], 'y' => n[:y] },
    is_start_node: n[:is_start] || false,
    is_end_node: n[:is_end] || false,
    configuration: n[:config]
  )
end

# Create edges with proper handle IDs and edge_type
# Condition: is_enterprise? True (right) -> approval, False (left) -> auto_approve
onboarding_edges = [
  { source: 'trigger', target: 'validate', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'validate', target: 'check_tier', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  # Condition node outputs: path determined by source_handle ('true'/'false'), not by condition expression
  { source: 'check_tier', target: 'auto_approve', source_handle: 'false', target_handle: 'input', edge_type: 'default' },
  { source: 'check_tier', target: 'approval', source_handle: 'true', target_handle: 'input', edge_type: 'default' },
  { source: 'auto_approve', target: 'create_account', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'approval', target: 'create_account', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'create_account', target: 'send_welcome', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'send_welcome', target: 'schedule_call', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'schedule_call', target: 'notify_team', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'notify_team', target: 'end', source_handle: 'output', target_handle: 'input', edge_type: 'default' }
]

onboarding_edges.each_with_index do |e, i|
  onboarding_workflow.workflow_edges.create!(
    edge_id: "edge_#{i + 1}",
    source_node_id: e[:source],
    target_node_id: e[:target],
    source_handle: e[:source_handle],
    target_handle: e[:target_handle],
    edge_type: e[:edge_type],
    # is_conditional is false for condition node outputs - path is determined by source_handle
    is_conditional: false,
    condition: {}
  )
end

puts "✓ Created Customer Onboarding Flow (#{onboarding_workflow.workflow_nodes.count} nodes, #{onboarding_workflow.workflow_edges.count} edges)"

# =============================================================================
# WORKFLOW 3: DATA INTEGRATION PIPELINE
# Demonstrates: API calls, data transforms, loops, database operations, webhooks
# =============================================================================

puts "\n" + '-' * 60
puts '3. DATA INTEGRATION PIPELINE'
puts '-' * 60

integration_workflow = Ai::Workflow.find_or_create_by!(
  account: account,
  name: 'Data Integration Pipeline'
) do |wf|
  wf.description = 'Sync and transform data between external APIs and internal database'
  wf.creator = user
  wf.status = 'active'
  wf.version = '1.0.0'
  wf.mcp_input_schema = {
    'type' => 'object',
    'properties' => {
      'api_endpoint' => { 'type' => 'string', 'format' => 'uri', 'description' => 'External API endpoint URL' },
      'api_key' => { 'type' => 'string', 'description' => 'API key for authentication' },
      'data_format' => { 'type' => 'string', 'enum' => %w[json csv xml], 'default' => 'json', 'description' => 'Expected data format' },
      'callback_url' => { 'type' => 'string', 'format' => 'uri', 'description' => 'Webhook URL for completion notification' }
    },
    'required' => %w[api_endpoint api_key]
  }
  wf.configuration = {
    'execution_mode' => 'sequential',
    'enable_checkpointing' => true,
    'timeout_seconds' => 1800
  }
  wf.metadata = {
    'category' => 'Data Integration',
    'complexity' => 'advanced',
    'estimated_duration' => '5-15 minutes',
    'example_inputs' => {
      'api_endpoint' => 'https://api.example.com/v1',
      'api_key' => 'sk_live_xxxx (set via secrets)',
      'callback_url' => 'https://hooks.example.com/webhook/sync-complete'
    }
  }
end

# Clear existing nodes/edges
integration_workflow.workflow_edges.destroy_all
integration_workflow.workflow_nodes.destroy_all

# Create nodes
# Layout: Vertical flow with loop body offset right (x=600)
# Consistent 120px vertical spacing
integration_nodes = [
  { id: 'trigger', type: 'scheduler', name: 'Daily Sync Trigger', x: 400, y: 50, is_start: true,
    config: { 'schedule_type' => 'cron', 'cron_expression' => '0 2 * * *', 'timezone' => 'UTC' } },
  { id: 'fetch_api', type: 'api_call', name: 'Fetch External Data', x: 400, y: 170,
    config: { 'method' => 'GET', 'url' => '{{api_endpoint}}/data', 'headers' => { 'Authorization' => 'Bearer {{api_key}}' } } },
  { id: 'validate', type: 'validator', name: 'Validate Response', x: 400, y: 290,
    config: { 'rules' => [ { 'field' => 'status', 'rule' => 'equals:success' }, { 'field' => 'data', 'rule' => 'required|array' } ] } },
  { id: 'transform', type: 'data_processor', name: 'Transform Data', x: 400, y: 410,
    config: { 'operation' => 'map', 'mapping' => { 'id' => '{{item.external_id}}', 'name' => '{{item.title}}', 'updated_at' => '{{now}}' } } },
  { id: 'loop', type: 'loop', name: 'Process Each Record', x: 400, y: 530,
    config: { 'iteration_source' => '{{transformed_data}}', 'item_variable' => 'record', 'max_iterations' => 1000 } },
  # Loop body offset right to show internal iteration
  { id: 'db_upsert', type: 'database', name: 'Upsert to Database', x: 600, y: 530,
    config: { 'operation' => 'upsert', 'table' => 'synced_records', 'conflict_key' => 'external_id', 'data' => '{{record}}' } },
  # Continue after loop
  { id: 'merge', type: 'merge', name: 'Collect Results', x: 400, y: 650,
    config: { 'merge_strategy' => 'array', 'output_variable' => 'sync_results' } },
  { id: 'webhook', type: 'webhook', name: 'Notify Completion', x: 400, y: 770,
    config: { 'method' => 'POST', 'url' => '{{callback_url}}', 'body' => { 'status' => 'completed', 'count' => '{{sync_results.length}}' } } },
  { id: 'end', type: 'end', name: 'Sync Complete', x: 400, y: 890, is_end: true,
    config: { 'output_mapping' => { 'records_synced' => '{{sync_results.length}}', 'completed_at' => '{{now}}' } } }
]

integration_nodes.each do |n|
  integration_workflow.workflow_nodes.create!(
    node_id: n[:id],
    node_type: n[:type],
    name: n[:name],
    position: { 'x' => n[:x], 'y' => n[:y] },
    is_start_node: n[:is_start] || false,
    is_end_node: n[:is_end] || false,
    configuration: n[:config]
  )
end

# Create edges with proper handle IDs for loop/merge nodes
# Loop node handles: input, loop-back (target), body, exit (source)
# Merge node handles: merge-1, merge-2, merge-3 (target), output (source)
integration_edges = [
  { source: 'trigger', target: 'fetch_api', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'fetch_api', target: 'validate', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'validate', target: 'transform', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'transform', target: 'loop', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  # Loop body: from loop's 'body' handle to the processing node
  { source: 'loop', target: 'db_upsert', source_handle: 'body', target_handle: 'input', edge_type: 'default' },
  # Loop back: from processing node back to loop's 'loop-back' handle (edge_type: 'loop')
  { source: 'db_upsert', target: 'loop', source_handle: 'output', target_handle: 'loop-back', edge_type: 'loop' },
  # Loop exit: from loop's 'exit' handle to next node
  { source: 'loop', target: 'merge', source_handle: 'exit', target_handle: 'merge-1', edge_type: 'default' },
  { source: 'merge', target: 'webhook', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'webhook', target: 'end', source_handle: 'output', target_handle: 'input', edge_type: 'default' }
]

integration_edges.each_with_index do |e, i|
  integration_workflow.workflow_edges.create!(
    edge_id: "edge_#{i + 1}",
    source_node_id: e[:source],
    target_node_id: e[:target],
    source_handle: e[:source_handle],
    target_handle: e[:target_handle],
    edge_type: e[:edge_type],
    is_conditional: false,
    condition: {}
  )
end

puts "✓ Created Data Integration Pipeline (#{integration_workflow.workflow_nodes.count} nodes, #{integration_workflow.workflow_edges.count} edges)"

# =============================================================================
# WORKFLOW 4: MCP-POWERED PAGE GENERATOR
# Demonstrates: Consolidated node types (page, mcp_operation), MCP integration
# =============================================================================

puts "\n" + '-' * 60
puts '4. MCP-POWERED PAGE GENERATOR'
puts '-' * 60

# Find MCP servers for workflow integration
content_mcp_server = account.mcp_servers.find_by(name: 'Content Enhancement MCP')
unless content_mcp_server
  puts '⚠️  Content Enhancement MCP Server not found - skipping workflow 4'
  puts '   Run MCP server seeds first: load db/seeds/mcp_servers_seeds.rb'
else

page_generator_workflow = Ai::Workflow.find_or_create_by!(
  account: account,
  name: 'MCP-Powered Page Generator'
) do |wf|
  wf.description = 'Generate and publish pages using MCP tools and AI with page management integration'
  wf.creator = user
  wf.status = 'active'
  wf.version = '1.0.0'
  wf.configuration = {
    'execution_mode' => 'sequential',
    'enable_checkpointing' => true,
    'timeout_seconds' => 300
  }
  wf.metadata = {
    'category' => 'Content Management',
    'complexity' => 'advanced',
    'estimated_duration' => '2-4 minutes',
    'consolidated_types' => %w[page mcp_operation]
  }
end

# Clear existing nodes/edges
page_generator_workflow.workflow_edges.destroy_all
page_generator_workflow.workflow_nodes.destroy_all

# Create nodes demonstrating consolidated types
# Layout: Vertical flow with condition branches (False=left x=200, True=right x=600)
# Consistent 120px vertical spacing
page_gen_nodes = [
  { id: 'start', type: 'start', name: 'Start Page Generation', x: 400, y: 50, is_start: true,
    config: { 'input_schema' => { 'topic' => 'string', 'template' => 'string' } } },
  # MCP Operation: Use prompt template from MCP server
  { id: 'mcp_prompt', type: 'mcp_operation', name: 'Get Prompt Template', x: 400, y: 170,
    config: { 'operation_type' => 'prompt', 'mcp_server_id' => content_mcp_server.id, 'execution_mode' => 'sync', 'prompt_name' => 'page_generator', 'arguments' => { 'topic' => '{{topic}}' } } },
  # AI Agent to generate content using prompt from MCP
  { id: 'generate', type: 'ai_agent', name: 'Generate Content', x: 400, y: 290,
    config: { 'agent_id' => writer_agent.id, 'prompt_template' => '{{mcp_prompt.output}}' } },
  # MCP Operation: Use tool to enhance content and score quality
  { id: 'mcp_tool', type: 'mcp_operation', name: 'Enhance with MCP Tool', x: 400, y: 410,
    config: { 'operation_type' => 'tool', 'mcp_server_id' => content_mcp_server.id, 'execution_mode' => 'sync', 'mcp_tool_name' => 'content_enhancer', 'parameters' => { 'content' => '{{generate.output}}', 'return_score' => true } } },
  # MCP Operation: Read resource for metadata
  { id: 'mcp_resource', type: 'mcp_operation', name: 'Get Page Template', x: 400, y: 530,
    config: { 'operation_type' => 'resource', 'mcp_server_id' => content_mcp_server.id, 'execution_mode' => 'sync', 'resource_uri' => 'templates://page/default' } },
  # Page: Create the page with enhanced content from MCP tool
  { id: 'page_create', type: 'page', name: 'Create Page', x: 400, y: 650,
    config: { 'action' => 'create', 'title' => '{{topic}}', 'content' => '{{mcp_tool.enhanced_content}}', 'slug' => '{{topic | slugify}}', 'status' => 'draft' } },
  # Page: Update with SEO metadata from enhanced content
  { id: 'page_update', type: 'page', name: 'Add SEO Metadata', x: 400, y: 770,
    config: { 'action' => 'update', 'page_id' => '{{page_create.id}}', 'meta_description' => '{{mcp_tool.meta_description}}', 'meta_keywords' => '{{mcp_tool.keywords}}' } },
  # Condition: Check content quality from MCP enhancement tool output
  { id: 'quality_gate', type: 'condition', name: 'Quality Gate', x: 400, y: 890,
    config: { 'conditions' => [ { 'field' => 'mcp_tool.content_score', 'operator' => '>=', 'value' => 75 } ] } },
  # Condition branches: False=left, True=right
  { id: 'notify_review', type: 'notification', name: 'Request Review', x: 200, y: 1010,
    config: { 'channel' => 'email', 'message' => 'Page {{page_create.title}} needs review' } },
  { id: 'page_publish', type: 'page', name: 'Publish Page', x: 600, y: 1010,
    config: { 'action' => 'publish', 'page_id' => '{{page_create.id}}' } },
  # End node (centered, both branches converge)
  { id: 'end', type: 'end', name: 'Complete', x: 400, y: 1130, is_end: true,
    config: { 'output_mapping' => { 'page_id' => '{{page_create.id}}', 'published' => '{{page_publish.success}}', 'content_score' => '{{mcp_tool.content_score}}' } } }
]

page_gen_nodes.each do |n|
  page_generator_workflow.workflow_nodes.create!(
    node_id: n[:id],
    node_type: n[:type],
    name: n[:name],
    position: { 'x' => n[:x], 'y' => n[:y] },
    is_start_node: n[:is_start] || false,
    is_end_node: n[:is_end] || false,
    configuration: n[:config]
  )
end

# Create edges with proper handle IDs and edge_type
page_gen_edges = [
  { source: 'start', target: 'mcp_prompt', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'mcp_prompt', target: 'generate', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'generate', target: 'mcp_tool', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'mcp_tool', target: 'mcp_resource', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'mcp_resource', target: 'page_create', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'page_create', target: 'page_update', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'page_update', target: 'quality_gate', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  # Condition node outputs: path determined by source_handle ('true'/'false'), not by condition expression
  { source: 'quality_gate', target: 'page_publish', source_handle: 'true', target_handle: 'input', edge_type: 'default' },
  { source: 'quality_gate', target: 'notify_review', source_handle: 'false', target_handle: 'input', edge_type: 'default' },
  { source: 'page_publish', target: 'end', source_handle: 'output', target_handle: 'input', edge_type: 'default' },
  { source: 'notify_review', target: 'end', source_handle: 'output', target_handle: 'input', edge_type: 'default' }
]

page_gen_edges.each_with_index do |e, i|
  page_generator_workflow.workflow_edges.create!(
    edge_id: "edge_#{i + 1}",
    source_node_id: e[:source],
    target_node_id: e[:target],
    source_handle: e[:source_handle],
    target_handle: e[:target_handle],
    edge_type: e[:edge_type],
    # is_conditional is false for condition node outputs - path is determined by source_handle
    is_conditional: false,
    condition: {}
  )
end

puts "✓ Created MCP-Powered Page Generator (#{page_generator_workflow.workflow_nodes.count} nodes, #{page_generator_workflow.workflow_edges.count} edges)"

end # unless content_mcp_server (workflow 4 guard)

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + '=' * 80
puts 'AI WORKFLOW SHOWCASE - COMPLETE'
puts '=' * 80

workflow_count = content_mcp_server ? 4 : 3
page_generator_workflow = Ai::Workflow.find_by(account: account, name: 'MCP-Powered Page Generator')

puts "\n📊 Summary:"
puts "   Total Workflows: #{workflow_count}"
puts "   Total Agents: #{Ai::Agent.where(account: account).count}"
puts "\n📝 Workflows Created:"
puts "\n   1. #{content_workflow.name}"
puts "      Purpose: AI-powered content creation pipeline"
puts "      Features: Multi-agent orchestration, KB integration, quality gates"
puts "      Nodes: #{content_workflow.workflow_nodes.count}"
puts "\n   2. #{onboarding_workflow.name}"
puts "      Purpose: Customer onboarding with approval workflow"
puts "      Features: Human approval, email/notifications, conditional branching"
puts "      Nodes: #{onboarding_workflow.workflow_nodes.count}"
puts "\n   3. #{integration_workflow.name}"
puts "      Purpose: External API data synchronization"
puts "      Features: API calls, data transforms, loops, database operations"
puts "      Nodes: #{integration_workflow.workflow_nodes.count}"
if page_generator_workflow
  puts "\n   4. #{page_generator_workflow.name}"
  puts "      Purpose: MCP-powered page generation and publishing"
  puts "      Features: MCP operations (tool, resource, prompt), page management"
  puts "      Nodes: #{page_generator_workflow.workflow_nodes.count}"
end

puts "\n🎯 Node Types Demonstrated:"
puts "   • start, end, trigger"
puts "   • ai_agent (multi-agent orchestration)"
puts "   • condition (branching logic)"
puts "   • human_approval (approval gates)"
puts "   • api_call, webhook (integrations)"
puts "   • email, notification (communications)"
puts "   • database (data persistence)"
puts "   • transform, data_processor, validator"
puts "   • loop, merge (flow control)"
puts "   • scheduler (scheduled execution)"
puts "\n🔷 Consolidated Node Types (Phase 1A):"
puts "   • kb_article (action: create, read, update, search, publish)"
puts "   • page (action: create, read, update, publish)"
puts "   • mcp_operation (operation_type: tool, resource, prompt)"

puts "\n" + '=' * 80
