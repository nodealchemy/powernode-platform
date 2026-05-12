# Concierge Routing + Meta-Skill Creation

**Status**: Design draft (2026-05-12)
**Scope**: Powernode Assistant front-door routing; agent-of-agents direction; meta-skill creation via tool recipes.
**Author**: Everett C. Haimes III

## Problem statement

The platform-wide concierge agent ("Powernode Assistant") doesn't answer platform-aware questions well. Empirically (smoke test 2026-05-12, 10 representative queries):

- 7 of 10 queries return wrong answers, generic-training-data fallback, or confidently-wrong domain matches (e.g., "NodeModule from nginx" → `npm init` recipe).
- 3 of 7 wrong answers are **wrong-negatives** — confidently asserting a resource doesn't exist when it does (e.g., "redis-server not in catalog" when it is).
- Wrong-negatives are the worst failure mode because they break operator trust: operators stop checking the platform's actual state because the assistant said it's empty.

The root cause is **tool surface mismatch**. Powernode Assistant has access to general-knowledge tools (`search_knowledge`, `search_documents`) and a small set of platform skills (productivity, knowledge-curator, etc.). It has *no access* to the extension specialists' tool surfaces (system, trading, marketing, etc.). When a query lands in extension territory, the assistant falls back to RAG over docs (empty) or general training data (no platform awareness).

The platform has invested in a multi-agent model — 7+ specialist agents (System Concierge, Fleet Autonomy, CVE Responder, Trading Overseer, SDWAN Manager, etc.) each with carefully-scoped `concierge_tool_filter` patterns. But there's no router connecting Powernode Assistant to those specialists, so the multi-agent investment doesn't reach the chat surface where most operators actually interact.

This document defines:
1. The agent-of-agents architecture for routing chat queries to the right specialist or invocation path
2. The meta-skill creation capability that lets operators define new skills on-demand via tool recipes
3. The intersection — how meta-skills compose with the router

## What's already built (2026-05-11 → 2026-05-12)

### Routing metadata on `Ai::Skill`

Every skill now declares two routing-relevant fields in `metadata`:

```ruby
metadata: {
  # ...existing fields (author, icon, executor_class, etc.)
  "domain" => "system" | "trading" | "marketing" | "supply_chain" | "business" | "platform",
  "invocation_mode" => "one_shot" | "workflow_step"
}
```

- `domain` is the extension that owns the skill. `"platform"` is the always-present built-in domain (no specialist — front-door invokes directly).
- `invocation_mode` is binary: `one_shot` skills return a useful answer in one call; `workflow_step` skills are part of a multi-step procedure best handled by a domain specialist.

Domain values are NOT hardcoded in the parent platform. Extensions register their own via `Ai::Skill.register_domain(name:, executor_namespace_pattern:)` in their engine `after_initialize` hook. Inferred fallback walks the runtime registry when explicit metadata is absent.

A `before_update` callback auto-bumps `Ai::Skill.version` when routing metadata changes — every behavior-affecting edit gets an audit trail.

### Tiebreaker algorithm — `Ai::Skill#specialist_agent`

For a given skill, identifies the canonical chat-facing specialist to delegate to:

1. Keep only `agent_type="assistant"` bindings (monitors like Fleet Autonomy aren't chat participants).
2. Prefer agents whose `autonomy_config["extension"]` matches the skill's domain (semantic affinity).
3. Prefer the highest-priority `AgentSkill` binding.
4. Deterministic last resort: earliest binding by `created_at`.

Returns `nil` for `domain="platform"` skills — they're never delegated, only invoked directly.

### `Ai::ConciergeRouter` service

Pre-LLM router with three outcomes:

| Mode | When | Behavior |
|------|------|----------|
| `:invoked` | Top candidate is `one_shot` and auto-invokable (has a single free-text input like `intent`, `query`, `task_context`) | Router calls the executor directly; result is injected into the LLM's system prompt as an authoritative "use this as the answer" addendum |
| `:delegated` | Top candidate is `workflow_step` AND has a chat-facing specialist | `ConciergeService` swaps `@agent` for the specialist for the current turn only |
| `:passthrough` | No skill surfaced, or top match is `platform` domain and not auto-invokable | Default chat flow runs as before |

Discovery uses direct `nearest_neighbors` against the skill knowledge graph with a router-tuned distance threshold (0.85 cosine, looser than the autonomous-agent traversal's 0.6). Top-5 candidates pulled, classified by domain + invocation_mode.

### Integration into `Ai::ConciergeService`

`ConciergeService#process_message` now calls `ConciergeRouter.route(...)` at the top, then `apply_routing!` mutates `@agent` (for delegate) or stashes the invocation result (for invoke). The existing `process_with_tools` / `process_with_action_grammar` paths run unchanged. The `concierge_tool_system_prompt` and `legacy_system_prompt` builders append the router's `context_addendum` so the LLM sees the skill result before phrasing its reply.

### Known limitation (discovered 2026-05-12)

In long-running conversations with many prior "couldn't find" responses, the LLM's recency bias can outweigh the router's emphatic system-prompt override. The router fires correctly and the skill returns correct data, but the LLM still defaults to the conversation's established "not found" pattern. Mitigations to evaluate:

- Inject addendum as a system message *immediately preceding* the user's latest content (rather than at the start of the global prompt)
- Trim conversation history when router fires — drop the prior turns that established the bad pattern
- Add an explicit "previous responses in this conversation may have been incorrect; this skill output supersedes them" line
- Start fresh conversations more aggressively in the chat UI

This is a tactical fix, not an architectural one — the routing pipeline itself is sound.

## Agent-of-agents direction

Powernode is structurally multi-agent already. The router is the **first piece** of an agent-of-agents architecture but not the final shape. The full picture:

### Routing tiers

```
                    ┌────────────────────────┐
                    │  User chat message     │
                    └───────────┬────────────┘
                                │
                    ┌───────────▼────────────┐
                    │  ConciergeRouter       │   ◀── tier 1: deterministic
                    │  (deterministic class) │       routing based on skill
                    │                        │       metadata + similarity
                    │  • invoke / delegate / │
                    │    passthrough         │
                    └───────────┬────────────┘
                                │
            ┌───────────────────┼───────────────────┐
            │                   │                   │
   ┌────────▼────────┐ ┌────────▼────────┐ ┌────────▼────────┐
   │ Powernode       │ │ System          │ │ Trading Overseer│ ◀── tier 2: domain
   │ Assistant       │ │ Concierge       │ │ Marketing Lead  │     specialist agents
   │ (front-door)    │ │ (system domain) │ │ (other domains) │
   │                 │ │                 │ │                 │
   │ • general Q&A   │ │ • node/module/  │ │ • domain-deep   │
   │ • routing       │ │   sdwan ops     │ │   workflows     │
   │ • meta-skill    │ │ • package mgmt  │ │ • approvals     │
   │   creation      │ │ • runtime mgmt  │ │ • multi-step    │
   └─────────────────┘ └────────┬────────┘ └─────────────────┘
                                │
                                │ uses
                                ▼
                       ┌─────────────────┐
                       │ Background      │  ◀── tier 3: autonomous
                       │ specialists     │       agents (monitors)
                       │ • Fleet Autonomy│       run on cron, no chat
                       │ • CVE Responder │
                       │ • SDWAN Manager │
                       │ • Disk Image    │
                       └─────────────────┘
```

**Tier 1 — Router (deterministic):** No LLM call. Inputs: user message + embedding. Outputs: `invoke / delegate / passthrough` decision. The routing logic is pure Ruby driven by metadata.

**Tier 2 — Chat-facing specialists:** When the router delegates, control transfers to a domain specialist whose system_prompt + tool surface are scoped to that domain. The user keeps chatting; the specialist owns the conversation until handed back.

**Tier 3 — Autonomous monitors:** Not part of chat routing. Fleet Autonomy, CVE Responder, etc. run on their own cron schedules and consume *their own* skill surface. Mentioned for completeness — the chat path doesn't interact with tier 3 directly.

### Hand-back semantics

When a specialist completes a delegated workflow, control returns to Powernode Assistant. Two designs considered:

| Design | Behavior |
|--------|----------|
| **Single-turn delegation (current)** | Each turn the router fires; specialists handle one turn and control snaps back to Powernode Assistant for the next user message |
| **Sticky delegation** | Conversation gains a `current_active_agent_id` field; specialist stays in control until an explicit handoff |

Current implementation is single-turn (simpler, no migration). Upgrade to sticky if user feedback shows specialists need multi-turn workflows. Migration would add the column + an `Ai::Conversation#handoff_to(agent:)` method.

### Multi-domain queries

When `discover_skills` returns matches spanning multiple domains (e.g., "what's the relationship between CVEs and SDWAN policies?"), the current rule chain defaults to passthrough. Future enhancement: a `:multi_specialist` mode that invokes 2+ specialists in parallel and synthesizes responses. Out of scope for v1.

## Meta-skill creation

### The shape

Operators say things like "I need a skill that finds the cheapest provider for a region and creates a NodeInstance there." Today they'd need to write Ruby code (an executor class), register it in seeds, and wait for a release. The meta-skill creation capability collapses this into an interactive chat flow.

### Tool-recipe scope (locked decision)

Generated skills are **prompt + tool-recipe**, not Ruby executor code. A skill is defined by:

1. A `system_prompt` (used for discovery via embedding)
2. A `metadata` block (domain, invocation_mode, recipe definition)
3. A binding to one or more agents (so it surfaces in `discover_skills`)

The recipe is a declarative ordered list of MCP tool invocations with variable interpolation. No Ruby code is generated — execution happens via a runtime interpreter that reads the recipe and dispatches existing MCP tools.

### Recipe specification

```yaml
# metadata.recipe (stored as JSON in DB)
recipe:
  version: "1"
  inputs:
    - name: region
      type: string
      required: true
      description: "AWS/GCP/Azure region slug (e.g. us-east-1)"
    - name: max_monthly_cost
      type: number
      required: false
      default: 100
  
  steps:
    - id: list_providers
      tool: system_list_providers
      params: {}
      capture: providers          # entire result captured as variable "providers"

    - id: find_cheapest
      tool: system_query_provider_pricing
      params:
        region: "{{ inputs.region }}"
        max_monthly_cost: "{{ inputs.max_monthly_cost }}"
      capture: cheapest

    - id: provision
      tool: system_provision_instance
      params:
        provider_id: "{{ cheapest.results[0].provider_id }}"
        region: "{{ inputs.region }}"
      capture: instance
      require_approval: true       # operator must confirm before this step runs

  output:
    instance_id: "{{ instance.data.id }}"
    provider: "{{ cheapest.results[0].provider_name }}"
    monthly_cost_estimate: "{{ cheapest.results[0].monthly_cost }}"
```

### Recipe-runtime semantics

| Concept | Behavior |
|---------|----------|
| Variable scope | Each step's `capture` name becomes a top-level variable accessible to later steps as `{{ varname.field }}` |
| Input variables | Available as `{{ inputs.* }}` |
| Conditional steps | `condition: "{{ providers.results.size > 0 }}"` skips the step if false |
| Loops | NOT supported in v1 — keep recipes linear |
| `require_approval` | Step pauses, surfaces in the chat as a pending action, runs only after operator confirms |
| Failure handling | If a step fails (tool error), recipe halts and the chat agent surfaces the failure with the step ID + error |
| Audit trail | Each step's invocation + result is persisted to a new `Ai::SkillRecipeRun` table for replay/debugging |

### How the concierge creates a recipe skill

User describes a need:

> "I'd like a skill that finds the cheapest provider in a region and provisions an instance there if it's under $100/month."

Concierge invokes a new skill `system-design-skill-from-intent`:

1. Embed the user's intent
2. Discover candidate MCP tools whose descriptors mention "provider," "pricing," "provision instance"
3. LLM-driven step: construct an ordered tool chain that achieves the goal, mapping outputs of earlier steps to inputs of later steps
4. Generate the recipe YAML
5. Validate via dry-run (recipe runtime accepts a `dry_run: true` mode that resolves all variable bindings but doesn't actually call any tool)
6. Present to operator: "Here's the proposed skill recipe — confirm to register it"
7. On confirm: create `Ai::Skill` row with `metadata.recipe` populated; bind to the appropriate agent (operator's choice)

### Where recipes execute

A new service `Ai::SkillRecipeRunner` interprets recipes:

```ruby
::Ai::SkillRecipeRunner.execute(
  skill: skill,
  inputs: { region: "us-east-1", max_monthly_cost: 50 },
  account: account,
  agent: agent,
  user: user,
  dry_run: false
)
# → { success: true, output: { instance_id: "...", ... }, run_id: "...", steps: [...] }
```

The runner:
- Resolves each step's params via variable interpolation
- Dispatches via the existing MCP tool registry (so permissions + audit trails work)
- Handles `require_approval` by pausing and emitting a confirmation request
- Captures every step's input + output to `Ai::SkillRecipeRun` for the audit log

### Recipe security

| Concern | Mitigation |
|---------|-----------|
| Operator creates a destructive recipe | Same permission gates apply — the runner dispatches through the registry; each tool checks its own permissions. A user without `system.instances.terminate` can't create a recipe that calls `system_terminate_instance` and bypass the check. |
| Recipe steps loop / spawn other recipes | v1 forbids recipe-invoking-recipe. Steps can only call MCP tools, not other skill slugs. |
| Recipes use up token budgets | Each recipe step counts against the user's `Ai::AgentBudget` per existing budget enforcement. |
| Recipes generate by AI with bad logic | `require_approval: true` on any step that mutates state. Operators see the full proposed recipe before any tool is invoked. |
| Recipe runtime crashes leave inconsistent state | Each step is independent; partial state is the same as if the operator manually invoked tools and stopped halfway. Recipes don't implement transactions across tools. |

## Meta-team creation

Operators sometimes need orchestration that crosses multiple agents — not a single skill that does N things, but a *team* of agents that collaborate. The platform already has `Ai::Team`, `platform.create_team`, `platform.add_team_member`, and `platform.execute_team` as the building blocks. Meta-team creation makes those reachable from chat.

### When meta-teams vs meta-skills

| Use case | Reach for... |
|----------|-------------|
| "I want a deterministic recipe of tool calls that does X" | Meta-skill (tool recipe) |
| "I want multiple agents collaborating on X" — e.g., a PR review with security + style + perf reviewers | Meta-team |
| "I want to invoke an existing team as part of a longer workflow" | Meta-skill whose recipe includes a `platform.execute_team` step |

Meta-teams and meta-skills compose cleanly: a recipe step can call `execute_team(team_id: ...)` to invoke a team as a black box, and a team's member agents can have meta-skills in their skill bindings. No layering conflict.

### Team specification

```yaml
# Stored in Ai::Team.composition_rules or a sibling metadata column.
team_spec:
  version: "1"
  name: "PR Code Review Team"
  description: "Reviews pull requests for security vulnerabilities, code style, and performance regressions"
  
  # Trigger context (when should this team be assembled)
  trigger:
    type: "manual" | "on_event"      # v1: manual + on_event(github_pr_opened)
    event_filter: { repo: "powernode-platform" }   # only for on_event

  # Composition — ordered list of roles
  members:
    - role: "security_reviewer"
      agent: "ai-security-specialist"        # existing agent slug
      priority: 100
      required: true                          # team fails if this member can't run
      skills: ["security-audit", "cve-cross-reference"]   # restricts agent's skill use within this team

    - role: "style_reviewer"
      agent_spec:                             # NEW agent created if no existing fit
        name: "Style Reviewer"
        agent_type: "assistant"
        system_prompt_template: "design_skill_from_intent_style_reviewer"
        autonomy_config: { extension: "platform" }
      priority: 90
      required: false

    - role: "coordinator"
      agent: "powernode-concierge"           # reuses the front-door
      priority: 50
      required: true
      responsibility: "summarize_findings"    # role-specific hint

  # Workflow — how members interact
  workflow:
    mode: "parallel" | "sequential" | "supervisor"
    timeout_seconds: 300
    approval_chain_id: nil                    # optional Ai::ApprovalChain reference

  # Outcome
  outputs:
    findings: "{{ security_reviewer.findings + style_reviewer.findings }}"
    summary: "{{ coordinator.summary }}"
```

### Meta-team workflows

**`workflow.mode` semantics:**

- `parallel`: all members run concurrently, results merged. Used for review-style teams where members consult different aspects of the same input.
- `sequential`: members run in priority order, each seeing the prior member's output. Used for pipelines (analyze → plan → execute).
- `supervisor`: one member (highest priority) coordinates the others, delegating sub-tasks. Used when domain-specific reasoning needs to drive who does what.

v1 ships with `parallel` and `sequential`. `supervisor` mode is a future enhancement requiring an explicit coordinator-skill capability.

### How the concierge creates a team

User describes a need:

> "I need a team that reviews every PR for security issues and coding style. I want them to run in parallel and a coordinator agent to summarize their findings."

Concierge invokes `system-design-agent-team-from-intent`:

1. Embed the intent + extract structural hints ("PR review," "parallel," "summarize," "security," "style")
2. Discover candidate **agents** that match each role (e.g., `ai-security-specialist`, existing style-related agents)
3. For each role with no good existing fit, **propose a new agent spec** (system_prompt, agent_type, suggested skills)
4. Build the team_spec YAML with the discovered + proposed composition
5. Validate via dry-run (resolve all agent IDs, verify permissions, check trigger compatibility)
6. Present to operator with three confirmation gates:
   - Approve any NEW agents to be created (each requires individual approval — agents have trust scores + cost ceilings)
   - Approve the team composition
   - Approve the trigger (especially for `on_event` triggers that fire autonomously)
7. On confirm: create new agents (if any), create `Ai::Team`, add members, register trigger if applicable

### Where team specs live

Two storage options considered:

| Option | Pros | Cons |
|--------|------|------|
| `Ai::Team.composition_rules` (existing JSONB column) | Reuses existing model; no migration | Schema convention for the team_spec format isn't enforced |
| New `Ai::AgentTeamSpec` row | Versioning + history come naturally via existing `Ai::SkillVersion`-style pattern | Extra table; couples team identity to spec history |

**Recommendation**: use `Ai::Team.composition_rules` for v1. The team_spec is what defines the team; treating them as one row matches the mental model. Migrate to a separate spec table if versioning needs grow.

### Team execution flow

When `execute_team(team_id:, inputs:)` runs against a recipe-generated team:

1. Load `Ai::Team` + composition_rules
2. Resolve member references (agent IDs from slugs)
3. For each member, instantiate their LLM context per the team_spec's role + skill restrictions
4. Dispatch per workflow mode:
   - `parallel`: spawn N worker jobs, await all
   - `sequential`: invoke one at a time, threading outputs forward
   - `supervisor`: invoke coordinator first, then delegated members as the coordinator requests
5. Merge outputs per the team_spec's `outputs` template
6. Persist a `Ai::TeamExecutionRun` row with each member's contribution (audit trail)
7. Return composite result

This reuses the existing `Ai::TeamExecutionService` (or whatever the platform calls its team-execution path); the recipe-generated team_spec just becomes another `composition_rules` shape the existing execution service understands.

### Meta-team security

| Concern | Mitigation |
|---------|-----------|
| Operator creates a team with a coordinator that delegates to high-trust agents | Each agent's `trust_score` + `intervention_policy` continues to apply per-action. The team membership doesn't elevate trust — it just composes. |
| Generated agent specs grant excessive tool access | Per-agent approval gate at confirmation time (operator sees full proposed agent spec before any agent is created) |
| Teams trigger autonomously via `on_event` without operator awareness | `on_event` triggers require a separate operator approval at team-creation time AND emit notifications when they fire |
| Teams cost more than expected | Each agent's budget continues to apply per-execution. Team-level budget aggregation is a future enhancement. |
| Cross-account team executions | Same account-scoping that exists today. A team belongs to one account; can't recruit agents from other accounts. |

### What's deliberately NOT in scope (teams)

- **Team-of-teams**: A team whose members are themselves teams. Out of v1. Composition stays one level deep.
- **Dynamic team membership**: Members joining/leaving based on runtime state. v1 is static composition.
- **Cross-account team recruitment**: Teams stay account-scoped.
- **AI-driven member replacement**: If a member agent is unavailable, v1 fails-fast; doesn't auto-substitute.

## Integration touchpoints

### Where new code lands

| Component | File | What |
|-----------|------|------|
| Skill executor | `server/app/services/ai/skills/design_skill_from_intent_executor.rb` (new) | Builds a recipe from user intent + tool catalog |
| Recipe runner | `server/app/services/ai/skill_recipe_runner.rb` (new) | Interprets recipe YAML + dispatches tools |
| Recipe audit table | `server/db/migrate/<ts>_create_ai_skill_recipe_runs.rb` (new) | Persists every recipe run |
| Skill model extension | `server/app/models/ai/skill.rb` | Add `recipe?` predicate, `recipe` accessor reading `metadata["recipe"]` |
| Router integration | `server/app/services/ai/concierge_router.rb` | When skill has a recipe, `invoke_skill` dispatches via `SkillRecipeRunner` instead of an executor class |

### Where existing code changes

| Change | Reason |
|--------|--------|
| `Ai::Skill#executor_class_name` | Falls back to `Ai::SkillRecipeRunner` when `metadata["recipe"]` is present |
| `ConciergeRouter#auto_invokable?` | Returns true for recipe skills if all recipe inputs are populated from the user's message via the LLM-driven step |
| Permission seeds (parent) | Add `ai.skills.create_from_intent` permission, granted to operators by default |
| Powernode Assistant skill bindings | Add `design-skill-from-intent` skill to the platform-wide concierge so operators can invoke meta-skill creation in chat |

## Implementation phases

| Phase | Scope | Status |
|-------|-------|--------|
| **R0** | Routing metadata + tiebreaker + version bump on `Ai::Skill` | ✅ Done (uncommitted) |
| **R1** | Domain registration in extension engines | ✅ Done (uncommitted) |
| **R2** | `Ai::ConciergeRouter` service | ✅ Done (uncommitted) |
| **R3** | Wire router into `ConciergeService#process_message` | ✅ Wired; LLM context-bias issue noted, mitigation TBD |
| **R4** | Verify chat fix in fresh conversation; commit R0–R3 | 🟡 Pending |
| **R5** | Address LLM context-bias (one of: trim history, addendum repositioning, "ignore prior context" directive) | 🟡 Pending |
| **M0** | Recipe model: schema + `Ai::SkillRecipeRun` table + migration | 🔴 Not started |
| **M1** | `Ai::SkillRecipeRunner` service (interprets + dispatches recipes) | 🔴 Not started |
| **M2** | `DesignSkillFromIntentExecutor` (LLM-driven recipe builder from natural language) | 🔴 Not started |
| **M3** | Confirmation flow integration (`require_approval` steps surface in chat) | 🔴 Not started |
| **M4** | Bind `design-skill-from-intent` to Powernode Assistant; live test | 🔴 Not started |
| **M5** | Operator UI: list/edit/delete recipe skills (frontend) | 🔴 Not started |
| **T0** | Team spec schema + `Ai::TeamExecutionRun` audit table | 🔴 Not started |
| **T1** | Team execution dispatcher (`parallel` + `sequential` modes; reuses existing team execution path) | 🔴 Not started |
| **T2** | `DesignAgentTeamFromIntentExecutor` (LLM-driven team composer; discovers existing agents + proposes new ones) | 🔴 Not started |
| **T3** | Per-agent + per-team confirmation flow (new agents require individual approval before team creation) | 🔴 Not started |
| **T4** | `on_event` trigger support for autonomous team activation | 🔴 Not started |
| **T5** | Bind `design-agent-team-from-intent` to Powernode Assistant; live test | 🔴 Not started |
| **T6** | Operator UI: team composition explorer + execution history | 🔴 Not started |

R0–R3 are uncommitted code from 2026-05-12. R4–R5 close out the router work. M0–M5 build the meta-skill capability on top.

## Out of scope

| Item | Why |
|------|-----|
| Ruby executor code generation | Decision locked: tool-recipe scope only. Code generation re-opens security and runtime-error surfaces that recipe-based approach avoids. |
| Cross-extension recipe steps | v1 recipes can call tools from any extension via MCP — they just can't call ANOTHER skill (no recipe-invoking-recipe). Cross-tool composition IS supported. |
| Recipe loops + conditionals beyond simple `condition:` | v1 keeps recipes linear. Loops introduce halting concerns; complex conditionals make recipes hard to audit. |
| Auto-suggesting recipes from observed operator behavior | A future "watch how operators manually chain tools, propose a recipe to capture that pattern" feature. Useful but out of v1. |
| Multi-domain handoff (parallel specialist consultation) | Router currently passes through on multi-domain matches. v1 stays simple. |
| Sticky agent across turns | Single-turn delegation is the v1 default. Sticky is a future enhancement gated on user feedback. |

## Open questions

These are decisions worth making before implementing M0–M5:

1. **Recipe storage format**: YAML in `metadata["recipe"]` (Strings) vs. a separate `Ai::SkillRecipe` row with structured columns? YAML keeps everything in one place; separate table makes querying recipes easier. **Recommend YAML-in-metadata** — simpler model, lower migration cost.

2. **Recipe versioning**: When an operator edits a recipe, do we keep history? Today `Ai::SkillVersion` exists but it captures full skill states. Should recipe edits use the existing version model, or a new `Ai::SkillRecipeVersion`? **Recommend reuse `Ai::SkillVersion`** — recipes are part of the skill, treat them uniformly.

3. **Approval policy granularity**: Does `require_approval: true` mean "any operator can confirm" (current) or should we integrate with `Ai::ApprovalChain` for multi-step approvals (e.g., budget gate + ops gate)? **Recommend single-operator confirm for v1**, integrate ApprovalChain in v2 once we see how recipes are used in production.

4. **Recipe failure semantics**: When step 3 of 5 fails, do we:
   - Halt and report? (Operator manually rolls back what happened in steps 1–2)
   - Auto-rollback (run inverse tools for completed steps if available)?
   - Resume from failure point on retry?
   
   **Recommend halt-and-report for v1** — auto-rollback is hard to get right; clarity over automation.

5. **Recipe access control**: Who can run a recipe skill? Today, any operator with the right MCP tool permissions can invoke it (each step's tool has its own permission gate). Should there be an *additional* permission scope at the recipe level (e.g., "approved for use," gated by a separate role)?
   **Recommend not now** — adding a recipe-level permission layer is convenient at first but accumulates governance complexity. Trust the per-tool permissions.

6. **Recipe namespace**: Recipe skills should be discoverable but might pollute the existing skill graph. Should they live in a separate "user-defined" domain (e.g., `domain: "custom"`) or use the inferred fallback ("platform")? **Recommend a new `domain: "custom"` value** — operators see which skills are platform-shipped vs. user-built. Add to `Ai::Skill::ROUTING_DOMAINS` registration if we restore the constant; otherwise it's implicit (any value works).

7. **LLM provider for recipe generation**: `DesignSkillFromIntentExecutor` will use an LLM to compose tool sequences from natural language. Which provider? **Recommend: use the calling user's default Ai::Provider** — consistent with how other skills route through that abstraction. Don't hardcode a model.

## Decision log (for posterity)

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-12 | Cross-domain skills have `domain: "platform"` | Decision 1.a — keeps platform skills always available, simplifies routing |
| 2026-05-12 | Multi-specialist tiebreaker via domain affinity → priority → created_at | Decision 2 — deterministic, debuggable, reuses existing data |
| 2026-05-12 | `invocation_mode` is per-skill, not per-binding | Decision 3 — simpler model; per-binding override deferred until a real case emerges |
| 2026-05-12 | Routing metadata changes bump `Ai::Skill.version` | Decision 4 — every behavior-affecting edit gets an audit trail |
| 2026-05-12 | Router is a deterministic Ruby service, not an LLM-driven supervisor | Cost + predictability — routing decisions don't consume LLM tokens or surprise operators |
| 2026-05-12 | Single-turn delegation (vs. sticky agent) | Simpler v1; upgrade gated on operator feedback |
| 2026-05-12 | Meta-skills use tool-recipe scope, not Ruby code generation | Security surface; no code injection risk; reuse existing tool permissions |
| 2026-05-12 | Meta-team creation is in scope (parallel to meta-skills) | Operators need agent composition for cross-domain workflows that no single skill recipe captures cleanly |
| 2026-05-12 | Team specs stored in existing `Ai::Team.composition_rules` JSONB | Simpler than a new spec table; matches one-team-one-row mental model |
| 2026-05-12 | Team workflow modes: `parallel` + `sequential` in v1; `supervisor` deferred | Supervisor mode requires coordinator-skill capability not yet designed |
| 2026-05-12 | New agents created during team design each require individual operator approval | Agents have trust scores + cost ceilings — bulk-approving via one team confirmation hides per-agent decisions |
| 2026-05-12 | Recipes and teams compose, but neither nests itself (no recipe-in-recipe, no team-of-teams) | Keeps halting + audit semantics simple in v1 |

## Next-step proposals

After alignment on this doc:

1. **Verify R3 fix in a fresh conversation** (low-risk; isolates whether the chat failure was conversation-context bias or something deeper).
2. **Commit R0–R3** as a series of staged commits (5-6 commits per the earlier sequencing).
3. **Address LLM context bias (R5)** — pick one of the mitigations from the "Known limitation" section.
4. **Implement M0–M2** as the meta-skill foundation (data model + runner + intent-driven design).
5. **M3–M4** to wire meta-skills into the chat experience.
6. **Implement T0–T2** as the meta-team foundation (data model + dispatcher + intent-driven composer). Can run in parallel with M3–M4.
7. **T3** confirmation flow (depends on both M3 and T2 landing).
8. **M5 + T6** frontend, gated on operator demand for curation UIs.

Phases M0–M5 and T0–T6 can largely interleave — recipe runtime and team dispatcher share no code path. The natural ordering is: ship recipes first (more contained), use what we learn to inform team design.

## Glossary

- **Concierge**: An `Ai::Agent` row with `agent_type="assistant"` that participates in chat conversations.
- **Powernode Assistant**: The platform-wide concierge; the default chat surface for any new conversation.
- **Specialist**: A domain-scoped concierge (System Concierge, Trading Overseer, etc.) that owns an extension's chat queries.
- **Router**: `Ai::ConciergeRouter` — the deterministic service that decides invoke/delegate/passthrough for each incoming message.
- **Skill**: An `Ai::Skill` row with `metadata` declaring its routing properties; either backed by a Ruby executor (existing pattern) or a recipe (new pattern).
- **Recipe**: Declarative ordered list of MCP tool invocations stored in `Ai::Skill.metadata["recipe"]`; interpreted at runtime by `Ai::SkillRecipeRunner`.
- **Domain**: `metadata["domain"]`; the extension that owns a skill (or `"platform"` for built-ins).
- **Invocation mode**: `metadata["invocation_mode"]`; either `one_shot` (single answer) or `workflow_step` (delegated to a specialist for orchestration).
- **Tier**: Routing layer (1 = router, 2 = chat specialists, 3 = autonomous monitors). Defined in §"Routing tiers."
- **Team spec**: Declarative composition of agents stored in `Ai::Team.composition_rules`; includes members, roles, workflow mode (parallel/sequential), and outputs template. Interpreted by the team execution dispatcher.
- **Workflow mode**: How members of a team interact — `parallel` (concurrent, results merged), `sequential` (priority-ordered with output threading), `supervisor` (one coordinator delegates to others; v2).
