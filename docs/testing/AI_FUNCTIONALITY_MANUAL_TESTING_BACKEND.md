# AI Functionality Manual Testing Plan

## Overview
A comprehensive testing plan covering the full AI functionality in Powernode, organized into 16 phases. This covers 93 AI models, 60+ services, and 22 frontend features.

**Prerequisites:**
- Development environment running (`scripts/auto-dev.sh ensure`)
- Custom "Ollama" provider configured and healthy
- At least one agent configured (Ollama Example Agent)

**Scope Summary:**
| Area | Components | Coverage |
|------|-----------|----------|
| Agent System | 8 models | Phases 1-3, 9-10 |
| Workflows | 15 models | Phases 4, 7, 11-12, 20 |
| Teams | 6 models | Phase 6 |
| Ralph Loops | 3 models | Phase 5, 7 |
| Memory/Context | 4 models | Phase 8 |
| Providers | 3 models | Phase 1, 19 |
| A2A Protocol | 2 models | Phase 10 |
| Marketplace | 7 models | Phase 14 |
| Credits/Billing | 8 models | Phase 15 |
| Governance | 8 models | Phase 13 |
| RAG/Knowledge | 4 models | Phase 16 |
| Monitoring | 3 models | Phase 17 |
| Sandboxes | 4 models | Phase 18 |
| Model Routing | 2 models | Phase 19 |

**Total: 20 Phases, 120+ Test Scenarios, 78+ Models Covered**

---

## Phase 0: Setup Verification

### 0.1 Check Development Environment
```bash
# Ensure all services are running
cd /home/rett/Drive/Projects/powernode-platform
scripts/auto-dev.sh status

# If not running, start them
scripts/auto-dev.sh ensure
```

### 0.2 Check Database State
```bash
# Enter Rails console from server directory
cd server
bundle exec rails c

# Check basic counts
puts "Accounts: #{Account.count}"
puts "Users: #{User.count}"
puts "AI Providers: #{Ai::Provider.count}"
puts "AI Agents: #{Ai::Agent.count}"
puts "AI Workflows: #{Ai::Workflow.count}"
puts "Ralph Loops: #{Ai::RalphLoop.count}"
puts "Agent Teams: #{Ai::AgentTeam.count}"
```

### 0.3 Verify Ollama Provider
```bash
# In Rails console - get the configured Ollama endpoint
provider = Ai::Provider.find_by(slug: 'ollama') || Ai::Provider.find_by(slug: 'remote-ollama-server')
puts "Ollama endpoint: #{provider.api_endpoint}"

# Test the remote endpoint (replace with actual endpoint from above)
# curl {OLLAMA_ENDPOINT}/api/tags
```

**Expected:** Remote Ollama server responds with available models.

---

## Phase 1: Basic Agent Functionality

### 1.1 Verify Provider Health
```bash
# Via Rails console
bundle exec rails c

# Check Ollama provider status
provider = Ai::Provider.find_by(slug: 'ollama')
puts "Provider: #{provider.name}"
puts "Active: #{provider.is_active}"
puts "Models: #{provider.supported_models.map { |m| m['id'] }.join(', ')}"
puts "Health: #{provider.health_status}"

# Test provider connection
credential = provider.provider_credentials.where(is_active: true).first
credential&.test_connection
```

**Expected:** Provider is active, has models listed, connection test succeeds.

### 1.2 Execute Simple Agent
```bash
# In Rails console
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')
user = User.first
account = user.account

# Create execution
execution = agent.executions.create!(
  account: account,
  user: user,
  execution_id: SecureRandom.uuid,
  ai_provider_id: agent.ai_provider_id,
  status: 'pending',
  input_parameters: { "input" => "Hello! Please respond with a brief greeting." }
)

# Start execution (mark as running)
execution.start_execution!

# Execute via MCP executor
executor = Ai::McpAgentExecutor.new(agent: agent, execution: execution, account: account)
result = executor.execute({ "input" => "Hello! Please respond with a brief greeting." })

# Check result structure (MCP format)
puts "Result keys: #{result.keys}"
puts "Has error: #{result['error'].present?}"

if result['error']
  puts "Error: #{result['error']['message']}"
else
  puts "Output: #{result.dig('result', 'output')}"
  puts "Tokens: #{result.dig('telemetry', 'tokens_used')}"
  puts "Execution ID: #{result['execution_id']}"
end

# Check execution record
execution.reload
puts "Status: #{execution.status}"
puts "Duration: #{execution.duration_ms}ms" if execution.completed?
```

**Expected:** Execution completes successfully, result contains MCP-formatted response with output.

### 1.2b Execute Agent via ManagementService (Recommended)
```bash
# The ManagementService provides a clean interface for agent execution
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')
user = User.first

# IMPORTANT: Ensure the agent has a valid model configured
# Check available models: agent.provider.supported_models.map { |m| m['id'] }
# Set model if needed:
manifest = agent.mcp_tool_manifest.dup
manifest["model"] = "llama3:8b"  # Use an available model
agent.update_columns(mcp_tool_manifest: manifest)

# Execute via service
service = Ai::Agents::ManagementService.new(agent: agent, user: user)
result = service.execute(input_parameters: { "input" => "Hello! Please respond with a brief greeting." })

if result.success?
  execution = result.data[:execution]
  puts "Status: #{execution.status}"
  puts "Response: #{execution.output_data["response"]}"
  puts "Model: #{execution.output_data.dig("metadata", "model_used")}"
  puts "Duration: #{execution.duration_ms}ms"
else
  puts "Error: #{result.error}"
end
```

**Expected:** Real AI-generated response in execution.output_data["response"].

### 1.3 Test via API Endpoint
```bash
# Get auth token first (or use existing session)
# Then call the execute endpoint

curl -X POST "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/execute" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"input_parameters": {"input": "What is 2 + 2?"}}'
```

**Expected:** JSON response with execution details and AI output.

---

## Phase 2: Agent Conversations (Multi-turn)

### 2.1 Create Conversation
```bash
# In Rails console
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')
user = User.first

# Create a conversation
conversation = Ai::Conversation.create!(
  account: user.account,
  user: user,
  agent: agent,
  ai_provider_id: agent.ai_provider_id,
  conversation_id: SecureRandom.uuid,
  status: 'active',
  title: 'Test Conversation'
)

puts "Conversation ID: #{conversation.id}"
```

### 2.2 Send Messages in Conversation
```bash
# Add first user message
msg1 = conversation.add_user_message("My name is Rett. Remember it for later.", user: user)

# Simulate assistant response (in real usage, this comes from AI execution)
# For manual testing, trigger via service:
service = Ai::Agents::ConversationService.new(agent: agent, user: user)
response = service.send_message(conversation, content: "My name is Rett. Remember it for later.")

# Send follow-up
response2 = service.send_message(conversation, content: "What is my name?")
puts response2.inspect
```

**Expected:** AI remembers context from previous messages.

### 2.3 Test Conversation via API
```bash
# Create conversation
curl -X POST "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/conversations" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"title": "API Test Conversation"}'

# Send message
curl -X POST "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/conversations/{CONV_ID}/send_message" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello from API!"}'
```

---

## Phase 3: Agent Validation & Lifecycle

### 3.1 Validate Agent Configuration
```bash
# In Rails console
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')
service = Ai::Agents::ManagementService.new(agent: agent, user: User.first)

result = service.validate
puts "Success: #{result.success?}"
puts "Valid: #{result.data[:valid]}"
puts "Errors: #{result.data[:errors]}"
puts "Warnings: #{result.data[:warnings]}"
```

### 3.2 Test Agent Lifecycle
```bash
# Pause agent
service.pause
puts agent.reload.status  # Should be 'paused'

# Try to execute (should fail)
begin
  service.execute(input_parameters: { input: "test" })
rescue => e
  puts "Expected error: #{e.message}"
end

# Resume agent
service.resume
puts agent.reload.status  # Should be 'active'
```

### 3.3 Get Agent Statistics
```bash
stats = service.stats
puts "Total executions: #{stats[:total_executions]}"
puts "Successful: #{stats[:successful_executions]}"
puts "Failed: #{stats[:failed_executions]}"
puts "Success rate: #{stats[:success_rate]}%"
puts "Total cost: $#{stats[:total_cost]}"
puts "Last executed: #{stats[:last_executed_at]}"
```

---

## Phase 4: Workflows

### 4.1 Create Simple Workflow
```bash
# In Rails console
account = Account.first
user = User.first

workflow = Ai::Workflow.create!(
  account: account,
  creator: user,
  name: 'Simple AI Test Workflow',
  description: 'Tests basic agent execution in workflow',
  status: 'draft',
  workflow_type: 'ai',  # 'ai' or 'cicd'
  is_template: false
)

# Add start node (is_start_node: true for start nodes)
start_node = workflow.nodes.create!(
  node_id: 'start_1',
  name: 'Start',
  node_type: 'start',
  is_start_node: true,
  position: { x: 100, y: 100 },
  configuration: {}
)

# Add AI agent node
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')
agent_node = workflow.nodes.create!(
  node_id: 'ai_agent_1',
  name: 'AI Processing',
  node_type: 'ai_agent',
  position: { x: 300, y: 100 },
  configuration: {
    ai_agent_id: agent.id,
    input_mapping: { input: '{{trigger.input}}' }
  }
)

# Add end node (is_end_node: true for end nodes)
end_node = workflow.nodes.create!(
  node_id: 'end_1',
  name: 'End',
  node_type: 'end',
  is_end_node: true,
  position: { x: 500, y: 100 },
  configuration: {}
)

# Create edges (use node_id strings, not node objects)
workflow.edges.create!(
  edge_id: 'edge_1',
  source_node_id: 'start_1',
  target_node_id: 'ai_agent_1'
)
workflow.edges.create!(
  edge_id: 'edge_2',
  source_node_id: 'ai_agent_1',
  target_node_id: 'end_1'
)

# Activate workflow
workflow.update!(status: 'active')
puts "Workflow ID: #{workflow.id}"
```

### 4.2 Execute Workflow
```bash
# Create workflow run
run = Ai::WorkflowRun.create!(
  workflow: workflow,
  account: account,
  triggered_by_user: user,
  status: 'pending',
  trigger_type: 'manual',
  input_variables: { input: 'Process this text through the workflow' }
)

# Execute via orchestrator
orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: run)
result = orchestrator.execute

puts "Run status: #{run.reload.status}"
puts "Output: #{run.output_data}"
puts "Run summary: #{run.run_summary}"
```

### 4.3 Test via API
```bash
# Trigger workflow execution
curl -X POST "https://dev.powernode.org/api/v1/ai/workflows/{WORKFLOW_ID}/execute" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"trigger_data": {"input": "Test input from API"}}'
```

---

## Phase 5: Ralph Loops

### 5.1 Create Ralph Loop
```bash
# In Rails console
account = Account.first
user = User.first

ralph_loop = Ai::RalphLoop.create!(
  account: account,
  name: 'Test Ralph Loop',
  description: 'Simple test of iterative AI execution',
  status: 'pending',
  ai_tool: 'ollama',
  scheduling_mode: 'manual',
  max_iterations: 5,
  configuration: {
    model: 'llama3:8b',  # Use available model (check provider.supported_models)
    temperature: 0.7
  }
)

puts "Ralph Loop ID: #{ralph_loop.id}"
```

### 5.2 Add Tasks to Ralph Loop
```bash
# Add tasks
task1 = ralph_loop.ralph_tasks.create!(
  task_key: 'analyze',
  description: 'Analyze the given requirements and identify key components',
  status: 'pending',
  priority: 3,
  position: 1
)

task2 = ralph_loop.ralph_tasks.create!(
  task_key: 'implement',
  description: 'Implement the solution based on analysis',
  status: 'pending',
  priority: 2,
  position: 2,
  dependencies: ['analyze']  # Depends on task1
)

task3 = ralph_loop.ralph_tasks.create!(
  task_key: 'review',
  description: 'Review and validate the implementation',
  status: 'pending',
  priority: 1,
  position: 3,
  dependencies: ['implement']
)

puts "Tasks created: #{ralph_loop.ralph_tasks.count}"
```

**Note:** Priority is descending (higher = executed first). Position determines UI ordering.

### 5.3 Execute Ralph Loop
```bash
# Start the loop
service = Ai::Ralph::ExecutionService.new(ralph_loop: ralph_loop)
result = service.start_loop

puts "Start result: #{result}"
puts "Loop status: #{ralph_loop.reload.status}"

# Run one iteration manually
result = service.run_iteration
puts "Iteration result: #{result}"
puts "Current iteration: #{ralph_loop.reload.current_iteration}"

# Check task status
ralph_loop.ralph_tasks.ordered.each do |task|
  puts "#{task.task_key}: #{task.status}"
end
```

### 5.4 Monitor Progress
```bash
# Get loop summary
puts ralph_loop.loop_summary

# Get learnings accumulated
ralph_loop.learnings.each do |learning|
  puts "Learning: #{learning['text']}"
end

# Get progress percentage
puts "Progress: #{ralph_loop.progress_percentage}%"
```

### 5.5 Test via API
```bash
# Start loop
curl -X POST "https://dev.powernode.org/api/v1/ai/ralph_loops/{LOOP_ID}/start" \
  -H "Authorization: Bearer {TOKEN}"

# Run iteration
curl -X POST "https://dev.powernode.org/api/v1/ai/ralph_loops/{LOOP_ID}/run_iteration" \
  -H "Authorization: Bearer {TOKEN}"

# Get progress
curl "https://dev.powernode.org/api/v1/ai/ralph_loops/{LOOP_ID}/progress" \
  -H "Authorization: Bearer {TOKEN}"
```

---

## Phase 6: Agent Teams

### 6.1 Create Agent Team
```bash
# In Rails console
account = Account.first
user = User.first

# team_type: hierarchical, mesh, sequential, parallel
# coordination_strategy: manager_led, consensus, auction, round_robin, priority_based
team = Ai::AgentTeam.create!(
  account: account,
  name: 'Analysis Team',
  description: 'Team for comprehensive analysis tasks',
  team_type: 'sequential',
  coordination_strategy: 'priority_based',
  status: 'active',
  team_config: {
    max_retries: 3,
    timeout_seconds: 300
  }
)

# Add agents to team
agent1 = Ai::Agent.find_by(slug: 'ollama-example-agent')
agent2 = Ai::Agent.find_by(slug: 'claude-strategic-planner')

team.add_member(agent: agent1, role: 'researcher', priority_order: 0)
team.add_member(agent: agent2, role: 'analyst', priority_order: 1) if agent2

puts "Team ID: #{team.id}"
puts "Members: #{team.members.count}"
puts "Team stats: #{team.team_stats}"
```

### 6.2 Execute Team
```bash
# Using the model's execute method
result = team.execute(input: "Analyze the current market trends in AI", user: user)

puts "Team execution result: #{result}"

# Or directly via orchestrator
orchestrator = Ai::AgentTeamOrchestrator.new(team: team, user: user)
result = orchestrator.execute(input: "Analyze the current market trends in AI")

puts "Team execution result: #{result}"
```

---

## Phase 7: Advanced - Workflow with Ralph Loop Node

### 7.1 Create Workflow with Ralph Loop
```bash
workflow = Ai::Workflow.create!(
  account: account,
  creator: user,
  name: 'Ralph Loop Workflow',
  description: 'Workflow that executes a Ralph Loop',
  status: 'draft',
  workflow_type: 'ai'
)

# Start node
start_node = workflow.nodes.create!(
  node_id: 'start_1',
  name: 'Start',
  node_type: 'start',
  is_start_node: true,
  position: { x: 100, y: 100 },
  configuration: {}
)

# Ralph Loop node
ralph_node = workflow.nodes.create!(
  node_id: 'ralph_loop_1',
  name: 'Execute Ralph Loop',
  node_type: 'ralph_loop',
  position: { x: 300, y: 100 },
  configuration: {
    operation: 'run_to_completion',
    ralph_loop_id: ralph_loop.id,
    timeout_seconds: 300
  }
)

# End node
end_node = workflow.nodes.create!(
  node_id: 'end_1',
  name: 'End',
  node_type: 'end',
  is_end_node: true,
  position: { x: 500, y: 100 },
  configuration: {}
)

workflow.edges.create!(edge_id: 'edge_1', source_node_id: 'start_1', target_node_id: 'ralph_loop_1')
workflow.edges.create!(edge_id: 'edge_2', source_node_id: 'ralph_loop_1', target_node_id: 'end_1')
workflow.update!(status: 'active')
```

---

## Phase 8: Memory and Context System

The AI memory system provides persistent context for agents with three memory types: factual, experiential, and working.

### 8.1 Create Persistent Context
```bash
# In Rails console
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')
account = agent.account

# Create persistent context for an agent
context = Ai::PersistentContext.create!(
  account: account,
  contextable: agent,  # polymorphic: agent, team, or workflow
  context_type: 'agent_context',
  name: 'Primary Context',
  description: 'Main memory store for the agent',
  status: 'active',
  is_default: true,
  max_entries: 1000,
  retention_days: 90
)

puts "Context ID: #{context.id}"
puts "Contextable: #{context.contextable_type}##{context.contextable_id}"
```

### 8.2 Add Context Entries (Factual Memory)
```bash
# Add factual memory entries
entry1 = context.context_entries.create!(
  account: account,
  entry_type: 'factual',  # factual, experiential, working
  key: 'user_preference_theme',
  value: { theme: 'dark', language: 'en' },
  importance: 0.8,       # 0.0 to 1.0
  confidence: 0.95,      # 0.0 to 1.0
  source: 'user_input',
  version: 1
)

entry2 = context.context_entries.create!(
  account: account,
  entry_type: 'factual',
  key: 'company_info',
  value: { name: 'Acme Corp', industry: 'Technology' },
  importance: 0.9,
  confidence: 1.0,
  source: 'system',
  version: 1
)

puts "Factual entries: #{context.context_entries.where(entry_type: 'factual').count}"
```

### 8.3 Add Experiential Memory (Learning from Interactions)
```bash
# Add experiential memory (what the agent has learned)
learning = context.context_entries.create!(
  account: account,
  entry_type: 'experiential',
  key: 'interaction_pattern_001',
  value: {
    pattern: 'User prefers concise responses',
    observed_at: Time.current,
    reinforcement_count: 3
  },
  importance: 0.6,
  confidence: 0.7,
  source: 'inference'
)

puts "Experiential entry: #{learning.key}"
```

### 8.4 Working Memory (Session Context)
```bash
# Add working memory for current session
working = context.context_entries.create!(
  account: account,
  entry_type: 'working',
  key: 'current_task',
  value: {
    task_type: 'analysis',
    started_at: Time.current,
    progress: 0.5
  },
  importance: 1.0,  # High importance for current work
  confidence: 1.0,
  source: 'runtime',
  expires_at: 1.hour.from_now
)

puts "Working memory expires: #{working.expires_at}"
```

### 8.5 Use Memory Service for Context Injection
```bash
# Use the MemoryManagementService to get relevant context
service = Ai::MemoryManagementService.new(agent: agent)

# Get all relevant context for a prompt
relevant_context = service.get_relevant_context(
  query: "What theme does the user prefer?",
  max_entries: 10,
  include_types: [:factual, :experiential]
)

puts "Found #{relevant_context.count} relevant entries"
relevant_context.each { |e| puts "  #{e.key}: #{e.value}" }

# Inject context into a prompt
enriched_prompt = service.inject_context(
  base_prompt: "Respond to the user's question about preferences.",
  context_entries: relevant_context
)

puts "Enriched prompt length: #{enriched_prompt.length}"
```

### 8.6 Context Access Logging
```bash
# Check context access logs
Ai::ContextAccessLog.where(context_entry: entry1).each do |log|
  puts "Accessed by: #{log.accessor_type}##{log.accessor_id}"
  puts "Access type: #{log.access_type}"  # read, write, delete
  puts "At: #{log.created_at}"
end
```

### 8.7 Test via API
```bash
# Get agent's context
curl "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/context" \
  -H "Authorization: Bearer {TOKEN}"

# Add context entry
curl -X POST "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/context/entries" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "entry_type": "factual",
    "key": "api_test_entry",
    "value": {"test": true},
    "importance": 0.5
  }'

# Search context
curl "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/context/search?query=preference" \
  -H "Authorization: Bearer {TOKEN}"
```

---

## Phase 9: Agent Templates and Versioning

### 9.1 Create Agent Template
```bash
# In Rails console
account = Account.first
user = User.first

template = Ai::AgentTemplate.create!(
  account: account,
  creator: user,
  name: 'Customer Support Agent',
  description: 'Template for customer support agents',
  slug: 'customer-support-template',
  status: 'published',
  visibility: 'public',  # private, account, public
  category: 'support',
  version: '1.0.0',
  mcp_tool_manifest: {
    name: 'customer-support',
    version: '1.0.0',
    description: 'Customer support assistant',
    model: 'llama3:8b',
    system_prompt: 'You are a helpful customer support agent.',
    capabilities: ['chat', 'ticket_lookup'],
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Customer query' }
      }
    }
  },
  default_configuration: {
    temperature: 0.7,
    max_tokens: 500
  },
  tags: ['support', 'customer-service', 'chat']
)

puts "Template ID: #{template.id}"
puts "Version: #{template.version}"
```

### 9.2 Create Agent from Template
```bash
# Install template (create agent from template)
agent = Ai::Agent.create_from_template!(
  template: template,
  account: account,
  creator: user,
  name: 'My Support Agent',
  ai_provider_id: Ai::Provider.find_by(slug: 'ollama').id
)

# Or use the installation service
service = Ai::Marketplace::InstallationService.new(account: account, user: user)
result = service.install_template(template)

if result.success?
  agent = result.data[:agent]
  puts "Installed agent: #{agent.name}"
else
  puts "Error: #{result.error}"
end
```

### 9.3 Version Management
```bash
# Update template version
template.create_new_version!(
  version: '1.1.0',
  changes: {
    system_prompt: 'You are a helpful and empathetic customer support agent.',
    changelog: 'Added empathy instruction'
  }
)

# Get version history
template.versions.order(created_at: :desc).each do |v|
  puts "v#{v.version}: #{v.changelog}"
end

# Check installed agents for update availability
template.installed_agents.each do |agent|
  if agent.template_version < template.version
    puts "#{agent.name} can be updated from #{agent.template_version} to #{template.version}"
  end
end
```

### 9.4 Template Discovery
```bash
# Search templates
templates = Ai::AgentTemplate.published
  .where(visibility: ['public', 'account'])
  .search('customer support')
  .order(install_count: :desc)

templates.each do |t|
  puts "#{t.name} v#{t.version} - #{t.install_count} installs"
end
```

---

## Phase 10: Agent-to-Agent (A2A) Protocol

### 10.1 Publish Agent Card (A2A)
```bash
# In Rails console
agent = Ai::Agent.find_by(slug: 'ollama-example-agent')

# Create A2A agent card for external discovery
card = Ai::AgentCard.create!(
  agent: agent,
  account: agent.account,
  card_id: SecureRandom.uuid,
  name: agent.name,
  description: agent.description,
  version: '1.0.0',
  status: 'published',
  url: "https://dev.powernode.org/a2a/agents/#{agent.id}",
  capabilities: {
    streaming: true,
    pushNotifications: false,
    stateTransitionHistory: true
  },
  skills: [
    { name: 'text-analysis', description: 'Analyze and summarize text' },
    { name: 'question-answering', description: 'Answer questions about content' }
  ],
  authentication: {
    type: 'bearer',
    required: true
  }
)

puts "Agent Card URL: #{card.url}"
puts "Skills: #{card.skills.map { |s| s['name'] }.join(', ')}"
```

### 10.2 Create A2A Task (Inter-Agent Communication)
```bash
# Create a task for another agent to execute
source_agent = Ai::Agent.first
target_agent = Ai::Agent.second

task = Ai::A2aTask.create!(
  account: source_agent.account,
  source_agent: source_agent,
  target_agent: target_agent,
  task_type: 'analyze',
  status: 'pending',
  input_data: {
    text: 'Analyze this document for key themes',
    context: { priority: 'high' }
  },
  metadata: {
    timeout_seconds: 60,
    retry_count: 3
  }
)

puts "A2A Task ID: #{task.id}"
puts "Status: #{task.status}"
```

### 10.3 Execute A2A Task
```bash
# Execute the task via service
service = Ai::A2a::Service.new(task: task)
result = service.execute

if result.success?
  puts "Task completed: #{task.reload.status}"
  puts "Output: #{task.output_data}"
else
  puts "Error: #{result.error}"
end

# Track task events
task.a2a_task_events.order(:created_at).each do |event|
  puts "#{event.event_type}: #{event.message} (#{event.created_at})"
end
```

### 10.4 A2A DAG Execution (Multi-Agent Pipeline)
```bash
# Execute agents as a directed acyclic graph
agents = [agent1, agent2, agent3]
dag_config = {
  nodes: [
    { agent_id: agent1.id, dependencies: [] },
    { agent_id: agent2.id, dependencies: [agent1.id] },
    { agent_id: agent3.id, dependencies: [agent1.id, agent2.id] }
  ]
}

executor = Ai::A2a::DagExecutor.new(
  account: account,
  dag_config: dag_config,
  input: { text: 'Process through pipeline' }
)

result = executor.execute
puts "DAG execution status: #{result[:status]}"
puts "Final output: #{result[:output]}"
```

### 10.5 External Agent Discovery
```bash
# Fetch external agent card from another system
external_url = 'https://external-ai-service.com/.well-known/agent.json'

# This would typically be done via job
result = Ai::A2a::AgentDiscoveryService.fetch_agent_card(external_url)

if result.success?
  external_card = result.data[:card]
  puts "Discovered: #{external_card['name']}"
  puts "Skills: #{external_card['skills']}"
end
```

### 10.6 Test via API
```bash
# Get agent's A2A card
curl "https://dev.powernode.org/api/v1/ai/agents/{AGENT_ID}/card" \
  -H "Authorization: Bearer {TOKEN}"

# Create A2A task
curl -X POST "https://dev.powernode.org/api/v1/ai/a2a_tasks" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "target_agent_id": "{TARGET_AGENT_ID}",
    "task_type": "analyze",
    "input_data": {"text": "Analyze this"}
  }'

# Get task status
curl "https://dev.powernode.org/api/v1/ai/a2a_tasks/{TASK_ID}" \
  -H "Authorization: Bearer {TOKEN}"
```

---

## Phase 11: Advanced Workflow Nodes

The workflow system supports 39 node types. Here we test the more complex ones.

### 11.1 Conditional Branching Node
```bash
# In Rails console
workflow = Ai::Workflow.create!(
  account: Account.first,
  creator: User.first,
  name: 'Conditional Workflow',
  status: 'draft',
  workflow_type: 'ai'
)

# Start node
workflow.nodes.create!(
  node_id: 'start_1', name: 'Start', node_type: 'start',
  is_start_node: true, position: { x: 100, y: 100 }
)

# Condition node with branches
condition_node = workflow.nodes.create!(
  node_id: 'condition_1',
  name: 'Check Priority',
  node_type: 'condition',
  position: { x: 300, y: 100 },
  configuration: {
    conditions: [
      { expression: '{{input.priority}} == "high"', target: 'urgent_path' },
      { expression: '{{input.priority}} == "low"', target: 'normal_path' },
      { default: true, target: 'default_path' }
    ]
  }
)

# Branch paths
workflow.nodes.create!(node_id: 'urgent_path', name: 'Urgent Handler',
  node_type: 'ai_agent', position: { x: 500, y: 50 },
  configuration: { ai_agent_id: Ai::Agent.first.id })

workflow.nodes.create!(node_id: 'normal_path', name: 'Normal Handler',
  node_type: 'ai_agent', position: { x: 500, y: 150 },
  configuration: { ai_agent_id: Ai::Agent.first.id })

# End node
workflow.nodes.create!(
  node_id: 'end_1', name: 'End', node_type: 'end',
  is_end_node: true, position: { x: 700, y: 100 }
)

# Create edges
workflow.edges.create!(edge_id: 'e1', source_node_id: 'start_1', target_node_id: 'condition_1')
workflow.edges.create!(edge_id: 'e2', source_node_id: 'urgent_path', target_node_id: 'end_1')
workflow.edges.create!(edge_id: 'e3', source_node_id: 'normal_path', target_node_id: 'end_1')

workflow.update!(status: 'active')
```

### 11.2 Loop Node with Iteration
```bash
# Create workflow with loop
workflow = Ai::Workflow.create!(
  account: Account.first, creator: User.first,
  name: 'Loop Workflow', status: 'draft', workflow_type: 'ai'
)

workflow.nodes.create!(
  node_id: 'start_1', name: 'Start', node_type: 'start',
  is_start_node: true, position: { x: 100, y: 100 }
)

# Loop node - iterates over array
loop_node = workflow.nodes.create!(
  node_id: 'loop_1',
  name: 'Process Items',
  node_type: 'loop',
  position: { x: 300, y: 100 },
  configuration: {
    iterator_variable: 'items',    # Array to iterate
    item_variable: 'current_item', # Current item variable name
    max_iterations: 100,           # Safety limit
    parallel_execution: false      # Sequential vs parallel
  }
)

# Loop body (AI agent)
workflow.nodes.create!(
  node_id: 'process_item', name: 'Process Item',
  node_type: 'ai_agent', position: { x: 500, y: 100 },
  configuration: {
    ai_agent_id: Ai::Agent.first.id,
    input_mapping: { input: '{{current_item}}' }
  }
)

workflow.nodes.create!(
  node_id: 'end_1', name: 'End', node_type: 'end',
  is_end_node: true, position: { x: 700, y: 100 }
)

# Edges - loop back
workflow.edges.create!(edge_id: 'e1', source_node_id: 'start_1', target_node_id: 'loop_1')
workflow.edges.create!(edge_id: 'e2', source_node_id: 'loop_1', target_node_id: 'process_item',
  edge_type: 'loop_body')
workflow.edges.create!(edge_id: 'e3', source_node_id: 'process_item', target_node_id: 'loop_1',
  edge_type: 'loop_continue')
workflow.edges.create!(edge_id: 'e4', source_node_id: 'loop_1', target_node_id: 'end_1',
  edge_type: 'loop_complete')

workflow.update!(status: 'active')

# Test with array input
run = Ai::WorkflowRun.create!(
  workflow: workflow, account: Account.first, triggered_by_user: User.first,
  status: 'pending', trigger_type: 'manual',
  input_variables: { items: ['item1', 'item2', 'item3'] }
)

orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: run)
orchestrator.execute
```

### 11.3 Parallel Split and Merge
```bash
workflow = Ai::Workflow.create!(
  account: Account.first, creator: User.first,
  name: 'Parallel Workflow', status: 'draft', workflow_type: 'ai'
)

# Start
workflow.nodes.create!(node_id: 'start', name: 'Start', node_type: 'start',
  is_start_node: true, position: { x: 100, y: 200 })

# Split into parallel branches
workflow.nodes.create!(
  node_id: 'split_1', name: 'Split', node_type: 'split',
  position: { x: 250, y: 200 },
  configuration: { split_type: 'parallel' }
)

# Parallel branches
workflow.nodes.create!(node_id: 'branch_a', name: 'Analysis A',
  node_type: 'ai_agent', position: { x: 400, y: 100 },
  configuration: { ai_agent_id: Ai::Agent.first.id })

workflow.nodes.create!(node_id: 'branch_b', name: 'Analysis B',
  node_type: 'ai_agent', position: { x: 400, y: 300 },
  configuration: { ai_agent_id: Ai::Agent.first.id })

# Merge parallel results
workflow.nodes.create!(
  node_id: 'merge_1', name: 'Merge Results', node_type: 'merge',
  position: { x: 550, y: 200 },
  configuration: {
    merge_strategy: 'all',  # all, any, first
    output_format: 'array'
  }
)

# End
workflow.nodes.create!(node_id: 'end', name: 'End', node_type: 'end',
  is_end_node: true, position: { x: 700, y: 200 })

# Edges
workflow.edges.create!(edge_id: 'e1', source_node_id: 'start', target_node_id: 'split_1')
workflow.edges.create!(edge_id: 'e2', source_node_id: 'split_1', target_node_id: 'branch_a')
workflow.edges.create!(edge_id: 'e3', source_node_id: 'split_1', target_node_id: 'branch_b')
workflow.edges.create!(edge_id: 'e4', source_node_id: 'branch_a', target_node_id: 'merge_1')
workflow.edges.create!(edge_id: 'e5', source_node_id: 'branch_b', target_node_id: 'merge_1')
workflow.edges.create!(edge_id: 'e6', source_node_id: 'merge_1', target_node_id: 'end')

workflow.update!(status: 'active')
```

### 11.4 Human Approval Node
```bash
# Workflow with human approval gate
workflow.nodes.create!(
  node_id: 'approval_gate',
  name: 'Manager Approval',
  node_type: 'human_approval',
  position: { x: 400, y: 100 },
  configuration: {
    approvers: ['manager@company.com'],  # or role-based
    approval_type: 'any',                 # any, all, majority
    timeout_hours: 24,
    escalation_policy: {
      escalate_after_hours: 12,
      escalate_to: ['director@company.com']
    },
    context_template: 'Please review: {{previous_node.output}}'
  }
)

# When workflow reaches this node, it pauses and:
# 1. Creates Ai::ApprovalRequest record
# 2. Sends notifications to approvers
# 3. Waits for approval/rejection via API or UI
```

### 11.5 Sub-Workflow Node
```bash
# Create a reusable sub-workflow
sub_workflow = Ai::Workflow.create!(
  account: Account.first, creator: User.first,
  name: 'Data Processing Sub-Workflow',
  status: 'active', workflow_type: 'ai'
)
# ... add nodes to sub_workflow ...

# Reference in parent workflow
parent_workflow.nodes.create!(
  node_id: 'sub_process',
  name: 'Run Data Processing',
  node_type: 'sub_workflow',
  position: { x: 400, y: 100 },
  configuration: {
    sub_workflow_id: sub_workflow.id,
    input_mapping: { data: '{{trigger.raw_data}}' },
    output_mapping: { processed: '{{sub_workflow.result}}' },
    max_depth: 3  # Prevent infinite recursion
  }
)
```

### 11.6 API Call Node
```bash
workflow.nodes.create!(
  node_id: 'external_api',
  name: 'Fetch External Data',
  node_type: 'api_call',
  position: { x: 400, y: 100 },
  configuration: {
    url: 'https://api.example.com/data',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer {{secrets.api_key}}'
    },
    body: { query: '{{trigger.search_term}}' },
    timeout_seconds: 30,
    retry_config: { max_retries: 3, backoff: 'exponential' },
    response_mapping: { data: '$.results', count: '$.total' }
  }
)
```

### 11.7 Transform Node
```bash
workflow.nodes.create!(
  node_id: 'transform_data',
  name: 'Transform Results',
  node_type: 'transform',
  position: { x: 500, y: 100 },
  configuration: {
    transform_type: 'jmespath',  # jmespath, jsonpath, javascript
    expression: 'items[?score > `0.5`].{name: name, value: score}',
    # or for javascript:
    # transform_type: 'javascript',
    # expression: 'data.items.filter(i => i.score > 0.5).map(i => ({name: i.name}))'
  }
)
```

---

## Phase 12: Workflow Triggers and Scheduling

### 12.1 Webhook Trigger
```bash
# Create webhook-triggered workflow
workflow = Ai::Workflow.find_by(name: 'Simple AI Test Workflow')

trigger = Ai::WorkflowTrigger.create!(
  workflow: workflow,
  trigger_type: 'webhook',
  name: 'External System Webhook',
  is_active: true,
  configuration: {
    secret_token: SecureRandom.hex(32),
    validation: {
      required_headers: ['X-Signature'],
      ip_whitelist: ['10.0.0.0/8']
    }
  }
)

puts "Webhook URL: https://dev.powernode.org/webhooks/ai/workflows/#{trigger.id}"
puts "Secret: #{trigger.configuration['secret_token']}"

# Test webhook (from external system)
# curl -X POST "https://dev.powernode.org/webhooks/ai/workflows/{TRIGGER_ID}" \
#   -H "X-Signature: {computed_signature}" \
#   -d '{"event": "new_ticket", "data": {...}}'
```

### 12.2 Schedule Trigger (Cron)
```bash
# Create scheduled workflow execution
schedule = Ai::WorkflowSchedule.create!(
  workflow: workflow,
  account: workflow.account,
  name: 'Daily Report Generation',
  schedule_type: 'cron',
  cron_expression: '0 9 * * *',  # Every day at 9 AM
  timezone: 'America/New_York',
  is_active: true,
  input_template: {
    report_date: '{{date.yesterday}}',
    format: 'pdf'
  },
  next_run_at: Ai::WorkflowSchedule.calculate_next_run('0 9 * * *', 'America/New_York')
)

puts "Next run: #{schedule.next_run_at}"

# Manual trigger test
schedule.trigger_now!
```

### 12.3 Event-Based Trigger
```bash
# Trigger workflow on system events
trigger = Ai::WorkflowTrigger.create!(
  workflow: workflow,
  trigger_type: 'event',
  name: 'On Subscription Created',
  is_active: true,
  configuration: {
    event_types: ['subscription.created', 'subscription.upgraded'],
    filter: {
      'subscription.plan_tier': ['professional', 'enterprise']
    }
  }
)

# Workflow will be triggered when matching events occur
```

### 12.4 Git Trigger (CI/CD)
```bash
# Trigger on git events
git_trigger = Ai::WorkflowTrigger.create!(
  workflow: workflow,
  trigger_type: 'git',
  name: 'On Push to Main',
  is_active: true,
  configuration: {
    repository: 'org/repo',
    events: ['push', 'pull_request'],
    branches: ['main', 'develop'],
    paths: ['src/**/*.rb', 'config/**']
  }
)
```

### 12.5 API Trigger
```bash
# Test manual API trigger
curl -X POST "https://dev.powernode.org/api/v1/ai/workflows/{WORKFLOW_ID}/execute" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "trigger_type": "api",
    "input_variables": {
      "input": "Process this data"
    },
    "priority": "high",
    "callback_url": "https://myapp.com/webhook/workflow-complete"
  }'
```

---

## Phase 13: Governance and Compliance

### 13.1 Create Compliance Policy
```bash
# In Rails console
account = Account.first

policy = Ai::CompliancePolicy.create!(
  account: account,
  name: 'PII Data Protection',
  description: 'Ensures no PII is processed without encryption',
  policy_type: 'data_handling',
  status: 'active',
  rules: {
    checks: [
      { type: 'no_pii_in_prompts', severity: 'critical' },
      { type: 'require_encryption', data_types: ['ssn', 'credit_card'] },
      { type: 'audit_logging', required: true }
    ],
    actions: {
      on_violation: 'block_and_alert',
      alert_channels: ['email', 'slack']
    }
  },
  applies_to: {
    agent_types: ['all'],
    workflow_types: ['ai'],
    exclude_sandboxes: true
  }
)

puts "Policy ID: #{policy.id}"
```

### 13.2 Check Policy Compliance
```bash
# Validate agent against policies
agent = Ai::Agent.first
service = Ai::GovernanceService.new(account: account)

result = service.check_compliance(entity: agent)

puts "Compliant: #{result.compliant?}"
result.violations.each do |v|
  puts "Violation: #{v.policy_name} - #{v.description}"
  puts "  Severity: #{v.severity}"
  puts "  Recommendation: #{v.recommendation}"
end
```

### 13.3 Audit Entry Logging
```bash
# Create audit entry (usually automatic)
Ai::ComplianceAuditEntry.create!(
  account: account,
  auditable: agent,
  action: 'agent_execution',
  actor_type: 'User',
  actor_id: User.first.id,
  details: {
    execution_id: 'exec_123',
    input_hash: Digest::SHA256.hexdigest('input data'),
    compliance_checks: ['pii_scan', 'rate_limit'],
    results: { pii_scan: 'pass', rate_limit: 'pass' }
  },
  ip_address: '192.168.1.1',
  user_agent: 'API Client'
)

# Query audit trail
Ai::ComplianceAuditEntry
  .where(auditable: agent)
  .where('created_at > ?', 7.days.ago)
  .order(created_at: :desc)
  .each { |e| puts "#{e.action} at #{e.created_at}" }
```

### 13.4 SLA Contract and Monitoring
```bash
# Create SLA contract
sla = Ai::SlaContract.create!(
  account: account,
  name: 'Premium Support SLA',
  status: 'active',
  targets: {
    response_time_ms: 5000,
    availability_percent: 99.9,
    max_errors_per_hour: 10
  },
  applies_to: {
    agent_ids: [Ai::Agent.first.id],
    workflow_ids: []
  },
  measurement_window: 'rolling_24h',
  alert_config: {
    threshold_warning: 0.95,
    threshold_critical: 0.90,
    channels: ['email', 'pagerduty']
  }
)

# Check SLA compliance
violations = sla.check_compliance
violations.each do |v|
  puts "SLA Violation: #{v.metric} - actual: #{v.actual_value}, target: #{v.target_value}"
end
```

### 13.5 Approval Workflows
```bash
# Create approval request
request = Ai::ApprovalRequest.create!(
  account: account,
  requestable: workflow,  # polymorphic
  request_type: 'workflow_publish',
  requester: User.first,
  status: 'pending',
  title: 'Publish Production Workflow',
  description: 'Request to publish workflow to production',
  metadata: {
    changes_summary: 'Added new AI agent node',
    risk_assessment: 'low'
  },
  expires_at: 7.days.from_now
)

# Create approval chain (multi-level)
chain = Ai::ApprovalChain.create!(
  account: account,
  approval_request: request,
  chain_type: 'sequential',  # sequential, parallel, any
  steps: [
    { level: 1, approvers: ['tech_lead@company.com'], required: true },
    { level: 2, approvers: ['manager@company.com'], required: true }
  ]
)

# Record approval decision
Ai::ApprovalDecision.create!(
  approval_request: request,
  approval_chain: chain,
  approver: User.find_by(email: 'tech_lead@company.com'),
  decision: 'approved',
  level: 1,
  comments: 'Looks good, approved for next level'
)
```

### 13.6 Policy Violation Tracking
```bash
# Record policy violation
violation = Ai::PolicyViolation.create!(
  account: account,
  compliance_policy: policy,
  violatable: agent,
  violation_type: 'pii_detected',
  severity: 'warning',
  description: 'Potential PII detected in prompt',
  evidence: {
    prompt_snippet: '...first 100 chars...',
    detected_patterns: ['email_address']
  },
  status: 'open',
  remediation_deadline: 24.hours.from_now
)

# Track remediation
violation.update!(
  status: 'remediated',
  remediation_notes: 'Added PII scrubbing filter',
  remediated_at: Time.current,
  remediated_by: User.first
)
```

---

## Phase 14: Marketplace

### 14.1 Browse Marketplace
```bash
# In Rails console
# Search marketplace
results = Ai::MarketplaceService.search(
  query: 'customer support',
  category: 'agents',
  filters: {
    price_range: { min: 0, max: 100 },
    rating_min: 4.0,
    verified_only: true
  },
  sort: 'popularity',
  page: 1,
  per_page: 20
)

results.each do |item|
  puts "#{item.name} - #{item.price_type}: $#{item.price}"
  puts "  Rating: #{item.average_rating} (#{item.review_count} reviews)"
end
```

### 14.2 List in Marketplace (Publisher)
```bash
# Create publisher account
publisher = Ai::PublisherAccount.create!(
  account: Account.first,
  name: 'Acme AI Solutions',
  slug: 'acme-ai',
  status: 'verified',
  publisher_type: 'organization',
  profile: {
    description: 'Enterprise AI solutions',
    website: 'https://acme.ai',
    support_email: 'support@acme.ai'
  },
  revenue_share_percent: 70,  # Publisher gets 70%
  payout_config: {
    method: 'stripe',
    threshold: 100.00
  }
)

# Publish agent to marketplace
agent_template = Ai::AgentTemplate.first
listing = Ai::MarketplaceService.create_listing(
  publisher: publisher,
  item: agent_template,
  pricing: {
    type: 'one_time',  # one_time, subscription, credits
    amount: 49.99,
    currency: 'USD'
  },
  visibility: 'public'
)
```

### 14.3 Purchase from Marketplace
```bash
# Create purchase
purchase = Ai::MarketplacePurchase.create!(
  account: Account.first,
  user: User.first,
  purchasable: agent_template,
  publisher_account: publisher,
  purchase_type: 'one_time',
  amount: 49.99,
  currency: 'USD',
  status: 'completed',
  payment_reference: 'ch_123abc'
)

# Record transaction for publisher
Ai::MarketplaceTransaction.create!(
  marketplace_purchase: purchase,
  publisher_account: publisher,
  transaction_type: 'sale',
  gross_amount: 49.99,
  platform_fee: 14.997,  # 30%
  net_amount: 34.993,
  currency: 'USD',
  status: 'pending_payout'
)
```

### 14.4 Reviews and Ratings
```bash
# Add review
review = Ai::AgentReview.create!(
  agent: agent,
  reviewer: User.first,
  rating: 5,
  title: 'Excellent agent!',
  content: 'Works perfectly for our customer support needs.',
  is_verified_purchase: true
)

# Get agent rating stats
stats = agent.review_stats
puts "Average: #{stats[:average_rating]}"
puts "Total: #{stats[:review_count]}"
puts "Distribution: #{stats[:distribution]}"  # { 5 => 10, 4 => 5, ... }
```

### 14.5 Content Moderation
```bash
# Create moderation entry
moderation = Ai::MarketplaceModeration.create!(
  moderatable: agent_template,
  account: Account.first,
  moderation_type: 'automated_scan',
  status: 'approved',
  checks: {
    malware_scan: 'pass',
    policy_compliance: 'pass',
    content_guidelines: 'pass'
  },
  moderator_notes: 'Automated scan passed all checks'
)

# Manual moderation review
moderation.update!(
  moderation_type: 'manual_review',
  status: 'approved',
  moderator_id: User.first.id,
  reviewed_at: Time.current
)
```

### 14.6 Test via API
```bash
# Browse marketplace
curl "https://dev.powernode.org/api/v1/ai/marketplace?category=agents&sort=popular" \
  -H "Authorization: Bearer {TOKEN}"

# Get item details
curl "https://dev.powernode.org/api/v1/ai/marketplace/items/{ITEM_ID}" \
  -H "Authorization: Bearer {TOKEN}"

# Purchase item
curl -X POST "https://dev.powernode.org/api/v1/ai/marketplace/items/{ITEM_ID}/purchase" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"payment_method_id": "pm_xxx"}'
```

---

## Phase 15: Credits and Billing

### 15.1 Account Credits Setup
```bash
# In Rails console
account = Account.first

# Add account credits
credit = Ai::AccountCredit.create!(
  account: account,
  credit_type: 'purchased',
  amount: 1000.0,
  remaining: 1000.0,
  currency: 'USD',
  expires_at: 1.year.from_now,
  source: 'purchase',
  metadata: { purchase_id: 'pur_123' }
)

puts "Credits: #{credit.remaining}/#{credit.amount}"
puts "Expires: #{credit.expires_at}"
```

### 15.2 Credit Packs
```bash
# Define credit packs
pack = Ai::CreditPack.create!(
  name: 'Starter Pack',
  slug: 'starter-pack',
  description: '1000 AI credits for getting started',
  credit_amount: 1000,
  price: 9.99,
  currency: 'USD',
  bonus_credits: 100,  # Extra 10%
  status: 'active',
  visibility: 'public'
)

# Purchase credit pack
purchase = Ai::CreditPurchase.create!(
  account: account,
  user: User.first,
  credit_pack: pack,
  amount_paid: pack.price,
  credits_granted: pack.credit_amount + pack.bonus_credits,
  payment_reference: 'pi_123',
  status: 'completed'
)
```

### 15.3 Credit Transactions
```bash
# Credit transaction (debit for usage)
Ai::CreditTransaction.create!(
  account: account,
  account_credit: credit,
  transaction_type: 'debit',
  amount: 5.0,
  description: 'Agent execution - GPT-4',
  reference_type: 'Ai::AgentExecution',
  reference_id: 'exec_123',
  balance_before: 1000.0,
  balance_after: 995.0
)

# Check balance
total_credits = account.ai_account_credits.where('expires_at > ?', Time.current).sum(:remaining)
puts "Available credits: #{total_credits}"
```

### 15.4 Credit Usage Rates
```bash
# Define usage rates per model
rate = Ai::CreditUsageRate.create!(
  provider: Ai::Provider.first,
  model_id: 'gpt-4',
  rate_type: 'per_token',
  input_rate: 0.00003,   # credits per input token
  output_rate: 0.00006,  # credits per output token
  is_active: true,
  effective_from: Time.current
)

# Calculate cost for an execution
input_tokens = 1000
output_tokens = 500
cost = (input_tokens * rate.input_rate) + (output_tokens * rate.output_rate)
puts "Execution cost: #{cost} credits"
```

### 15.5 Credit Transfers
```bash
# Transfer credits between accounts
transfer = Ai::CreditTransfer.create!(
  source_account: Account.first,
  target_account: Account.second,
  amount: 100.0,
  reason: 'Team allocation',
  initiated_by: User.first,
  status: 'completed'
)
```

### 15.6 Outcome-Based Billing
```bash
# Define outcome metrics
outcome = Ai::OutcomeDefinition.create!(
  account: account,
  name: 'Successful Resolution',
  outcome_type: 'success_rate',
  measurement: {
    metric: 'resolution_rate',
    threshold: 0.8,
    window: '7d'
  },
  billing_rate: 0.50  # $0.50 per successful outcome
)

# Record billing for outcomes
Ai::OutcomeBillingRecord.create!(
  account: account,
  outcome_definition: outcome,
  billable: agent,
  period_start: 1.week.ago,
  period_end: Time.current,
  outcome_count: 150,
  amount: 75.0,  # 150 * 0.50
  status: 'invoiced'
)
```

### 15.7 ROI Metrics
```bash
# Track ROI metrics
metric = Ai::RoiMetric.create!(
  account: account,
  measurable: workflow,
  metric_type: 'cost_savings',
  period: 'monthly',
  period_start: 1.month.ago.beginning_of_month,
  values: {
    ai_cost: 500.0,
    manual_cost_equivalent: 5000.0,
    savings: 4500.0,
    roi_percent: 900
  }
)

puts "ROI: #{metric.values['roi_percent']}%"
```

### 15.8 Test via API
```bash
# Get credit balance
curl "https://dev.powernode.org/api/v1/ai/credits/balance" \
  -H "Authorization: Bearer {TOKEN}"

# Get credit packs
curl "https://dev.powernode.org/api/v1/ai/credits/packs" \
  -H "Authorization: Bearer {TOKEN}"

# Purchase credits
curl -X POST "https://dev.powernode.org/api/v1/ai/credits/purchase" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"pack_id": "{PACK_ID}", "payment_method_id": "pm_xxx"}'

# Get usage history
curl "https://dev.powernode.org/api/v1/ai/credits/transactions?page=1" \
  -H "Authorization: Bearer {TOKEN}"
```

---

## Phase 16: RAG and Knowledge Bases

### 16.1 Create Knowledge Base
```bash
# In Rails console
account = Account.first

kb = Ai::KnowledgeBase.create!(
  account: account,
  name: 'Product Documentation',
  description: 'Product docs and FAQs',
  status: 'active',
  configuration: {
    embedding_model: 'text-embedding-ada-002',
    chunk_size: 500,
    chunk_overlap: 50,
    similarity_threshold: 0.7
  }
)

puts "Knowledge Base ID: #{kb.id}"
```

### 16.2 Add Documents
```bash
# Add document to knowledge base
doc = Ai::Document.create!(
  knowledge_base: kb,
  account: account,
  title: 'Getting Started Guide',
  content: <<~CONTENT,
    # Getting Started

    Welcome to our product! This guide will help you get started.

    ## Installation
    Run `npm install` to install dependencies.

    ## Configuration
    Create a `.env` file with your API keys.

    ## Usage
    Import the library and initialize with your config.
  CONTENT
  source_type: 'manual',  # manual, url, file, api
  status: 'active',
  metadata: {
    author: 'Documentation Team',
    version: '1.0',
    tags: ['getting-started', 'installation']
  }
)

puts "Document ID: #{doc.id}"
```

### 16.3 Process Document into Chunks
```bash
# Chunk the document for embeddings
service = Ai::RagService.new(knowledge_base: kb)
result = service.process_document(doc)

if result.success?
  puts "Chunks created: #{doc.document_chunks.count}"

  doc.document_chunks.each do |chunk|
    puts "Chunk #{chunk.position}: #{chunk.content[0..50]}..."
    puts "  Embedding: #{chunk.embedding.present? ? 'Yes' : 'No'}"
  end
else
  puts "Error: #{result.error}"
end
```

### 16.4 Query Knowledge Base (RAG)
```bash
# Perform RAG query
query = Ai::RagQuery.create!(
  knowledge_base: kb,
  account: account,
  user: User.first,
  query_text: 'How do I install the product?',
  status: 'pending'
)

# Execute RAG query
result = service.query(query)

if result.success?
  puts "Query: #{query.query_text}"
  puts "Answer: #{result.data[:answer]}"
  puts "\nSources:"
  result.data[:sources].each do |source|
    puts "  - #{source[:document_title]} (score: #{source[:similarity]})"
    puts "    #{source[:chunk_content][0..100]}..."
  end
else
  puts "Error: #{result.error}"
end
```

### 16.5 Use RAG with Agent
```bash
# Configure agent to use knowledge base
agent = Ai::Agent.first
manifest = agent.mcp_tool_manifest.dup
manifest['rag_config'] = {
  knowledge_base_ids: [kb.id],
  enabled: true,
  max_chunks: 5,
  include_sources: true
}
agent.update!(mcp_tool_manifest: manifest)

# Execute agent with RAG
service = Ai::Agents::ManagementService.new(agent: agent, user: User.first)
result = service.execute(input_parameters: {
  input: 'Based on our documentation, how do I configure the product?'
})

if result.success?
  execution = result.data[:execution]
  puts "Response: #{execution.output_data['response']}"
  puts "RAG Sources: #{execution.output_data.dig('metadata', 'rag_sources')}"
end
```

### 16.6 Document Sync from URL
```bash
# Add document from URL
url_doc = Ai::Document.create!(
  knowledge_base: kb,
  account: account,
  title: 'API Reference',
  source_type: 'url',
  source_url: 'https://docs.example.com/api',
  status: 'pending',
  sync_config: {
    frequency: 'daily',
    last_synced_at: nil
  }
)

# Sync document content
Ai::RagService.sync_url_document(url_doc)
puts "Synced: #{url_doc.reload.status}"
```

### 16.7 Data Classification
```bash
# Classify data sensitivity
classification = Ai::DataClassification.create!(
  account: account,
  classifiable: doc,
  classification_type: 'sensitivity',
  level: 'internal',  # public, internal, confidential, restricted
  labels: ['product-docs', 'no-pii'],
  detected_patterns: {
    pii: false,
    financial: false,
    health: false
  },
  classifier: 'automated'
)
```

### 16.8 Test via API
```bash
# Create knowledge base
curl -X POST "https://dev.powernode.org/api/v1/ai/knowledge_bases" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Support KB",
    "description": "Customer support knowledge"
  }'

# Add document
curl -X POST "https://dev.powernode.org/api/v1/ai/knowledge_bases/{KB_ID}/documents" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "FAQ",
    "content": "Q: How do I reset my password?\\nA: Click forgot password...",
    "source_type": "manual"
  }'

# RAG query
curl -X POST "https://dev.powernode.org/api/v1/ai/rag/query" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "knowledge_base_id": "{KB_ID}",
    "query": "How do I reset my password?"
  }'
```

---

## Verification Checklist

### Core Agent & Provider (Phases 1-3)
| Phase | Feature | Status |
|-------|---------|--------|
| 1.1 | Provider health check | ☐ |
| 1.2 | Simple agent execution (console) | ☐ |
| 1.2b | Agent execution via ManagementService | ☐ |
| 1.3 | Agent execution (API) | ☐ |
| 2.1 | Create conversation | ☐ |
| 2.2 | Multi-turn conversation | ☐ |
| 2.3 | Conversation API | ☐ |
| 3.1 | Agent validation | ☐ |
| 3.2 | Agent lifecycle (pause/resume) | ☐ |
| 3.3 | Agent statistics | ☐ |

### Workflows (Phases 4, 7, 11-12)
| Phase | Feature | Status |
|-------|---------|--------|
| 4.1 | Create simple workflow | ☐ |
| 4.2 | Execute workflow | ☐ |
| 4.3 | Workflow API | ☐ |
| 7.1 | Workflow with Ralph Loop node | ☐ |
| 11.1 | Conditional branching node | ☐ |
| 11.2 | Loop node with iteration | ☐ |
| 11.3 | Parallel split and merge | ☐ |
| 11.4 | Human approval node | ☐ |
| 11.5 | Sub-workflow node | ☐ |
| 11.6 | API call node | ☐ |
| 11.7 | Transform node | ☐ |
| 12.1 | Webhook trigger | ☐ |
| 12.2 | Schedule trigger (cron) | ☐ |
| 12.3 | Event-based trigger | ☐ |
| 12.4 | Git trigger (CI/CD) | ☐ |
| 12.5 | API trigger | ☐ |

### Ralph Loops (Phase 5)
| Phase | Feature | Status |
|-------|---------|--------|
| 5.1 | Create Ralph Loop | ☐ |
| 5.2 | Add tasks with dependencies | ☐ |
| 5.3 | Execute Ralph Loop iterations | ☐ |
| 5.4 | Monitor progress & learnings | ☐ |
| 5.5 | Ralph Loop API | ☐ |

### Agent Teams (Phase 6)
| Phase | Feature | Status |
|-------|---------|--------|
| 6.1 | Create Agent Team | ☐ |
| 6.2 | Execute Agent Team | ☐ |

### Memory & Context (Phase 8)
| Phase | Feature | Status |
|-------|---------|--------|
| 8.1 | Create persistent context | ☐ |
| 8.2 | Add factual memory entries | ☐ |
| 8.3 | Add experiential memory | ☐ |
| 8.4 | Working memory (session) | ☐ |
| 8.5 | Memory service context injection | ☐ |
| 8.6 | Context access logging | ☐ |
| 8.7 | Context API | ☐ |

### Templates & A2A (Phases 9-10)
| Phase | Feature | Status |
|-------|---------|--------|
| 9.1 | Create agent template | ☐ |
| 9.2 | Create agent from template | ☐ |
| 9.3 | Version management | ☐ |
| 9.4 | Template discovery | ☐ |
| 10.1 | Publish A2A agent card | ☐ |
| 10.2 | Create A2A task | ☐ |
| 10.3 | Execute A2A task | ☐ |
| 10.4 | A2A DAG execution | ☐ |
| 10.5 | External agent discovery | ☐ |
| 10.6 | A2A API | ☐ |

### Governance (Phase 13)
| Phase | Feature | Status |
|-------|---------|--------|
| 13.1 | Create compliance policy | ☐ |
| 13.2 | Check policy compliance | ☐ |
| 13.3 | Audit entry logging | ☐ |
| 13.4 | SLA contract and monitoring | ☐ |
| 13.5 | Approval workflows | ☐ |
| 13.6 | Policy violation tracking | ☐ |

### Marketplace (Phase 14)
| Phase | Feature | Status |
|-------|---------|--------|
| 14.1 | Browse marketplace | ☐ |
| 14.2 | List in marketplace (publisher) | ☐ |
| 14.3 | Purchase from marketplace | ☐ |
| 14.4 | Reviews and ratings | ☐ |
| 14.5 | Content moderation | ☐ |
| 14.6 | Marketplace API | ☐ |

### Credits & Billing (Phase 15)
| Phase | Feature | Status |
|-------|---------|--------|
| 15.1 | Account credits setup | ☐ |
| 15.2 | Credit packs | ☐ |
| 15.3 | Credit transactions | ☐ |
| 15.4 | Credit usage rates | ☐ |
| 15.5 | Credit transfers | ☐ |
| 15.6 | Outcome-based billing | ☐ |
| 15.7 | ROI metrics | ☐ |
| 15.8 | Credits API | ☐ |

### RAG & Knowledge Bases (Phase 16)
| Phase | Feature | Status |
|-------|---------|--------|
| 16.1 | Create knowledge base | ☐ |
| 16.2 | Add documents | ☐ |
| 16.3 | Process document into chunks | ☐ |
| 16.4 | Query knowledge base (RAG) | ☐ |
| 16.5 | Use RAG with agent | ☐ |
| 16.6 | Document sync from URL | ☐ |
| 16.7 | Data classification | ☐ |
| 16.8 | RAG API | ☐ |

### Monitoring & Debugging (Phase 17)
| Phase | Feature | Status |
|-------|---------|--------|
| 17.1 | Real-time execution monitoring | ☐ |
| 17.2 | Execution tracing | ☐ |
| 17.3 | Debug execution | ☐ |
| 17.4 | AIOps metrics | ☐ |
| 17.5 | Monitoring API | ☐ |

### Sandboxes & Testing (Phase 18)
| Phase | Feature | Status |
|-------|---------|--------|
| 18.1 | Create sandbox environment | ☐ |
| 18.2 | Deploy agent to sandbox | ☐ |
| 18.3 | Execute in sandbox | ☐ |
| 18.4 | Test workflows in sandbox | ☐ |
| 18.5 | Record and replay interactions | ☐ |
| 18.6 | A/B testing | ☐ |
| 18.7 | Cleanup sandbox | ☐ |
| 18.8 | Sandbox API | ☐ |

### Model Routing (Phase 19)
| Phase | Feature | Status |
|-------|---------|--------|
| 19.1 | Create routing rules | ☐ |
| 19.2 | Route request to model | ☐ |
| 19.3 | Track routing decisions | ☐ |
| 19.4 | Cost optimization | ☐ |
| 19.5 | Model routing API | ☐ |

### Workflow Validation (Phase 20)
| Phase | Feature | Status |
|-------|---------|--------|
| 20.1 | Validate workflow structure | ☐ |
| 20.2 | Auto-fix workflow issues | ☐ |
| 20.3 | Workflow circuit breaker | ☐ |
| 20.4 | Workflow recovery from checkpoint | ☐ |
| 20.5 | Compensation (rollback) | ☐ |
| 20.6 | Validation statistics | ☐ |
| 20.7 | Validation API | ☐ |

---

## Phase 17: Monitoring and Debugging

### 17.1 Real-Time Execution Monitoring
```bash
# In Rails console
account = Account.first

# Get monitoring health status
service = Ai::MonitoringHealthService.new(account: account)
health = service.check_all

puts "Provider Health:"
health[:providers].each do |p|
  puts "  #{p[:name]}: #{p[:status]} (latency: #{p[:latency_ms]}ms)"
end

puts "\nActive Executions: #{health[:active_executions]}"
puts "Queue Depth: #{health[:queue_depth]}"
puts "Error Rate (1h): #{health[:error_rate_1h]}%"
```

### 17.2 Execution Tracing
```bash
# Create execution trace for debugging
execution = Ai::AgentExecution.last
trace = Ai::ExecutionTrace.create!(
  traceable: execution,
  account: account,
  trace_id: SecureRandom.uuid,
  trace_type: 'agent_execution',
  status: 'active',
  started_at: Time.current
)

# Add trace spans (timing breakdown)
span1 = trace.execution_trace_spans.create!(
  span_id: SecureRandom.uuid,
  name: 'prompt_construction',
  span_type: 'internal',
  started_at: Time.current,
  ended_at: 5.milliseconds.from_now,
  duration_ms: 5,
  metadata: { prompt_tokens: 500 }
)

span2 = trace.execution_trace_spans.create!(
  span_id: SecureRandom.uuid,
  name: 'llm_inference',
  span_type: 'external',
  parent_span_id: span1.span_id,
  started_at: span1.ended_at,
  ended_at: 2.seconds.from_now,
  duration_ms: 2000,
  metadata: { model: 'gpt-4', tokens_out: 200 }
)

# Complete trace
trace.update!(status: 'completed', ended_at: Time.current)

# View trace timeline
trace.execution_trace_spans.order(:started_at).each do |s|
  puts "#{s.name}: #{s.duration_ms}ms (#{s.span_type})"
end
```

### 17.3 Debug Execution
```bash
# Use debugging service
debug_service = Ai::DebuggingService.new(execution: execution)

# Get execution breakdown
breakdown = debug_service.analyze
puts "Total duration: #{breakdown[:total_duration_ms]}ms"
puts "Time in LLM: #{breakdown[:llm_time_ms]}ms"
puts "Time in preprocessing: #{breakdown[:preprocessing_ms]}ms"
puts "Token efficiency: #{breakdown[:tokens_per_second]}"

# Get step-by-step log
debug_service.step_log.each do |step|
  puts "[#{step[:timestamp]}] #{step[:action]}: #{step[:details]}"
end
```

### 17.4 AIOps Metrics
```bash
# Get AIOps dashboard metrics
metrics_service = Ai::AiOpsMetricsService.new(account: account)
metrics = metrics_service.dashboard_metrics(period: '24h')

puts "Executions: #{metrics[:total_executions]}"
puts "Success Rate: #{metrics[:success_rate]}%"
puts "Avg Latency: #{metrics[:avg_latency_ms]}ms"
puts "Total Cost: $#{metrics[:total_cost]}"
puts "Active Agents: #{metrics[:active_agents]}"
puts "Active Workflows: #{metrics[:active_workflows]}"

# Get alerts
alerts = metrics_service.active_alerts
alerts.each do |alert|
  puts "⚠️  #{alert[:severity]}: #{alert[:message]}"
end
```

### 17.5 Test via API
```bash
# Get monitoring dashboard
curl "https://dev.powernode.org/api/v1/ai/monitoring/dashboard" \
  -H "Authorization: Bearer {TOKEN}"

# Get execution trace
curl "https://dev.powernode.org/api/v1/ai/execution_traces/{TRACE_ID}" \
  -H "Authorization: Bearer {TOKEN}"

# Get AIOps metrics
curl "https://dev.powernode.org/api/v1/ai/aiops/metrics?period=24h" \
  -H "Authorization: Bearer {TOKEN}"
```

---

## Phase 18: Sandboxes and Testing Environments

### 18.1 Create Sandbox Environment
```bash
# In Rails console
account = Account.first
user = User.first

# Create isolated sandbox
sandbox = Ai::Sandbox.create!(
  account: account,
  creator: user,
  name: 'Development Sandbox',
  description: 'Isolated environment for testing new agents',
  status: 'active',
  sandbox_type: 'development',  # development, staging, testing
  configuration: {
    resource_limits: {
      max_executions_per_hour: 100,
      max_tokens_per_execution: 10000,
      max_concurrent_executions: 5
    },
    allowed_providers: ['ollama'],
    data_isolation: true,
    audit_all_operations: true
  },
  expires_at: 30.days.from_now
)

puts "Sandbox ID: #{sandbox.id}"
puts "Expires: #{sandbox.expires_at}"
```

### 18.2 Deploy Agent to Sandbox
```bash
# Clone agent to sandbox
original_agent = Ai::Agent.first
service = Ai::SandboxService.new(sandbox: sandbox)

result = service.deploy_agent(original_agent)

if result.success?
  sandbox_agent = result.data[:agent]
  puts "Sandbox agent: #{sandbox_agent.id}"
  puts "Linked to original: #{sandbox_agent.source_agent_id}"
else
  puts "Error: #{result.error}"
end
```

### 18.3 Execute in Sandbox
```bash
# All executions in sandbox are isolated
sandbox_execution = service.execute_agent(
  agent: sandbox_agent,
  input_parameters: { input: 'Test in sandbox' }
)

puts "Execution ID: #{sandbox_execution.id}"
puts "Sandbox constrained: #{sandbox_execution.sandbox_id.present?}"

# Check sandbox usage
usage = service.get_usage
puts "Executions this hour: #{usage[:executions_this_hour]}"
puts "Remaining: #{usage[:remaining_executions]}"
```

### 18.4 Test Workflows in Sandbox
```bash
# Deploy workflow to sandbox
workflow = Ai::Workflow.first
sandbox_workflow = service.deploy_workflow(workflow)

# Run with test data
test_run = service.execute_workflow(
  workflow: sandbox_workflow,
  input_variables: { test_mode: true, input: 'Test data' }
)

puts "Test run status: #{test_run.status}"
```

### 18.5 Record and Replay Interactions
```bash
# Record an interaction for replay
interaction = Ai::RecordedInteraction.create!(
  sandbox: sandbox,
  account: account,
  interaction_type: 'agent_execution',
  recordable: sandbox_agent,
  input_data: { input: 'Recorded test input' },
  output_data: { response: 'Recorded response' },
  metadata: {
    model: 'llama3:8b',
    tokens_used: 500,
    duration_ms: 1500
  }
)

# Replay interaction (useful for regression testing)
replayed = service.replay_interaction(interaction)
puts "Original output: #{interaction.output_data}"
puts "Replayed output: #{replayed.output_data}"
puts "Output matches: #{interaction.output_data == replayed.output_data}"
```

### 18.6 A/B Testing
```bash
# Create A/B test for agent variants
ab_test = Ai::AbTest.create!(
  account: account,
  name: 'Prompt Optimization Test',
  status: 'active',
  testable: sandbox_agent,
  variants: [
    { name: 'control', weight: 50, config: { prompt: 'Original prompt...' } },
    { name: 'variant_a', weight: 50, config: { prompt: 'Optimized prompt...' } }
  ],
  success_metric: 'user_satisfaction',
  sample_size: 1000,
  started_at: Time.current
)

# Execute with A/B routing
result = service.execute_with_ab_test(
  ab_test: ab_test,
  input_parameters: { input: 'Test query' }
)

puts "Variant used: #{result[:variant]}"
puts "Output: #{result[:output]}"
```

### 18.7 Cleanup Sandbox
```bash
# Deactivate and cleanup sandbox
sandbox.update!(status: 'archived')

# Or delete all sandbox data
service.cleanup!
puts "Sandbox cleaned up"
```

### 18.8 Test via API
```bash
# Create sandbox
curl -X POST "https://dev.powernode.org/api/v1/ai/sandboxes" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Sandbox",
    "sandbox_type": "testing",
    "expires_at": "2024-12-31"
  }'

# Deploy agent to sandbox
curl -X POST "https://dev.powernode.org/api/v1/ai/sandboxes/{SANDBOX_ID}/deploy_agent" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "{AGENT_ID}"}'

# Execute in sandbox
curl -X POST "https://dev.powernode.org/api/v1/ai/sandboxes/{SANDBOX_ID}/execute" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "{SANDBOX_AGENT_ID}",
    "input_parameters": {"input": "Test"}
  }'
```

---

## Phase 19: Model Routing and Optimization

### 19.1 Create Routing Rules
```bash
# In Rails console
account = Account.first

# Create model routing rule
rule = Ai::ModelRoutingRule.create!(
  account: account,
  name: 'Cost Optimization Routing',
  status: 'active',
  priority: 10,  # Higher priority = evaluated first
  conditions: {
    rules: [
      { field: 'estimated_tokens', operator: 'less_than', value: 1000 },
      { field: 'complexity', operator: 'equals', value: 'simple' }
    ],
    match_type: 'all'  # all, any
  },
  routing_config: {
    target_provider: 'ollama',
    target_model: 'llama3:8b',
    fallback_model: 'gpt-3.5-turbo'
  }
)

puts "Rule ID: #{rule.id}"
```

### 19.2 Route Request to Model
```bash
# Use model router service
router = Ai::ModelRouterService.new(account: account)

# Route a request
request_context = {
  estimated_tokens: 500,
  complexity: 'simple',
  required_capabilities: ['chat'],
  max_latency_ms: 5000,
  max_cost: 0.01
}

routing = router.route(request_context)
puts "Selected provider: #{routing[:provider]}"
puts "Selected model: #{routing[:model]}"
puts "Reason: #{routing[:reason]}"
```

### 19.3 Track Routing Decisions
```bash
# Routing decisions are logged automatically
Ai::RoutingDecision.where(account: account).order(created_at: :desc).limit(10).each do |d|
  puts "#{d.created_at}: #{d.selected_model} (#{d.reason})"
  puts "  Input: #{d.request_context['estimated_tokens']} tokens"
  puts "  Cost: $#{d.estimated_cost}"
end
```

### 19.4 Cost Optimization
```bash
# Get cost optimization recommendations
optimizer = Ai::CostOptimizationService.new(account: account)
recommendations = optimizer.analyze(period: '30d')

recommendations.each do |rec|
  puts "#{rec[:type]}: #{rec[:description]}"
  puts "  Potential savings: $#{rec[:estimated_savings]}"
  puts "  Action: #{rec[:action]}"
end

# Apply optimization automatically
optimizer.apply_recommendations(recommendations.select { |r| r[:auto_apply] })
```

### 19.5 Test via API
```bash
# Get routing rules
curl "https://dev.powernode.org/api/v1/ai/model_router/rules" \
  -H "Authorization: Bearer {TOKEN}"

# Test routing decision
curl -X POST "https://dev.powernode.org/api/v1/ai/model_router/route" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "estimated_tokens": 500,
    "complexity": "simple",
    "required_capabilities": ["chat"]
  }'
```

---

## Phase 20: Workflow Validation and Auto-Fix

### 20.1 Validate Workflow Structure
```bash
# In Rails console
workflow = Ai::Workflow.first

# Full validation
validator = Ai::WorkflowValidationService.new(workflow: workflow)
result = validator.validate

puts "Valid: #{result.valid?}"

if !result.valid?
  result.errors.each do |error|
    puts "❌ #{error[:severity]}: #{error[:code]}"
    puts "   #{error[:message]}"
    puts "   Node: #{error[:node_id]}" if error[:node_id]
  end
end

result.warnings.each do |warning|
  puts "⚠️  #{warning[:code]}: #{warning[:message]}"
end
```

### 20.2 Auto-Fix Workflow Issues
```bash
# Attempt automatic fixes
autofix = Ai::WorkflowAutoFixService.new(workflow: workflow)
fix_result = autofix.fix

if fix_result.success?
  puts "Fixed #{fix_result.data[:fixes_applied].count} issues:"
  fix_result.data[:fixes_applied].each do |fix|
    puts "  ✓ #{fix[:type]}: #{fix[:description]}"
  end
else
  puts "Could not auto-fix: #{fix_result.error}"
end
```

### 20.3 Workflow Circuit Breaker
```bash
# Get circuit breaker status
workflow_run = Ai::WorkflowRun.last
circuit = Ai::WorkflowRetryStrategyService.circuit_breaker_status(workflow_run)

puts "Circuit status: #{circuit[:state]}"  # closed, open, half_open
puts "Failure count: #{circuit[:failure_count]}"
puts "Last failure: #{circuit[:last_failure_at]}"

# Manual circuit breaker control
Ai::WorkflowRetryStrategyService.trip_circuit(workflow)  # Open
Ai::WorkflowRetryStrategyService.reset_circuit(workflow) # Close
```

### 20.4 Workflow Recovery from Checkpoint
```bash
# Create checkpoint during execution
checkpoint = Ai::WorkflowCheckpoint.create!(
  workflow_run: workflow_run,
  node_id: 'current_node',
  state: workflow_run.runtime_context,
  checkpoint_type: 'automatic',
  created_at: Time.current
)

# Recover from checkpoint after failure
recovery_service = Ai::WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)
recovered_run = recovery_service.recover_from_checkpoint(checkpoint)

puts "Recovered run ID: #{recovered_run.id}"
puts "Resuming from: #{checkpoint.node_id}"
```

### 20.5 Compensation (Rollback)
```bash
# Define compensation actions for nodes
workflow.nodes.find_by(node_id: 'api_call_1').update!(
  compensation_config: {
    enabled: true,
    action: 'api_call',
    config: {
      url: 'https://api.example.com/rollback',
      method: 'POST',
      body: { transaction_id: '{{node.output.transaction_id}}' }
    }
  }
)

# Execute compensation on failure
compensation_service = Ai::WorkflowCompensationService.new(workflow_run: failed_run)
compensation_service.execute_compensations

# Check compensation status
failed_run.workflow_compensations.each do |comp|
  puts "#{comp.node_id}: #{comp.status}"
end
```

### 20.6 Validation Statistics
```bash
# Get validation statistics
stats = Ai::WorkflowValidationService.statistics(account: account)

puts "Total validations: #{stats[:total_validations]}"
puts "Pass rate: #{stats[:pass_rate]}%"
puts "Common issues:"
stats[:common_issues].each do |issue|
  puts "  #{issue[:code]}: #{issue[:count]} occurrences"
end
```

### 20.7 Test via API
```bash
# Validate workflow
curl -X POST "https://dev.powernode.org/api/v1/ai/workflows/{WORKFLOW_ID}/validate" \
  -H "Authorization: Bearer {TOKEN}"

# Auto-fix workflow
curl -X POST "https://dev.powernode.org/api/v1/ai/workflows/{WORKFLOW_ID}/auto_fix" \
  -H "Authorization: Bearer {TOKEN}"

# Get circuit breaker status
curl "https://dev.powernode.org/api/v1/ai/workflows/{WORKFLOW_ID}/circuit_breaker" \
  -H "Authorization: Bearer {TOKEN}"
```

---

## Troubleshooting

### Common Issues

1. **Provider connection fails**
   - Check remote Ollama server is accessible: `curl {provider.api_endpoint}/api/tags`
   - Verify credentials are active: `provider.provider_credentials.active.any?`
   - Check provider `api_endpoint` is correctly configured

2. **Agent execution hangs**
   - Check Sidekiq is running: `scripts/auto-dev.sh status`
   - Check model availability on remote server: `curl {provider.api_endpoint}/api/tags`
   - Review logs: `tail -f server/log/development.log`

3. **Workflow fails to execute**
   - Verify all nodes are properly connected
   - Check workflow status is 'active'
   - Verify agent referenced in nodes exists and is active

4. **Ralph Loop stuck**
   - Check task dependencies are satisfiable
   - Verify max_iterations hasn't been reached
   - Check iteration error messages in `ai_ralph_iterations` table

5. **"Agent cannot be executed" error**
   - Agent must have status 'active': `agent.update!(status: 'active')`
   - Agent must have valid MCP tool manifest
   - Provider must have active credentials

6. **Workflow structure validation fails**
   - Ensure at least one node has `is_start_node: true`
   - Ensure at least one node has `is_end_node: true`
   - Check for circular dependencies in edges

7. **Memory/context not retrieving entries**
   - Check context is `status: 'active'`
   - Verify entries haven't expired (`expires_at`)
   - Check `entry_type` filter matches what you're querying

8. **A2A task fails**
   - Verify target agent is accessible and active
   - Check agent card is published with correct URL
   - Verify authentication tokens are valid

9. **RAG query returns no results**
   - Verify documents have been chunked: `kb.documents.first.document_chunks.count`
   - Check embeddings exist: `chunk.embedding.present?`
   - Lower `similarity_threshold` in configuration
   - Verify knowledge base is active

10. **Credit transaction fails**
    - Check sufficient credit balance
    - Verify credits haven't expired
    - Check usage rate is defined for the model

11. **Marketplace purchase fails**
    - Verify payment method is valid
    - Check item is still listed and available
    - Verify account permissions for marketplace purchases

12. **Approval workflow stuck**
    - Check approval request hasn't expired
    - Verify approvers have received notification
    - Check all required levels in approval chain

---

## Quick Reference

### Model Associations
```ruby
# Account has many:
account.ai_providers
account.ai_agents
account.ai_workflows
account.ai_ralph_loops
account.ai_agent_teams
account.ai_knowledge_bases
account.ai_account_credits
account.ai_compliance_policies

# Agent belongs to:
agent.account
agent.creator  # User
agent.provider # Ai::Provider

# Agent has many:
agent.executions     # Ai::AgentExecution
agent.conversations  # Ai::Conversation
agent.messages       # Ai::Message
agent.contexts       # Ai::PersistentContext
agent.agent_card     # Ai::AgentCard

# Workflow has many:
workflow.nodes       # Ai::WorkflowNode
workflow.edges       # Ai::WorkflowEdge
workflow.runs        # Ai::WorkflowRun
workflow.triggers    # Ai::WorkflowTrigger
workflow.schedules   # Ai::WorkflowSchedule
workflow.variables   # Ai::WorkflowVariable

# Knowledge Base has many:
kb.documents           # Ai::Document
kb.document_chunks     # via documents
kb.rag_queries         # Ai::RagQuery
```

### Status Values
```ruby
# Agent status
%w[active inactive paused error archived]

# Execution status
%w[pending running completed failed cancelled]

# Workflow status
%w[draft active paused inactive archived]

# Ralph Loop status
%w[pending running paused completed failed cancelled]

# Ralph Task status
%w[pending in_progress passed failed blocked skipped]

# Memory entry types
%w[factual experiential working]

# Context entry status
%w[active archived expired]

# Team types
%w[hierarchical mesh sequential parallel]

# Coordination strategies
%w[manager_led consensus auction round_robin priority_based]

# Trigger types
%w[manual webhook schedule event api_call git]

# Credit transaction types
%w[credit debit transfer refund]

# Compliance policy types
%w[data_handling access_control rate_limiting content_filtering]

# Approval statuses
%w[pending approved rejected expired]
```

### Service Result Pattern
```ruby
# All services return Result struct
result = service.some_method
result.success?  # true/false
result.data      # Hash with data on success
result.error     # String error message on failure
```

### Key Services
```ruby
# Agent Management
Ai::Agents::ManagementService.new(agent:, user:)
  .execute(input_parameters:)
  .validate
  .pause / .resume
  .stats

# Workflow Execution
Mcp::AiWorkflowOrchestrator.new(workflow_run:)
  .execute

# Memory Management
Ai::MemoryManagementService.new(agent:)
  .get_relevant_context(query:, max_entries:)
  .inject_context(base_prompt:, context_entries:)

# RAG Service
Ai::RagService.new(knowledge_base:)
  .process_document(doc)
  .query(rag_query)

# A2A Service
Ai::A2a::Service.new(task:)
  .execute

# Credit Management
Ai::CreditManagementService.new(account:)
  .debit(amount:, description:, reference:)
  .credit(amount:, source:)
  .balance

# Governance
Ai::GovernanceService.new(account:)
  .check_compliance(entity:)
  .create_audit_entry(auditable:, action:, details:)
```

### Node Types (39 total)
```ruby
# Control Flow
%w[start end trigger condition loop delay merge split]

# AI Operations
%w[ai_agent prompt_template data_processor transform]

# External
%w[api_call webhook database file email notification]

# CI/CD
%w[ci_trigger ci_wait_status git_commit_status deploy run_tests]

# Advanced
%w[ralph_loop sub_workflow human_approval mcp_operation]
```

---

## Coverage Statistics

This testing plan covers **20 phases** with **120+ test scenarios**:

| Category | Models | Services | Controllers | Tests |
|----------|--------|----------|-------------|-------|
| Agent System | 8 | 5 | 3 | 15 |
| Workflows | 15 | 10 | 5 | 30 |
| Teams | 6 | 3 | 2 | 4 |
| Ralph Loops | 3 | 2 | 1 | 5 |
| Memory/Context | 4 | 5 | 3 | 7 |
| A2A Protocol | 2 | 3 | 2 | 6 |
| Marketplace | 7 | 4 | 3 | 6 |
| Credits | 8 | 2 | 1 | 8 |
| Governance | 8 | 2 | 1 | 6 |
| RAG | 4 | 1 | 1 | 8 |
| Monitoring | 3 | 4 | 3 | 5 |
| Sandboxes | 4 | 2 | 1 | 8 |
| Model Routing | 2 | 2 | 1 | 5 |
| Validation | 4 | 4 | 2 | 7 |
| **Total** | **78+** | **49+** | **29+** | **120** |

### Phase Summary

| Phase | Topic | Test Count |
|-------|-------|------------|
| 0 | Setup Verification | 3 |
| 1 | Basic Agent Functionality | 4 |
| 2 | Agent Conversations | 3 |
| 3 | Agent Validation & Lifecycle | 3 |
| 4 | Workflows | 3 |
| 5 | Ralph Loops | 5 |
| 6 | Agent Teams | 2 |
| 7 | Workflow with Ralph Loop | 1 |
| 8 | Memory and Context | 7 |
| 9 | Agent Templates | 4 |
| 10 | A2A Protocol | 6 |
| 11 | Advanced Workflow Nodes | 7 |
| 12 | Workflow Triggers | 5 |
| 13 | Governance | 6 |
| 14 | Marketplace | 6 |
| 15 | Credits and Billing | 8 |
| 16 | RAG and Knowledge Bases | 8 |
| 17 | Monitoring and Debugging | 5 |
| 18 | Sandboxes and Testing | 8 |
| 19 | Model Routing | 5 |
| 20 | Workflow Validation | 7 |
