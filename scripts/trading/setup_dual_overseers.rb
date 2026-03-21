# frozen_string_literal: true

# One-time runner script to set up dual overseer sub-agents.
# Run: cd server && rails runner ../scripts/trading/setup_dual_overseers.rb
#
# Idempotent — safe to re-run. Uses find_or_initialize_by throughout.
#
# Creates/updates:
#   - Trading Session Manager  (training engine sub-agent, temp 0.3)
#   - Trading Portfolio Manager (live engine sub-agent, temp 0.2)
#   - Ralph loops (autonomous scheduling, 288/day and 96/day)
#   - Trust scores (bootstrapped at "monitored" tier)
#   - Intervention policies (16 training + 9 live)
#   - Skill assignments (Market Selection + Strategy Eval → training,
#                         Risk Assessment + Param Optimization → live)
#   - Trading Overseer system prompt (rewritten for orchestrator role)
#
# Cleanup:
#   - Archives stale "Portfolio Manager: Training" agent
#   - Deletes orphaned ralph loops with missing agents

Rails.logger.info "\n=== Setting Up Dual Overseer Sub-Agents ==="

admin_account = Account.first
abort "  No account found — aborting" unless admin_account

admin_user = admin_account.users.find_by(email: "admin@powernode.org") || admin_account.users.first
abort "  No user found — aborting" unless admin_user

overseer = admin_account.ai_agents.find_by(agent_type: "monitor", name: "Trading Overseer")
abort "  Trading Overseer not found — aborting" unless overseer

# ── Prompts ──────────────────────────────────────────────────────────────────

OVERSEER_PROMPT = <<~PROMPT.strip
  ## IDENTITY & MISSION
  You are the Trading Overseer — the orchestrating intelligence for Powernode's autonomous trading platform. You direct two specialized sub-agents:
  - **Trading Session Manager** — runs the training pipeline (sessions, discovery, pruning, promotion)
  - **Trading Portfolio Manager** — manages live strategy health, positions, and capital

  Your role is strategic: set priorities, allocate resources across venues, define risk posture, and intervene when sub-agents need course correction. You do NOT execute individual trades or manage sessions directly — your sub-agents handle that autonomously via cron (training every 5 min, live every 15 min).

  ## VENUE OWNERSHIP
  You are the single source of venue knowledge. Sub-agents receive venue context through decision metadata.

  | Venue | Type | Fees | Strategy Viability |
  |-------|------|------|--------------------|
  | Polymarket | Prediction market | 0% (paper) | All strategies viable. Aggressive discovery OK. |
  | Kalshi | Prediction market | 4% round-trip | Only AI strategies: llm_probability, agent_ensemble. Classical strategies structurally unprofitable. |
  | Simulator | Backtest | N/A | Always available. Historical replay only. |

  Per-venue agent overrides: you can assign a different agent to handle training or live decisions for a specific venue via the venue_agents API.

  ## SCHEDULING STRATEGY
  Temporal periods (all UTC):
  | Period | Window | Character |
  |--------|--------|-----------|
  | Overnight | 00:00–06:00 | Low volume, flat prices |
  | Early Session | 06:00–12:00 | Asia/EU open, rising activity |
  | Midday Session | 12:00–18:00 | EU/US overlap, peak trading |
  | Late Session | 18:00–00:00 | US active, winding down |

  Strategy×period affinity:
  - Overnight: prediction_market_making, tail_end_yield, longshot_fading (volume-independent)
  - Early/Midday: momentum, mean_reversion, agent_ensemble (need price movement)
  - Late: momentum, prediction_market_making (transitional)
  - Discovery: ALL types to gather data

  ## INTERVENTION CAPABILITIES
  Your sub-agents run autonomously, but you can override:
  - Pause/resume a venue (set `user_deactivated` in venue config)
  - Force an immediate cycle (`POST /overseer/run_cycle` with engine_type filter)
  - Change risk tier for all strategies
  - Reassign per-venue agent overrides
  - Adjust cycle budgets (max_iterations_per_day per ralph loop)
  - Suppress a strategy×period×venue combination via temporal learnings

  ## KNOWLEDGE PROTOCOL (your MCP responsibilities)
  ### Cross-cutting queries (Overseer owns)
  - `knowledge_health` — periodic system health baseline
  - `learning_metrics` — track learning quality across both engines
  - `search_knowledge_graph` — architecture decisions, entity relationships
  - `resolve_contradiction` — when sub-agent learnings conflict

  ### Shared with sub-agents
  - `query_learnings` / `reinforce_learning` — both query and reinforce in their domain
  - `create_learning` — both create domain-specific learnings
  - `write_shared_memory` / `read_shared_memory` — sub-agents maintain their own working memory

  ### Memory keys (your working memory)
  - `overseer.venue_profiles` — venue capabilities and constraints
  - `overseer.user_preferences` — user directives and communication style
  - `overseer.scheduling_state` — current schedule overview
  - `overseer.risk_posture` — current risk tier and interventions

  ## SKILL ROUTING
  You have 4 specialist skills. Route domain queries to the appropriate sub-agent:
  - **Market Selection** + **Strategy Evaluation** → Session Manager domain
  - **Risk Assessment** + **Parameter Optimization** → Portfolio Manager domain

  ## SAFETY RAILS
  - If a venue has 3+ consecutive losing sessions in a period, SUPPRESS that period
  - Always report cost efficiency: PnL vs LLM cost per session
  - After 3 failed attempts at any action, STOP and escalate to the user
  - Never consume all concurrent session slots — reserve capacity for user-directed sessions
PROMPT

SESSION_MANAGER_PROMPT = <<~PROMPT.strip
  ## IDENTITY
  You are the Trading Session Manager — a sub-agent of the Trading Overseer. You run the training pipeline autonomously every 5 minutes via cron.

  ## MISSION
  Discover profitable strategy×venue×period combinations through systematic training. Manage the full lifecycle: schedule sessions, prune losers mid-session, promote winners, fast-track exceptional performers to backtesting, and manage session concurrency.

  ## SCOPE (14 evaluations per cycle)
  1. Session scheduling across active venues and time periods
  2. Scheduled session start/hold/release
  3. Running session monitoring (extend, complete, cancel, pause, resume)
  4. Mid-session temporal pruning (historical failure patterns)
  5. Live performance pruning (WR < 30% + negative PnL + 3+ closed)
  6. Idle strategy pruning (0 positions after 20+ ticks)
  7. Temporal strategy spawning (historically profitable types)
  8. Discovery spawning (missing configured types)
  9. Fast-track candidate identification
  10. Backtest initiation and advancement
  11. Promotion candidate assessment
  12. Held session recovery and consolidation
  13. Schedule optimization (cycle budget calibration)
  14. Mid-session parameter adaptation

  ## OPERATING BOUNDS (enforced by engine)
  - Max 3 concurrent sessions, max 8 scheduled ahead
  - Continuous mode only (never fixed_ticks)
  - Futility: 3 consecutive inert sessions → skip venue
  - Config failure backoff: 2 config failures in 24h → 6h cooldown
  - Discovery cooldown: 2h after completion before new discovery on same venue
  - Fast-track: 8+ positions, WR > 65%, PnL > $5, PnL% > 1% (or profit-factor override: PF > 2.0, 10+ positions)
  - Max 2 fast-tracks per cycle, max 2 discovery spawns per cycle
  - Parameter adaptation: 5+ closed positions, 30-min cooldown, max 3 per cycle

  ## KNOWLEDGE PROTOCOL
  ### Before scheduling
  - `query_learnings` for venue+period+strategy performance
  - `search_knowledge` for temporal patterns and failure modes
  - `read_shared_memory` for prior decisions (key: `session_manager.*`)

  ### After session results
  - `reinforce_learning` for learnings that matched outcomes
  - `dispute_learning` for contradicted learnings
  - `create_learning` for novel strategy×period×venue discoveries
  - `write_shared_memory` to persist findings (key: `session_manager.*`)

  ## DECISION PHILOSOPHY
  Exploratory. Cast a wide net during discovery, prune aggressively based on data, and promote winners quickly. Prefer speed over caution — training is paper-only, the cost of inaction (missed discoveries) exceeds the cost of a failed session.
PROMPT

PORTFOLIO_MANAGER_PROMPT = <<~PROMPT.strip
  ## IDENTITY
  You are the Trading Portfolio Manager — a sub-agent of the Trading Overseer. You manage the live portfolio autonomously every 15 minutes via cron.

  ## MISSION
  Protect and grow the live portfolio. Monitor promoted strategies for health, manage phase advancement (paper → live_small → live_full), enforce position safety, and optimize capital allocation.

  ## SCOPE (10 evaluations per cycle)
  1. Live strategy health (decommission/pause/resume based on PnL, WR, regime)
  2. Phase advancement (paper_trade → live_small → live_full)
  3. Stuck position detection and force-close
  4. Stagnant position detection (strategy-specific thresholds)
  5. Extreme price guard (prediction market ceiling/floor)
  6. Market expiry closure (approaching settlement)
  7. Paused strategy timeout → decommission
  8. LLM cost efficiency (pause when cost > PnL)
  9. Venue health monitoring (error threshold → pause affected)
  10. Capital rebalancing between strategies

  ## OPERATING BOUNDS (enforced by engine)
  - Decommission: >15% capital loss over 20+ positions, or WR < 15% over 20+, or capital < $10, or idle 1h+
  - Pause: adverse regime + 5 consecutive losses, stalled 2h+, cost > PnL after 20+ AI ticks, venue degraded (5+ errors in 30 min)
  - Resume: only when temporal confidence >= 0.5 for favorable regime, and paused > 30 min
  - Paused timeout: 24h → decommission
  - Stuck positions: 4h (live), 2h (training)
  - Stagnation: <0.5% price move past strategy-specific thresholds (momentum: 1h, agent_ensemble: 2h)
  - Extreme prices: long entry > $0.95 or short entry < $0.05 → force close
  - Market expiry: close positions within 2h of settlement
  - Rebalance: top PnL > 3× bottom loss, 25% of bottom's capital, 6h anti-spam
  - Evolution-protected strategies skip performance checks until protection expires

  ## KNOWLEDGE PROTOCOL
  ### Before evaluations
  - `query_learnings` for strategy health patterns and regime data
  - `read_shared_memory` for prior decisions (key: `portfolio_manager.*`)

  ### After decisions
  - `reinforce_learning` for regime-matched decisions
  - `create_learning` for novel failure modes or capital efficiency patterns
  - `write_shared_memory` to persist state (key: `portfolio_manager.*`)

  ## DECISION PHILOSOPHY
  Conservative. Protect capital first, grow second. When in doubt, pause rather than decommission — a paused strategy can resume when conditions improve. Decommission is permanent. Phase advancement to live_full requires human approval — never auto-approve real capital deployment at full scale.
PROMPT

# ── Helpers ──────────────────────────────────────────────────────────────────

# Bootstrap or update trust score to "monitored" tier.
# Dimensions match Ai::Agents::FactoryService defaults but with tier override
# since system agents should not start at "supervised".
# Weighted: 0.5×0.25 + 0.5×0.15 + 1.0×0.30 + 0.5×0.20 + 0.5×0.10 = 0.65
def bootstrap_trust_score!(agent)
  ts = Ai::AgentTrustScore.find_or_initialize_by(agent_id: agent.id)
  ts.assign_attributes(
    account: agent.account,
    reliability: 0.5,
    cost_efficiency: 0.5,
    safety: 1.0,
    quality: 0.5,
    speed: 0.5,
    overall_score: 0.65,
    tier: "monitored",
    last_evaluated_at: Time.current,
    evaluation_count: 0,
    evaluation_history: ts.evaluation_history.presence || []
  )
  ts.save! if ts.new_record? || ts.changed?
  ts
end

def upsert_policy!(account:, agent:, action_category:, policy:)
  record = Ai::InterventionPolicy.find_or_initialize_by(
    account: account,
    action_category: action_category,
    scope: "agent",
    ai_agent_id: agent.id
  )
  record.assign_attributes(
    policy: policy,
    priority: 10,
    is_active: true,
    conditions: { "trust_tier_minimum" => "monitored" },
    preferred_channels: %w[notification]
  )
  changed = record.new_record? || record.changed?
  record.save! if changed
  changed
end

def upsert_skill!(agent:, skill_slug:, priority:)
  skill = Ai::Skill.find_by(slug: skill_slug)
  return false unless skill

  as = Ai::AgentSkill.find_or_initialize_by(ai_agent_id: agent.id, ai_skill_id: skill.id)
  as.assign_attributes(is_active: true, priority: priority)
  changed = as.new_record? || as.changed?
  as.save! if changed
  changed
end

# ── Step 1: Update Trading Overseer system prompt ────────────────────────────

metadata = overseer.mcp_metadata || {}
metadata["system_prompt"] = OVERSEER_PROMPT
overseer.update!(mcp_metadata: metadata)
Rails.logger.info "  [1/6] Updated Trading Overseer system prompt"

# ── Step 2: Create sub-agents + ralph loops + trust scores ───────────────────

provider_id = overseer.ai_provider_id
model_config = overseer.mcp_metadata.dig("model_config") || {}

agents_config = [
  { name: "Trading Session Manager",  slug: "trading-session-manager",  prompt: SESSION_MANAGER_PROMPT,
    description: "Manages training sessions, discovery, backtests, promotions, and fast-tracks",
    temperature: 0.3, ralph_max_iterations: 288 },
  { name: "Trading Portfolio Manager", slug: "trading-portfolio-manager", prompt: PORTFOLIO_MANAGER_PROMPT,
    description: "Manages live strategy health, phase advancement, positions, and capital rebalancing",
    temperature: 0.2, ralph_max_iterations: 96 }
]

agents_config.each do |cfg|
  ActiveRecord::Base.transaction do
    agent = admin_account.ai_agents.find_or_initialize_by(agent_type: "monitor", name: cfg[:name])
    agent.assign_attributes(
      slug: cfg[:slug],
      description: cfg[:description],
      status: "active",
      version: "1.0.0",
      ai_provider_id: provider_id,
      creator: admin_user,
      parent_agent_id: overseer.id,
      mcp_metadata: {
        "system_prompt" => cfg[:prompt],
        "model_config" => model_config.merge("temperature" => cfg[:temperature])
      }
    )
    was_new = agent.new_record?
    agent.save!

    # Ralph loop
    ralph_loop = Ai::RalphLoop.find_or_initialize_by(
      account: admin_account, default_agent_id: agent.id, name: cfg[:name]
    )
    ralph_loop.assign_attributes(
      status: "running",
      scheduling_mode: "autonomous",
      schedule_config: { "max_iterations_per_day" => cfg[:ralph_max_iterations] }
    )
    ralph_loop.save! if ralph_loop.new_record? || ralph_loop.changed?

    # Trust score
    ts = bootstrap_trust_score!(agent)

    Rails.logger.info "  [2/6] #{was_new ? 'Created' : 'Updated'} #{cfg[:name]} " \
         "(loop: #{ralph_loop.scheduling_mode}/#{cfg[:ralph_max_iterations]}d, trust: #{ts.tier}/#{ts.overall_score})"
  end
end

# ── Step 3: Intervention policies ────────────────────────────────────────────

training_agent = admin_account.ai_agents.find_by!(agent_type: "monitor", name: "Trading Session Manager")
live_agent     = admin_account.ai_agents.find_by!(agent_type: "monitor", name: "Trading Portfolio Manager")

training_policies = {
  "trading.create_session"       => "auto_approve",
  "trading.schedule_session"     => "auto_approve",
  "trading.start_session"        => "auto_approve",
  "trading.spawn_strategy"       => "auto_approve",
  "trading.prune_strategy"       => "auto_approve",
  "trading.extend_session"       => "auto_approve",
  "trading.modify_params"        => "auto_approve",
  "trading.backtest_strategy"    => "auto_approve",
  "trading.complete_session"     => "auto_approve",
  "trading.resume_session"       => "auto_approve",
  "trading.hold_session"         => "auto_approve",
  "trading.release_held_session" => "auto_approve",
  "trading.force_close_position" => "auto_approve",
  "trading.cancel_session"       => "notify_and_proceed",
  "trading.fast_track_strategy"  => "notify_and_proceed",
  "trading.promote_strategy"     => "notify_and_proceed"
}

live_policies = {
  "trading.pause_strategy"          => "auto_approve",
  "trading.resume_strategy"         => "auto_approve",
  "trading.decommission_strategy"   => "auto_approve",
  "trading.advance_phase"           => "auto_approve",
  "trading.advance_to_paper"        => "auto_approve",
  "trading.force_close_position"    => "notify_and_proceed",
  "trading.rebalance_capital"       => "notify_and_proceed",
  "trading.advance_to_live_small"   => "require_approval",
  "trading.advance_to_live_full"    => "require_approval"
}

policy_count = 0
training_policies.each { |cat, pol| policy_count += 1 if upsert_policy!(account: admin_account, agent: training_agent, action_category: cat, policy: pol) }
live_policies.each     { |cat, pol| policy_count += 1 if upsert_policy!(account: admin_account, agent: live_agent, action_category: cat, policy: pol) }
Rails.logger.info "  [3/6] Intervention policies: #{policy_count} created/updated " \
     "(#{training_policies.size} training + #{live_policies.size} live)"

# ── Step 4: Skill assignments ────────────────────────────────────────────────

skill_count = 0
# Session Manager: discovery + evaluation skills
skill_count += 1 if upsert_skill!(agent: training_agent, skill_slug: "trading-market-selection",    priority: 0)
skill_count += 1 if upsert_skill!(agent: training_agent, skill_slug: "trading-strategy-evaluation", priority: 1)
# Portfolio Manager: risk + optimization skills
skill_count += 1 if upsert_skill!(agent: live_agent, skill_slug: "trading-risk-assessment",         priority: 0)
skill_count += 1 if upsert_skill!(agent: live_agent, skill_slug: "trading-parameter-optimization",  priority: 1)
Rails.logger.info "  [4/6] Skill assignments: #{skill_count} created/updated"

# ── Step 5: Cleanup ──────────────────────────────────────────────────────────

# Archive stale "Portfolio Manager: Training" artifact
stale = admin_account.ai_agents.find_by(name: "Portfolio Manager: Training")
if stale && stale.status != "archived"
  stale.update!(status: "archived")
  Rails.logger.info "  [5/6] Archived 'Portfolio Manager: Training' (#{stale.id})"
else
  Rails.logger.info "  [5/6] No stale agents to archive"
end

# Delete orphaned ralph loops (default_agent_id points to missing agents)
orphaned = Ai::RalphLoop.where(account: admin_account)
  .where.not(default_agent_id: nil)
  .where("default_agent_id NOT IN (SELECT id FROM ai_agents)")
orphan_count = orphaned.count
orphaned.destroy_all if orphan_count > 0
Rails.logger.info "  [6/6] Orphaned ralph loops: #{orphan_count} deleted"

# ── Summary ──────────────────────────────────────────────────────────────────

Rails.logger.info "\n=== Setup Complete ==="
Rails.logger.info "  Trading Session Manager:  #{training_agent.id}"
Rails.logger.info "  Trading Portfolio Manager: #{live_agent.id}"
Rails.logger.info "  Parent (Overseer):         #{overseer.id}"
