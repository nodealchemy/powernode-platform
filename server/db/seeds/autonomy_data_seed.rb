# frozen_string_literal: true

# Autonomy Data Seed
# 1. Consolidates agents from 37 → 10 (one per type, 4 providers)
# 2. Cleans up orphaned teams
# 3. Seeds trust scores, budgets, circuit breakers, fingerprints,
#    delegation policies, and telemetry events
#
# Idempotent — safe to re-run.

Rails.logger.info "[AutonomySeed] Starting autonomy data seeding..."

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
  "Process Automation Optimizer"
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
  "Powernode Documentation Specialist" => ollama_provider
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

  # Clean FK references in dependency order
  Ai::AgentTeamMember.where(ai_agent_id: delete_ids).delete_all
  Ai::TeamRole.where(ai_agent_id: delete_ids).delete_all
  Ai::ContextEntry.where(ai_agent_id: delete_ids).delete_all if defined?(Ai::ContextEntry)

  # A2A tasks: must delete child events first, then tasks
  if defined?(Ai::A2aTask)
    a2a_task_ids = Ai::A2aTask.where(to_agent_id: delete_ids)
      .or(Ai::A2aTask.where(from_agent_id: delete_ids)).pluck(:id)
    if a2a_task_ids.any?
      Ai::A2aTaskEvent.where(ai_a2a_task_id: a2a_task_ids).delete_all if defined?(Ai::A2aTaskEvent)
      Ai::A2aTask.where(id: a2a_task_ids).delete_all
    end
  end

  Ai::AgentSkill.where(ai_agent_id: delete_ids).delete_all
  Ai::AgentCard.where(ai_agent_id: delete_ids).delete_all if defined?(Ai::AgentCard)
  Ai::PersistentContext.where(ai_agent_id: delete_ids).delete_all if defined?(Ai::PersistentContext)
  Ai::Message.where(ai_agent_id: delete_ids).delete_all
  Ai::AgentConnection.where(source_type: "Ai::Agent", source_id: delete_ids).delete_all
  Ai::EncryptedMessage.where(from_agent_id: delete_ids).or(Ai::EncryptedMessage.where(to_agent_id: delete_ids)).delete_all if defined?(Ai::EncryptedMessage)

  # Nullify optional FKs
  Ai::RalphLoop.where(default_agent_id: delete_ids).update_all(default_agent_id: nil) if defined?(Ai::RalphLoop)
  Ai::Conversation.where(ai_agent_id: delete_ids).update_all(ai_agent_id: nil)
  Ai::AgentTemplate.where(source_agent_id: delete_ids).update_all(source_agent_id: nil) if defined?(Ai::AgentTemplate)

  # Cascading associations (executions, trust_scores, budgets, etc.) auto-delete
  Ai::Agent.where(id: delete_ids).destroy_all

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
  Ai::AgentTeamMember.where(ai_agent_team_id: team_ids).delete_all
  Ai::TeamRole.where(agent_team_id: team_ids).delete_all
  Ai::TeamChannel.where(agent_team_id: team_ids).delete_all if defined?(Ai::TeamChannel)
  Ai::MemoryPool.where(team_id: team_ids).delete_all if defined?(Ai::MemoryPool)
  Ai::AgentConnection.where(source_type: "Ai::AgentTeam", source_id: team_ids).delete_all

  teams_to_delete.destroy_all
  Rails.logger.info "[AutonomySeed] Deleted #{team_ids.size} orphaned teams"
end

# ===========================================================================
# STEP 2 — Seed Autonomy Data
# ===========================================================================

# Reload kept agents
agents = Ai::Agent.where(account: admin_account, name: KEEP_AGENT_NAMES)
  .index_by(&:name)

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
  "Powernode Documentation Specialist" => { tier: "supervised", rel: 0.40, cost: 0.40, safety: 0.45, qual: 0.35, speed: 0.35, evals: 8  },
  "Powernode Project Lead"           => { tier: "monitored",  rel: 0.55, cost: 0.50, safety: 0.60, qual: 0.45, speed: 0.50, evals: 12 },
  "Claude Research Analyst"          => { tier: "monitored",  rel: 0.60, cost: 0.55, safety: 0.60, qual: 0.50, speed: 0.55, evals: 15 },
  "Powernode DevOps Engineer"        => { tier: "monitored",  rel: 0.70, cost: 0.60, safety: 0.75, qual: 0.60, speed: 0.60, evals: 20 },
  "Powernode Frontend Developer"     => { tier: "trusted",    rel: 0.80, cost: 0.70, safety: 0.80, qual: 0.70, speed: 0.70, evals: 25 },
  "Powernode QA/Test Engineer"       => { tier: "trusted",    rel: 0.85, cost: 0.75, safety: 0.85, qual: 0.80, speed: 0.75, evals: 28 },
  "Powernode Backend Developer"      => { tier: "trusted",    rel: 0.90, cost: 0.80, safety: 0.90, qual: 0.85, speed: 0.80, evals: 32 },
  "Infrastructure Health Monitor"    => { tier: "trusted",    rel: 0.92, cost: 0.85, safety: 0.95, qual: 0.85, speed: 0.85, evals: 35 }
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
  # Supervised agents — $10 budget, low spend
  "Visual Design Assistant"          => { total: 1000,  spent: 50   },
  "Process Automation Optimizer"     => { total: 1000,  spent: 120  },
  "Powernode Documentation Specialist" => { total: 1000,  spent: 200  },
  # Monitored agents — $25 budget, moderate spend
  "Powernode Project Lead"           => { total: 2500,  spent: 1250 },
  "Claude Research Analyst"          => { total: 2500,  spent: 1500 },
  "Powernode DevOps Engineer"        => { total: 2500,  spent: 1750 },
  # Trusted agents — $50 budget, high spend
  "Powernode Frontend Developer"     => { total: 5000,  spent: 3800 },
  "Powernode QA/Test Engineer"       => { total: 5000,  spent: 4000 },
  "Powernode Backend Developer"      => { total: 5000,  spent: 4200 },
  # Critical utilization
  "Infrastructure Health Monitor"    => { total: 5000,  spent: 4600 }
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
# Circuit Breakers (3 — for trusted agents)
# ---------------------------------------------------------------------------
CIRCUIT_BREAKER_DATA = [
  { agent: "Powernode Backend Developer",   action: "execute_code",      state: "closed",    failure_count: 1, success_count: 12 },
  { agent: "Powernode QA/Test Engineer",    action: "execute_tool",      state: "closed",    failure_count: 0, success_count: 8  },
  { agent: "Infrastructure Health Monitor", action: "external_api_call", state: "half_open", failure_count: 3, success_count: 1  }
].freeze

cb_created = 0

CIRCUIT_BREAKER_DATA.each do |data|
  agent = agents[data[:agent]]
  next unless agent

  cb = Ai::CircuitBreaker.find_or_initialize_by(agent_id: agent.id, action_type: data[:action])
  attrs = {
    account:           admin_account,
    state:             data[:state],
    failure_count:     data[:failure_count],
    success_count:     data[:success_count],
    failure_threshold: 5,
    success_threshold: 3,
    cooldown_seconds:  300,
    history:           []
  }
  attrs[:opened_at]      = 10.minutes.ago if data[:state] == "half_open"
  attrs[:half_opened_at] = 2.minutes.ago  if data[:state] == "half_open"

  cb.assign_attributes(attrs)
  cb.save!
  cb_created += 1
end

Rails.logger.info "[AutonomySeed] Created/updated #{cb_created} circuit breakers"

# ---------------------------------------------------------------------------
# Behavioral Fingerprints (2 — for trusted agents)
# ---------------------------------------------------------------------------
FINGERPRINT_DATA = [
  { agent: "Powernode Backend Developer",   metric: "response_time_ms",    mean: 450.0, stddev: 120.0, threshold: 2.5, observations: 150, anomalies: 3 },
  { agent: "Infrastructure Health Monitor", metric: "api_calls_per_hour",  mean: 25.0,  stddev: 8.0,   threshold: 3.0, observations: 720, anomalies: 5 }
].freeze

fp_created = 0

FINGERPRINT_DATA.each do |data|
  agent = agents[data[:agent]]
  next unless agent

  fp = Ai::BehavioralFingerprint.find_or_initialize_by(agent_id: agent.id, metric_name: data[:metric])
  fp.assign_attributes(
    account:             admin_account,
    baseline_mean:       data[:mean],
    baseline_stddev:     data[:stddev],
    deviation_threshold: data[:threshold],
    rolling_window_days: 7,
    observation_count:   data[:observations],
    anomaly_count:       data[:anomalies],
    last_observation_at: Time.current
  )
  fp.save!
  fp_created += 1
end

Rails.logger.info "[AutonomySeed] Created/updated #{fp_created} behavioral fingerprints"

# ---------------------------------------------------------------------------
# Delegation Policies (2 — for trusted agents)
# ---------------------------------------------------------------------------
DELEGATION_DATA = [
  {
    agent: "Powernode Backend Developer",
    max_depth: 3,
    allowed_types: %w[assistant code_assistant],
    actions: %w[read_data execute_tool execute_code],
    budget_pct: 0.4,
    inheritance: "moderate"
  },
  {
    agent: "Powernode Frontend Developer",
    max_depth: 2,
    allowed_types: %w[assistant code_assistant],
    actions: %w[read_data execute_tool],
    budget_pct: 0.3,
    inheritance: "conservative"
  }
].freeze

dp_created = 0

DELEGATION_DATA.each do |data|
  agent = agents[data[:agent]]
  next unless agent

  dp = Ai::DelegationPolicy.find_or_initialize_by(agent_id: agent.id)
  dp.assign_attributes(
    account:              admin_account,
    max_depth:            data[:max_depth],
    allowed_delegate_types: data[:allowed_types],
    delegatable_actions:  data[:actions],
    budget_delegation_pct: data[:budget_pct],
    inheritance_policy:   data[:inheritance]
  )
  dp.save!
  dp_created += 1
end

Rails.logger.info "[AutonomySeed] Created/updated #{dp_created} delegation policies"

# ---------------------------------------------------------------------------
# Telemetry Events (3 per agent = 30 total, correlated chains)
# ---------------------------------------------------------------------------

# Clear old seed telemetry to avoid accumulation on re-runs
Ai::TelemetryEvent.where(account_id: admin_account.id)
  .where("event_data @> ?", { seed: true }.to_json)
  .delete_all

telem_created = 0

agents.each_value do |agent|
  correlation_id = SecureRandom.uuid

  # Event 1: trust_evaluated
  e1 = Ai::TelemetryEvent.create!(
    account:          admin_account,
    agent:            agent,
    event_category:   "trust",
    event_type:       "trust_evaluated",
    sequence_number:  0,
    correlation_id:   correlation_id,
    event_data:       { seed: true, agent_name: agent.name, action: "periodic_evaluation" },
    outcome:          "success"
  )

  # Event 2: capability_checked (child of e1)
  e2 = Ai::TelemetryEvent.create!(
    account:          admin_account,
    agent:            agent,
    event_category:   "action",
    event_type:       "capability_checked",
    sequence_number:  1,
    parent_event_id:  e1.id,
    correlation_id:   correlation_id,
    event_data:       { seed: true, agent_name: agent.name, capability: "execute_tool", result: "allowed" },
    outcome:          "success"
  )

  # Event 3: budget_checked (child of e2)
  Ai::TelemetryEvent.create!(
    account:          admin_account,
    agent:            agent,
    event_category:   "budget",
    event_type:       "budget_checked",
    sequence_number:  2,
    parent_event_id:  e2.id,
    correlation_id:   correlation_id,
    event_data:       { seed: true, agent_name: agent.name, budget_remaining_cents: 1000 },
    outcome:          "success"
  )

  telem_created += 3
end

Rails.logger.info "[AutonomySeed] Created #{telem_created} telemetry events"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
final_agent_count = Ai::Agent.where(account: admin_account).active.count
concierge_count   = Ai::Agent.where(account: admin_account, is_concierge: true).count

Rails.logger.info "[AutonomySeed] Complete!"
Rails.logger.info "[AutonomySeed]   Active agents: #{final_agent_count} (+ #{concierge_count} concierge)"
Rails.logger.info "[AutonomySeed]   Trust scores: #{Ai::AgentTrustScore.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Budgets: #{Ai::AgentBudget.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Circuit breakers: #{Ai::CircuitBreaker.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Fingerprints: #{Ai::BehavioralFingerprint.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Delegation policies: #{Ai::DelegationPolicy.where(account_id: admin_account.id).count}"
Rails.logger.info "[AutonomySeed]   Telemetry events: #{Ai::TelemetryEvent.where(account_id: admin_account.id).count}"

puts "\n🤖 Autonomy Data Seeding Summary:"
puts "   Active agents: #{final_agent_count} (+ #{concierge_count} concierge)"
puts "   Trust scores: #{Ai::AgentTrustScore.where(account_id: admin_account.id).count}"
puts "   Budgets: #{Ai::AgentBudget.where(account_id: admin_account.id).count}"
puts "   Circuit breakers: #{Ai::CircuitBreaker.where(account_id: admin_account.id).count}"
puts "   Fingerprints: #{Ai::BehavioralFingerprint.where(account_id: admin_account.id).count}"
puts "   Delegation policies: #{Ai::DelegationPolicy.where(account_id: admin_account.id).count}"
puts "   Telemetry events: #{Ai::TelemetryEvent.where(account_id: admin_account.id).count}"
puts "✅ Autonomy data seeding completed!"
