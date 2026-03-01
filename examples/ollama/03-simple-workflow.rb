# frozen_string_literal: true

# 03-simple-workflow.rb
#
# Creates and executes a simple workflow using an Ollama-based AI agent.
# Run with: bundle exec rails runner ../examples/ollama/03-simple-workflow.rb

puts "=" * 60
puts "Simple Workflow with Ollama AI Agent"
puts "=" * 60

# Find or create test account
account = Account.find_by(name: "Ollama Test") || Account.first
unless account
  puts "ERROR: No account found. Please seed the database first."
  exit 1
end

puts "\nUsing account: #{account.name}"

# Find a user to be the creator
creator = account.users.first
unless creator
  puts "ERROR: No user found in account. Please seed the database."
  exit 1
end

# Verify Ollama provider exists
provider = account.ai_providers.find_by(provider_type: "ollama")
provider ||= account.ai_providers.find_by(slug: "ollama")
provider ||= account.ai_providers.find_by(slug: "remote-ollama-server")

unless provider
  puts "\nERROR: Ollama provider not configured."
  puts "Run: bundle exec rails runner db/seeds/examples/ollama_examples_seed.rb"
  exit 1
end

puts "Using Ollama provider: #{provider.name}"

# Find or create an Ollama-based AI agent
model = ENV["OLLAMA_MODEL"] || provider.default_model || "llama3.2"

agent = Ai::Agent.find_by(account: account, name: "Ollama Workflow Agent")
agent ||= Ai::Agent.create!(
  account: account,
  creator: creator,
  name: "Ollama Workflow Agent",
  description: "Simple agent for workflow testing",
  agent_type: "assistant",
  provider: provider,
  status: "active",
  version: "1.0.0",
  mcp_capabilities: %w[text_generation chat],
  mcp_metadata: {
    "model" => model,
    "max_tokens" => 1024,
    "temperature" => 0.7,
    "system_prompt" => "You are a helpful assistant. Be concise and clear."
  }
)

puts "Using AI Agent: #{agent.name}"

# Create a simple workflow
workflow = Ai::Workflow.create!(
  account: account,
  creator: creator,
  name: "Simple Ollama Workflow #{Time.current.to_i}",
  description: "A simple workflow that uses Ollama for text processing",
  status: "active",
  version: "1.0.0",
  configuration: {
    "execution_mode" => "sequential",
    "max_execution_time" => 300
  }
)

puts "\nCreated Workflow: #{workflow.name} (ID: #{workflow.id})"

# Create nodes: start -> ai_agent -> end
puts "\nCreating workflow nodes..."

start_node = workflow.workflow_nodes.create!(
  node_id: "start_1",
  node_type: "start",
  name: "Start",
  position: { "x" => 100, "y" => 200 },
  configuration: {}
)
puts "  - Start node"

ai_node = workflow.workflow_nodes.create!(
  node_id: "ai_agent_1",
  node_type: "ai_agent",
  name: "Process with Ollama",
  position: { "x" => 300, "y" => 200 },
  configuration: {
    "agent_id" => agent.id,
    "prompt_template" => "Summarize the following in one sentence: {{input.text}}",
    "input_mapping" => { "text" => "$.input.text" },
    "output_key" => "summary"
  }
)
puts "  - AI Agent node (using #{agent.name})"

end_node = workflow.workflow_nodes.create!(
  node_id: "end_1",
  node_type: "end",
  name: "End",
  position: { "x" => 500, "y" => 200 },
  configuration: {}
)
puts "  - End node"

# Create edges
puts "\nCreating workflow edges..."

workflow.workflow_edges.create!(
  edge_id: "edge_1",
  source_node_id: "start_1",
  target_node_id: "ai_agent_1"
)
puts "  - start -> ai_agent"

workflow.workflow_edges.create!(
  edge_id: "edge_2",
  source_node_id: "ai_agent_1",
  target_node_id: "end_1"
)
puts "  - ai_agent -> end"

# Execute the workflow
puts "\n" + "-" * 60
puts "Executing Workflow..."
puts "-" * 60

input_data = {
  text: "Ruby on Rails is a server-side web application framework written in Ruby. " \
        "It provides default structures for a database, a web service, and web pages. " \
        "It encourages and facilitates the use of web standards such as JSON or XML for data transfer " \
        "and HTML, CSS and JavaScript for user interfacing."
}

puts "Input text: #{input_data[:text][0..100]}..."

# Create workflow run
workflow_run = workflow.workflow_runs.create!(
  account: account,
  status: "pending",
  input_data: input_data
)

# Execute using the workflow executor
begin
  executor = Mcp::WorkflowExecutor.new(
    workflow: workflow,
    workflow_run: workflow_run,
    account: account
  )

  start_time = Time.current
  result = executor.execute(input_data)
  elapsed = ((Time.current - start_time) * 1000).round

  puts "\n" + "=" * 60
  puts "Workflow Execution Result"
  puts "=" * 60

  workflow_run.reload

  puts "Status: #{workflow_run.status}"
  puts "Execution time: #{elapsed}ms"

  if workflow_run.output_data.present?
    puts "\nOutput:"
    puts "-" * 40
    output = workflow_run.output_data
    if output["summary"]
      puts "Summary: #{output['summary']}"
    else
      puts output.to_json[0..500]
    end
  end

  if workflow_run.error_message.present?
    puts "\nError: #{workflow_run.error_message}"
  end

  puts "\nNode execution log:"
  workflow_run.execution_log&.each do |log_entry|
    puts "  - #{log_entry['node_id']}: #{log_entry['status']} (#{log_entry['duration_ms']}ms)"
  end
rescue StandardError => e
  puts "\nERROR: Workflow execution failed"
  puts "Message: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
end

# Cleanup
puts "\nCleaning up test data..."
workflow.destroy
agent.destroy if agent.name == "Ollama Workflow Agent"
puts "Done!"
