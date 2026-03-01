# frozen_string_literal: true

# 01-basic-chat.rb
#
# Basic Ollama connectivity test.
# Run with: bundle exec rails runner ../examples/ollama/01-basic-chat.rb

puts "=" * 60
puts "Ollama Basic Chat Test"
puts "=" * 60

# Find or create test account
account = Account.find_by(name: "Ollama Test") || Account.first
unless account
  puts "ERROR: No account found. Please seed the database first."
  exit 1
end

puts "\nUsing account: #{account.name} (#{account.slug})"

# Find Ollama provider
provider = account.ai_providers.find_by(provider_type: "ollama")
provider ||= account.ai_providers.find_by(slug: "ollama")
provider ||= account.ai_providers.find_by(slug: "remote-ollama-server")

unless provider
  puts "\nERROR: Ollama provider not configured."
  puts "Run: bundle exec rails runner db/seeds/examples/ollama_examples_seed.rb"
  exit 1
end

puts "Found provider: #{provider.name} (#{provider.slug})"

# Get credential
credential = provider.provider_credentials.active.first
unless credential
  puts "\nERROR: No active credentials for Ollama provider."
  exit 1
end

puts "Credential: #{credential.name}"

# Create client
client = Ai::ProviderClientService.new(credential)

# Test message
model = ENV["OLLAMA_MODEL"] || provider.default_model || "llama3.2"
puts "\nSending test message to model: #{model}"
puts "-" * 40

messages = [
  { role: "system", content: "You are a helpful assistant. Be concise." },
  { role: "user", content: "What is 2 + 2? Answer in one word." }
]

start_time = Time.current
result = client.send_message(messages, model: model, max_tokens: 100)
elapsed = ((Time.current - start_time) * 1000).round

puts "\nResult:"
puts "-" * 40

if result[:success]
  response = result[:response]
  content = if response[:choices]&.first
              response.dig(:choices, 0, :message, :content)
            elsif response[:message]
              response[:message][:content]
            else
              response.to_s
            end

  puts "Response: #{content}"
  puts "Status: SUCCESS"
  puts "Time: #{elapsed}ms"
  puts "Model: #{response[:model] || model}"

  if result[:metadata]
    puts "Tokens used: #{result[:metadata][:tokens_used]}"
  end
else
  puts "Status: FAILED"
  puts "Error: #{result[:error]}"
  puts "Error type: #{result[:error_type]}"
end

puts "\n" + "=" * 60
puts result[:success] ? "Test PASSED" : "Test FAILED"
puts "=" * 60
