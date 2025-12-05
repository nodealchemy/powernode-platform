#!/usr/bin/env ruby
# frozen_string_literal: true

puts '═══════════════════════════════════════════════════════'
puts 'COMPREHENSIVE PROVIDER & AGENT TESTING'
puts '═══════════════════════════════════════════════════════'
puts ''

# Get account and setup
account = Account.first
results = {
  providers: [],
  credentials: [],
  agents: [],
  summary: {
    total_providers: 0,
    working_providers: 0,
    total_credentials: 0,
    working_credentials: 0,
    total_agents: 0,
    verified_agents: 0
  }
}

# Test 1: Provider Inventory
puts '📋 STEP 1: PROVIDER INVENTORY'
puts '─────────────────────────────────────────────────────'
puts ''

providers = account.ai_providers.active
results[:summary][:total_providers] = providers.count

providers.each do |provider|
  credential_count = provider.ai_provider_credentials.where(account: account).active.count

  provider_info = {
    name: provider.name,
    slug: provider.slug,
    type: provider.provider_type,
    active: provider.is_active,
    credentials: credential_count,
    models: provider.supported_models.count,
    status: credential_count > 0 ? 'configured' : 'no_credentials'
  }

  results[:providers] << provider_info

  status_icon = credential_count > 0 ? '✅' : '⚠️'
  puts "#{status_icon} #{provider.name}"
  puts "   Slug: #{provider.slug}"
  puts "   Type: #{provider.provider_type}"
  puts "   Credentials: #{credential_count}"
  puts "   Models: #{provider.supported_models.count}"
  puts ''
end

# Test 2: Credential Testing
puts ''
puts '🔑 STEP 2: CREDENTIAL CONNECTION TESTING'
puts '─────────────────────────────────────────────────────'
puts ''

credentials = account.ai_provider_credentials.active.includes(:ai_provider)
results[:summary][:total_credentials] = credentials.count

credentials.each do |credential|
  print "Testing #{credential.ai_provider.name} (#{credential.name})... "

  begin
    test_service = AiProviderTestService.new(credential)
    test_result = test_service.test_with_details

    credential_info = {
      provider: credential.ai_provider.name,
      name: credential.name,
      success: test_result[:success],
      response_time: test_result[:response_time_ms],
      error: test_result[:error]
    }

    results[:credentials] << credential_info

    if test_result[:success]
      results[:summary][:working_credentials] += 1
      results[:summary][:working_providers] += 1 if results[:providers].find { |p| p[:slug] == credential.ai_provider.slug }&.tap { |p| p[:tested] = true }

      credential.record_success!
      puts "✅ SUCCESS (#{test_result[:response_time_ms]}ms)"
    else
      credential.record_failure!(test_result[:error])
      puts "❌ FAILED: #{test_result[:error]}"
    end
  rescue => e
    credential.record_failure!(e.message)
    results[:credentials] << {
      provider: credential.ai_provider.name,
      name: credential.name,
      success: false,
      error: e.message
    }
    puts "❌ ERROR: #{e.message}"
  end
end

# Test 3: Agent Verification
puts ''
puts '🤖 STEP 3: AGENT VERIFICATION'
puts '─────────────────────────────────────────────────────'
puts ''

agents = account.ai_agents.includes(:ai_provider)
results[:summary][:total_agents] = agents.count

agents.each do |agent|
  provider = agent.ai_provider
  provider_has_working_credential = results[:credentials].any? do |cred|
    cred[:provider] == provider.name && cred[:success]
  end

  agent_info = {
    name: agent.name,
    type: agent.agent_type,
    provider: provider.name,
    status: agent.status,
    mcp_tool_id: agent.mcp_tool_id,
    capabilities: agent.mcp_capabilities&.count || 0,
    provider_working: provider_has_working_credential,
    verified: agent.status == 'active' && provider_has_working_credential
  }

  results[:agents] << agent_info
  results[:summary][:verified_agents] += 1 if agent_info[:verified]

  status_icon = agent_info[:verified] ? '✅' : (provider_has_working_credential ? '⚠️' : '❌')

  puts "#{status_icon} #{agent.name}"
  puts "   Type: #{agent.agent_type}"
  puts "   Provider: #{provider.name} #{provider_has_working_credential ? '✅' : '❌'}"
  puts "   Status: #{agent.status}"
  puts "   MCP Tool: #{agent.mcp_tool_id}"
  puts "   Capabilities: #{agent.mcp_capabilities&.count || 0}"
  puts ''
end

# Test 4: Workflow Orchestrator Specific Test
puts ''
puts '🎯 STEP 4: WORKFLOW ORCHESTRATOR VERIFICATION'
puts '─────────────────────────────────────────────────────'
puts ''

orchestrator = AiAgent.find_by(slug: 'workflow-orchestrator')
workflow = AiWorkflow.first

if orchestrator && workflow
  orchestrator_credential = orchestrator.ai_provider.ai_provider_credentials
                                        .where(account: account)
                                        .active
                                        .first

  puts "Orchestrator: #{orchestrator.name}"
  puts "   Provider: #{orchestrator.ai_provider.name}"
  puts "   Credential: #{orchestrator_credential ? '✅ Available' : '❌ Missing'}"
  puts "   Workflow Assignment: #{workflow.configuration['orchestrator'] ? '✅ Assigned' : '❌ Not Assigned'}"

  if orchestrator_credential
    credential_test = results[:credentials].find { |c| c[:provider] == orchestrator.ai_provider.name }
    puts "   Connection Test: #{credential_test&.dig(:success) ? '✅ Working' : '❌ Failed'}"
  end

  puts ''

  if workflow.configuration['orchestrator']
    config = workflow.configuration['orchestrator']
    puts "   Orchestrator Configuration:"
    puts "     - Agent ID: #{config['agent_id']}"
    puts "     - Strategy: #{config['coordination_strategy']}"
    puts "     - Error Recovery: #{config['error_handling']['retry_failed_nodes'] ? 'Enabled' : 'Disabled'}"
    puts "     - Checkpointing: #{config['error_handling']['create_checkpoints'] ? 'Enabled' : 'Disabled'}"
  end
else
  puts "❌ Orchestrator or Workflow not found"
end

# Final Summary
puts ''
puts '═══════════════════════════════════════════════════════'
puts 'TESTING SUMMARY'
puts '═══════════════════════════════════════════════════════'
puts ''

puts "📊 Providers: #{results[:summary][:working_providers]}/#{results[:summary][:total_providers]} working"
puts "🔑 Credentials: #{results[:summary][:working_credentials]}/#{results[:summary][:total_credentials]} working"
puts "🤖 Agents: #{results[:summary][:verified_agents]}/#{results[:summary][:total_agents]} verified"
puts ''

# Identify Issues
issues = []

# Providers without credentials
providers_no_creds = results[:providers].select { |p| p[:status] == 'no_credentials' }
if providers_no_creds.any?
  issues << "⚠️  Providers without credentials: #{providers_no_creds.map { |p| p[:name] }.join(', ')}"
end

# Failed credentials
failed_creds = results[:credentials].select { |c| !c[:success] }
if failed_creds.any?
  issues << "❌ Failed credentials:"
  failed_creds.each do |cred|
    issues << "   - #{cred[:provider]} (#{cred[:name]}): #{cred[:error]}"
  end
end

# Agents with non-working providers
agents_bad_provider = results[:agents].select { |a| !a[:provider_working] }
if agents_bad_provider.any?
  issues << "⚠️  Agents with non-working providers: #{agents_bad_provider.map { |a| a[:name] }.join(', ')}"
end

if issues.any?
  puts '🔴 ISSUES FOUND:'
  puts ''
  issues.each { |issue| puts issue }
  puts ''
else
  puts '✅ ALL SYSTEMS OPERATIONAL'
  puts ''
end

# Recommendations
puts '💡 RECOMMENDATIONS:'
puts ''

if providers_no_creds.any?
  puts "1. Add credentials for: #{providers_no_creds.map { |p| p[:name] }.join(', ')}"
end

if failed_creds.any?
  puts "2. Fix failed credentials:"
  failed_creds.each do |cred|
    puts "   - Check API key for #{cred[:provider]}"
  end
end

if agents_bad_provider.any?
  puts "3. Update agents to use working providers or fix provider credentials"
end

if issues.empty?
  puts "🎉 System is fully configured and operational!"
  puts "   - All providers have working credentials"
  puts "   - All agents are verified and ready"
  puts "   - Workflow orchestrator is configured"
end

puts ''
puts '═══════════════════════════════════════════════════════'
