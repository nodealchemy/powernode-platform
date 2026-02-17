# frozen_string_literal: true

puts "\n🤖 Seeding AI Concierge Agent..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping Concierge Agent"
  return
end

provider = Ai::Provider.find_by(provider_type: 'anthropic') ||
           Ai::Provider.find_by(provider_type: 'openai') ||
           Ai::Provider.where(is_active: true).first

unless provider
  puts "  ⚠️  No AI provider found — skipping Concierge Agent"
  return
end

agent = Ai::Agent.find_or_initialize_by(
  account: admin_account,
  slug: "powernode-assistant"
)

agent.assign_attributes(
  name: "Powernode Assistant",
  agent_type: "assistant",
  is_concierge: true,
  status: "active",
  description: "Intelligent concierge agent that helps you navigate all Powernode platform capabilities through natural language.",
  creator: admin_user,
  provider: provider,
  version: "1.0.0",
  conversation_profile: {
    "tone" => "helpful",
    "verbosity" => "concise",
    "style" => "professional",
    "greeting" => "Hi! I'm your Powernode Assistant. I can help you create missions, check status, analyze repos, and more. What would you like to do?"
  },
  mcp_metadata: {
    "system_prompt" => "You are the Powernode Assistant, an intelligent concierge for the Powernode platform. You help users navigate and use all platform capabilities through natural language.",
    "model" => nil
  }
)

if agent.save
  puts "  ✅ Concierge agent created: #{agent.name} (#{agent.id})"
else
  puts "  ❌ Failed to create concierge agent: #{agent.errors.full_messages.join(', ')}"
end
