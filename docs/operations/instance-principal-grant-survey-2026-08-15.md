# Instance-principal `granted_mcp_tools` survey — 2026-08-15

Prerequisite survey for the parked decision on offer `01a003aa-5702` ("an instance principal
waives EVERY per-action permission map: 213 raised actions are gated only by the destroy-shaped
name overlay").

The decision was parked because deriving the deny set from `ACTION_PERMISSIONS` would newly deny
213 currently-grantable actions, and the blast radius of that was unknown. This survey measures it.

**Report only — nothing was changed.** No grant was narrowed, no code was modified, no live row
was written. Break-glass was armed for two read-only queries and revoked in the same command.

---

## Method

Two halves, deliberately computed in different places:

| Half | Where | Why |
|---|---|---|
| The 213-action set | **locally**, against branch `dev-loop/dev-improve` | ops-hub runs an older deployed module; computing there would silently measure the wrong code |
| The live grants | **ops-hub** `powernode_production` | dev-cell's platform DB is a fixture shell (0 agents/providers) |

Live rows were dumped to JSON and intersected locally. Predicates (`destructive_tool?`, glob
matching) were **executed**, not read.

## Result 1 — the 213 figure reproduces exactly

Against `PlatformApiToolRegistry.all_tools` on HEAD:

```
total registered actions            602
  have a per-action map entry       271
  map-elevated (per-action != floor) 255
    destroy-shaped (overlay denies)  42
    NOT denied by the overlay       213   <-- the figure in the offer
class REQUIRED_PERMISSION is nil     29
```

Concentrated in two tools: `SystemFleetTool` 131 elevated (111 open) and `SdwanTool` 80 (67 open).

## Result 2 — the live grant surface is ONE row, and it holds the wildcard

The entire fleet has **exactly one** `system_node_instance_peers` row with a non-empty grant:

```
node_instance_id <redacted>                             (the dev-cell executor peer;
                                                          status running, heartbeat current)
capabilities     {"role": "dev_cell_executor"}
enabled          false          <-- see Result 4
status           active
granted_mcp_tools (14):
  platform.dev_next_task, platform.dev_complete_task, platform.dev_list_tasks,
  platform.search_knowledge, platform.query_learnings, platform.code_semantic_search,
  platform.search_knowledge_graph, platform.discover_skills, platform.get_skill_context,
  platform.create_learning, platform.create_knowledge, platform.create_skill,
  platform.*improvement*,
  platform.system_*            <-- the wildcard
```

The first twelve are exactly `DevCellBootstrapService::DEV_CELL_MCP_TOOLS`. The last two are
**operator widenings** layered on top (the grant is applied as a floor, and widenings are
preserved across re-bootstrap).

`platform.system_*` is, verbatim, the pattern `Mcp::Principal`'s own overlay comment names as the
motivating hazard:

> "one over-broad pattern — `platform.system_*`, or a careless `platform.*` — is an
> unattributed, unapproved, unaudited destroy."

And `DevCellBootstrapService` documents the opposite intent for this exact role:

> "Deliberately excludes ... every `system_*` fleet-mutation tool — a dev cell reads the graph
> and files new learnings/knowledge/skills; it does not curate the graph or run fleet ops."

## Result 3 — 205 of the 213 are reachable today

| | count |
|---|---|
| map-elevated, not overlay-denied (the 213) | 213 |
| …reachable by the live grant | **205** |
| …unreachable today | 8 |
| destroy-shaped elevated actions the glob would reach, but the overlay blocks | 37 |

All 205 are reached by the single `platform.system_*` pattern. Sharpest examples, each with the
per-action permission an instance principal skips:

```
system_grant_instance_mcp_tools        system.node_instances.manage
system_mint_peer_capability_token      system.node_instances.manage
system_launch_agent_fleet              system.node_instances.manage
system_expose_service_publicly         system.ingress.manage
system_expose_service_public_tcp       system.ingress.manage
system_sdwan_accept_federation_peer    system.sdwan.federation.manage
system_multi_tenant_isolation          system.sdwan.federation.manage
system_deploy_platform                 system.platform.deploy
system_sdwan_create_access_grant       system.sdwan.user_devices.manage
```

The overlay does work where it applies — `system_terminate_instance` and `delete_knowledge` both
came back `DENIED(overlay)` as controls.

## Result 4 — two defects the survey surfaced (filed)

**`01a00672-242e` — the grant is self-mutable, so 213 is not a ceiling.**
`system_grant_instance_mcp_tools` is not destroy-shaped, is matched by the live glob, and its
terminal function (`system_fleet_tool.rb:2206`) has *no* permission rung at all — it resolves the
peer from a caller-supplied `instance_id` and calls `grant_mcp_tools!(mode: :replace)`.
`enforce_action_scope!` does not help: the pinned action *is* the grant-rewriting one.

Measured closure: **243 actions reachable now → 533 after one self-grant of `platform.*`**,
unlocking 290 more including `approve_plan`, `validate_plan`, `create_agent_goal`,
`decompose_goal`, `list_intervention_policies`. The 8 "unreachable today" actions are one call
away. Same hole in the sibling `grant_instance_peer_skills`.

**`01a00672-74e7` — `enabled: false` is not a brake.**
The resolver is `NodeInstancePeer.where(node_instance_id: …).pick(:granted_mcp_tools)` — it
consults neither `enabled` nor `status`. The live row is `enabled: false` and its grant applies in
full. There is currently no operator-facing off switch for an instance principal short of
terminating the instance or editing the JSONB column.

## What this means for the parked decision

The "213 newly denied actions" objection **does not survive the survey**, for a reason that was
not visible without it:

- The blast radius is **one peer**, not a fleet.
- That peer's *designed* function — the dev-loop plus MCP-first recall — uses **zero** of the 213.
  Its twelve intended tools are core dev-loop and knowledge tools, none of which carry an elevated
  per-action entry.
- Everything at risk of being "newly denied" arrives via a single operator widening that the
  owning service's own comment says should not be there.

So enforcing per-action permissions for instance principals would break nothing that is designed
to work, while closing 205 currently-reachable elevated actions.

Two independent remediations, in increasing cost:

1. **Data, immediate, reversible, no deploy** — drop `platform.system_*` from the one live grant.
   Takes reachable-elevated from 205 to ~0 on its own. This is an operator action on live data and
   is **not** something to do from the improvement loop.
2. **Code, structural** — make instance principals consult `ACTION_PERMISSIONS` (offer
   `01a003aa-5702`), and close the self-grant hole (`01a00672-242e`) so the grant means something.

(1) without (2) leaves the hole open for the next grant. (2) without (1) leaves a live wildcard in
place until it deploys. The self-grant defect argues for doing (1) first regardless, since while it
stands, any narrowing of the grant can be undone by the principal it was narrowing.

## Reproduction

```
# 213-set (local, branch code)
bundle exec rails runner <scratch>/survey_actions.rb
```

The live half was a single read-only query against the control-plane database —
`SELECT jsonb_pretty(to_jsonb(t)) FROM system_node_instance_peers t;` — run through the
maintainer break-glass path, which was armed and revoked in the same command and confirmed
`REVOKED` at the end of the survey. Host addresses and the break-glass invocation are
deliberately not reproduced here; see `CLAUDE.local.md` for the maintainer-local access paths.

Nothing in the live half was written. The predicates behind Result 1 (`destructive_tool?`, glob
matching) were **executed** rather than read, which is what makes the 205/213 figure a
measurement rather than an estimate.
