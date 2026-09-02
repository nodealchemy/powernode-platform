# Ops Control-Plane Topology: Where Destructive Operations Live

> Status: design recommendation, 2026-07-28. Companion to
> [ops-hub-management-and-devcell-design.md](./ops-hub-management-and-devcell-design.md)
> (dev-cell provisioning grades) and [ops-hub-watchdog.md](./ops-hub-watchdog.md)
> (the external watchdog this design generalizes). Proposed code changes are
> marked **[NEW]**.
>
> **Implementation status, updated 2026-07-29** (the doc below is the original
> recommendation; it is left unedited except where a later finding proved a
> claim FALSE, which is corrected in place under a bold **Correction** marker —
> see §2):
>
> | Migration step | State |
> |---|---|
> | 1. Provision `ops-cell` | **DONE** — VM 9003 on dna, pet (`lifecycle_class: persistent`), lean 6-module `powernode-ops-cell` template, enrolled and composing |
> | 2. User-principal MCP + scoped tokens | **NOT STARTED** — and the "scoped tokens" half has no seam to build on: §2's claim that the registrar already enforces a token-permission intersection was FALSE (see the Correction in §2), so this step must now BUILD that control, not merely configure it. Also blocked on an operator-set Claude Code credential; the managed tmux session cannot start until then, so the principal it authenticates as is still unverified (see "Open uncertainties") |
> | 3. Demote serial console to logged break-glass | not started |
> | 4. Instance-grant deny-overlay **[NEW]** | **DONE and LIVE** — `Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS`, deny wins over any grant incl. exact-name; 60 destroy-shaped tools unreachable by any instance principal |
> | 5. `require_approval` chains for destructive categories | not started |
> | 6. Enable `NodeInstancePeer` for ops-cell | not started |
>
> The §2 finding that motivated step 4 was **independently verified** before
> implementing, not taken on trust: `mcp_platform_tool_registrar.rb`'s
> `return if instance_authorized` skips `has_permission?`, and
> `system_fleet_tool.rb#action_permitted?`'s `return true if @user.nil?` skips
> the per-action map — so the grant glob was genuinely the only control. Both
> call sites were read directly.
>
> That sentence originally said the early return skips "both `has_permission?`
> and the token intersection". **There was no token intersection to skip**
> (IMP-a18f5a8ed393, 2026-08-29): the registrar carried a `token:` kwarg that no
> caller passed, so the branch reading it was dead on every path and has been
> deleted. The finding's conclusion is unchanged and in fact stronger — one
> fewer layer existed than was credited.

**The question.** Should Claude Code (the operator's destructive-ops driver) run on
ops-hub itself, on a new dedicated instance, or on the hypervisor `dna`? And what is
the long-term dev / operations / control-plane management structure — including the
principal model for destructive MCP tools and where peer-to-peer skill invocation fits?

---

## Decision

**Winner: a three-tier structure whose center is option B — a dedicated ops
NodeInstance ("ops-cell") running the shipped `claude-tmux` module, speaking to
ops-hub's MCP as a *user* principal.** Option A (claude-tmux on ops-hub) is rejected.
Option C (full agent tooling on `dna`) is rejected as a primary seat but *retained,
minimal and dumb, as the break-glass tier* — which it already is today.

| Tier | Lives on | Authority | Exists? |
|---|---|---|---|
| **0 — Break-glass** | `dna` (hypervisor) | root + `qm`; no platform dependency | Yes (watchdog, qm, serial console) |
| **1 — Management seat** | **ops-cell** (new NodeInstance on dna) | Claude Code via claude-tmux; MCP as **user principal** with scoped tokens | Module shipped; instance is new. **Scoped tokens do NOT exist** — no token narrows a user's authority (see the Correction in §2) |
| **2 — Autonomous ops** | ops-hub (platform agents) + fleet instances | Ai::Agent intervention policies + ApprovalChain; instance principals default-deny, read/diagnostic only | Yes; needs grant hygiene **[NEW]** |

The organizing rule, generalized from the 2026-07-27 self-detach incident (51 min
down, ended only by reboot): **anything that must function while ops-hub is broken
cannot live on ops-hub — and anything that can break ops-hub must not share its
resources.** The in-platform watchdog (`InstanceStatusSensor`, runs in Sidekiq) was
detached first and monitored nothing; the external watchdog on `dna` is the fix and
the pattern.

---

## 1. Failure domains: what must survive ops-hub being down

Operations that were actually needed during the incident, and where they can only live:

| Operation | Requires | Can only live |
|---|---|---|
| Reboot / stop / start VM 600 | `qm` on the hypervisor | `dna` |
| Read ops-hub's journal when SSH is dead | serial console (`socat` → `600.serial0`) or `qm` | `dna` |
| Repair /persist composition offline | `qm stop` + `--lock` + mount (see memory: dual-mount truncation) | `dna` |
| Select boot entry / A-B fallback | `systemd-boot` oneshot via ESP | `dna` (or in-guest pre-boot) |
| Detect ops-hub death at all | a prober outside the guest | `dna` (external watchdog — shipped) |

None of these may depend on the platform API, Vault, or MCP — all three are served by
the thing that is down. Hence **Tier 0 stays on `dna` and stays dumb**: scripts and
runbooks, not agents. `dna` is deliberately *not* made a management seat: it is the
hypervisor under every guest including ops-hub itself; enlarging its attack surface or
coupling it to platform credentials converts a guest-level failure domain into a
host-level one. (Optional, low-priority: a manually-installed Claude Code CLI on `dna`
with a root-only local key, for assisted recovery when the platform is down. It would
need no MCP — its tools are `qm`, ssh, journals. Deferred; the runbooks cover Tier 0.)

Everything else — terminate/provision instances, module and cert operations, SDWAN
changes, CVE remediation — goes through the platform API and therefore **requires
ops-hub to be up regardless of where the client sits**. Co-locating the client with
ops-hub buys zero availability; it only adds shared fate. That is the core case
against option A:

- **Shared fate at the worst moment.** A management session on ops-hub degrades
  exactly when it is needed — tonight's incident class (DB saturation → cascading
  detach) would have taken the seat down with the platform.
- **Resource competition.** A heavy Claude session (builds, log scans, embeddings)
  competes with Postgres/Sidekiq on the control-plane VM. The incident's trigger was
  precisely resource saturation on ops-hub.
- **The rails-runner temptation.** A root shell on ops-hub makes `rails runner` the
  path of least resistance — recreating the serial-console problem (unaudited local
  mutation bypassing every MCP layer) with *less* friction, not more.
- **Blast radius.** An errant or compromised agent session would sit on the box with
  Postgres, Vault access, and module-signing material.

**ops-cell (Tier 1)** is a sibling of dev-cell (VM 9000): a NodeInstance managed by
ops-hub, on `dna`, running `claude-tmux`
([extensions/system/docs/CLAUDE_TMUX_MODULE.md](../../extensions/system/docs/CLAUDE_TMUX_MODULE.md)
— systemd-supervised tmux, Vault-injected Anthropic key, mTLS-only credential pull;
dev-cell is its first consumer, so the pattern is proven). Because module composition
is applied at boot, ops-cell keeps running when ops-hub is down — the session
survives, can observe the outage, and can SSH to `dna` to drive Tier 0. It shares the
`dna` hardware failure domain with ops-hub, which is unavoidable in a one-hypervisor
fleet and acceptable: recovery from `dna` itself failing is physical/iLO, out of
platform scope. (Pick its VMID mindfully — the dev/ops-hub VMID collision has
happened before.)

## 2. Principal model: destructive ops are user-principal-only

The instance-principal path is default-deny by construction, but **once a tool is
granted, an instance principal bypasses BOTH permission layers**:

1. The only gate is the glob match in
   [server/app/models/mcp/principal.rb:88-93](../../server/app/models/mcp/principal.rb)
   applied at
   [server/app/controllers/api/v1/mcp/streamable_http_controller.rb:487-490](../../server/app/controllers/api/v1/mcp/streamable_http_controller.rb).
2. The registrar's per-tool permission check is then explicitly skipped
   (`return if instance_authorized`,
   [server/app/services/ai/tools/mcp_platform_tool_registrar.rb:161-176](../../server/app/services/ai/tools/mcp_platform_tool_registrar.rb) — BUG-R).
3. Inside the tool body, `@user.nil?` triggers the internal/system bypass
   (`return true if @user.nil?`,
   [extensions/system/server/app/services/ai/tools/system_fleet_tool.rb:1374-1386](../../extensions/system/server/app/services/ai/tools/system_fleet_tool.rb))
   — so the per-action table mapping `system_terminate_instance` /
   `system_destroy_instance` to `system.instances.control`
   (system_fleet_tool.rb:67-68) is **never consulted** for an instance principal.

So a single over-broad grant (`platform.system_*`) hands an instance
terminate/destroy with no permission check, no approval chain, and no
human-attributable subject. And the three-layer history (BUG-Q/R/S: sessions,
registrar, claimant — each patched separately to tolerate userless callers) shows the
stack structurally assumes a User; every privileged path pushed through instance
principals is another round of that treadmill.

**Recommendation:**

- **Destructive/irreversible ops run as a user principal, always.** Users pass
  `enforce_permission!` per-tool (registrar:178), are session-bound
  ([server/app/models/mcp_session.rb:21-29](../../server/app/models/mcp_session.rb)),
  and attributable to a human. The ops-cell operator authenticates the MCP
  connection with their own OAuth identity.
- **Scope routine authority with MCP token intersection.** Mint a routine token for
  the ops-cell session that *excludes* `system.instances.control` and similar, and a
  break-glass token with full authority. Escalation = re-auth, not a standing grant.
  This is still the right authorization seam, and the recommendation stands.

  > **Correction (IMP-a18f5a8ed393, 2026-08-29). This bullet originally claimed
  > "the registrar already enforces token-permission intersection
  > (registrar:183-188) … it exists and is enforced today". That was FALSE. THE
  > CONTROL DOES NOT EXIST.** (The quoted "registrar:183-188" was the original's
  > own citation and did not point at the branch either; when deleted it was at
  > `mcp_platform_tool_registrar.rb:289-294`.) The registrar carried a `token:` kwarg and a branch
  > reading `token&.permissions` / `token.has_permission?`, but none of its four
  > callers (`streamable_http_controller.rb`, `agent_tool_bridge_service.rb`,
  > `skill_recipe_runner.rb`, `mcp/protocol_service.rb`) ever passed one, so the
  > branch was unreachable on every path. It was deleted rather than left standing
  > as an inert gate that reads as protection. Today a user principal's authority
  > over MCP is bounded by `user.has_permission?` alone; **no token narrows it**.
  >
  > **Step 2 must therefore BUILD this seam, not configure it.** What exists to
  > build on: MCP bearer tokens are `Doorkeeper::AccessToken`s, which do carry real
  > OAuth **scopes** (verified in
  > [`server/app/controllers/concerns/mcp_token_authentication.rb`](../../server/app/controllers/concerns/mcp_token_authentication.rb)).
  >
  > **Map the ACCEPTED scopes, not the advertised ones — the gap is the trap.**
  > Doorkeeper *accepts* eight: `read`, `write`, `admin`, `billing`, `users`,
  > `webhooks`, `workflows`, `files` (`config/initializers/doorkeeper.rb:124`;
  > default `:read` at `:121`). Only four are *advertised* — `read`, `write`,
  > `workflows`, `files` (`well_known_controller.rb:48`). A mapping built from the
  > advertised list lets a token minted with `admin` fall straight through it.
  >
  > What is missing is (a) that scope→permission mapping, so a scope can narrow the
  > permission set a tool call is checked against, (b) a mint-time surface for
  > issuing a deliberately narrowed token — no UI offers one — and (c) the
  > enforcement point in `enforce_permission!` itself. Note that the deleted branch
  > could **not** simply be re-wired: a Doorkeeper token responds to neither
  > `#permissions` nor `#has_permission?`. (`UserToken` does respond to both, but
  > no `UserToken` ever reaches the registrar: the only arm that authenticates one
  > *on a path leading there* is the `[DEPRECATED]`-logged ActionCable path, which
  > passes no token to it. An earlier revision of this note went further and said
  > `UserToken` "is never minted in production" and has "no production callers".
  > Both were FALSE and are corrected here: an extension mints an impersonation
  > `UserToken` on a live path and authenticates it on another.
  > Neither claim was ever the reason the branch was dead — only "no token reaches
  > the registrar" is. And since IMP-f86b6be57e74 `UserToken#has_permission?`
  > resolves live from the user, so its `permissions` column narrows nothing
  > either. Note this is an extension-only path; in core mode nothing mints a
  > `UserToken` at all.)
  >
  > Until all three land, do not treat "mint a routine token" as an available
  > mitigation anywhere else in this doc or in operational runbooks: a narrowed
  > token would be accepted and would narrow nothing.
- **Instance principals never hold destroy-shaped tools.** Keep
  `granted_mcp_tools` to read/diagnostic/dev-loop patterns. **[NEW]** Add a small
  static deny-overlay so `Mcp::Principal#may_invoke?` (or
  `NodeInstancePeer#grant_mcp_tools!`,
  [extensions/system/server/app/models/system/node_instance_peer.rb:85-91](../../extensions/system/server/app/models/system/node_instance_peer.rb))
  refuses patterns matching `platform.system_terminate_*`,
  `platform.system_destroy_*`, `platform.system_delete_*`,
  `platform.system_rotate_vault_transit_pepper` regardless of grant — converting
  today's convention into an invariant.
- **Agent-initiated destructive categories route through `require_approval`.**
  `Ai::InterventionPolicy` supports `require_approval`/`block`
  ([server/app/models/ai/intervention_policy.rb:8](../../server/app/models/ai/intervention_policy.rb))
  bound to an `Ai::ApprovalChain` whose approvers resolve by user/permission/role
  with timeouts and sequential steps
  ([server/app/models/ai/approval_chain.rb:13,82-95](../../server/app/models/ai/approval_chain.rb))
  — real enforcement, already used by the eight system agents. The approval click is
  the human-attributable second factor for Tier 2.

## 3. Peer-to-peer skills (L2.5 / A2A)

`NodeInstancePeer` gives a separately-gated delegation plane: operator-activation
(`enabled: false` by default, node_instance_peer.rb:4-8), default-deny
`granted_peer_skills` globs (:26-27, :95-108), reputation drift (+0.005 / −0.02 per
execution, :50-60), a 24 h rolling `daily_decision_budget` (:64-76), and offline-
verified capability tokens with fail-closed revocation publishing (F2-04, :42-47).

**Fit for ops: good for bounded diagnostic and well-scoped remediation delegation;
wrong for destructive ops.** Trust scores and budgets are *rate/reputation* controls,
not authorization; and offline token verification means revocation has latency — the
opposite of what you want on a terminate. Concretely:

- Enable peering for ops-cell with diagnostic skills only (health probes, log
  collection, composition inspection) so it can fan out across the fleet without
  ops-hub proxying every hop.
- Keep destructive skills out of every `granted_peer_skills`; the **[NEW]**
  deny-overlay above should cover this field too.
- Use `trust_score` as a *gate input* — intervention-policy conditions already
  support `trust_tier_minimum` (intervention_policy.rb:113-118) — never as a
  permission substitute.

## 4. Blast radius and audit

- **MCP path (Tiers 1–2):** `McpSession` binds every session to a principal (user or
  `principal_kind`/`principal_subject_id` for instances, mcp_session.rb:5-29);
  `McpToolExecution` includes `Auditable` and records per-call status/params
  ([server/app/models/mcp_tool_execution.rb:4-15](../../server/app/models/mcp_tool_execution.rb));
  the registrar logs every execution with user/account/agent (registrar:131-135).
  *Verify:* that `McpToolExecution` rows are written on the streamable-HTTP path for
  all `platform.*` calls, not only ProtocolService tools — I did not trace the write
  site.
- **Approvals:** `ApprovalRequest` rows record the chain, steps, and approver — the
  durable "who said yes" for Tier 2.
- **Serial console:** has no audit trail and today is the *default* destructive path.
  This design demotes it to Tier 0 break-glass only. **[NEW, small]** wrap it on
  `dna` in a `pn-breakglass` script that `script(1)`-logs the transcript locally and
  back-syncs to the platform audit log when ops-hub returns.

## 5. Migration path (no dev-plane dependency)

1. **Provision ops-cell** on `dna` from an existing template + `claude-tmux` +
   Vault-injected key — all shipped machinery; dev-cell is the working precedent.
   *This is the smallest useful first step and is valuable on its own:* the operator
   gets an auditable, dev-independent management seat pointed at the live plane.
2. **Point its MCP at ops-hub as the operator's user principal**; mint the routine
   (reduced) and break-glass (full) MCP tokens; document the escalation step.
   — **Blocked, and larger than it reads: the token-scoping seam does not exist**
   (see the Correction in §2). A "reduced" token is accepted today and narrows
   nothing, so this step must first BUILD the scope→permission mapping and a
   mint-time surface. Do not tick it off by minting tokens.
3. **Demote the serial console** to documented break-glass; add the logging wrapper
   on `dna`.
4. **[NEW]** Land the instance-grant deny-overlay (small change in
   `Mcp::Principal#may_invoke?` + `grant_mcp_tools!`/`grant_peer_skills!`).
5. **Author `require_approval` intervention policies + an ApprovalChain** for
   destructive action categories across the system agents that lack them.
6. **Enable `NodeInstancePeer` for ops-cell** with diagnostic-only peer skills.
7. Retire the dev workstation's management role (its dev role follows the separate
   dev-cell track and its existing hard gate: no decommission until the replacement
   dev VM exists).

## Rejected alternatives

- **A — claude-tmux on ops-hub:** shared fate, resource competition on the control
  plane, unaudited local-root temptation, maximal blast radius (§1).
- **C — full agent tooling on dna:** correct for Tier 0 only; as a primary seat it
  couples the hypervisor to platform credentials and grows the host attack surface.
- **Instance-principal destructive grants:** double permission bypass once granted
  (§2); structurally fights the User-assuming stack (BUG-Q/R/S).

## Open uncertainties

- The MCP client identity claude-tmux sessions use by default: the module docs cover
  Anthropic-key injection, not MCP OAuth. Assumed (and recommended) configuration:
  operator's own user OAuth. Verify at ops-cell provisioning time.
- `McpToolExecution` coverage on the streamable path (§4).
- Whether ops-cell should be pool-provisioned (Grade A) or pet (Grade B) per the
  dev-cell grades doc — recommend **pet** (it is the management seat; it must not be
  reaped), but that interacts with the pool-reaper design and deserves a check.
