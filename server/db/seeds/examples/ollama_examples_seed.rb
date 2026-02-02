# frozen_string_literal: true

# Ollama Examples Seed Data
#
# Creates the necessary data for running Ollama examples:
# - Test account (if needed)
# - Ollama AI provider
# - Provider credentials
# - Sample AI agent
# - Sample Ralph Loop
# - Sample Workflow
#
# Run with: bundle exec rails runner db/seeds/examples/ollama_examples_seed.rb

puts "\n" + "=" * 60
puts "Seeding Ollama Examples Data"
puts "=" * 60

# =============================================================================
# 1. Find or Create Test Account
# =============================================================================

puts "\n1. Setting up test account..."

account = Account.find_by(name: "Ollama Test") || Account.find_by(name: "Powernode Admin") || Account.first

if account
  puts "   Using account: #{account.name}"
else
  puts "   ERROR: No account found. Please seed the main database first."
  exit 1
end

# =============================================================================
# 2. Find Ollama AI Provider
# =============================================================================

puts "\n2. Looking for Ollama AI provider..."

# Look for existing Ollama provider (do not create a local one)
ollama_provider = account.ai_providers.find_by(slug: "ollama")
ollama_provider ||= account.ai_providers.find_by(provider_type: "ollama")

if ollama_provider
  puts "   Using existing provider: #{ollama_provider.name}"
else
  puts "   ERROR: No Ollama provider found. Please configure one in the admin panel."
  puts "   The provider should have slug 'ollama' or provider_type 'ollama'."
  exit 1
end

# =============================================================================
# 3. Create Provider Credentials
# =============================================================================

puts "\n3. Setting up provider credentials..."

credential = ollama_provider.provider_credentials.active.first

if credential
  puts "   Using existing credential: #{credential.name}"
else
  credential = ollama_provider.provider_credentials.new(
    account: account,
    name: "Ollama Local",
    is_active: true,
    is_default: true
  )
  credential.credentials = {
    "base_url" => ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434")
  }
  credential.save!
  puts "   Created credential: #{credential.name}"
end

# =============================================================================
# 4. Create Sample AI Agent
# =============================================================================

puts "\n4. Setting up sample AI agent..."

# Find a user to be the creator
creator = account.users.first
unless creator
  puts "   WARNING: No user found in account, skipping agent creation"
else
  agent = Ai::Agent.find_by(account: account, name: "Ollama Example Agent")

  if agent
    puts "   Using existing agent: #{agent.name}"
  else
    agent = Ai::Agent.create!(
      account: account,
      creator: creator,
      name: "Ollama Example Agent",
      description: "A simple conversational agent using Ollama for examples and testing",
      agent_type: "assistant",
      provider: ollama_provider,
      status: "active",
      version: "1.0.0",
      mcp_capabilities: %w[text_generation chat],
      mcp_metadata: {
        "auto_created" => true,
        "source" => "ollama_examples_seed",
        "purpose" => "examples_and_testing",
        "ollama_config" => {
          "model" => ENV.fetch("OLLAMA_MODEL", "llama3.2"),
          "max_tokens" => 2048,
          "temperature" => 0.7,
          "system_prompt" => "You are a helpful AI assistant. Be concise, clear, and helpful."
        }
      }
    )
    puts "   Created agent: #{agent.name}"
  end
end

# =============================================================================
# 5. Create Sample Ralph Loop
# =============================================================================

puts "\n5. Setting up sample Ralph Loop..."

ralph_loop = Ai::RalphLoop.find_by(account: account, name: "Ollama Example Loop")

if ralph_loop
  puts "   Using existing Ralph Loop: #{ralph_loop.name}"
else
  ralph_loop = Ai::RalphLoop.create!(
    account: account,
    name: "Ollama Example Loop",
    description: "A sample Ralph Loop demonstrating Ollama integration for iterative AI development",
    ai_tool: "ollama",
    status: "pending",
    max_iterations: 10,
    current_iteration: 0,
    scheduling_mode: "manual",
    configuration: {
      "model" => ENV.fetch("OLLAMA_MODEL", "llama3.2"),
      "max_tokens" => 2048,
      "temperature" => 0.7
    },
    prd_json: {
      "title" => "Sample Development Tasks",
      "description" => "A set of simple tasks to demonstrate Ralph Loop functionality",
      "tasks" => [
        {
          "key" => "setup",
          "description" => "Review project structure and identify main components",
          "priority" => 3,
          "acceptance_criteria" => "List of main components identified"
        },
        {
          "key" => "analysis",
          "description" => "Analyze code patterns and suggest improvements",
          "priority" => 2,
          "acceptance_criteria" => "At least 3 improvement suggestions",
          "dependencies" => [ "setup" ]
        },
        {
          "key" => "documentation",
          "description" => "Write brief documentation for the main module",
          "priority" => 1,
          "acceptance_criteria" => "Documentation covers purpose, usage, and examples",
          "dependencies" => [ "analysis" ]
        }
      ]
    }
  )

  # Create tasks from PRD
  ralph_loop.prd_json["tasks"].each_with_index do |task_data, index|
    ralph_loop.ralph_tasks.create!(
      task_key: task_data["key"],
      description: task_data["description"],
      priority: task_data["priority"] || 0,
      position: index + 1,
      dependencies: task_data["dependencies"] || [],
      acceptance_criteria: task_data["acceptance_criteria"],
      status: "pending"
    )
  end

  ralph_loop.update!(total_tasks: ralph_loop.ralph_tasks.count)
  puts "   Created Ralph Loop: #{ralph_loop.name} with #{ralph_loop.total_tasks} tasks"
end

# =============================================================================
# 6. Create Sample Workflow
# =============================================================================

puts "\n6. Setting up sample workflow..."

unless creator
  puts "   WARNING: No user found, skipping workflow creation"
else
  workflow = Ai::Workflow.find_by(account: account, name: "Ollama Example Workflow")

  if workflow
    puts "   Using existing workflow: #{workflow.name}"
  else
    workflow = Ai::Workflow.create!(
      account: account,
      creator: creator,
      name: "Ollama Example Workflow",
      description: "A simple workflow demonstrating Ollama-based AI processing",
      status: "active",
      version: "1.0.0",
      configuration: {
        "execution_mode" => "sequential",
        "max_execution_time" => 300
      },
      metadata: {
        "auto_created" => true,
        "source" => "ollama_examples_seed"
      }
    )

    # Create nodes
    start_node = workflow.workflow_nodes.create!(
      node_id: "start_1",
      node_type: "start",
      name: "Start",
      position: { "x" => 100, "y" => 200 },
      configuration: {}
    )

    # Only create agent node if agent exists
    if agent
      ai_node = workflow.workflow_nodes.create!(
        node_id: "ai_summarize",
        node_type: "ai_agent",
        name: "Summarize Text",
        position: { "x" => 300, "y" => 200 },
        configuration: {
          "agent_id" => agent.id,
          "prompt_template" => "Please summarize the following text in 2-3 sentences:\n\n{{input.text}}",
          "input_mapping" => { "text" => "$.input.text" },
          "output_key" => "summary"
        }
      )
    end

    transform_node = workflow.workflow_nodes.create!(
      node_id: "transform_1",
      node_type: "data_transform",
      name: "Format Output",
      position: { "x" => 500, "y" => 200 },
      configuration: {
        "transform_type" => "jmespath",
        "expression" => "{ summary: ai_summarize.summary, original_length: length(input.text), timestamp: `now` }",
        "output_key" => "result"
      }
    )

    end_node = workflow.workflow_nodes.create!(
      node_id: "end_1",
      node_type: "end",
      name: "End",
      position: { "x" => 700, "y" => 200 },
      configuration: {}
    )

    # Create edges
    if agent
      workflow.workflow_edges.create!(
        edge_id: "edge_1",
        source_node_id: "start_1",
        target_node_id: "ai_summarize"
      )

      workflow.workflow_edges.create!(
        edge_id: "edge_2",
        source_node_id: "ai_summarize",
        target_node_id: "transform_1"
      )
    else
      # Skip AI node if no agent
      workflow.workflow_edges.create!(
        edge_id: "edge_1",
        source_node_id: "start_1",
        target_node_id: "transform_1"
      )
    end

    workflow.workflow_edges.create!(
      edge_id: "edge_3",
      source_node_id: "transform_1",
      target_node_id: "end_1"
    )

    puts "   Created workflow: #{workflow.name} with #{workflow.workflow_nodes.count} nodes"
  end
end

# =============================================================================
# Summary
# =============================================================================

puts "\n" + "=" * 60
puts "Ollama Examples Seed Complete"
puts "=" * 60
puts "\nCreated/verified:"
puts "  - Account: #{account.name}"
puts "  - AI Provider: #{ollama_provider.name}"
puts "  - Credential: #{credential&.name || 'N/A'}"
puts "  - AI Agent: #{agent&.name || 'N/A (no user in account)'}"
puts "  - Ralph Loop: #{ralph_loop&.name || 'N/A'}"
puts "  - Workflow: #{workflow&.name || 'N/A (no user in account)'}"
puts "\nTo run the examples:"
puts "  cd server"
puts "  bundle exec rails runner ../examples/ollama/01-basic-chat.rb"
puts "  bundle exec rails runner ../examples/ollama/02-simple-ralph-loop.rb"
puts "  bundle exec rails runner ../examples/ollama/03-simple-workflow.rb"
puts "=" * 60
