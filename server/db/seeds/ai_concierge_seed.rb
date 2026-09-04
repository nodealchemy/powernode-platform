# frozen_string_literal: true

puts "\n🤖 Seeding AI Concierge Agent..."

# The concierge is a GLOBAL canonical (account_id nil, source_key-managed) and
# needs NO account, user or provider to exist (IMP-6cda93db7f31): on a fresh
# core/prod DB — before first-admin bootstrap / the setup wizard — it is
# written with no creator and no provider (both optional on a global row; an
# account's executing clone gets THAT account's through
# Ai::Agents::AccountPrincipalResolver). A later re-seed fills them in.
admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

provider = Ai::Provider.find_by(provider_type: 'openai', name: 'OpenAI') ||
           Ai::Provider.find_by(provider_type: 'openai') ||
           Ai::Provider.find_by(provider_type: 'ollama') ||
           Ai::Provider.where(is_active: true).first

ActiveRecord::Base.transaction do
  # GLOBAL platform concierge (account_id nil); an account customizes it by
  # cloning. Resolution prefers the account's own concierge (resolve_concierge_for).
  agent = Ai::Agent.find_or_initialize_global(slug: "powernode-assistant")

  agent.assign_attributes(
    name: "Powernode Assistant",
    agent_type: "assistant",
    is_concierge: true,
    status: "active",
    description: "Intelligent concierge agent that helps you navigate all Powernode platform capabilities through natural language.",
    # Never blank a creator/provider an earlier seed set: nil only on a fresh
    # DB with none to give.
    creator: (admin_user || agent.creator),
    provider: (provider || agent.provider),
    # Create-only (see ai_utility_agents_seed): keep the callback-bumped version
    # on re-seed instead of downgrading it to 1.0.0 and churning an audit.
    version: (agent.version || "1.0.0"),
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
        - **Knowledge & Learning**: Search knowledge, query learnings, manage skills, explore the knowledge graph
        - **Memory**: Read/write shared memory, search across memory pools
        - **RAG & Documents**: Query knowledge bases, search documents
        - **Pipelines & DevOps**: Trigger CI/CD pipelines, dispatch to runners, create repositories
        - **Activity Monitoring**: Check activity feeds, mission status, notifications, system health
        - **Content**: Manage KB articles and pages
        - **Workspaces**: Send messages to workspace agents, manage sessions, coordinate multi-agent collaboration

        RISK ASSESSMENT RULES:
        - **Read operations** (list_*, get_*, search_*, query_*): Execute immediately, summarize results naturally
        - **Write operations** (create_*, update_*, add_*): Execute with a brief explanation of what you're doing
        - **High-risk operations** (execute_agent, execute_team, trigger_pipeline, dispatch_to_runner, create_gitea_repository): Use the `request_confirmation` tool so the user can approve first
        - When in doubt about risk level, prefer using `request_confirmation`

        In workspace conversations, follow the delegation instructions from your workspace skill.
      PROMPT
      "model_config" => {
        "provider" => "openai",
        "max_tokens" => 4096,
        "cost_per_1k" => { "input" => 0.0004, "output" => 0.0016 },
        "temperature" => 0.3
      },
      "cost_tier" => "low"
    }
  )
  agent.save!
  puts "  ✅ Concierge agent created: #{agent.name} (#{agent.id})"

  # Link concierge to its workspace routing skill (find_or_initialize + assign
  # ensures re-running seeds always reactivates the link, even if previously disabled)
  # The concierge skill is global baseline content (account_id nil); for_account
  # resolves global + this account's rows, and with no account yet only the
  # global row can exist.
  skill_scope = admin_account ? Ai::Skill.for_account(admin_account.id) : Ai::Skill.global
  concierge_skill = skill_scope.find_by(slug: "powernode-concierge")
  raise "ai_concierge_seed: Powernode Concierge skill not found — run ai_skills_seed.rb first" unless concierge_skill

  agent_skill = Ai::AgentSkill.find_or_initialize_by(ai_agent_id: agent.id, ai_skill_id: concierge_skill.id)
  agent_skill.assign_attributes(priority: -1, is_active: true)
  agent_skill.save!
  puts "  ✅ Linked Powernode Concierge skill (active=true, priority=-1)"
end
