# frozen_string_literal: true

# Agent Functionality Test Script
# Validates agent creation, configuration, and basic functionality

puts "🧪 Testing Agent Functionality...\n"

# Test 1: Agent retrieval by type
puts "Test 1: Agent retrieval by type"
workflow_ops = Ai::Agent.where(agent_type: 'workflow_operations')
puts "  Workflow Operations Agents: #{workflow_ops.count}"
workflow_ops.each { |agent| puts "    - #{agent.name} (#{agent.slug})" }

monitors = Ai::Agent.where(agent_type: 'monitor')
puts "  Monitor Agents: #{monitors.count}"
monitors.each { |agent| puts "    - #{agent.name} (#{agent.slug})" }

optimizers = Ai::Agent.where(agent_type: 'workflow_optimizer')
puts "  Workflow Optimizer Agents: #{optimizers.count}"
optimizers.each { |agent| puts "    - #{agent.name} (#{agent.slug})" }

assistants = Ai::Agent.where(agent_type: 'assistant')
puts "  Assistant Agents: #{assistants.count}"
assistants.each { |agent| puts "    - #{agent.name} (#{agent.slug})" }

# Test 2: Agent validation
puts "\nTest 2: Agent validation"
invalid_agents = Ai::Agent.all.select { |agent| not agent.valid? }
if invalid_agents.empty?
  puts "  ✅ All agents are valid"
else
  puts "  ❌ Found #{invalid_agents.count} invalid agents:"
  invalid_agents.each { |agent| puts "    - #{agent.name}: #{agent.errors.full_messages.join(', ')}" }
end

# Test 3: Agent configuration
puts "\nTest 3: Agent configuration"
sample_agent = Ai::Agent.where(agent_type: 'workflow_operations').first
if sample_agent&.configuration&.present?
  puts "  ✅ Sample agent has configuration"
  puts "    - Model: #{sample_agent.configuration['model']}"
  puts "    - Temperature: #{sample_agent.configuration['temperature']}"
  puts "    - Has system_prompt: #{sample_agent.configuration['system_prompt'].present?}"
else
  puts "  ❌ Sample agent missing configuration"
end

# Test 4: Agent capabilities
puts "\nTest 4: Agent capabilities"
agents_with_capabilities = Ai::Agent.where.not(capabilities: [])
puts "  Agents with capabilities: #{agents_with_capabilities.count}/#{Ai::Agent.count}"
if agents_with_capabilities.count == Ai::Agent.count
  puts "  ✅ All agents have capabilities defined"
else
  puts "  ❌ Some agents missing capabilities"
end

# Test 5: Agent execution readiness
puts "\nTest 5: Agent execution readiness"
ready_agents = Ai::Agent.all.select { |agent| agent.can_execute? }
puts "  Ready for execution: #{ready_agents.count}/#{Ai::Agent.count}"
if ready_agents.count > 0
  puts "  ✅ Agents are ready for execution"
  ready_agents.first(3).each { |agent| puts "    - #{agent.name}" }
else
  puts "  ❌ No agents ready for execution"
end

# Test 6: Agent metadata and versioning
puts "\nTest 6: Agent metadata and versioning"
agents_with_metadata = Ai::Agent.where.not(metadata: {})
puts "  Agents with metadata: #{agents_with_metadata.count}/#{Ai::Agent.count}"
if agents_with_metadata.count > 0
  puts "  ✅ Agents have metadata configured"
else
  puts "  ❌ Agents missing metadata"
end

# Test 7: Account associations
puts "\nTest 7: Account associations"
agents_with_accounts = Ai::Agent.joins(:account).count
puts "  Agents with accounts: #{agents_with_accounts}/#{Ai::Agent.count}"
if agents_with_accounts == Ai::Agent.count
  puts "  ✅ All agents properly associated with accounts"
else
  puts "  ❌ Some agents missing account associations"
end

# Test 8: Provider associations
puts "\nTest 8: Provider associations"
agents_with_providers = Ai::Agent.joins(:ai_provider).count
puts "  Agents with providers: #{agents_with_providers}/#{Ai::Agent.count}"
if agents_with_providers == Ai::Agent.count
  puts "  ✅ All agents properly associated with providers"
else
  puts "  ❌ Some agents missing provider associations"
end

puts "\n🎯 Agent Functionality Test Complete"
puts "\n📊 Final Summary:"
puts "   Total Agents: #{Ai::Agent.count}"
puts "   Valid Agents: #{Ai::Agent.count - invalid_agents.count}"
puts "   Ready for Execution: #{ready_agents.count}"
puts "   Agent Types: #{Ai::Agent.distinct.count(:agent_type)}"
