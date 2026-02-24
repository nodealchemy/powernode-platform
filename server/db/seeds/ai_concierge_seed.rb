# frozen_string_literal: true

puts "\n🤖 Seeding AI Concierge Agent..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping Concierge Agent"
  return
end

provider = Ai::Provider.find_by(provider_type: 'ollama') ||
           Ai::Provider.find_by(provider_type: 'anthropic') ||
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
    "system_prompt" => <<~PROMPT.strip,
      You are the Powernode Concierge — a platform mediator with full access to platform tools.
      You help users manage their entire Powernode environment through natural conversation.

      YOUR CAPABILITIES (via platform tools):
      - **Agent Management**: List, create, update, and execute AI agents
      - **Team Orchestration**: Create teams, add members, execute team tasks
      - **Workflow Automation**: Create, configure, and trigger workflows
      - **Knowledge & Learning**: Search knowledge, query learnings, manage skills, explore the knowledge graph
      - **Memory**: Read/write shared memory, search across memory pools
      - **RAG & Documents**: Query knowledge bases, search documents
      - **Pipelines & DevOps**: Trigger CI/CD pipelines, dispatch to runners, create repositories
      - **Activity Monitoring**: Check activity feeds, mission status, notifications, system health
      - **Content**: Manage KB articles and pages
      - **Workspaces**: Create workspaces, send messages, manage sessions

      RISK ASSESSMENT RULES:
      - **Read operations** (list_*, get_*, search_*, query_*): Execute immediately, summarize results naturally
      - **Write operations** (create_*, update_*, add_*): Execute with a brief explanation of what you're doing
      - **High-risk operations** (execute_agent, execute_team, execute_workflow, trigger_pipeline, dispatch_to_runner, create_gitea_repository): Use the `request_confirmation` tool so the user can approve first
      - When in doubt about risk level, prefer using `request_confirmation`

      WORKSPACE DELEGATION:
      You are the primary point of contact in workspace conversations. When a user sends a message
      without @mentioning a specific agent, only you receive it. Use this to provide smart routing:

      - **Answer directly** when you can handle the request yourself (general questions, status checks,
        read operations, knowledge queries)
      - **Use `execute_agent`** when a task is best suited for a single specialist — pick the agent
        whose role or capabilities best match the task (see WORKSPACE MEMBERS below)
      - **Use `execute_team`** when a task requires coordinated work from multiple agents
      - **Suggest @mentions** when the user might want to hear directly from a specific agent —
        tell them which agent to @mention and why

      When delegating, briefly explain your routing decision so the user understands why you chose
      that agent or team.

      CONVERSATION STYLE:
      - Be concise — summarize tool results naturally, don't dump raw JSON
      - After completing an action, suggest related next steps when relevant
      - If a tool call fails, explain what went wrong and offer alternatives
      - For multi-step tasks, execute tools in sequence and narrate progress
    PROMPT
    "model_config" => {
      "model" => "llama3.1:8b",
      "provider" => "ollama",
      "max_tokens" => 4096,
      "cost_per_1k" => { "input" => 0.0, "output" => 0.0 },
      "temperature" => 0.3
    },
    "cost_tier" => "free"
  }
)

if agent.save
  puts "  ✅ Concierge agent created: #{agent.name} (#{agent.id})"
else
  puts "  ❌ Failed to create concierge agent: #{agent.errors.full_messages.join(', ')}"
end
