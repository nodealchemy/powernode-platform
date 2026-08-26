# MCP Environment Isolation: Production, Sandbox, and Federated Destinations

**Status**: design / recommendation — nothing here is implemented yet.
**Date**: 2026-08-25
**Scope**: Part I — the two-server prod/sandbox hazard as originally posed. Part II (§7–§12) —
operator-requested expansion: proxy-side routing for an arbitrary number of destinations
(production, local dev, federated peers). **Part II revises the Part I recommendation; §12 is the
current recommendation.**

## 1. The hazard, concretely

Two MCP servers are registered at **user scope** in `~/.claude.json`, so both are live in every
Claude Code session on this machine:

| Name | URL | Reaches |
|---|---|---|
| `powernode` | `http://127.0.0.1:18443/mcp` | **production ops-hub** (via the root-owned `dev-cell-mcp-proxy.js`, which presents the node's mTLS client cert) |
| `powernode-local` | `http://localhost:3000/api/v1/mcp/message` | dev sandbox Rails on `powernode_development` (Bearer token) |

Both advertise a near-identical ~615-tool catalog with identical tool names. The only
distinguisher of a production call is the prefix: `mcp__powernode__X` vs
`mcp__powernode_local__X`. Both URLs are localhost, so the address carries no signal. A
mis-prefixed state-changing call is a real fleet action against a **self-hosted** control plane —
some calls can take down the platform issuing them (see the self-detach outage memory).

Sessions frequently run in `bypassPermissions` mode and spawn subagents that inherit it, so any
defense that only works when permission prompts are enabled is inadequate.

### An aggravating config mess found during investigation

`powernode` is *defined three different ways* in this repo's config, with three different URLs:

- `~/.claude.json` (user scope): `http://127.0.0.1:18443/mcp` — **this one wins and is the only one live**
- `.claude/settings.json` `mcpServers`: `http://localhost:3000/api/v1/mcp/message` — i.e. **`powernode` = the sandbox**
- `.claude/settings.local.json` `mcpServers`: `https://ops-hub.ipnode.us/api/v1/mcp/message` — production, direct, no proxy

Verified empirically that the settings-file `mcpServers` blocks are **inert**: `claude mcp list`
connects only the two user-scope servers (plus claude.ai connectors), and the `filesystem` /
`sequential-thinking` servers declared in `.claude/settings.json` are not connected in this
session either. Claude Code reads MCP servers from `~/.claude.json` (user/local scope) and
`.mcp.json` (project scope), not from settings files. These blocks are decoys — but dangerous
ones: the project-settings block literally says "`powernode` is the dev server", and anyone who
"fixes" MCP registration by copying it into a live source flips the meaning of the production
prefix.

## 2. Levers verified (what was tested, what was found)

### L1 — Claude Code permission rules (`permissions.deny` / `ask`)  ✅ strongest client-side lever

From the current permissions docs (code.claude.com/docs/en/permissions, permission-modes):

- MCP rules match `mcp__server` (whole server), `mcp__server__tool` (exact), and **deny/ask rules
  accept globs in the tool-name position** that must match the full name — e.g.
  `mcp__powernode__platform_system_provision_instance` or
  `mcp__powernode__platform_system_sdwan_create_*`.
- A tool matched by a name/glob **deny** rule is **removed from Claude's context entirely** — the
  model never sees it, so it cannot mis-call it. This is exactly "structural rather than
  attentional".
- **"Deny rules block in every mode, including `bypassPermissions`."** (verbatim from the
  permission-modes doc). Allow rules have no effect in bypass; deny rules do. This lever does
  **not** silently no-op under bypass.
- **`ask` rules are in the "actions no mode auto-approves" list**: they prompt even in
  `bypassPermissions`. In non-interactive `-p` runs the call is **denied instead** — fails closed.
- Precedence is deny → ask → allow, first match wins; a managed/user deny cannot be overridden by
  a project allow.
- Server segment in allow-globs must be literal (`mcp__powernode__*` fine); deny globs are even
  freer (`mcp__*` legal). Rules can live at user, project, or local scope; user scope covers every
  session on the machine.

### L2 — PreToolUse hooks  ✅ works, with one caveat

- Hook stdin includes `tool_name` (`mcp__powernode__platform_system_x`), full `tool_input`, and
  `permission_mode` — whose documented values **include `"bypassPermissions"`**, which is direct
  evidence hooks run in that mode.
- Matchers are regex: `mcp__powernode__.*` is valid.
- Exit code 2 or `permissionDecision: "deny"` blocks the call, and the docs state a blocking hook
  "stops the tool call before permission rules are evaluated", with no mode qualifier.
- **Caveat**: unlike deny rules, the docs never *explicitly* say a hook block is honored in
  `bypassPermissions`. Confidence is high (hooks run pre-permission-evaluation; the mode is passed
  in), but do a 5-minute live test (hook that denies one harmless read) before treating a hook as
  the load-bearing layer. The repo already runs 14 PostToolUse + SessionStart/Stop hooks, so the
  operational pattern is established; there is currently **no** PreToolUse hook.

### L3 — MCP scope separation  ⚠ partial fit

- Scope precedence: local (per-project entry in `~/.claude.json`) > project (`.mcp.json`) > user.
  Same-name duplicates: highest scope wins wholesale.
- Both servers are user-scope today, hence live everywhere. Registering the sandbox only in a
  dedicated directory would remove it from fleet-ops sessions — but the sandbox's documented use
  (testing MCP tool changes without a deploy) happens **in this same repo**, and comparison
  sessions legitimately want both. Scope separation alone cannot fully separate them, and it does
  nothing about production tools being callable from anywhere. Useful hygiene, not the core fix.

### L4 — Server-side gating on production  ✅ already half-built, and the strongest layer overall

Read from `server/app/models/mcp/principal.rb` and
`server/app/services/ai/tools/mcp_platform_tool_registrar.rb`:

- The dev-cell reaches production through the mTLS proxy ⇒ it is an **instance principal**
  (`Principal.for_instance_cn`). Instance principals are **default-deny**: invocable = matches a
  granted glob AND not destroy-shaped.
- `DESTRUCTIVE_TOOL_PATTERNS` (`*terminate*`, `*destroy*`, `*delete*`, `*purge*`, `*revoke*`,
  `*rotate*`, `emergency_*`, `*_stop_instance`, `*_reboot_instance`, `*upgrade_boot_image*`,
  `*_hold`, `*_deferred_operation`, `*intervention_policy`, …) is a static overlay that **no grant
  can override**, re-applied even to nested/delegated tool executions.
- `Principal#filter_tools` filters **advertisement** through the same check — ungranted and
  destroy-shaped tools are not even listed. Confirmed against this session's actual
  `mcp__powernode__*` catalog: **no `terminate`/`destroy`/`delete` verbs are advertised**, while
  `system_provision_instance`, `system_promote_module_version`, `system_rollback_module_version`,
  storage-migration and `system_sdwan_*` mutations **are**.
- So the premise "both servers advertise the same destructive verbs" is only true of the
  **sandbox** (Bearer token ⇒ user principal ⇒ full catalog, `may_invoke?` returns true for
  users). Production, from this cell, already lacks the destroy-shaped tier. The residual
  production hazard is the **granted mutation tier**: provision, module promote/rollback,
  deploy_platform, SDWAN create/update, storage migration, expose_service_*, etc.
- **Hole found**: `platform_system_grant_instance_mcp_tools` is itself granted and advertised to
  this instance principal, and "grant" matches no destructive pattern — an instance can **widen
  its own grant** (the session has in fact used `mode:"add"` on itself; see the
  instance-grant memory). Any grant-trim is therefore soft against compounded confusion until this
  tool is excluded from the instance's own grant (or gated), though a simple mis-prefix accident
  would not traverse it.
- The account **kill switch** (`Ai::Autonomy::KillSwitchService`) is an account-wide emergency
  stop for platform-side agentic activity — an incident response, not a per-call gate for external
  MCP clients. Not a lever here.

### L5 — `requiresUserInteraction` tool annotation  ✅ real, unused today

A server can set `_meta["anthropic/requiresUserInteraction"]: true` on a tool in `tools/list`.
Claude Code then prompts **on every call, even in `acceptEdits`, `auto`, and `bypassPermissions`**,
offers no "don't ask again", ignores allow rules, and in non-interactive contexts **denies**
(fails closed). Grepped `server/app`: the platform does not emit this annotation anywhere today.
Powerful but blunt: it binds *every* Claude Code client of the production server, including
headless ones, so it fits only a tiny "a human must be in the loop, always" tier (e.g.
`approve_storage_migration`, `deploy_platform`).

### L6 — The dev-cell proxy as a chokepoint  ⚠ possible, second-best

`/usr/local/bin/dev-cell-mcp-proxy.js` (root-owned, the only holder of the node's mTLS key) is
already an allowlist-shaped trust boundary and forwards the `mcp-name` header, which carries the
tool name on `tools/call`. It could deny by tool-name pattern. Caveats: `mcp-name` is
client-supplied (an honest client sends the truth; enforcement of header/body agreement is
upstream), bodies are deliberately streamed rather than parsed, and the proxy protects only
clients that use it — the server-side grant (L4) dominates it on every axis. Also note:
**the proxy itself is unauthenticated on 127.0.0.1:18443**, so any local process — including a
Bash `curl` from a session — can drive production tools without touching the MCP tool layer at
all.

### L7 — Renaming (`powernode` → `powernode-PROD`)  ✗ not structural

Changes every existing skill/doc/memory reference and retrains habits, while a mis-typed prefix
remains a valid call. Attentional only; rejected as a primary control. (The *sandbox* name is
already distinct.)

## 3. Ranked options

1. **Server-side grant trim on production (structural, fails closed, protects every client).**
   Narrow the dev-cell instance's tool grant to the verbs the workflow actually uses. Derive the
   list from production's `McpToolExecution` audit rows for this principal (e.g. last 60 days)
   rather than from guesswork. Ungranted verbs vanish from advertisement (out of model context)
   and 403 if called. Include excluding `system_grant_instance_mcp_tools` from the instance's own
   grant so the trim cannot be self-reversed; re-widening then goes through a user principal
   (operator UI / authenticated API), which is the correct authority anyway.
   *Tradeoffs*: needs a one-time audit-driven inventory; a genuinely new production verb needs an
   operator re-grant (one call, but by a human); the grant-change/severed-session gotcha means the
   trim must be applied carefully (`mode:"add"`-style semantics, verify before dropping).
2. **Claude Code user-scope `permissions.deny` globs for the same never-used families on
   `mcp__powernode__` only** (e.g. `mcp__powernode__platform_system_provision_instance`,
   `mcp__powernode__platform_system_sdwan_create_*`, `…update_*`, storage-migration mutations).
   Documented to block **in every mode including bypass** and to remove the tools from context.
   Zero friction on reads and on used verbs; sandbox prefix untouched. Redundant with (1) by
   design — this layer holds if the server grant ever drifts wide again, and (1) holds if local
   config is edited.
3. **`ask` rules for the rare-but-legitimate destructive verbs** that must stay reachable
   (`mcp__powernode__platform_system_rollback_module_version`,
   `…approve_storage_migration`, `…deploy_platform` if desired): prompts even under bypass,
   auto-denies in non-interactive runs. Friction lands only on calls that are rare and worth a
   breath. Do **not** apply to high-frequency loop verbs (`dev_*`, abort/cancel task, module
   build dispatch) or automation breaks.
4. **Config hygiene (do regardless):** delete the three inert `mcpServers` blocks from
   `.claude/settings.json` / `.claude/settings.local.json` (especially the one equating
   `powernode` with the dev server), and move `powernode-local` from user scope to local/project
   scope in the directories where sandbox testing actually happens, so most fleet-ops sessions
   simply do not contain a second lookalike server.
5. **PreToolUse hook** (optional, later): an arming-style gate ("production mutations require a
   session marker") is more expressive than static rules, but it is a script that can rot, its
   bypass-mode blocking is unverified in docs, and layers 1–3 already cover the accident class.
   Add only if a need appears that static deny/ask cannot express.
6. **`requiresUserInteraction` annotation** (platform change, later): reserve for a tiny
   always-human tier; do not spray across the catalog (kills headless clients).

## 4. Recommendation (Part I — revised by §12)

**Adopt 1 + 2 + 3 + 4 together.** The primary defense is the production server's own
default-deny instance grant, trimmed to observed usage and made non-self-widening (1) — it is the
only layer that fails closed for every client, every mode, and every future session, and the
platform already owns all the machinery (`Principal`, grants, `filter_tools`,
`DESTRUCTIVE_TOOL_PATTERNS`). Claude Code deny globs (2) mirror the same trim client-side so each
layer covers the other's drift; ask-rules (3) put a human on the few destructive verbs that must
remain; hygiene (4) removes the lookalike server from sessions that don't need it and deletes the
config decoys. Reads stay frictionless; the routinely-used mutation verbs stay frictionless; only
never-used and rare-destructive verbs change behavior.

## 5. What this does NOT protect against

- **Bash-level bypass**: the proxy on 127.0.0.1:18443 is unauthenticated locally and
  `Bash(curl:*)` is allow-listed — a hand-rolled `curl` `tools/call` skips MCP permission rules
  entirely. Only the server-side grant (layer 1) catches it. Same for direct authenticated calls
  to `https://ops-hub.ipnode.us`.
- **Verbs that stay granted**: a mis-prefixed `deploy_platform` / `promote_module_version` /
  `abort_task` is still a production action. The design shrinks the dangerous surface; it cannot
  eliminate verbs the workflow legitimately needs.
- **Self-regrant until fixed**: while `system_grant_instance_mcp_tools` remains in the instance
  grant, a sufficiently confused (or injected) agent can re-widen the grant with one deliberate
  call.
- **Other principals**: user-principal sessions (frontend, admin connectors) get the full catalog
  by design; nothing here constrains them.
- **Other machines/sessions**: user-scope deny rules live on this machine only; another cell with
  its own proxy needs the same grant trim (which is why layer 1 is primary).
- **Non-MCP channels**: `psql` to the wrong DB, `ssh`, `qm` — the prod/sandbox confusion class is
  broader than MCP.
- **Stale docs/config drift**: nothing stops a future edit re-adding a lookalike server; the
  deleted decoy blocks only stay deleted by convention.

## 6. Verification notes (for whoever implements)

- Before trimming: pull the distinct tool names this principal invoked from `McpToolExecution` on
  production; diff against the current grant; review the never-used remainder individually (bulk
  -op safety rule applies).
- After trimming: `tools/list` through the proxy must show the reduced set; a denied verb must
  403; `claude mcp list` still connects; a dev-loop iteration must complete end-to-end.
- Deny-rule sanity: startup warning check catches typo'd rules ("matches no known tool"); test one
  denied verb in a bypass-mode session and confirm the tool is absent from context.
- Hook route (if ever used): first verify an exit-2 PreToolUse block is honored in
  `bypassPermissions` on the installed CLI version.

---

# Part II — Proxy-side routing and federated destinations

## 7. The expanded question

The operator's hypothesis: rather than registering N MCP servers in the client, do destination
selection/routing inside the local proxy — and make the scheme extend to **federated instances**
(the platform federates across accounts/regions: `FederationPartner` model,
`system_sdwan_*federation*` verbs, a federation arm in `mcp_token_authentication.rb`). So: how
should a Claude Code session reach an arbitrary number of Powernode instances — prod, local dev,
federated peers — without a combinatorial explosion of registered servers, and without the wrong
one being reachable by accident?

## 8. Q1 — Is proxy-side routing better than N registered servers? Only in one specific shape.

The decisive question is **what carries the destination identity**. Options, worst to best:

| Carrier | Shape | Verdict |
|---|---|---|
| Per-call tool argument | one server, `target_instance:` param on every call | **Worst.** The destination becomes a model-supplied string on every call — exactly the failure mode we are designing against, now with no prefix signal at all. |
| Session-level binding | a `select_instance` tool sets where subsequent calls go | **Worse than today.** Hidden mutable state: the destination is invisible in the call itself; a stale binding silently retargets an entire session. Subagents inherit or don't — either way ambiguously. |
| Single collapsed namespace, any variant | `mcp__powernode__X` means "whichever" | Destroys the only disambiguation signal that exists today. Routing that collapses the namespace makes the isolation problem strictly worse. |
| **Path segment, bound at registration** | proxy serves `/mcp/prod`, `/mcp/dev`, `/mcp/fed/<peer>`; the client registers one thin HTTP server per destination pointing at the corresponding path | **Right shape.** The destination is fixed in configuration, not chosen by the model per call. Each destination keeps a distinct tool prefix (`mcp__pn-prod__…`, `mcp__pn-dev__…`, `mcp__pn-fed-eu1__…`), so the prefix signal is preserved — and every registration is credential-free and three lines. |

So the honest answer: **proxy-side routing does not eliminate per-destination client
registrations, and should not try to.** What it eliminates is per-destination *credentials and
policy* in the client, and the marginal cost of adding a destination. The model can still
mis-pick a prefix between two registered servers — no routing scheme can remove that while
keeping both destinations reachable — which is why enforcement (§11) has to carry the safety, not
the namespace.

The context-size objection to N registrations ("615 tools × N") is real but solved by the same
mechanism either way: advertisement is already filtered per principal upstream
(`Principal#filter_tools`) — a trimmed prod grant, a federation peer's `allowed_capabilities`
scope, and proxy-side `tools/list` filtering (§11) each shrink what a destination adds to
context. A federated peer route advertising 20 granted capabilities costs 20 tool defs, not 615.

## 9. Q2 — Does routing preserve the proxy's security property? Yes, with discipline; the risk is real.

The proxy exists so `pnagent` (and every other local client) never holds `node.key` — with it, an
agent could re-call `dev_cell_bootstrap` and mint itself a Gitea deploy key. Verified in source:
root-owned, header allowlist (drops `authorization`/`cookie`/`x-forwarded-*`), single fixed
upstream (`const target = new URL(mcpUrl)`), method/path allowlist, slowloris and body-size
bounds.

Multi-destination routing changes it from "the thing that holds one credential" to "the thing
that holds all of them": node mTLS key (prod), the sandbox Doorkeeper bearer, and one shared
bearer per federation peer. Two honest observations:

- **Credential concentration is the proxy's existing job, done more.** Root-only custody is the
  point; extending it to the sandbox bearer is an *improvement* over today, where that token sits
  in user-readable `~/.claude.json` and is visible to every process running as the user.
- **A routing bug becomes a credential-confusion bug** — the new failure class. A request meant
  for `/mcp/dev` forwarded over the node-mTLS agent to prod is precisely the accident this design
  exists to prevent, now implemented in Node. Required discipline: a **static route table** (path
  → {upstream URL, credential, policy}) loaded at boot from root-only config; one dedicated
  `https.Agent` per destination constructed at boot, never selected dynamically from request
  content other than the path prefix; unknown path stays a 404 (fail closed, as today); no
  credential ever derived from an inbound header. The current 244-line single-target simplicity
  is a genuine security asset being spent — the routing core must stay small enough to review the
  way `Principal#may_invoke?` is reviewed (two independent critics; boot-critical-review memory
  applies in spirit).

## 10. Q3 — How the three auth arms compose

Verified in `server/app/controllers/concerns/mcp_token_authentication.rb` (order: mTLS →
federation → Doorkeeper) and `server/app/models/mcp/principal.rb`:

| Destination | Auth arm | Principal on the far side | Far-side posture |
|---|---|---|---|
| Production ops-hub | node mTLS (proxy holds `node.key`) | `:instance` | default-deny grant + `DESTRUCTIVE_TOOL_PATTERNS` overlay; advertisement filtered |
| Local dev sandbox | Doorkeeper bearer | `:user` | full catalog, `has_permission?` + token intersection; blast radius = one dev DB, no fleet |
| Federated peer | shared bearer + `X-Federation-Organization` header | `:federation` | default-deny, scoped to `FederationPartner#allowed_capabilities` (validated non-overbroad, `allowed_capabilities_not_overbroad`), destructive overlay applies, failure-throttled |

Composition rules for the router: each route sends **exactly one** arm's credentials —
node mTLS is never presented to a federated peer, federation bearers never to prod; the inbound
`authorization` header stays dropped on every route (the client holds no credentials, on any
arm). Trust ordering falls out of the far-side posture: federated peers are *already* the most
constrained destination server-side — the peer enforces its own capability scope, so our router
adds fan-out, not trust. The asymmetry worth stating: the **sandbox** is the least-guarded
destination by design (user principal, full catalog) — which is correct, because the design goal
is "sandbox unrestricted, production requires more".

## 11. Q4 — The proxy as enforcement point: stronger than every client-side lever, with one sharp caveat

If the proxy routes, it can also enforce, per destination:

- **`tools/list` filtering**: strip denied tool names from the prod route's advertisement. This
  removes them from *every* client's context — Claude Code in any permission mode, headless
  `pnagent`, non-Claude executors, raw `curl` — which client-side deny rules can only do for one
  configured client. Model-agnostic and immune to `bypassPermissions` by construction.
- **`tools/call` denial by name**: refuse destructive names on the prod route (HTTP 403 or a
  JSON-RPC error), allow-all on the dev route, pass-through on federation routes (the peer
  enforces its own scope).

**The caveat — what name does the proxy trust?** The proxy deliberately streams bodies without
parsing. The `Mcp-Name` header carries the tool name on `tools/call`, and the upstream controller
**enforces that the header mirrors the body** (`streamable_http_controller.rb:896-908` rejects a
mismatch with `-32020`) — so a client lying in the header either matches the body (deny was
correct) or gets rejected upstream. But that mirroring check is applied **only for stateless
protocol 2026-07-28+** (`return unless STATELESS_VERSIONS.include?(requested)` guard at
`:872`); a client negotiating an older stateful version could lie in the header while the body
does something else. Consequences:

- Against the *accident* class (an honest client mis-prefixing a call) header-based denial is
  fully sufficient.
- Against the *adversarial* class (a hostile local process evading the proxy's policy), the
  proxy must either (a) require/pin protocol 2026-07-28+ on policy-bearing routes and refuse
  requests without the stateless markers, or (b) buffer-and-parse JSON bodies for `tools/call`
  (bounded by the existing 10 MB cap). (a) is cheaper and matches the current v2 client runtime;
  (b) is airtight. Choose per route: (a) for prod is a reasonable start.

**Does this subsume Part I?** Partially, and it changes the recommendation:

- It **replaces layer 2** (client-side `permissions.deny` globs). Proxy-side list-filtering +
  call-denial does everything the deny globs did, for every client instead of one, and also
  closes the "`curl` through the proxy" bypass flagged in §5.
- It does **not** replace layer 1 (server-side grant trim). The grant is authoritative at the
  destination and protects paths that never touch this proxy — other cells, direct authenticated
  calls to `ops-hub.ipnode.us`, future clients. The proxy policy is this *cell's* enforcement;
  the grant is the *fleet's*.
- It does **not** replace layer 3 (ask-rules): only the interactive client can put a human
  prompt on rare destructive verbs. A proxy can deny or allow; it cannot ask.

## 12. Revised recommendation

**What changed and why**: the proxy-routing expansion replaces the client-side deny-glob layer
with proxy-enforced per-destination policy — enforcement moves from one client's config to a
root-owned chokepoint that binds every local client in every permission mode, and the same
mechanism gives federated destinations a home. Everything else from Part I survives.

Adopt, in priority order:

1. **Server-side grant trim on production** (Part I §3.1, unchanged, still primary): audit-driven
   trim of the dev-cell instance grant; exclude `system_grant_instance_mcp_tools` from the
   instance's own grant to close self-widening. Fails closed for every client and every path,
   including ones that bypass the proxy entirely.
2. **Proxy becomes a routing + policy point** (replaces Part I §3.2's client deny globs):
   - Static root-only route table: `/mcp/prod` (node mTLS), `/mcp/dev` (Doorkeeper bearer moves
     out of `~/.claude.json` into root-only config), `/mcp/fed/<peer>` (per-peer shared bearer +
     `X-Federation-Organization`). One `https.Agent` per route built at boot; unknown paths 404.
   - Per-route policy: prod route filters `tools/list` and denies destructive `tools/call` names
     (same family list as layer 1, so the two layers mirror each other); dev route is
     unrestricted; federation routes pass through to the peer's own capability scope.
   - Policy trusts `Mcp-Name` only alongside a pinned 2026-07-28+ protocol requirement on the
     prod route (§11 caveat), upgrading to body parsing if adversarial-grade enforcement is ever
     required.
   - Client side: one thin, credential-free registration per destination
     (`pn-prod`/`pn-dev`/`pn-fed-<peer>` — or keep the existing `powernode` name for prod to
     avoid retraining every skill/doc/memory reference, renaming only the sandbox registration).
     Destination identity lives in registration config, never in a model-supplied argument.
3. **Ask-rules** for the rare-but-legitimate destructive prod verbs (Part I §3.3, unchanged) —
   the only layer that can insert a human rather than a refusal.
4. **Config hygiene** (Part I §3.4, unchanged): delete the three decoy `mcpServers` blocks;
   after step 2, the sandbox bearer disappears from user-readable config as a bonus.

**Honest costs of the routing move**: the proxy grows from a 244-line single-purpose shim into a
router with a policy engine — complexity in a root process is a security cost, and it must be
reviewed like boot-critical code; a routing-table mistake is a credential-confusion incident; the
prefix-confusion hazard between registered destinations remains (it is inherent to reachability,
and is why layers 1–3 exist); federated fan-out adds per-peer secret management to the proxy's
config surface.

## 13. What Part II does NOT protect against (delta to §5)

- Everything in §5 except the "`curl` through the proxy" item, which proxy policy now covers.
- **Direct-to-upstream bypass**: a process with its own credentials calling
  `https://ops-hub.ipnode.us` or a peer directly never meets the proxy. Only layer 1 / the
  destination's own gates apply.
- **Prefix confusion between registered destinations**: still possible by construction; bounded,
  not eliminated, by layers 1–3.
- **Older-protocol header lying** on policy routes until the version pin (or body parsing) from
  §11 is in place.
- **A compromised proxy**: it holds every destination credential; its integrity is now
  load-bearing for all three trust domains. Root-only config, minimal diff review, and the
  existing "never log bodies" discipline are the mitigations, not guarantees.
