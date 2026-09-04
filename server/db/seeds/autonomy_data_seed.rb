# frozen_string_literal: true

# Autonomy Data Seed
# Ensures the curated agent set exists (creating the extra industry/utility
# agents if earlier seeds didn't) and seeds trust scores + budgets for them.
#
# Idempotent — safe to re-run. (The legacy destructive 37→10 consolidation that
# used to run here was removed in 0.4.0 — see the note below.)

Rails.logger.info "[AutonomySeed] Starting autonomy data seeding..."

# (The recursive clean_fk_references_for FK-cascade helper that lived here was
# removed along with the legacy 37→10 consolidation it was the only caller of.)

require_relative "concerns/canonical_agent_owner"

# The three GLOBAL canonicals below (GLOBAL_AUTONOMY_AGENT_SLUGS) need NO
# account, user or provider to exist (IMP-6cda93db7f31) and are written first;
# everything account-scoped — the industry/business demo agents, provider
# re-pointing, trust scores, budgets, intervention policies — waits for the
# admin account + user (the gate sits below the canonical writes).
admin_account = Account.find_by(name: "Powernode Admin")
admin_user    = admin_account&.users&.find_by(email: "admin@powernode.org")

# ===========================================================================
# STEP 1 — Agent Consolidation
# ===========================================================================
KEEP_AGENT_NAMES = [
  # Dev team agents (ai_dev_team_seed.rb)
  "Powernode Project Lead",
  "Powernode Backend Developer",
  "Powernode Frontend Developer",
  "Powernode QA/Test Engineer",
  "Powernode DevOps Engineer",
  "Powernode Documentation Specialist",
  # Business agents (claude_agents_seed.rb + monitoring_analytics_agents_seed.rb)
  "Strategic Planner",
  "Research Analyst",
  "Visual Design Assistant",
  "Infrastructure Health Monitor",
  "Process Automation Optimizer",
  "Legal & Compliance Analyst",
  "Life Sciences Research Analyst",
  "Finance Operations Analyst",
  "Sales Operations Specialist",
  "Customer Success Agent",
  # Utility agents (ai_utility_agents_seed.rb)
  "PRD Generator",
  "LLM Judge",
  "Knowledge Graph Curator",
  "RAG Reranker",
  "RAG Query Engine",
  "Intent Classifier",
  # semantic-tool-scorer retired (IMP-85c9964aa840) — no longer seeded, so
  # protecting it here would preserve rows on planes that already have one while
  # naming an agent no seed creates.
  # Example extension agents (dynamically created, must survive seeds)
  "Example Overseer"
].freeze

# Ensure the 4 extra agents exist (they may not have been created by earlier seeds)
openai_provider   = Ai::Provider.find_by(provider_type: "openai")
grok_provider     = Ai::Provider.find_by(provider_type: "custom")     # Grok is custom type
claude_provider   = Ai::Provider.find_by(provider_type: "anthropic")
ollama_provider   = Ai::Provider.find_by(provider_type: "ollama")

extra_agents = [
  {
    # NOTE: classified content_generator (text/spec output), NOT image_generator.
    # This agent writes design briefs, UI mockup specs, brand-asset specs, and
    # image-generation PROMPTS — all text — and resolves a reasoning-tier text
    # model. The old image_generator type would have steered model selection to
    # an image model (wrong). See reclassification data-fix below the loop.
    name: "Visual Design Assistant",
    slug: "visual-design-assistant",
    agent_type: "content_generator",
    provider: openai_provider,
    description: "Visual design assistant — design briefs, UI mockup specs, brand-asset specs, and image-generation prompts (text/spec output)"
  },
  {
    name: "Infrastructure Health Monitor",
    slug: "infrastructure-health-monitor",
    agent_type: "monitor",
    provider: claude_provider,
    description: "Continuous infrastructure monitoring agent tracking system health, performance metrics, and availability"
  },
  {
    name: "Process Automation Optimizer",
    slug: "process-automation-optimizer",
    agent_type: "assistant",
    provider: grok_provider,
    description: "Process optimization agent that analyzes and improves automated processes for efficiency and reliability"
  },
  {
    name: "Legal & Compliance Analyst",
    slug: "legal-compliance-analyst",
    agent_type: "data_analyst",
    provider: claude_provider,
    description: "Reviews contracts, triages NDAs, assesses legal risk, and evaluates regulatory compliance across GDPR, SOC 2, HIPAA, PCI DSS, and ISO 27001 frameworks."
  },
  {
    name: "Life Sciences Research Analyst",
    slug: "life-sciences-research-analyst",
    agent_type: "data_analyst",
    provider: ollama_provider,
    description: "Conducts literature reviews, target assessments, and genomics queries for life science and pharmaceutical research using PubMed, bioRxiv, ChEMBL, and Benchling."
  },
  {
    name: "Finance Operations Analyst",
    slug: "finance-operations-analyst",
    agent_type: "data_analyst",
    provider: ollama_provider,
    description: "Creates journal entries, reconciles accounts, generates financial statements, and performs variance analysis across accounting and data warehouse systems."
  },
  {
    name: "Sales Operations Specialist",
    slug: "sales-operations-specialist",
    agent_type: "assistant",
    provider: openai_provider,
    description: "Researches prospects, prepares call briefings, manages pipeline health, drafts personalized outreach, and builds competitive battlecards using CRM and enrichment tools."
  },
  {
    name: "Customer Success Agent",
    slug: "customer-success-agent",
    agent_type: "assistant",
    provider: openai_provider,
    description: "Triages support tickets, drafts customer responses, manages escalations, and maintains knowledge base articles across helpdesk and CRM platforms."
  }
]

# Fundamental platform agents that are GLOBAL (account_id nil) — accounts clone
# to customize. The industry/business example agents below stay account-scoped
# demo data.
GLOBAL_AUTONOMY_AGENT_SLUGS = %w[
  infrastructure-health-monitor
  process-automation-optimizer
  visual-design-assistant
].freeze

extra_agents.each do |ad|
  # These definitions carry no model pin, so the per-agent provider above is
  # editorial; the seam keeps it whenever the family rule allows and never
  # offers one that could not run a pin the row ends up with.
  chosen_provider = CoreSeeds::CanonicalAgentOwner.provider_for(pinned_model: nil, preferred: ad[:provider])

  if GLOBAL_AUTONOMY_AGENT_SLUGS.include?(ad[:slug])
    # Canonical: creator and provider are optional on a global row, so a
    # missing provider (or user) never skips it.
    canonical = Ai::Agent.find_or_create_global(slug: ad[:slug]) do |a|
      a.name        = ad[:name]
      a.agent_type  = ad[:agent_type]
      a.provider    = chosen_provider
      a.creator     = admin_user
      a.status      = "active"
      a.version     = "1.0.0"
      a.description = ad[:description]
    end
    # The block above is create-only, so a canonical first written before the
    # admin account and the providers existed acquires its owner columns here
    # on the next re-seed (never blanking what is already set).
    CoreSeeds::CanonicalAgentOwner.backfill_owner!(canonical, creator: admin_user, provider: ad[:provider])
  else
    # Account-scoped demo agent: needs the admin account, its user and a provider.
    next unless admin_account && admin_user && chosen_provider

    Ai::Agent.find_or_create_by!(account: admin_account, name: ad[:name]) do |a|
      a.slug        = ad[:slug]
      a.agent_type  = ad[:agent_type]
      a.provider    = chosen_provider
      a.creator     = admin_user
      a.status      = "active"
      a.version     = "1.0.0"
      a.description = ad[:description]
    end
  end
end

# Reclassification data-fix (idempotent): the block above only sets agent_type on
# CREATE, so an already-seeded "Visual Design Assistant" keeps its stale
# image_generator type. It produces text/specs, not images — correct it in place
# (slug-scoped so it catches the now-global row too).
Ai::Agent.where(slug: "visual-design-assistant", agent_type: "image_generator")
         .update_all(agent_type: "content_generator")

# Everything from here on is account-scoped and waits for the admin account +
# user; a re-seed after setup writes it. The canonicals above are already in.
unless admin_account && admin_user
  Rails.logger.warn "[AutonomySeed] Admin account/user not found — canonicals seeded; " \
                    "skipping account-scoped trust scores, budgets and policies"
  return
end

# Reassign providers for the dev team agents to match the plan
provider_assignments = {
  "Powernode Project Lead"       => grok_provider,
  "Powernode Frontend Developer" => grok_provider,
  "Powernode DevOps Engineer"    => grok_provider,
  "Process Automation Optimizer" => grok_provider,
  "Powernode Backend Developer"  => claude_provider,
  "Research Analyst"      => claude_provider,
  "Infrastructure Health Monitor" => claude_provider,
  "Powernode QA/Test Engineer"   => openai_provider,
  "Visual Design Assistant"      => openai_provider,
  "Powernode Documentation Specialist" => ollama_provider,
  "Legal & Compliance Analyst"         => claude_provider,
  "Life Sciences Research Analyst"     => ollama_provider,
  "Finance Operations Analyst"         => ollama_provider,
  "Sales Operations Specialist"        => openai_provider,
  "Customer Success Agent"             => openai_provider
}

provider_assignments.each do |agent_name, provider|
  next unless provider

  agent = Ai::Agent.resolve_for(admin_account.id, name: agent_name)
  next unless agent

  # The plan above is a PREFERENCE, and this write skips validation, so it was
  # the exact door the deploy-4 incident (2026-09-04) came through: on a plane
  # whose only active provider was OpenAI it moved the claude-pinned global
  # `visual-design-assistant` onto OpenAI, an invalid row that then failed
  # every later save and aborted the hierarchy seed. Ask the seam what can
  # actually run this row's pin, and leave the provider alone when nothing can.
  chosen = CoreSeeds::CanonicalAgentOwner.provider_for(
    pinned_model: agent.mcp_metadata&.dig("model_config", "model"), preferred: provider
  )
  next unless chosen

  agent.update_columns(ai_provider_id: chosen.id) if agent.ai_provider_id != chosen.id
end

# (0.4.0) The legacy "37→10" agent + orphaned-team consolidation (a destructive
# allowlist delete: "delete every agent/team NOT in KEEP_*") was REMOVED. On a
# fresh 0.4.0 install it destroyed legitimately seeded demo agents (the example /
# industry agents) and the teams referencing them — leaving an incomplete install
# (41 agents instead of 55) and churning their intervention policies / connections
# on every re-seed. Seeds are additive + idempotent (every agent/team create is
# find_or_create_by-guarded); deduplicating a pre-0.4.0 install is a Phase 9
# data-migration concern, not a recurring seed.

# ===========================================================================
# STEP 2 — Seed Trust Scores and Budgets
# ===========================================================================

# Reload kept agents
agents = Ai::Agent.for_account(admin_account.id).where(name: KEEP_AGENT_NAMES)
  .index_by(&:name)

# Also include the concierge agent
concierge = Ai::Agent.resolve_concierge_for(admin_account.id)
agents[concierge.name] = concierge if concierge

if agents.size < KEEP_AGENT_NAMES.size
  missing = KEEP_AGENT_NAMES - agents.keys
  Rails.logger.warn "[AutonomySeed] Missing agents: #{missing.join(', ')} — seeding partial data"
end

# ---------------------------------------------------------------------------
# Trust Scores
# ---------------------------------------------------------------------------
TRUST_PROFILES = {
  "Visual Design Assistant"          => { tier: "supervised", rel: 0.20, cost: 0.30, safety: 0.30, qual: 0.20, speed: 0.30, evals: 3  },
  "Process Automation Optimizer"     => { tier: "supervised", rel: 0.35, cost: 0.35, safety: 0.40, qual: 0.30, speed: 0.35, evals: 5  },
  "Powernode Documentation Specialist" => { tier: "monitored",  rel: 0.40, cost: 0.40, safety: 0.45, qual: 0.35, speed: 0.35, evals: 8  },
  "Powernode Assistant"                => { tier: "trusted",    rel: 0.85, cost: 0.80, safety: 0.90, qual: 0.80, speed: 0.80, evals: 40 },
  "Powernode Project Lead"           => { tier: "monitored",  rel: 0.55, cost: 0.50, safety: 0.60, qual: 0.45, speed: 0.50, evals: 12 },
  "Research Analyst"          => { tier: "monitored",  rel: 0.60, cost: 0.55, safety: 0.60, qual: 0.50, speed: 0.55, evals: 15 },
  "Powernode DevOps Engineer"        => { tier: "monitored",  rel: 0.70, cost: 0.60, safety: 0.75, qual: 0.60, speed: 0.60, evals: 20 },
  "Powernode Frontend Developer"     => { tier: "trusted",    rel: 0.80, cost: 0.70, safety: 0.80, qual: 0.70, speed: 0.70, evals: 25 },
  "Powernode QA/Test Engineer"       => { tier: "trusted",    rel: 0.85, cost: 0.75, safety: 0.85, qual: 0.80, speed: 0.75, evals: 28 },
  "Powernode Backend Developer"      => { tier: "trusted",    rel: 0.90, cost: 0.80, safety: 0.90, qual: 0.85, speed: 0.80, evals: 32 },
  "Infrastructure Health Monitor"    => { tier: "trusted",    rel: 0.92, cost: 0.85, safety: 0.95, qual: 0.85, speed: 0.85, evals: 35 },
  "Legal & Compliance Analyst"       => { tier: "supervised", rel: 0.30, cost: 0.40, safety: 0.50, qual: 0.35, speed: 0.30, evals: 3  },
  "Life Sciences Research Analyst"   => { tier: "supervised", rel: 0.25, cost: 0.80, safety: 0.35, qual: 0.25, speed: 0.40, evals: 3  },
  "Finance Operations Analyst"       => { tier: "supervised", rel: 0.30, cost: 0.80, safety: 0.45, qual: 0.30, speed: 0.40, evals: 3  },
  "Sales Operations Specialist"      => { tier: "supervised", rel: 0.25, cost: 0.50, safety: 0.30, qual: 0.25, speed: 0.35, evals: 3  },
  "Customer Success Agent"           => { tier: "supervised", rel: 0.30, cost: 0.50, safety: 0.35, qual: 0.30, speed: 0.40, evals: 3  },
  "Example Overseer"                 => { tier: "trusted",    rel: 0.88, cost: 0.75, safety: 0.90, qual: 0.80, speed: 0.80, evals: 30 }
}.freeze

trust_created = 0

TRUST_PROFILES.each do |agent_name, profile|
  agent = agents[agent_name]
  next unless agent

  weights = { rel: 0.25, cost: 0.15, safety: 0.30, qual: 0.20, speed: 0.10 }
  overall = weights.sum { |dim, w| profile[dim] * w }

  score = Ai::AgentTrustScore.find_or_initialize_by(agent_id: agent.id)
  score.assign_attributes(
    account:            admin_account,
    tier:               profile[:tier],
    reliability:        profile[:rel],
    cost_efficiency:    profile[:cost],
    safety:             profile[:safety],
    quality:            profile[:qual],
    speed:              profile[:speed],
    overall_score:      overall.round(4),
    evaluation_count:   profile[:evals],
    last_evaluated_at:  Time.current,
    evaluation_history: [
      {
        score: overall.round(4),
        tier: profile[:tier],
        dimensions: {
          reliability: profile[:rel],
          cost_efficiency: profile[:cost],
          safety: profile[:safety],
          quality: profile[:qual],
          speed: profile[:speed]
        },
        evaluated_at: Time.current.iso8601
      }
    ]
  )
  score.save!
  trust_created += 1
end

Rails.logger.info "[AutonomySeed] Created/updated #{trust_created} trust scores"

# ---------------------------------------------------------------------------
# Budgets (monthly, current month)
# ---------------------------------------------------------------------------
BUDGET_PROFILES = {
  "Visual Design Assistant"          => { total: 1000,  spent: 0 },
  "Process Automation Optimizer"     => { total: 1000,  spent: 0 },
  "Powernode Documentation Specialist" => { total: 1000,  spent: 0 },
  "Powernode Project Lead"           => { total: 2500,  spent: 0 },
  "Research Analyst"          => { total: 2500,  spent: 0 },
  "Powernode DevOps Engineer"        => { total: 2500,  spent: 0 },
  "Powernode Frontend Developer"     => { total: 5000,  spent: 0 },
  "Powernode QA/Test Engineer"       => { total: 5000,  spent: 0 },
  "Powernode Backend Developer"      => { total: 5000,  spent: 0 },
  "Infrastructure Health Monitor"    => { total: 5000,  spent: 0 },
  "Legal & Compliance Analyst"       => { total: 1000,  spent: 0 },
  "Life Sciences Research Analyst"   => { total: 1000,  spent: 0 },
  "Finance Operations Analyst"       => { total: 1000,  spent: 0 },
  "Sales Operations Specialist"      => { total: 1000,  spent: 0 },
  "Customer Success Agent"           => { total: 1500,  spent: 0 },
  "Example Overseer"                 => { total: 5000,  spent: 0 }
}.freeze

period_start = Time.current.beginning_of_month
period_end   = Time.current.end_of_month

budgets_created = 0

BUDGET_PROFILES.each do |agent_name, profile|
  agent = agents[agent_name]
  next unless agent

  budget = Ai::AgentBudget.find_or_initialize_by(
    agent_id: agent.id,
    period_type: "monthly",
    period_start: period_start
  )
  budget.assign_attributes(
    account:            admin_account,
    total_budget_cents: profile[:total],
    spent_cents:        profile[:spent],
    reserved_cents:     0,
    currency:           "USD",
    period_end:         period_end
  )
  budget.save!
  budgets_created += 1
end

Rails.logger.info "[AutonomySeed] Created/updated #{budgets_created} budgets"

# ---------------------------------------------------------------------------
# Intervention Policies (default notification policies)
# ---------------------------------------------------------------------------
# Without these, InterventionPolicyService falls back to "require_approval"
# for all categories — which is wrong for informational categories like
# status_update, issue_alert, and feedback. The LLM sees the policy in
# the tool response and misinterprets it as a permission failure.

INTERVENTION_POLICIES = [
  { action_category: "status_update",  policy: "notify_and_proceed", channels: %w[notification], priority: 0 },
  { action_category: "issue_alert",    policy: "notify_and_proceed", channels: %w[notification], priority: 0 },
  { action_category: "feedback",       policy: "notify_and_proceed", channels: %w[notification], priority: 0 },
  { action_category: "escalation",     policy: "notify_and_proceed", channels: %w[notification], priority: 0 },
  { action_category: "proposal",       policy: "require_approval",   channels: %w[notification], priority: 0 },
  { action_category: "approval",       policy: "require_approval",   channels: %w[notification], priority: 0 },
].freeze

policies_created = 0

INTERVENTION_POLICIES.each do |pd|
  policy = Ai::InterventionPolicy.find_or_initialize_by(
    account: admin_account,
    scope: "global",
    action_category: pd[:action_category],
    user_id: nil,
    ai_agent_id: nil
  )
  policy.assign_attributes(
    policy: pd[:policy],
    preferred_channels: pd[:channels],
    priority: pd[:priority],
    is_active: true
  )
  policy.save!
  policies_created += 1
end

Rails.logger.info "[AutonomySeed] Created/updated #{policies_created} intervention policies"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
final_agent_count = Ai::Agent.for_account(admin_account.id).active.count
concierge_count   = Ai::Agent.for_account(admin_account.id).where(is_concierge: true).count

Rails.logger.info "[AutonomySeed] Complete!"
Rails.logger.info "[AutonomySeed]   Active agents: #{final_agent_count} (+ #{concierge_count} concierge)"
Rails.logger.info "[AutonomySeed]   Trust scores: #{Ai::AgentTrustScore.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Budgets: #{Ai::AgentBudget.where(account_id: admin_account.id).count}"

puts "\n  Autonomy Data Seeding Summary:"
puts "   Active agents: #{final_agent_count} (+ #{concierge_count} concierge)"
puts "   Trust scores: #{Ai::AgentTrustScore.where(account_id: admin_account.id).count}"
puts "   Budgets: #{Ai::AgentBudget.where(account_id: admin_account.id).count}"
puts "  Autonomy data seeding completed!"
