# frozen_string_literal: true

# Reasoning & Analysis Agents Seed Data
# Creates provider-agnostic specialized agents (model chosen at runtime by Ai::AgentModelSelector)
# NOT the Claude Code export: this seeds PLATFORM Ai::Agent records INTO the DB ("claude" is legacy
# naming); Ai::ClaudeExport::AgentSkeletonSync is the inverse — it EXPORTS platform agents OUT as CC skeletons.

puts "🧠 Creating reasoning/analysis workflow agents..."

# GLOBAL canonicals (account_id nil, source_key-managed) need NO account, user
# or provider to exist (IMP-6cda93db7f31): on a fresh core/prod DB — before
# first-admin bootstrap / the setup wizard — they are written with no creator
# and no provider (both optional on a global row; an account's executing clone
# gets THAT account's through Ai::Agents::AccountPrincipalResolver). Only the
# provider configuration below, an account-scoped row, waits for setup.
require_relative "concerns/canonical_agent_owner"
require_relative "concerns/canonical_tool_access"
require_relative "concerns/canonical_content"

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")
claude_provider = Ai::Provider.find_by(provider_type: 'anthropic')

ActiveRecord::Base.transaction do
  puts "✅ Admin account: #{admin_account ? "#{admin_account.name} (ID: #{admin_account.id})" : 'none yet — canonicals seed without a creator'}"
  puts "✅ Claude provider: #{claude_provider ? "#{claude_provider.name} (ID: #{claude_provider.id})" : 'none yet — canonicals seed without a provider'}"

  # Only set default configuration if provider has no existing configuration
  # This prevents overwriting real API keys with placeholders
  if claude_provider.nil?
    puts "  ⏭️  No Anthropic provider yet — nothing to configure"
  elsif claude_provider.configuration.blank? || claude_provider.configuration == {}
    model_names = claude_provider.supported_models.map { |m| m['name'] }
    model_ids = claude_provider.supported_models.map { |m| m['id'] }
    all_models = (model_names + model_ids).uniq

    claude_provider.configuration = {
      'models' => all_models,
      'default_model' => 'claude-haiku-4-5-20251001',
      'api_key' => 'YOUR_ANTHROPIC_API_KEY_HERE'
    }
    puts "  Set default Claude provider configuration (no existing config found)"
  else
    puts "  ⏭️  Claude provider already has configuration - preserving existing credentials"
  end

  # Provider-agnostic rename (agents must not be named after a provider —
  # model/provider is chosen at runtime by Ai::AgentModelSelector). Idempotent:
  # updates any pre-rename rows in place so the find_or_create_by calls below
  # match them instead of creating duplicates on an already-seeded DB.
  {
    'claude-strategic-planner' => [ 'strategic-planner', 'Strategic Planner' ],
    'claude-research-analyst'  => [ 'research-analyst',  'Research Analyst' ]
  }.each do |old_slug, (new_slug, new_name)|
    Ai::Agent.where(account: admin_account, slug: old_slug)
             .update_all(slug: new_slug, name: new_name)
  end

  # Strategic Planning Agent (provider-agnostic; reasoning-tier via model_requirements)
  strategic_planner = Ai::Agent.find_or_create_global(slug: 'strategic-planner') do |agent|
    agent.agent_type = 'assistant'
    agent.name = "Strategic Planner"
    agent.description = CoreSeeds::CanonicalAgentContent.description("strategic-planner")
    # Unpinned (reasoning tier, no model id): the seam keeps the seed's
    # Anthropic preference when it can, and never attaches a provider that
    # could not run a pin the row carries.
    agent.provider = CoreSeeds::CanonicalAgentOwner.provider_for(pinned_model: nil, preferred: claude_provider)
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_tool_manifest = {
      'name' => 'claude_strategic_planner',
      'description' => 'Strategic planning and business analysis agent',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'temperature' => 0.3,
        'max_tokens' => 4096,
        'response_format' => 'strategic_analysis'
      }
    }
    agent.mcp_metadata = {
      'specialization' => 'strategic_planning',
      'priority_level' => 'high',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'claude_optimized' => true,
      'reasoning_focus' => 'strategic_analysis',
      'model_config' => {
        'model_requirements' => { 'tier' => 'reasoning' },
        'temperature' => 0.3,
        'max_tokens' => 4096,
        'response_format' => 'strategic_analysis'
      }
    }
  end

  # The block above is create-only, so a canonical first written before the
  # admin account and the providers existed acquires its owner columns here on
  # the next re-seed (never blanking what is already set).
  CoreSeeds::CanonicalAgentOwner.backfill_owner!(strategic_planner, creator: admin_user, provider: claude_provider)
  # Tool scope from its planning duties: campaigns, goals, projects, missions,
  # improvements and governance. Written on every seed (the block is create-only).
  CoreSeeds::CanonicalToolAccess.declare_families!(strategic_planner, %w[
    campaign_list campaign_status campaign_list_proposals campaign_propose
    list_agent_goals create_agent_goal update_agent_goal decompose_goal
    project_list project_status get_mission_status list_improvements governance_dashboard get_governance_report
  ])
  # The block is create-only; later seed text reaches the row through the
  # operator-edit guard (concerns/canonical_content.rb).
  CoreSeeds::CanonicalContent.refresh_from_catalog!(strategic_planner)

  # Domain skills for the Strategic Planner are assigned by
  # platform_skill_assignments_seed.rb (loaded last, after all target agents
  # exist). It previously inherited SYSTEM-extension infra skills
  # (system-platform-deploy / -capacity-recommend / -resilience /
  # -runbook-generate) via each executor's `binds_to`, but a generic strategy
  # agent owning fleet-infra skills was a domain mismatch (2026-06-28 audit) —
  # those `binds_to` were removed, so this agent now carries only planning-domain
  # skills. (A core seed still must not bind/hard-require extension skills: a
  # fresh db:seed runs core before extensions, so the skills don't exist yet.)

  # Research Analyst — now on Ollama for cost optimization
  ollama_provider = Ai::Provider.find_by(provider_type: 'ollama')
  research_analyst = Ai::Agent.find_or_create_global(slug: 'research-analyst') do |agent|
    agent.agent_type = 'data_analyst'
    agent.name = "Research Analyst"
    agent.description = CoreSeeds::CanonicalAgentContent.description("research-analyst")
    agent.provider = CoreSeeds::CanonicalAgentOwner.provider_for(
      pinned_model: nil, preferred: (ollama_provider || claude_provider)
    )
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_tool_manifest = {
      'name' => 'claude_research_analyst',
      'description' => 'Comprehensive research and analysis agent',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'research_report'
      }
    }
    agent.mcp_metadata = {
      'specialization' => 'research_analysis',
      'priority_level' => 'high',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'free',
      'model_config' => {
        'provider' => 'ollama',
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'research_report',
        'cost_per_1k' => { 'input' => 0.0, 'output' => 0.0 }
      }
    }
  end

  CoreSeeds::CanonicalAgentOwner.backfill_owner!(research_analyst, creator: admin_user,
                                                 provider: (ollama_provider || claude_provider))
  # Tool scope from its research duties: documents, knowledge bases, the
  # knowledge graph, and recording what it found.
  CoreSeeds::CanonicalToolAccess.declare_families!(research_analyst, %w[
    query_knowledge_base list_knowledge_bases search_knowledge_graph reason_knowledge_graph
    list_kb_articles get_kb_article get_api_reference create_learning create_knowledge
  ])
  CoreSeeds::CanonicalContent.refresh_from_catalog!(research_analyst)

  # Research Analyst's domain skills (technical-researcher / data /
  # knowledge-system-curator / business-search / user-research) are assigned by
  # platform_skill_assignments_seed.rb. It previously inherited SYSTEM-extension
  # infra skills (system-attribute-failure / -cve-runbook-generate /
  # -suggest-architectures-for-fleet / -discover-packages-by-intent) via each
  # executor's `binds_to` — removed in the 2026-06-28 domain-purity audit, since
  # a generic research agent should not own fleet-infra skills.


  puts "✅ Created Strategic Planner (ID: #{strategic_planner.id})"
  puts "✅ Created Research Analyst (ID: #{research_analyst.id})"

  puts "\n📊 Reasoning/Analysis Agents Summary:"
  claude_agents = claude_provider ? Ai::Agent.where(provider: claude_provider) : Ai::Agent.none
  puts "   Total reasoning/analysis agents: #{claude_agents.count}"
  puts "   Strategic Planning: #{claude_agents.where(agent_type: 'assistant').count}"
  puts "   Research Analysis: #{claude_agents.where(agent_type: 'data_analyst').count}"
  puts "   Content Creation: #{claude_agents.where(agent_type: 'content_generator').count}"
end

puts "✅ Reasoning/analysis agents seeding completed!"
