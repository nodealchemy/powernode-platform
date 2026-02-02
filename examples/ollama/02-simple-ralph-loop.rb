# frozen_string_literal: true

# 02-simple-ralph-loop.rb
#
# Creates and runs a simple Ralph Loop using Ollama.
# Run with: bundle exec rails runner ../examples/ollama/02-simple-ralph-loop.rb

puts "=" * 60
puts "Simple Ralph Loop with Ollama"
puts "=" * 60

# Find or create test account
account = Account.find_by(name: "Ollama Test") || Account.first
unless account
  puts "ERROR: No account found. Please seed the database first."
  exit 1
end

puts "\nUsing account: #{account.name}"

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

# Create a simple Ralph Loop
model = ENV["OLLAMA_MODEL"] || provider.default_model || "llama3.2"

ralph_loop = Ai::RalphLoop.create!(
  account: account,
  name: "Simple Ollama Test Loop",
  description: "A simple Ralph Loop to test Ollama integration",
  ai_tool: "ollama",
  status: "pending",
  max_iterations: 5,
  current_iteration: 0,
  scheduling_mode: "manual",
  configuration: {
    "model" => model,
    "max_tokens" => 2048,
    "temperature" => 0.7
  }
)

puts "\nCreated Ralph Loop: #{ralph_loop.name} (ID: #{ralph_loop.id})"

# Create simple tasks
tasks_data = [
  {
    task_key: "task_1",
    description: "Write a haiku about programming",
    priority: 3,
    position: 1,
    acceptance_criteria: "A valid haiku (5-7-5 syllable structure)"
  },
  {
    task_key: "task_2",
    description: "Explain what a variable is in one sentence",
    priority: 2,
    position: 2,
    acceptance_criteria: "A clear, concise definition"
  },
  {
    task_key: "task_3",
    description: "List 3 benefits of code documentation",
    priority: 1,
    position: 3,
    acceptance_criteria: "Three distinct benefits"
  }
]

puts "\nCreating tasks..."
tasks_data.each do |task_data|
  task = ralph_loop.ralph_tasks.create!(task_data.merge(status: "pending"))
  puts "  - #{task.task_key}: #{task.description[0..50]}..."
end

ralph_loop.update!(total_tasks: ralph_loop.ralph_tasks.count)

# Initialize execution service
service = Ai::Ralph::ExecutionService.new(ralph_loop: ralph_loop, account: account)

# Start the loop
puts "\n" + "-" * 60
puts "Starting Ralph Loop..."
puts "-" * 60

start_result = service.start_loop
unless start_result[:success]
  puts "ERROR: Failed to start loop: #{start_result[:error]}"
  exit 1
end

puts "Loop started successfully!"

# Run iterations
ralph_loop.ralph_tasks.count.times do |i|
  puts "\n" + "=" * 60
  puts "Running iteration #{i + 1}..."
  puts "=" * 60

  result = service.run_iteration

  if result[:success]
    iteration = result[:iteration]
    puts "Task: #{iteration[:ralph_task_id] ? Ai::RalphTask.find(iteration[:ralph_task_id]).task_key : 'unknown'}"
    puts "Status: #{iteration[:status]}"

    if iteration[:output]
      puts "\nOutput:"
      puts "-" * 40
      puts iteration[:output].to_s[0..500]
      puts "..." if iteration[:output].to_s.length > 500
    end

    if iteration[:learning]
      puts "\nLearning: #{iteration[:learning]}"
    end

    puts "\nLoop progress: #{result[:loop][:progress_percentage]}%"

    break if result[:next_action] == "completed"
  else
    puts "Iteration failed: #{result[:error]}"
    break
  end
end

# Final status
ralph_loop.reload
puts "\n" + "=" * 60
puts "Ralph Loop Final Status"
puts "=" * 60
puts "Status: #{ralph_loop.status}"
puts "Iterations: #{ralph_loop.current_iteration}/#{ralph_loop.max_iterations}"
puts "Tasks completed: #{ralph_loop.completed_tasks}/#{ralph_loop.total_tasks}"
puts "Progress: #{ralph_loop.progress_percentage}%"

if ralph_loop.learnings&.any?
  puts "\nLearnings:"
  ralph_loop.learnings.each_with_index do |learning, idx|
    puts "  #{idx + 1}. #{learning['text']}"
  end
end

# Cleanup
puts "\nCleaning up test data..."
ralph_loop.destroy
puts "Done!"
