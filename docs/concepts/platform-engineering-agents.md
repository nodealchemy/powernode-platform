# Platform Engineering Agents

The platform maintains a suite of canonical agents for its **own** design, development,
build and documentation — the Engineering hierarchy. Operations (Fleet Autonomy and the
four operations managers in the system extension) runs the fleet; Engineering builds the
platform. Both hang under System Concierge, the root of the whole forest.

## The hierarchy

```
System Concierge (system extension — root of both hierarchies)
├── Powernode Assistant (core concierge → the fundamental core forest)
└── Platform Architect (core, is_governance — manager of the Platform Engineering team)
    ├── Platform Developer        code_assistant   drains dev-improve as the platform_agent driver
    ├── Release Manager           monitor          builds, promotion ladder, disk images, deploys
    ├── Documentation Specialist  content_generator keeps docs, catalog and reference counts truthful
    ├── Research Analyst          research, tech-radar sweeps
    ├── Strategic Planner         long-horizon planning
    ├── PRD Generator             spec-driven plans from approved offers
    ├── LLM Judge                 independent review of every drained task
    ├── System Quality Assurance  test-gap and verification
    └── Knowledge Graph Curator   consolidates learnings into platform knowledge
```

Every agent above is a **seeded global canonical** (`account_id NULL`, `is_system`,
`source_key`-managed): the four new ones come from `server/db/seeds/ai_engineering_agents_seed.rb`,
the six existing ones from the fundamental agent seeds. Lineage edges and delegation
policies are written by `server/db/seeds/ai_agent_hierarchy_seed.rb` through
`Ai::Agents::HierarchyWriter`, the same seam every runtime creation path uses.

**Why the Platform Architect is a core root.** Core seeds never reach for an extension
agent, so the Engineering forest is rooted at the Platform Architect in core, and the
system extension's hierarchy seed (`extensions/system/server/db/seeds/system_agent_hierarchy.rb`)
attaches it under System Concierge when the extension is present — exactly how Powernode
Assistant joins the forest. An install without the system extension keeps two core roots.

## Delegation

| Agent | Inheritance | Max depth | May delegate to |
|-------|-------------|-----------|-----------------|
| Platform Architect | moderate | 3 | every Engineering agent type (derived from its children at seed time) |
| Platform Developer | conservative | 1 | the LLM Judge's agent type only — review, nothing else |
| Release Manager | conservative | 1 | nobody (a delegate-type list no agent carries; the model refuses depth 0) |
| every other child | conservative | 1 | the P1 leaf policy |

## The `engineering` policy set

The categories are core (`Ai::InterventionPolicy::ENGINEERING_CATEGORIES`, registered
beside `ai.delegation_policy.update`); the rows are seeded on the **owning** agent.

| Category | Owner | Verdict | Gated by |
|----------|-------|---------|----------|
| `dev.task_claim`, `dev.task_complete` | Platform Developer | auto_approve | (rows for the loop's own bookkeeping; `dev_next_task` / `dev_complete_task` stay ungated so a Claude Code session is never parked) |
| `dev.campaign_propose` | Platform Developer, Platform Architect | auto_approve — proposals **are** the gate | `campaign_propose` (ungated; the proposal itself awaits approval) |
| `dev.skill_refine` | Platform Developer, Platform Architect | auto_approve from `trusted`, require_approval below | `auto_evolve_skill` |
| `dev.prompt_refine` | Platform Developer, Platform Architect | auto_approve from `trusted`, require_approval below | `mutate_skill` |
| `release.build_dispatch` | Release Manager + an account-wide floor | auto_approve (see the note below on "on develop") | `system_dispatch_module_build_batch` |
| `release.promote` | Release Manager | require_approval, no trust unlock | `system_promote_module_version` |
| `release.rollback` | Release Manager | require_approval, no trust unlock | `system_rollback_module_version` |
| `release.deploy_platform` | Release Manager | require_approval, no trust unlock | `system_deploy_platform` (the mode-less wizard read is the verb's declared read arm and never meets the gate) |
| `docs.update` | Documentation Specialist | auto_approve | **nothing yet** — the row is seeded and the category registered, but no verb or executor carries it. It exists so the Documentation Specialist's authority is declared where the others are; a documentation write path that gates on it is later work. |

**Trust-conditioned refinements** (operator ruling 2026-09-03 #3) use the existing
conditions mechanism, not a new one: each refine category is a row **pair** on the owning
agent — an `auto_approve` row with `conditions: { trust_tier_minimum: "trusted" }` at
priority 20 above an unconditioned `require_approval` row at priority 10. Below `trusted`
the conditioned row does not match and the call parks; from `trusted` both match and the
higher priority wins. The release rows carry no condition at all: promotion, rollback and
deployment stay approval-gated whatever the tier, because a self-hosted control plane
cannot recover itself from a bad rollout and the rollback tool is dead while it is down.

**The build-dispatch floor.** An agent-scoped policy row matches only the agent it names,
and the principals that legitimately dispatch a build over MCP carry none: an operator's
Claude Code session (whose MCP principal is an `mcp_client` identity, not the Release
Manager) and a dev-cell **instance** principal (mTLS node cert — no user and no agent at
all). One `scope: "global"` auto_approve row for `release.build_dispatch` keeps that path
flowing once the MCP verb is gated; every other release verb has no floor, so those
callers meet the unmatched default and park. This is *not* about the automatic
push-triggered build, which runs through the system extension's own trigger service and
never reaches the MCP verb.

**Two clauses the rows cannot carry.** The ruling asks for `release.build_dispatch` to
auto-approve *on develop*; `Ai::InterventionPolicy`'s conditions vocabulary has no
branch/ref key (a dispatch context carries `base_sha` / `head_sha`, not a branch name), so
the seeded row is an **unconditioned** auto_approve and the develop rule lives in the
Release Manager's prompt — a branch-conditioned verdict needs a new condition key. The
ruling also asks for Release Manager delegation at **depth 0**; `Ai::DelegationPolicy`
validates `max_depth > 0` and reads an *empty* `allowed_delegate_types` as unrestricted,
so "delegates to nobody" is spelled depth 1 plus the no-such-type sentinel `["none"]`,
which `#allows_delegate_type?` refuses for every real agent type. Same verdict, in the
vocabulary the model has.

**Landing the floor on an install that is already up.** `db:seed` runs on **first boot
only** (the hub's `rails-start.sh` gates it behind a durable `.db-initialized` marker and
runs `db:migrate` alone afterwards), so an install upgraded onto the release gating gets
the *code* — the gated verbs — without the *row*. Every build dispatch would then park.
The floor is therefore written through one seam,
`Ai::Engineering::ReleaseDispatchFloorSeeder`, which the seed calls, which a boot-time
governance reconcile hook calls on **every boot** where an extension wires one (the hub
image's per-boot reconcile does, behind `defined?` so the two trees may skew), and which
is also exposed as `rake db:seed:engineering_release_floor` — **run it once after
upgrading** on an install with no such hook. It is absence-only: it never rewrites,
deactivates or deletes a row an operator retuned.
The other engineering rows are deliberately not backfilled — the agents they hang off do
not exist on such an install either, and `release.promote` / `release.rollback` /
`release.deploy_platform` are *meant* to start requiring approval.

All six gated verbs replay through `Ai::Executors::DeferredToolCall` as the original
principal on approval (see [Deferred tool-call replay](deferred-tool-call-replay.md)); each
gate context resolves the target under the account and applies the verb's own admission
rule **before** parking, and the rollback context pins the auto-selected version into the
approval so the operator approves the version the card names.

## The Platform Developer as the platform_agent driver

`campaign_delegate driver_kind: platform_agent` with no `target.agent_id` resolves to the
Platform Developer — specifically to **the account's own row** for
`Ai::RalphLoop::PLATFORM_AGENT_DEFAULT_SLUG`, cloned from the global canonical on first
use through the HIER-P1 canonical rule (lineage edge, `cloned_from_id`, a creator and
provider from this account). The global canonical itself is never wired onto a loop:
`Ai::Ralph::TaskExecutor` runs a loop's `default_agent` through
`Ai::AgentToolBridgeService`, which resolves tools and permissions as `agent.creator`, and
a canonical's creator is a user in the *seeding* account — so a foreign principal would
end up executing another account's work.

The loop's `default_agent` becomes that clone, and it can then claim work through
`dev_next_task` under its own identity (`agent:<id>`) while every other caller — a Claude
Code session, another platform agent — meets the `delegated_to_platform` halt. Note that
"its own identity" is decided on the **agent** principal, not on the absence of a user:
the bridge passes `agent.creator` as the calling user on every tool call, so a present
user is the normal shape of an agent principal; what separates a human session is that the
MCP door's agent is always an `mcp_client` identity. With no Platform Developer canonical
present, an empty target still raises: the default is a resolution, never a wedged loop. See
[Use Powernode from Claude Code](../guides/use-powernode-from-claude.md#handing-a-task-to-the-platform-developer-vs-claude-code)
for when to hand a task to which executor.

## Canonical principals never execute (HIER-P2I)

Operator ruling 8 of the
[hierarchy proposal](../reference/system-agent-hierarchy-proposal-2026-09-03.md#5-operator-rulings-2026-09-03-1812-utc):
a global canonical (`account_id NULL`) is a **template**, never an executing principal.
`Ai::Tools::BaseTool.permitted?` used to answer `true` for any agent without an account, so a
canonical that reached a tool was **unbounded** — no permission at all — while the account-scoped
clone it should have been running as is bounded by the account's role.

What holds now:

- **The tool seam refuses a canonical by name.** `Ai::Tools::BaseTool#execute` answers a
  NULL-account acting agent with a result envelope — `success: false`,
  `refusal: "canonical_principal"`, `canonical_slug`, and an `error` naming the slug and the
  clone path (`agent_management create_agent canonical_slug: <slug>`) — never a `-32603`. It is
  the first check in `#execute`, ahead of the deny overlay and parameter validation, so a
  malformed call from a canonical is still a principal refusal. `permitted?` answers `false` for
  the same principal, so a caller consulting it alone (the replay re-check in
  `Ai::Executors::DeferredToolCall`, the per-agent tool list) fails closed. Each refusal is
  logged and audited as `mcp.tools.canonical_principal_refused` (slug, tool, action — never the
  params), deduplicated per `(account, canonical, action)` per hour like the undeclared-action
  telemetry. The nil-agent path — a user or instance principal — is untouched. The two tools that
  override `permitted?` without calling `super` (`Ai::Tools::KillSwitchTool`,
  `Ai::Tools::AgentAutonomyTool`, both of which answer `true` for any agent so that escalation
  stays visible) carry the same refusal, or `PlatformApiToolRegistry.advertised_class?` would
  keep advertising them to a canonical.
- **What executes is the account's clone**, resolved through **one** seam:
  `Ai::Agents::AccountPrincipalResolver` (`for(canonical_slug:, account:)`,
  `acting(agent, account:)`, `concierge_for(account)`). It hands back the account's own row for
  the canonical, or mints the clone on first use through the HIER-P1 canonical rule —
  `clone_to_account`, a creator and provider from the account, the `canonical_clone` lineage
  edge via `Ai::Agents::HierarchyWriter` — keeping the canonical's name and slug (uniqueness is
  per account, so every `Ai::Agent.resolve_for(name:)` site then finds the clone override-first).
  The account's agent-scoped `Ai::InterventionPolicy` rows written against the canonical are
  **re-homed** onto the clone (the operator's tuned verbs travel with them), and the canonical's
  skill bindings, trust score and the delegation policy that governed it for the account are
  copied, so the first tick through the clone acts exactly as the canonical would have. The
  Platform Developer resolution above is one consumer of this seam.
- **Every seeded canonical that acts on its own resolves through it.** In the system extension,
  `System::Governance::AgentResolver` — the rule the fleet tick (`FleetAutonomyService.tick!`,
  `#for_owner` for every `SIGNAL_BINDINGS` `owner:`), the `PolicyReconciler`, the CVE responder
  tick and the adaptation gate all share — answers with the account's clone, so the writer of
  policy rows and the reader of them agree on the acting id on the same tick. The concierge
  doors (`POST /conversations/concierge` and `/provisioning`, workspaces, the system extension's
  concierge panel) attach conversations to the account's clone, and `Ai::ConciergeService`
  maps a conversation attached to the canonical before this increment onto the clone for
  execution without rewriting the conversation. The doors that can hand any global row to
  execution map the same way: workspace membership (`Ai::WorkspaceService#add_agents_to_team`
  and `ConversationTool`'s `create_workspace` / `invite_agent`, whose members are executed by
  `Ai::TeamStrategies::BaseStrategy`), `POST /api/v1/ai/agents/:id/execute`, and
  `POST /api/v1/ai/agents/:agent_id/conversations` — each attaches or executes the account's
  clone, so the serialized response names the row that actually ran. Reads are left alone:
  `set_agent` still resolves a canonical for `show`, and `Ai::Agent.resolve_concierge_for`
  is still a read. `platform.route_task`
  (`Ai::Routing::AgentRouterService`) may still name a canonical — it is a read — and says so
  (`canonical: true` on the winner and each candidate, plus an `execution_note`); the caller
  clones before executing.
- **An approved operation still replays.** `Ai::Executors::DeferredToolCall` parks a gated call
  with the acting agent's id, and every approval already in the table was parked by the
  canonical, because that is what ticked before this increment. The replay therefore resolves
  the descriptor's agent through the same seam (`#agent_for`) and re-invokes as the account's
  clone: the operator's decision is about the operation, not about which row the scheduler
  resolved. It fails closed only where no clone exists and none can be minted — an account with
  no user to own one — and then `permitted?` answers `false` and the replay refuses
  `permission_revoked` rather than running an unbounded principal.
- **A Claude Code skeleton is unaffected.** `.claude/agents/powernode/*.md` runs locally under
  the *user's* principal (the MCP door's `mcp_client` identity), not the agent's, so the export
  of a canonical is a prompt, never a NULL-account principal reaching a tool.

## The Platform Architect's loop: sense, propose, materialise, verify (HIER-P3)

Phase 3 of the hierarchy proposal gives the Platform Architect a closed loop over the
platform's own governance, so the drift the 2026-09-03 audit found by hand is found by
the fleet tick from then on. The four arms, and where each lives:

1. **Sense.** `System::Fleet::Sensors::GovernanceGapSensor` (system extension, on the
   Fleet Autonomy tick) compares the declarations the hierarchy is built from with the
   running database and emits one `system.governance_gap` signal per gap — a registered
   category no agent set owns, an agent with a policy set and no skill, a lane bound to
   no skill that nothing declares deliberate, an executor with no catalog row, a
   canonical with no lineage edge or delegation policy, a declared category's row parked
   on an agent the declarations do not know, a `tool_families` entry naming nothing the
   registry serves. Each carries a stable fingerprint and, for a gap the runtime can
   close, the exact materialisation.
2. **Propose.** `DecisionEngine` routes the signal to `GovernanceGapProposeExecutor`,
   bound to the Platform Architect (the first extension executor bound to a core
   canonical) and gated under `dev.campaign_propose` — `auto_approve`, because the offer
   IS the human gate. It files one `Ai::ImprovementRecommendation` per fingerprint of the
   matching type (`capability_gap`, `team_composition`, `skill_creation`;
   `prompt_refinement` is in the vocabulary but no detector emits it yet) with the
   concrete spec: the files a code fix touches and the fix.
   A re-detection updates the open offer; nothing ever files a second. Offers are the
   code path; `Ai::AgentProposal` stays the runtime-materialisation vocabulary of other
   lanes.
3. **Materialise.** For a runtime-closable gap the executor also hands the
   materialisation to `System::Governance::GapMaterializer`, which applies it through
   the platform's own seams — `Ai::Agents::HierarchyWriter` for an edge or a delegation
   policy, `Ai::AgentSkill` for a binding, `Ai::SelfImprovement::SkillRefinementService`
   for a prompt — under the ruling-3 gates through `Ai::AutonomyGate`:
   - a **skill binding** or a **prompt refinement** gates on the trust-conditioned
     `dev.skill_refine` / `dev.prompt_refine` pair this document describes above: it
     applies at once for a `trusted` Platform Architect and parks below that tier;
   - a **lineage edge** or a **delegation policy** is structural and gates on
     `dev.governance_materialize` (`require_approval`, declared by the system extension
     on the Platform Architect): it parks whatever the tier.
   A parked materialisation is an `Ai::DeferredOperation` on the `Platform Architect
   Actions` chain that replays on approval as the same principal; an applied one
   closes the offer as `applied` and writes one audit row and one fleet event naming
   it. The existing MCP verbs (`set_delegation_policy`, `attach_skill_to_agent`,
   `mutate_skill`) are deliberately not called from here — each carries its own gate,
   and a gated call under this gate would park twice for one decision.

   `SkillRefinementService` is ruling 6's versioned path for a canonical skill: the new
   prompt is recorded as an active `Ai::SkillVersion` (the previous prompt kept in its
   metadata, the acting agent as its author) and then applied to the skill, so a
   canonical is never edited in place without a record and any refinement can be
   reverted by re-activating the prior version. It writes and does not gate; the caller
   resolves `dev.prompt_refine` first.

   The prompt-refinement arm is WIRED but has NO SENSOR PRODUCER: every
   `materialization` hash `GovernanceGapSensor` stamps today is a skill binding, a
   lineage edge or a delegation policy — there is no prompt-drift detector, so no
   governance offer carries a prompt refinement yet. The seam exists so that when one
   arrives (or the Platform Architect proposes a refinement of its own) the write is
   gated and versioned rather than an in-place edit of `ai_skills.system_prompt`.
4. **Verify.** The sensor clears the moment the gap closes, so nothing needs cleaning
   up. The lane is scored, not exempt: filing the offer is its remediation, so
   `RemediationValidator` mints an outcome for the fingerprint and a gap that stands
   `STUCK_STREAK_THRESHOLD` settle windows escalates as a HIGH
   `fleet.governance_gap_stuck` event with the lane forced to `require_approval` — one
   operator decision on the Platform Architect's chain, quiet while it is open. The
   recommendation scoreboard records the cycle like any other offer.

Two declarations make the loop possible, both in the system extension's
`PolicyDeclarations`: the Platform Architect is listed in `AGENT_IDENTITIES` under
`CORE_CANONICAL_KEYS` (declared as an owner, seeded and delegation-governed by core — the
extension's hierarchy reconciler attaches its edge under System Concierge and never
writes its delegation policy), and `PLATFORM_ARCHITECT_POLICIES` declares
`dev.campaign_propose` and `dev.governance_materialize` on it. The first is a core
category that `ai_engineering_agents_seed.rb` writes on the admin account at the same
verb; the extension's declaration exists so the routed lane has an owner and so every
other account converges through `PolicyReconciler`, which finds the admin row present and
writes nothing. The operator procedure — what each offer means, what parks and what
applies, how to read the stuck event — is the system extension's
`docs/runbooks/governance-gaps.md`.

## The Platform Engineering team (HIER-P4)

The hierarchy above is also a **canonical team** — `Ai::TeamTemplate` `platform-engineering`
(global, `is_system`, `source_key`-managed; `server/db/seeds/ai_canonical_teams_seed.rb`),
materialised for the account as a `hierarchical` / `manager_led` / `hub_spoke` `Ai::AgentTeam`
whose manager is the Platform Architect:

| Member | Team role |
|--------|-----------|
| Platform Architect | `manager` (lead) |
| Platform Developer, Release Manager | `executor` |
| Research Analyst, Strategic Planner | `researcher` |
| PRD Generator, Documentation Specialist | `writer` |
| LLM Judge, System Quality Assurance | `reviewer` |
| Knowledge Graph Curator | `analyst` |

**One structure, three views.** The template is the nodes and roles; the lineage edges the
hierarchy seed writes are the tree; the Platform Architect's delegation policy is the edge set the
manager may actually use. `Ai::Teams::CanonicalTeamReconciler` reports where they disagree
(`drift`: a removed lineage edge, a member the Architect's policy cannot delegate to, a delegate
type the team lacks) and repairs the team's **membership** on `rails system:governance:reconcile`
— never the edges or policies, which keep their own writers. The seated members are the account's
executing principals (the clones `Ai::Agents::AccountPrincipalResolver` mints), never the
canonicals: ruling 8 applies to teams exactly as to agents.

**Running it.** `platform.execute_team` on "Platform Engineering" dispatches to the worker, which
calls back into `Ai::TeamStrategies::HierarchicalStrategy`. Before the Architect decomposes the
objective, every worker is checked with `Ai::Autonomy::DelegationAuthorityService`; a member outside
the Architect's `allowed_delegate_types` is refused with the policy's reason and never executed
(pinned by `spec/services/ai/team_strategies/hierarchical_strategy_delegation_spec.rb`). Through the
MCP verbs the team is read-only — clone the template to customise. The "System Operations" twin
(manager System Concierge, the eleven domain agents) is the system extension's seed. See
[Canonical teams](canonical-teams.md).

## Claude Code subagents

Each Engineering canonical is exported as a Claude Code subagent under
`.claude/agents/powernode/` (`rails claude:sync_agents`). The Platform Developer's
skeleton carries `Edit`, `Write` and `Bash` (the `code_assistant` rule in
`Ai::ClaudeExport::ToolAllowlist`); the Release Manager's does not — it reads, dispatches
and promotes through platform verbs only.

## Related

- [Canonical teams](canonical-teams.md) — the two seeded teams, drift and repair, execution under the delegation policies
- [Agents and autonomy](agents-and-autonomy.md)
- [Deferred tool-call replay](deferred-tool-call-replay.md)
- The ruling record: `docs/reference/system-agent-hierarchy-proposal-2026-09-03.md` §2 Phases 2b and 3, and §5
