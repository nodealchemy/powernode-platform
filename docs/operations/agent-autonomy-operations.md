# Agent Autonomy Operations

> Status: active

When to use this runbook: daily trust score sweeps, post-incident demotions, promotion reviews, and account-level autonomy policy tuning. Covers the operator paths into `Ai::Agent`, `Ai::AgentTrustScore`, and the intervention policy engine that gates what trusted agents can do without asking.

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Autonomy tiers overview](#autonomy-tiers-overview)
- [Procedure - Reading the agent dashboard](#procedure---reading-the-agent-dashboard)
- [Procedure - Promoting an agent](#procedure---promoting-an-agent)
- [Procedure - Demoting an agent](#procedure---demoting-an-agent)
- [Procedure - Monitoring trust score trends](#procedure---monitoring-trust-score-trends)
- [Procedure - Configuring account policies](#procedure---configuring-account-policies)
- [Verification](#verification)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)
- [Related runbooks](#related-runbooks)

## Prerequisites

- `ai.autonomy.manage` permission (kill switch, intervention policies, duty cycles, and override paths)
- `ai.monitoring.read` permission (trust score dashboard, telemetry endpoints)
- `ai.agents.execute` permission (required by the MCP tools that mutate agent state)
- Backend running (`sudo scripts/systemd/powernode-installer.sh status` should report `powernode-backend@default` active)
- MCP access via the `powernode` streamable-http MCP server (registered in `.claude/settings.json`)
- A Rails console session for read-only model queries: `cd server && bundle exec rails console`

## When to use this

- Daily trust score sweep (see [ai-operations.md](ai-operations.md) checklist for cadence)
- After a security incident — confirm any agent involved is demoted and the demotion event is recorded
- Weekly review of promotion candidates (`promotable: true`)
- When the autonomy distribution chart shows more than 50% of agents in `supervised` tier (alert threshold)
- When auditing an account's autonomy posture before extending more capabilities

## Autonomy tiers overview

Tier names are defined in `Ai::AgentTrustScore::TIERS`. The thresholds in the table below come from `Ai::AgentTrustScore::TIER_THRESHOLDS`. See [`../concepts/agents-and-autonomy.md#trust-tiers`](../concepts/agents-and-autonomy.md#trust-tiers) for the conceptual model.

| Tier | Score range | What agents in this tier can do |
|------|------------|----------------------------------|
| `supervised` | 0.00 - 0.39 | Every action requires human approval. Default for new agents and emergency-demoted agents. |
| `monitored` | 0.40 - 0.69 | Most actions logged. Sensitive categories still gated by intervention policies. |
| `trusted` | 0.70 - 0.89 | Most actions auto-approved. High-risk and critical categories still require approval. |
| `autonomous` | 0.90 - 1.00 | Full autonomy across all non-blocked categories. Subject to emergency demotion. |

Tier is stored two places: `ai_agents.trust_level` (operator override / current effective tier) and `ai_agent_trust_scores.tier` (computed by the trust engine). The two diverge only when an operator has used `platform.set_agent_autonomy_level` since the last evaluation.

## Procedure - Reading the agent dashboard

The autonomy dashboard surfaces three panels: trust score breakdown, tier distribution, and recent demotions. Pull the raw JSON when investigating; the UI is a view over the same endpoints.

```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@powernode.org","password":"..."}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")

curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/ai/autonomy/trust_scores" | jq .
```

Sample response (annotated):

```json
{
  "success": true,
  "data": [
    {
      "id": "0193a1...",                  // ai_agent_trust_scores PK
      "agent_id": "0193a0...",            // ai_agents.id
      "agent_name": "Fleet Autonomy",
      "tier": "monitored",                // current tier
      "overall_score": 0.7405,            // weighted dimension blend
      "reliability": 0.7000,
      "cost_efficiency": 0.7000,
      "safety": 0.8500,                   // highest weight (0.30)
      "quality": 0.7000,
      "speed": 0.7000,
      "evaluation_count": 142,
      "last_evaluated_at": "2026-05-19T03:01:22Z",
      "promotable": true,                 // overall_score >= next tier threshold
      "demotable": false                  // overall_score < current tier threshold
    }
  ]
}
```

`promotable: true` with `demotable: false` is the green-light pattern for a manual promotion review. Filter by tier with `?tier=trusted` to see only candidates close to autonomous.

For a single agent's evaluation history, hit `GET /api/v1/ai/autonomy/trust_scores/:agent_id` — that variant includes `evaluation_history` (last 50 evaluations with dimension snapshots).

The dashboard's tier distribution panel groups trust scores by tier. The same data is one line in a Rails console:

```ruby
Ai::AgentTrustScore.group(:tier).count
# => { "supervised" => 2, "monitored" => 4, "trusted" => 1, "autonomous" => 0 }
```

Watch this ratio over time. The alert in [ai-operations.md](ai-operations.md) fires when `supervised / total > 0.5` for an hour - if you see that ratio drifting up across a daily sweep, investigate before the alert pages someone.

To list recent demotions from a console session:

```ruby
Ai::AgentTrustScore.all.flat_map { |s|
  (s.evaluation_history || []).select { |h| h["type"] == "emergency_demotion" }
    .map { |h| h.merge("agent_id" => s.agent_id, "agent_name" => s.agent.name) }
}.sort_by { |h| h["evaluated_at"] }.last(10)
```

Each emergency demotion record carries `reason` and `previous_tier` so you can reconstruct what happened without cross-referencing the audit log. For pre-emergency drops (slow degradation rather than violation), iterate `evaluation_history` looking for tier changes between consecutive entries:

```ruby
Ai::AgentTrustScore.find_by(agent_id: id).evaluation_history.each_cons(2)
  .select { |a, b| a["tier"] != b["tier"] }
  .map { |a, b| { from: a["tier"], to: b["tier"], at: b["evaluated_at"] } }
```

## Procedure - Promoting an agent

Promotion is a four-step gate: the trust score must already qualify, the agent must have a clean recent run, you must record a justification, and you must verify post-change.

1. Check eligibility via `platform.agent_introspect`:

```
platform.agent_introspect(agent_id: "fleet-autonomy")
```

Expected fields: `trust.tier`, `trust.overall_score`, `performance_24h.failure_rate`, `active_goals`. Promote only if `failure_rate < 5` and the agent has at least one completed goal in the last 24h.

2. Verify the trust engine agrees by checking `promotable: true` on the trust score endpoint (see dashboard procedure above).

3. Promote the agent. There are two MCP paths depending on whether you want to override the computed tier or sync the trust score record:

   - **Override only (fast path)** - sets `ai_agents.trust_level` directly. The trust engine may re-evaluate to a different tier on the next execution:

```
platform.set_agent_autonomy_level(
  agent_id: "fleet-autonomy",
  trust_level: "trusted"
)
```

   - **Sync the trust score record** - updates `ai_agent_trust_scores.tier` and dimension scores so the trust engine won't undo the change on next evaluation. Use this when you've reviewed the dimension breakdown and want to bake in the change:

```
platform.update_agent_trust_score(
  agent_id: "fleet-autonomy",
  tier: "trusted",
  overall_score: 0.78,
  reliability: 0.80,
  safety: 0.90
)
```

4. Verify with `platform.get_agent` and the dashboard endpoint. Confirm `trust_level: "trusted"` in the agent payload and `tier: "trusted"` in the trust score payload.

5. Record the promotion. Either create a learning so future operators can search the rationale:

```
platform.create_learning(
  category: "best_practice",
  title: "Promoted Fleet Autonomy to trusted tier",
  content: "After 142 evaluations and 7 days at monitored with safety >= 0.85, ..."
)
```

   ...or include the rationale in a workspace message to the on-call channel.

## Procedure - Demoting an agent

Two demotion paths exist. Use **manual demotion** for planned downgrades after policy review; use **emergency demotion** when an agent has violated a guardrail and needs to be neutered immediately.

**Manual demotion** mirrors promotion - same MCP calls, just with a lower `trust_level`:

```
platform.set_agent_autonomy_level(
  agent_id: "sdwan-manager",
  trust_level: "supervised"
)
```

After the override, the next intervention-policy resolution treats every action as requiring approval (because the conditions check `trust_tier_minimum` against the agent's tier).

**Emergency demotion** drops the agent to `supervised`, deducts 0.3 from the safety dimension, and appends an emergency record to the evaluation history. Use the autonomy controller endpoint directly because it triggers the audit trail correctly:

```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason": "Security policy violation - unauthorized credential access"}' \
  "http://localhost:3000/api/v1/ai/autonomy/trust_scores/<agent_id>/emergency_demote"
```

The backing service is `Ai::Autonomy::TrustEngineService#emergency_demote!`. From a Rails console:

```ruby
engine = Ai::Autonomy::TrustEngineService.new(account: Account.find_by(slug: "default"))
engine.emergency_demote!(agent: Ai::Agent.find(id), reason: "Security policy violation")
```

If you also need to adjust dimension scores after the emergency (for example, to mark `safety: 0.0` until a human review clears it), use `platform.update_agent_trust_score` with explicit dimension values. The trust engine's automatic re-evaluation will not push the score above the manually-set floor on the next pass.

**Restore path** after a false-positive emergency demotion: see [Rollback](#rollback).

## Procedure - Monitoring trust score trends

The weekly rollup answers two questions: which agents are degrading, and which are coasting toward stale scores?

From a Rails console session:

```ruby
# Agents whose trust score has changed in the last 7 days, newest first.
Ai::AgentTrustScore.where("last_evaluated_at > ?", 7.days.ago)
  .order(last_evaluated_at: :desc)
  .pluck(:agent_id, :tier, :overall_score, :last_evaluated_at)

# Agents that need evaluation (not evaluated in the last 24h).
Ai::AgentTrustScore.needs_evaluation.count

# Per-tier headcount.
Ai::AgentTrustScore.group(:tier).count
# => { "supervised" => 2, "monitored" => 4, "trusted" => 1, "autonomous" => 0 }
```

**Alert thresholds** (mirrors `ai-operations.md` keys with autonomy-specific framing):

| Metric | Yellow | Red |
|--------|--------|-----|
| % of agents in `supervised` tier | 30% | 50% (paging) |
| Agents needing evaluation (`needs_evaluation` scope) | 10% of fleet | 25% of fleet |
| Emergency demotion events in the last 24h | 1 | 3+ |
| Mean `safety` dimension across active agents | < 0.7 | < 0.5 |

**Escalation:** if more than 3 emergency demotions fire within a 24h window, treat as a potential coordinated incident. Trigger `platform.emergency_halt` (see [ralph-loops.md#rollback](ralph-loops.md#rollback)) while investigating, and review the security audit trail in parallel.

For a weekly trust score report covering all five dimensions, the trust score evaluation history can be aggregated to find drift patterns:

```ruby
window = 7.days.ago
Ai::AgentTrustScore.all.map { |s|
  recent = (s.evaluation_history || []).select { |h| h["evaluated_at"] && Time.parse(h["evaluated_at"]) > window }
  next if recent.size < 2
  first, last = recent.first, recent.last
  {
    agent: s.agent.name,
    safety_delta: (last.dig("dimensions", "safety") || 0) - (first.dig("dimensions", "safety") || 0),
    overall_delta: (last["score"] || 0) - (first["score"] || 0),
    evaluations: recent.size
  }
}.compact.sort_by { |r| r[:safety_delta] }
```

Agents with negative `safety_delta` over a week are candidates for proactive review even if they haven't been emergency-demoted.

## Procedure - Configuring account policies

Account-level autonomy posture is the union of three things: the default tier for new agents, the account-wide intervention policies, and the per-action `trust_tier_minimum` condition that gates sensitive actions.

To set the **default tier for new agents** at the account level, lean on the agent factory's default of `supervised` (set in `ai_agents.trust_level default: "supervised"`). The default is intentional - never lower it. Instead, raise specific agents after manual review.

Account-wide promotion floor: the trust engine's promotion requirements (10+ evaluations, 5 consecutive successes, 24h cooldown, 12h at current tier) are constants in `Ai::Autonomy::TrustEngineService`. They are not per-account configurable today - tightening or loosening them requires a code change. The hooks for per-account thresholds are sketched but not wired; check `platform.search_knowledge` for the latest status before assuming they're configurable.

To set an **account-wide promotion floor** that gates a sensitive category, create an intervention policy with `trust_tier_minimum` in conditions. Example: only let agents at `trusted` or higher auto-approve `system.module_assign`:

```
platform.create_intervention_policy(
  scope: "global",
  action_category: "system.module_assign",
  policy: "auto_approve",
  conditions: { trust_tier_minimum: "trusted" },
  priority: 100
)
```

When the policy engine resolves this category for an agent below `trusted`, `Ai::InterventionPolicy#conditions_met?` returns false, the policy doesn't match, and the default policy (`require_approval`) applies. See [intervention-policies-guide.md](../guides/intervention-policies-guide.md) for the full DSL.

To define an **account-wide quiet hours window**, attach `quiet_hours` to the conditions of `notify_and_proceed` policies so notifications are suppressed during off-hours:

```
platform.update_intervention_policy(
  policy_id: "<uuid>",
  conditions: { quiet_hours: { start: 22, end: 6 } }
)
```

## Verification

After any intervention, confirm three signals:

1. **Backend health** — `GET /api/v1/ai/monitoring/health` returns `data.healthy: true`.
2. **Autonomy dashboard** — `GET /api/v1/ai/autonomy/trust_scores` returns the new tier for the affected agent.
3. **Kill switch state** — `platform.kill_switch_status` returns `halted: false` (or `true` if you intentionally halted as part of the procedure).

Run `sudo scripts/systemd/powernode-installer.sh status` to confirm `powernode-backend@default` and `powernode-worker@default` are both active.

## Rollback

Two rollback paths cover the operator scenarios:

**Restore a tier after a mistaken demotion:**

```
platform.set_agent_autonomy_level(
  agent_id: "<agent_id>",
  trust_level: "trusted"
)

platform.update_agent_trust_score(
  agent_id: "<agent_id>",
  tier: "trusted",
  safety: 0.85
)
```

The emergency demotion's evaluation history entry stays in `ai_agent_trust_scores.evaluation_history` as an audit artifact even after restoring the tier.

**Restore agent configuration from history** (when the agent itself was modified, not just the trust score). The `Ai::Agent` model is `Auditable` - its prior state is recoverable from `Audit::Event` records:

```ruby
agent = Ai::Agent.find(id)
event = Audit::Event.where(auditable: agent).order(created_at: :desc).limit(5).each_with_index { |e, i| puts "#{i}: #{e.action} #{e.created_at} #{e.metadata}" }
# Inspect, then manually update agent fields from event.metadata["before"] payload.
```

If you've already restored the wrong revision, `platform.emergency_halt` halts all AI activity while you investigate. See [ralph-loops.md#rollback](ralph-loops.md#rollback) for the kill switch flow.

## Troubleshooting

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| `set_agent_autonomy_level` returns "Agent not found" | Identifier doesn't match a UUID, slug, or name in the current account | Use `platform.list_agents` to confirm the canonical ID |
| Agent immediately re-demoted after promotion | Trust engine recomputed tier from low dimension scores | Use `platform.update_agent_trust_score` with explicit dimension scores instead of `set_agent_autonomy_level` |
| `promotable: false` but `overall_score` meets the threshold | Trust engine cooldown (24h since last promotion) or fewer than 10 evaluations | Wait for cooldown; verify `evaluation_count >= 10` |
| Emergency demotion didn't reach the agent | Audit trail recorded but autonomy_level unchanged | Check `Ai::KillSwitchEvent` log; the kill switch may be halted, suppressing further state changes |
| Dashboard shows stale scores (`needs_evaluation` > 0) | `AiTrustScoreDecayJob` or evaluation job not running | `journalctl -u powernode-worker@default -f` and restart per [worker-operations.md](worker-operations.md) |
| Intervention policies aren't gating an agent's actions | `is_active: false` or `trust_tier_minimum` in conditions excludes the agent | `platform.list_intervention_policies(agent_id:)` and check the matched record |

## Related runbooks

- [ai-operations.md](ai-operations.md) - daily AI ops checklist and alert thresholds
- [ralph-loops.md](ralph-loops.md) - autonomous loop lifecycle (uses these trust tiers)
- [../guides/intervention-policies-guide.md](../guides/intervention-policies-guide.md) - policy authoring + DSL
- [../concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md) - trust scoring conceptual model
- [worker-operations.md](worker-operations.md) - maintenance jobs that touch trust scores

_Last verified: 2026-05-19_
