# Canonical Teams

The platform ships two **canonical teams** as seeded data — the organisation of its own agents,
readable three ways and runnable as one:

| Team | Manager | Members (role) | Seed |
|------|---------|----------------|------|
| **System Operations** | System Concierge | Fleet Autonomy, CVE Responder, Runtime Manager, GitOps Reconciler (`executor`); SDWAN Manager, Disk Image Manager, System Topology Designer, Capacity / Storage / Ingress / Supply Chain Managers (`specialist`) | `extensions/system/server/db/seeds/system_operations_team_seed.rb` |
| **Platform Engineering** | Platform Architect | Platform Developer, Release Manager (`executor`); Research Analyst, Strategic Planner (`researcher`); PRD Generator, Documentation Specialist (`writer`); LLM Judge, System Quality Assurance (`reviewer`); Knowledge Graph Curator (`analyst`) | `server/db/seeds/ai_canonical_teams_seed.rb` |

Both are `hierarchical` / `manager_led` / `hub_spoke`. Roles come from
`Ai::AgentTeamMember::ROLES`; the backing `Ai::TeamRole` type is derived from the role by
`Ai::AgentTeamMember.role_type_for`.

## One structure, three views

There is **no agent-graph model**. A graph is:

| View | Rows | Writer |
|------|------|--------|
| **Nodes and roles** | an `Ai::TeamTemplate` — global, `is_system`, `source_key`-managed, `role_definitions` naming canonical agents by slug | `Ai::Teams::CanonicalTeamSeeder` (one seam for both seeds) |
| **Edges** | the manager's `Ai::DelegationPolicy` (`allowed_delegate_types`) and one active `Ai::AgentLineage` edge manager → member per member | the hierarchy seeds, through `Ai::Agents::HierarchyWriter` (`server/db/seeds/ai_agent_hierarchy_seed.rb`, `System::Governance::HierarchyReconciler`) |
| **A run** | an `Ai::TeamExecution` driven by `Ai::TeamStrategies::HierarchicalStrategy` (manager_led) | the worker's `AiTeamExecutionJob`, calling back into the server's internal strategy endpoint |

The Autonomy page's lineage forest and the Teams page therefore render **the same organisation**:
the forest shows the edges, the team shows the seats, and both come from the same canonical rows.

## The materialised team

A template is the canonical; the **team** is its per-account materialisation — an
`Ai::AgentTeam` with `template_id` set and `team_config.canonical = true`
(`Ai::AgentTeam#canonical?`). Its members are the account's **executing principals** for the
canonical agents: the clones `Ai::Agents::AccountPrincipalResolver` mints, never the global
canonicals themselves. Operator ruling 8 makes a global canonical a template that never executes,
so a team that seated one could never run.

### Read-only through every door

A canonical team is read-only at **both** seams, the way a canonical agent is:

- **MCP.** `platform.list_teams` / `get_team` flag it `canonical: true` with its `template_id`
  and `source_key`; `update_team`, `delete_team`, `add_team_member` and `remove_team_member`
  answer a result envelope (`success: false, canonical: true`) naming the clone path.
- **REST.** `PATCH`/`DELETE /api/v1/ai/agent_teams/:id`, its `members` sub-routes and
  `PATCH`/`DELETE /api/v1/ai/teams/:id` refuse with **403**. The one guard is
  `Ai::AgentTeam#guard_mutable!`, which RAISES `Ai::AgentTeam::ReadOnlyCanonical` — both
  controllers render it, and `Ai::Teams::CrudService#update_team` / `#delete_team` call it, so the
  MCP wording and the HTTP wording cannot drift (`Ai::AgentTeam::READ_ONLY_MESSAGE`).

### Customising: clone

Two different objects, both fully writable:

- **Clone the TEMPLATE** — `POST /api/v1/ai/teams/templates/:id/clone` copies the template into the
  account (`GloballyScopedContent`). The copy is a template, not a team, and carries no
  `template_id` back to the canonical.
- **Build a TEAM from the template** — `POST /api/v1/ai/teams` with `template_id`
  (`Ai::TeamTemplate#create_team!`). The team carries the `template_id` but **not** the canonical
  flag, and is the account's own. With no `name:` it takes the template's name, suffixed
  (`Platform Engineering (2)`) when the account's materialised canonical team already holds it —
  team names are unique per account.

## Drift and repair

`Ai::Teams::CanonicalTeamReconciler` (`server/app/services/ai/teams/canonical_team_reconciler.rb`)
is the only writer of a canonical team's membership.

- **`drift`** is read-only. It reports where the three views disagree — `missing_edges`
  (a member whose lineage edge to the manager is gone), `undelegatable_members` (a member whose
  `agent_type` the manager's policy does not admit), `unrepresented_delegate_types` (a type the
  manager may delegate to that no member carries), `absent_agents` — and where the materialised
  team disagrees with the template (`team_absent`, `missing_members`, `extra_members`,
  `role_mismatches`, `lead_mismatch`). It resolves principals through the non-minting
  `AccountPrincipalResolver.existing`, so a health check materialises nothing.
- **`reconcile!`** repairs **membership only**: the team row, its members, their roles, priorities
  and lead, minting the principals it needs. It never writes a lineage edge or a delegation row —
  a missing edge stays reported until the hierarchy seed runs. A same-named team that is not the
  canonical materialisation is never adopted (reported as a name conflict, like a stray agent
  under the canonical rule).

Wired on `rails system:governance:reconcile` (repair) and `rails system:governance:drift`
(report, exits 1) in the system extension, and run once by each seed at first boot.

The repair pass does **not** walk every account: materialising a team mints an account principal
per seat, so `CanonicalTeamReconciler.reconcilable_accounts` scopes the write set to the accounts
that already hold a canonical team plus the primary account the seeds materialise in
(`SiteSetting canonical_team_primary_account_name`, default `Powernode Admin`, falling back to the
first account). A tenant holding no canonical team is left untouched. `drift` still reads every
account.

## Execution under the delegation policies

`HierarchicalStrategy` checks every delegation with `Ai::Autonomy::DelegationAuthorityService`
before the manager's decomposition sees the worker pool: a member outside the manager's
`allowed_delegate_types` (or beyond its `max_depth`) is **refused** — recorded in the results with
the policy's reason (`refused:`), counted as failed, never executed. With no admitted member the
manager runs the task alone. The action type checked is `execute`, the same word
`AgentManagementTool#spawn_task` passes, so a policy's `delegatable_actions` reads one vocabulary
at both doors.

## Related

- [Platform Engineering agents](platform-engineering-agents.md) — the Engineering hierarchy and its team
- [Agents and autonomy](agents-and-autonomy.md)
- The ruling record: `docs/reference/system-agent-hierarchy-proposal-2026-09-03.md` §2 Phase 4, §5 rulings 7–8 and §6
