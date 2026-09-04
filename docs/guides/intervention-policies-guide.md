# Intervention Policies Guide

> Status: active

When to use this guide: authoring, debugging, or extending the per-action policies that govern what autonomous agents can do without asking. Hybrid audience - operators author and tune policies; backend developers register new action categories.

## Table of Contents

- [Prerequisites](#prerequisites)
- [What are intervention policies?](#what-are-intervention-policies)
- [When policies trigger](#when-policies-trigger)
- [Policy resolution rules](#policy-resolution-rules)
- [Authoring a policy](#authoring-a-policy)
- [Conditions DSL](#conditions-dsl)
- [Channel routing](#channel-routing)
- [Approval timeouts and chains](#approval-timeouts-and-chains)
- [Listing and updating policies](#listing-and-updating-policies)
- [Registering a new action category](#registering-a-new-action-category)
- [Troubleshooting](#troubleshooting)
- [Related](#related)

## Prerequisites

- `ai.intervention_policies.manage` permission (CRUD on `Ai::InterventionPolicy`)
- `ai.autonomy.manage` permission (broader autonomy posture - kill switch, duty cycles)
- `ai.autonomy.approve` permission to approve pending deferred operations from the approval queue
- MCP access via the `powernode` server (registered in `.claude/settings.json`)
- For new action categories: write access to `extensions/<name>/server/db/seeds/*.rb` and the relevant extension engine file

A working knowledge of [trust tiers](../concepts/agents-and-autonomy.md#trust-tiers) helps because the `trust_tier_minimum` condition is the most common gate.

## What are intervention policies?

`Ai::InterventionPolicy` binds an **action category** (e.g. `system.module_assign`, `system.cert_rotate`, `*`) to one of five **policies** that determine what happens when an autonomous agent attempts the action:

| Policy | Behavior |
|--------|----------|
| `auto_approve` | Action runs without human input; logged for audit |
| `notify_and_proceed` | Action runs; a notification is sent on the preferred channels |
| `require_approval` | Action becomes a deferred operation; waits for explicit approval via approval workflow |
| `silent` | Action runs without notification (most permissive; auto-promoted to `require_approval` for `critical` severity) |
| `block` | Action is denied outright; agent receives a blocked-action error |

These five values come from `Ai::InterventionPolicy::POLICIES`. The default policy when no row matches is `require_approval` - a conservative default that ensures unknown actions don't slip through.

Policies have a `scope` (one of `global`, `agent`, `action_type`) and bind to either the whole account, a specific agent (`ai_agent_id`), or a specific user (`user_id`). The most specific match wins - see [Policy resolution rules](#policy-resolution-rules).

## When policies trigger

`Ai::InterventionPolicyService#resolve` is invoked at three hot paths in the autonomy pipeline:

1. **Proposal creation** - when an agent calls `platform.create_proposal` or `platform.propose_feature`, the policy for `proposal` decides whether the proposal queues up for review or auto-approves.
2. **Escalations** - `platform.escalate` resolves against the `escalation` category; combined with the escalation's severity to route notifications.
3. **Autonomous actions** - the system and SDWAN reconcilers gate every action through their respective categories before dispatching. The Fleet Autonomy seed at `extensions/system/server/db/seeds/fleet_autonomy_agent.rb` shows the canonical pattern.

The service signature:

```ruby
service = Ai::InterventionPolicyService.new(account: account)
result = service.resolve(
  action_category: "system.module_assign",
  agent: ai_agent,
  user: triggering_user,        # optional
  severity: "warning"            # optional: info | warning | critical
)
# => { policy: "auto_approve", channels: ["notification"],
#      conditions: { "trust_tier_minimum" => "monitored" }, record: <InterventionPolicy> }
```

Two convenience methods wrap `resolve`: `auto_approve?(action_category:, ...)` and `blocked?(...)`. Callers in `ExecutionGateService` use these to short-circuit decisions.

## Policy resolution rules

### Specificity ranking

Multiple policies may match the same action category. `Ai::InterventionPolicy#specificity_key` ranks them and the highest key wins. The key is an array compared **lexicographically** — element by element, most significant first — so no element can ever be outweighed by a larger value in a later one:

```ruby
[
  user_id.present? ? 1 : 0,          # tier
  ai_agent_id.present? ? 1 : 0,      # tier
  action_category == "*" ? 0 : 1,    # a row naming the category beats a wildcard
  priority                           # tie-break WITHIN a tier
]
```

Practical ranking, at **any** priorities:

| Policy shape | Key | Wins over |
|--------------|-----|-----------|
| user + agent + specific category | `[1, 1, 1, p]` | Everything below |
| user + specific category | `[1, 0, 1, p]` | Agent and global |
| agent + specific category | `[0, 1, 1, p]` | Global |
| Global + specific category | `[0, 0, 1, p]` | Wildcard category |
| Global + wildcard `*` | `[0, 0, 0, p]` | Nothing (last resort) |

`priority` orders rows that are **otherwise identical in shape** and nothing more. Negative values are legal and useful for "fallback" wildcards.

> **This changed in IMP-6430e3a8c4a1.** The four elements above were previously *weights* summed into one integer (`priority + 10/5/2`). Because `priority` is operator-settable and unbounded it outranked the hierarchy rather than breaking ties inside it — a global `auto_approve` at priority 10 scored 12 and beat an agent's own explicit `require_approval` at priority 0, which scored 7, so a gate an operator had set on one specific agent was silently discarded. **Bumping `priority` to make a global policy outrank an agent-specific one no longer works, by design**; it was the mechanism of that fail-open. To widen or narrow one agent, write a row scoped to that agent.

Ranking is applied *after* the audience cut, which decides which rows a caller may be ranked against at all. For an agent caller that is the agent's own rows plus the scope-`global` floor — the operator path (scope `action_type`) is never admitted, at any priority:

```ruby
# server/app/services/ai/intervention_policy_service.rb
if agent
  audience = matching.select { |p| p.ai_agent_id == agent.id || p.scope == "global" }
  return default_policy if audience.empty?

  matching = audience
end
```

### Critical severity override

If `severity: "critical"` is passed to `resolve` and the winning policy is `silent`, the service promotes it to `require_approval`. This is a hard rule - critical events never pass silently.

```ruby
# server/app/services/ai/intervention_policy_service.rb
if severity == "critical" && best.policy == "silent"
  return { policy: "require_approval", channels: ["notification"], ... }
end
```

`auto_approve` is NOT promoted - an operator who explicitly auto-approves a critical category has taken responsibility.

### Daily notification limits

If the winning policy is `notify_and_proceed` and its conditions include `max_daily_notifications: N`, the service counts today's `Notification` rows for the user in category `ai`. Once the count reaches N, the policy auto-degrades to `silent` for the rest of the UTC day:

```ruby
if best.policy == "notify_and_proceed" && notification_limit_reached?(best, user)
  return { policy: "silent", channels: [], reason: "Daily notification limit reached", ... }
end
```

This prevents notification storms during reconciler bursts. Combined with the critical-severity override above, you get the right behavior automatically: routine notifications throttle to silent; critical events bypass the throttle and route to approval.

## Authoring a policy

### Anatomy of a policy

| Field | Required | Type | Meaning |
|-------|----------|------|---------|
| `scope` | yes | string | `global`, `agent`, or `action_type` - documentation hint; resolution uses `ai_agent_id` and `user_id` columns |
| `action_category` | yes | string | The action being gated (e.g. `system.module_assign`) or `*` for wildcard |
| `policy` | yes | string | One of `auto_approve`, `notify_and_proceed`, `require_approval`, `silent`, `block` |
| `ai_agent_id` | no | uuid | Narrow to one agent |
| `user_id` | no | uuid | Narrow to one user (combines with agent for max specificity) |
| `priority` | no | integer | Manual tiebreaker; default 0 |
| `preferred_channels` | no | array | `["notification", "email", "slack"]` - empty array means no preference |
| `conditions` | no | object | JSON conditions - see [Conditions DSL](#conditions-dsl) |
| `approval_chain_id` | no | uuid | Multi-step approval chain (when `policy: "require_approval"`) |
| `is_active` | no | boolean | Default `true`; set to false to disable without deleting |

### Example 1: auto-approve a low-risk action

Auto-approve fleet certificate rotation because it's idempotent and a failed rotation is recoverable on the next loop.

```
platform.create_intervention_policy(
  scope: "agent",
  ai_agent_id: "<fleet_autonomy_uuid>",
  action_category: "system.cert_rotate",
  policy: "auto_approve",
  priority: 50
)
```

This mirrors the declaration in
`extensions/system/server/app/services/system/governance/policy_declarations.rb`, which
`PolicyReconciler` writes (the agent seeds stopped upserting rows at IMP-10e4f6c3bcd2):

```ruby
FLEET_AUTONOMY_POLICIES = {
  "system.cert_rotate" => "require_approval",
  # ...
}
```

### Example 2: require approval with email + Slack channels

Critical action - architecture catalog mutation - requires approval routed through both email and Slack so the on-call channel sees it within minutes.

```
platform.create_intervention_policy(
  scope: "global",
  action_category: "system.architecture.update",
  policy: "require_approval",
  preferred_channels: ["notification", "email", "slack"],
  priority: 100,
  conditions: { "trust_tier_minimum": "trusted" }
)
```

The `trust_tier_minimum` condition means: this policy only matches when the agent is at `trusted` or `autonomous`. Below `trusted`, the policy falls through to the default `require_approval` - same outcome, but the trust tier check explicitly disqualifies low-trust agents from being subject to this routing rule.

### Example 3: agent-specific override

Narrow a global policy. Suppose `system.module_assign` is `require_approval` globally, but the Fleet Autonomy agent has earned `autonomous` tier and you want it to assign modules without asking - except during quiet hours when notifications would be missed.

```
platform.create_intervention_policy(
  scope: "agent",
  ai_agent_id: "<fleet_autonomy_uuid>",
  action_category: "system.module_assign",
  policy: "notify_and_proceed",
  preferred_channels: ["notification"],
  priority: 200,
  conditions: {
    "trust_tier_minimum": "autonomous",
    "quiet_hours": { "start": 22, "end": 6 },
    "max_daily_notifications": 5
  }
)
```

Specificity score: `200 (priority) + 5 (agent) + 2 (specific category) = 207` - this beats any global policy at priority 100.

The `quiet_hours` condition means: don't match during 22:00-06:00 UTC (server timezone). The action falls back to the global `require_approval` during that window, which queues it for morning review instead of firing a notification nobody will see.

## Conditions DSL

Conditions are a JSON object stored on the policy row. `Ai::InterventionPolicy#conditions_met?` evaluates them against the resolution context. Three condition keys are supported in code today:

| Key | Type | Meaning |
|-----|------|---------|
| `trust_tier_minimum` | string | One of `supervised`, `monitored`, `trusted`, `autonomous`. Policy matches only if the agent's tier is at or above this floor. |
| `quiet_hours` | object `{start, end}` | UTC hour range; policy does not match when `start <= current_hour < end`. Use to exclude a time window. |
| `max_daily_notifications` | integer | Used only by `notify_and_proceed` policies. Per-user daily cap; resolve auto-degrades to `silent` once reached. |

Multi-condition policy combining all three:

```json
{
  "trust_tier_minimum": "trusted",
  "quiet_hours": { "start": 22, "end": 6 },
  "max_daily_notifications": 10
}
```

All conditions are AND'd together inside `conditions_met?`. If any one returns false, the policy doesn't match and resolution moves to the next-most-specific row.

Conditions that look reasonable but are **not** implemented today: `cost_above`, `dry_run_only`, `requires_manual_review`, and arbitrary `severity` filters. The intervention policy service applies severity at resolution time (the critical override above); it doesn't read severity from `conditions`. Adding new condition keys requires changes to `Ai::InterventionPolicy#conditions_met?`; see [Registering a new action category](#registering-a-new-action-category) for the pattern.

## Channel routing

`preferred_channels` is an array stored on the policy. The notification service inspects the array and routes accordingly:

| Channel | Behavior |
|---------|----------|
| `notification` | Creates an in-app `Notification` row; lights up the notification bell |
| `email` | Sends transactional email via the configured provider |
| `slack` | Posts to the configured Slack channel for the account |

Empty array (`[]`) is treated as "no preference" - the resolution service substitutes `["notification"]` as a sane default:

```ruby
channels: best.preferred_channels.presence || %w[notification]
```

For `silent` and `block` policies, channels are ignored. For `auto_approve`, channels still fire for the audit notification (so operators see what auto-approved). For `require_approval`, the channels select which surfaces the pending deferred operation appears on.

## Approval timeouts and chains

When `policy: "require_approval"` matches, the autonomy framework creates an `Ai::DeferredOperation` and either:

- Uses the default account approval chain (single step, owner approval, 24h timeout), OR
- Uses the chain specified by `approval_chain_id` on the matched policy

Approval chains live in `Ai::ApprovalChain` - a core model (table `ai_approval_chains`) available in all modes, including core mode. A chain has steps, a `timeout_action` (`reject` or `escalate`), and a `timeout_hours` per step. The fleet autonomy seed builds a single-step 4-hour chain:

```ruby
fleet_chain = Ai::ApprovalChain.find_or_initialize_by(
  account: admin_account,
  name: "Fleet Autonomy Actions"
)
fleet_chain.assign_attributes(
  trigger_type: "autonomy_action",
  is_sequential: true,
  timeout_action: "reject",
  timeout_hours: 4,
  steps: [{ "name" => "Fleet Operator Approval", "approvers" => ["*"], "required_approvals" => 1 }]
)
fleet_chain.save!
```

Then attach it to a policy at create time:

```
platform.create_intervention_policy(
  scope: "global",
  action_category: "system.fleet_rolling_upgrade",
  policy: "require_approval",
  approval_chain_id: "<chain_uuid>",
  priority: 100
)
```

When the chain times out without approval, `timeout_action: "reject"` rejects the deferred operation; the action never executes. `timeout_action: "escalate"` advances to the next chain step. Note: there is **no dedicated approval-chain-timeout sweeper job scheduled** today - no job sweeps `Ai::ApprovalChain` `timeout_hours`. The closest scheduled enforcement is `AiEscalationTimeoutJob` (sidekiq-cron `ai_escalation_timeout`, every 15m), which auto-escalates overdue `escalation`-category items; if the worker is unhealthy, that enforcement may lag. See [ralph-loops.md#troubleshooting](../operations/ralph-loops.md#troubleshooting).

Approve or reject a pending operation:

```
platform.approve_deferred_operation(
  deferred_operation_id: "<uuid>",
  comments: "Verified the upgrade window; proceed."
)

platform.reject_deferred_operation(
  deferred_operation_id: "<uuid>",
  comments: "Defer to next window - production traffic spike right now."
)
```

The `deferred_operation_id` parameter accepts either the `Ai::DeferredOperation` UUID or the `Ai::ApprovalRequest` UUID directly - the tool resolves whichever was passed.

## Listing and updating policies

List all policies for the current account:

```
platform.list_intervention_policies()
```

Filter by agent or category:

```
platform.list_intervention_policies(
  agent_id: "<agent_uuid>",
  action_category: "system.module_assign"
)
```

Update a policy by ID:

```
platform.update_intervention_policy(
  policy_id: "<uuid>",
  policy: "auto_approve",
  priority: 150,
  conditions: { "trust_tier_minimum": "trusted" }
)
```

`update_intervention_policy` merges `conditions` into the existing JSON rather than replacing - this is intentional so you can tweak one condition without rewriting the rest. To remove a condition, set it to `null` in a manual SQL update or delete and recreate the policy.

Disable without deleting:

```
platform.update_intervention_policy(
  policy_id: "<uuid>",
  is_active: false
)
```

Delete permanently:

```
platform.delete_intervention_policy(policy_id: "<uuid>")
```

## Registering a new action category

This section is for backend developers extending the policy system to gate a new autonomous action.

`Ai::InterventionPolicy::STATIC_CATEGORIES` is the core registry. Extensions append at boot via `Ai::InterventionPolicy.register_category!("<category>")` from their engine's `after_initialize` block. The registry is thread-safe at boot (single-threaded init) and lock-free at request time.

### Steps to register a new category

1. **Pick a namespaced category name.** Use a domain prefix: `system.<action>`, `sdwan.<action>`. The wildcard `*` is reserved.

2. **Register the category from the extension engine.** Example for a hypothetical SDWAN action:

```ruby
# extensions/system/server/lib/powernode_system/engine.rb
config.after_initialize do
  Ai::InterventionPolicy.register_categories!([
    "system.sdwan.new_peer_provisioning",
    "system.sdwan.peer_revocation"
  ])
end
```

3. **Add the default policy to the owning declaration set** — never to an agent seed, which
   since IMP-10e4f6c3bcd2 writes no policy row. Edit
   `extensions/system/server/app/services/system/governance/policy_declarations.rb`:
   `SDWAN_REMEDIATION_POLICIES` for an SDWAN remediation, `FLEET_AUTONOMY_POLICIES` for the
   node-lifecycle core, and so on:

```ruby
SDWAN_REMEDIATION_POLICIES = {
  "system.sdwan.new_peer_provisioning" => "notify_and_proceed",
  "system.sdwan.peer_revocation" => "require_approval",
  # ...
}
```

4. **Gate the action in your service code.** Wrap the autonomous action with a `resolve` call:

```ruby
result = Ai::InterventionPolicyService.new(account: account).resolve(
  action_category: "system.sdwan.peer_revocation",
  agent: current_agent,
  severity: "warning"
)

case result[:policy]
when "auto_approve", "notify_and_proceed"
  execute_revocation!
when "require_approval"
  enqueue_deferred_operation!
when "block"
  log_blocked_action!
when "silent"
  execute_revocation!  # silent = run without notification
end
```

5. **Add an executor for `require_approval`.** Deferred operations carry an `executor_class` that runs after approval. The executor exposes a class method `execute(params, deferred_operation:)` (and optionally `preview(params, deferred_operation:)`); `executor_class` is constantized and the method is called synchronously by `Ai::DeferredOperation#execute_now!`. `preview` receives the operation on the same keyword so an approval card can scope any row it names to the account the gate opened the operation in — an executor that renders a caller-supplied id must resolve it through that account, never unscoped. Place it under the extension's `app/services/<extension>/ai/skills/` directory.

6. **Declare the default row.** In the system extension, declared intervention-policy
   rows have ONE writer — `System::Governance::PolicyReconciler` (proposal §5 ruling 7,
   IMP-10e4f6c3bcd2). Add the category to a `PolicyDeclarations` set rather than upserting
   it from a seed; the extension's seed orchestrator ends with a reconcile pass, so
   `rails db:seed` still installs it, and rails-start.sh reconciles on every later boot:

```bash
cd server && rails db:seed          # first install (runs the reconcile pass last)
cd server && rails system:governance:reconcile   # established install, absence only
```

Verify the category is registered:

```ruby
Ai::InterventionPolicy.category_registered?("system.sdwan.peer_revocation")
# => true
```

## Troubleshooting

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Action always requires approval despite a matching policy | Policy has `is_active: false`, or `trust_tier_minimum` excludes the agent | `platform.list_intervention_policies(action_category:)`; check `is_active` and conditions vs agent's current tier |
| Global policy isn't applying - agent-scoped policy wins instead | Resolution prefers agent-scoped matches when an agent is provided | Bump global policy's `priority` above the agent-scoped one, or delete the agent-scoped row |
| Critical actions still firing silently | `severity: "critical"` not passed to `resolve` from caller | Check the call site - severity must be threaded through from the action's service layer |
| `notify_and_proceed` flooding the on-call channel | No `max_daily_notifications` cap on the conditions | `platform.update_intervention_policy(conditions: { max_daily_notifications: 10 })` |
| New action category not gating - `resolve` returns default `require_approval` | Category not registered at boot, or seed didn't run | Verify with `Ai::InterventionPolicy.category_registered?("...")`; run `rails db:seed` |

## Related

- [../operations/agent-autonomy-operations.md](../operations/agent-autonomy-operations.md) - trust tiers (gate conditions reference these)
- [../operations/ralph-loops.md](../operations/ralph-loops.md) - autonomous loops that trigger policy resolution
- [../operations/ai-operations.md](../operations/ai-operations.md) - daily AI ops runbook
- [../concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md) - intervention policy conceptual model
- `extensions/system/server/app/services/system/governance/policy_declarations.rb` - where the system extension's rows are declared (its `PolicyReconciler` is the only writer; the agent seeds write identity, prompt, chain, trust and tool access only)
- `server/app/services/ai/intervention_policy_service.rb` - resolution algorithm
- `server/app/models/ai/intervention_policy.rb` - schema, scopes, condition evaluation

_Last verified: 2026-06-04_
