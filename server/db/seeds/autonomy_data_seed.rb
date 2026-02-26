# frozen_string_literal: true

# Autonomy Data Seed
# 1. Consolidates agents from 37 → 10 (one per type, 4 providers)
# 2. Cleans up orphaned teams
# 3. Seeds trust scores and budgets for kept agents
#
# Idempotent — safe to re-run.

Rails.logger.info "[AutonomySeed] Starting autonomy data seeding..."

# Helper: recursively clean all FK references to rows being deleted from a table.
# Prevents FK violations regardless of how many cascading references exist.
def clean_fk_references_for(table_name, ids_to_delete, conn: ActiveRecord::Base.connection, visited: Set.new)
  return if ids_to_delete.empty?
  return if visited.include?(table_name)
  visited.add(table_name)

  quoted_ids = ids_to_delete.map { |id| conn.quote(id) }.join(",")

  # Find all tables that reference this table via FK
  refs = conn.execute(<<~SQL)
    SELECT kcu.table_name AS from_table, kcu.column_name AS from_column
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = '#{table_name}'
  SQL

  refs.each do |ref|
    child_table  = ref["from_table"]
    child_column = ref["from_column"]
    next if child_table == table_name # skip self-references

    col_info = conn.columns(child_table).find { |c| c.name == child_column }

    if col_info&.null
      conn.execute("UPDATE #{conn.quote_table_name(child_table)} SET #{conn.quote_column_name(child_column)} = NULL WHERE #{conn.quote_column_name(child_column)} IN (#{quoted_ids})")
    else
      # Before deleting child rows, recursively clean THEIR dependents
      child_ids = conn.execute("SELECT id FROM #{conn.quote_table_name(child_table)} WHERE #{conn.quote_column_name(child_column)} IN (#{quoted_ids})").map { |r| r["id"] }
      clean_fk_references_for(child_table, child_ids, conn: conn, visited: visited) if child_ids.any?
      conn.execute("DELETE FROM #{conn.quote_table_name(child_table)} WHERE #{conn.quote_column_name(child_column)} IN (#{quoted_ids})")
    end
  end
end

admin_account = Account.find_by(name: "Powernode Admin")
admin_user    = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  Rails.logger.warn "[AutonomySeed] Admin account/user not found — skipping"
  return
end

# ===========================================================================
# STEP 1 — Agent Consolidation
# ===========================================================================
KEEP_AGENT_NAMES = [
  "Powernode Project Lead",
  "Powernode Backend Developer",
  "Powernode Frontend Developer",
  "Powernode QA/Test Engineer",
  "Powernode DevOps Engineer",
  "Powernode Documentation Specialist",
  "Claude Research Analyst",
  "Visual Design Assistant",
  "Infrastructure Health Monitor",
  "Process Automation Optimizer",
  "Legal & Compliance Analyst",
  "Life Sciences Research Analyst",
  "Finance Operations Analyst",
  "Sales Operations Specialist",
  "Customer Success Agent"
].freeze

# Ensure the 4 extra agents exist (they may not have been created by earlier seeds)
openai_provider   = Ai::Provider.find_by(provider_type: "openai")
grok_provider     = Ai::Provider.find_by(provider_type: "custom")     # Grok is custom type
claude_provider   = Ai::Provider.find_by(provider_type: "anthropic")
ollama_provider   = Ai::Provider.find_by(provider_type: "ollama")

extra_agents = [
  {
    name: "Visual Design Assistant",
    slug: "visual-design-assistant",
    agent_type: "image_generator",
    provider: openai_provider,
    description: "Visual design and image generation assistant using DALL-E capabilities"
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
    agent_type: "workflow_optimizer",
    provider: grok_provider,
    description: "Workflow optimization agent that analyzes and improves automated processes for efficiency and reliability"
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

extra_agents.each do |ad|
  next unless ad[:provider]

  Ai::Agent.find_or_create_by!(account: admin_account, name: ad[:name]) do |a|
    a.slug        = ad[:slug]
    a.agent_type  = ad[:agent_type]
    a.provider    = ad[:provider]
    a.creator     = admin_user
    a.status      = "active"
    a.version     = "1.0.0"
    a.description = ad[:description]
  end
end

# Reassign providers for the dev team agents to match the plan
provider_assignments = {
  "Powernode Project Lead"       => grok_provider,
  "Powernode Frontend Developer" => grok_provider,
  "Powernode DevOps Engineer"    => grok_provider,
  "Process Automation Optimizer" => grok_provider,
  "Powernode Backend Developer"  => claude_provider,
  "Claude Research Analyst"      => claude_provider,
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

  agent = Ai::Agent.find_by(account: admin_account, name: agent_name)
  if agent && agent.ai_provider_id != provider.id
    agent.update_columns(ai_provider_id: provider.id)
  end
end

# Identify agents to delete
keep_ids = Ai::Agent.where(account: admin_account, name: KEEP_AGENT_NAMES).pluck(:id)
delete_ids = Ai::Agent.where(account: admin_account)
  .where.not(id: keep_ids)
  .where.not(is_concierge: true) # Never delete the concierge agent
  .pluck(:id)

if delete_ids.any?
  Rails.logger.info "[AutonomySeed] Deleting #{delete_ids.size} agents and cleaning FK references..."

  clean_fk_references_for("ai_agents", delete_ids)
  Ai::Agent.where(id: delete_ids).delete_all

  Rails.logger.info "[AutonomySeed] Deleted #{delete_ids.size} agents"
end

# ===========================================================================
# STEP 1b — Team Cleanup
# ===========================================================================
KEEP_TEAM_NAMES = ["Powernode Development Team", "Architecture Review Board"].freeze

teams_to_delete = Ai::AgentTeam.where(account: admin_account)
  .where.not(name: KEEP_TEAM_NAMES)

if teams_to_delete.any?
  team_ids = teams_to_delete.pluck(:id)

  clean_fk_references_for("ai_agent_teams", team_ids)
  Ai::AgentTeam.where(id: team_ids).delete_all

  Rails.logger.info "[AutonomySeed] Deleted #{team_ids.size} orphaned teams"
end

# ===========================================================================
# STEP 2 — Seed Trust Scores and Budgets
# ===========================================================================

# Reload kept agents
agents = Ai::Agent.where(account: admin_account, name: KEEP_AGENT_NAMES)
  .index_by(&:name)

# Also include the concierge agent
concierge = Ai::Agent.find_by(account: admin_account, is_concierge: true)
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
  "Claude Research Analyst"          => { tier: "monitored",  rel: 0.60, cost: 0.55, safety: 0.60, qual: 0.50, speed: 0.55, evals: 15 },
  "Powernode DevOps Engineer"        => { tier: "monitored",  rel: 0.70, cost: 0.60, safety: 0.75, qual: 0.60, speed: 0.60, evals: 20 },
  "Powernode Frontend Developer"     => { tier: "trusted",    rel: 0.80, cost: 0.70, safety: 0.80, qual: 0.70, speed: 0.70, evals: 25 },
  "Powernode QA/Test Engineer"       => { tier: "trusted",    rel: 0.85, cost: 0.75, safety: 0.85, qual: 0.80, speed: 0.75, evals: 28 },
  "Powernode Backend Developer"      => { tier: "trusted",    rel: 0.90, cost: 0.80, safety: 0.90, qual: 0.85, speed: 0.80, evals: 32 },
  "Infrastructure Health Monitor"    => { tier: "trusted",    rel: 0.92, cost: 0.85, safety: 0.95, qual: 0.85, speed: 0.85, evals: 35 },
  "Legal & Compliance Analyst"       => { tier: "supervised", rel: 0.30, cost: 0.40, safety: 0.50, qual: 0.35, speed: 0.30, evals: 3  },
  "Life Sciences Research Analyst"   => { tier: "supervised", rel: 0.25, cost: 0.80, safety: 0.35, qual: 0.25, speed: 0.40, evals: 3  },
  "Finance Operations Analyst"       => { tier: "supervised", rel: 0.30, cost: 0.80, safety: 0.45, qual: 0.30, speed: 0.40, evals: 3  },
  "Sales Operations Specialist"      => { tier: "supervised", rel: 0.25, cost: 0.50, safety: 0.30, qual: 0.25, speed: 0.35, evals: 3  },
  "Customer Success Agent"           => { tier: "supervised", rel: 0.30, cost: 0.50, safety: 0.35, qual: 0.30, speed: 0.40, evals: 3  }
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
  "Claude Research Analyst"          => { total: 2500,  spent: 0 },
  "Powernode DevOps Engineer"        => { total: 2500,  spent: 0 },
  "Powernode Frontend Developer"     => { total: 5000,  spent: 0 },
  "Powernode QA/Test Engineer"       => { total: 5000,  spent: 0 },
  "Powernode Backend Developer"      => { total: 5000,  spent: 0 },
  "Infrastructure Health Monitor"    => { total: 5000,  spent: 0 },
  "Legal & Compliance Analyst"       => { total: 1000,  spent: 0 },
  "Life Sciences Research Analyst"   => { total: 1000,  spent: 0 },
  "Finance Operations Analyst"       => { total: 1000,  spent: 0 },
  "Sales Operations Specialist"      => { total: 1000,  spent: 0 },
  "Customer Success Agent"           => { total: 1500,  spent: 0 }
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
# Summary
# ---------------------------------------------------------------------------
final_agent_count = Ai::Agent.where(account: admin_account).active.count
concierge_count   = Ai::Agent.where(account: admin_account, is_concierge: true).count

Rails.logger.info "[AutonomySeed] Complete!"
Rails.logger.info "[AutonomySeed]   Active agents: #{final_agent_count} (+ #{concierge_count} concierge)"
Rails.logger.info "[AutonomySeed]   Trust scores: #{Ai::AgentTrustScore.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Budgets: #{Ai::AgentBudget.where(account_id: admin_account.id).count}"

puts "\n  Autonomy Data Seeding Summary:"
puts "   Active agents: #{final_agent_count} (+ #{concierge_count} concierge)"
puts "   Trust scores: #{Ai::AgentTrustScore.where(account_id: admin_account.id).count}"
puts "   Budgets: #{Ai::AgentBudget.where(account_id: admin_account.id).count}"
puts "  Autonomy data seeding completed!"
