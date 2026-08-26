# Federated Identity and Resource Sharing

**Status**: design / implementation plan — nothing here is implemented.
**Date**: 2026-08-25 (rev 3, same day). Rev 2 incorporated the finding that the federation peer
population is empty, which removed the grandfathering tier the original design carried. Rev 3
makes four changes, all simplifications:
1. **The empty-population premise is now verified on BOTH stacks** (§3.2). Rev 2 could only show
   the extension side and flagged the core count as unverified — more of the design leaned on it
   than that caveat admitted. A direct query settles it: zero core partners, zero peers, zero
   grants.
2. **The `open` subject policy is gone** (§3.2) — one policy, always strict. With no permissive
   tier there is no `subject_policy` column either; the design loses a migration, a branch on the
   fail-closed auth hot path, and a reachable state in which a call is authorized but
   unattributable.
3. **The single-MCP-connection question is answered** (§5.3): for federated destinations the
   single-connection, server-routed shape **already exists** — `federation_invoke_tool` over the
   one prod registration — so the per-peer proxy route leaves campaign scope.
4. **Increments 1 and 2 merge** (§8): capturing a subject before the registry that validates it
   would durably persist unverified attribution.

**Ask**: let a credential such as `admin@powernode.org` reach resources across federated
entities, from both the MCP surface and the React frontend; provide discovery and consumption
of federated/shared resources; express the implementation plan as an `Ai::Campaign`.
**Companion**: [docs/operations/mcp-environment-isolation.md](../operations/mcp-environment-isolation.md)
§7–§13. Rev 2 **consumed** that doc's `/mcp/fed/<peer>` proxy-routing recommendation; rev 3 does
not, and does not contradict it either — §5.3 shows the federated case is already served by a
single registration with server-side routing, so the per-peer route becomes a future option
rather than a dependency. The one extension this design would ask of it (a per-route `subject`
field) is described there and is not needed unless that route is built.

---

## 1. What exists today (per-component verdict)

Powernode has **three distinct federation stacks**. Most of the ask's machinery already exists;
the survey's most important output is which pieces suffice as-is.

### 1.1 Core: `FederationPartner` — org↔org cross-plane MCP

| Component | What it does | Verdict |
|---|---|---|
| `server/app/models/federation_partner.rb` | Partner registry: bcrypt inbound token, encrypted `outbound_token`, `allowed_capabilities` (validated non-overbroad), trust_level 1–5, status lifecycle, per-partner rate limit, SSRF guard on outbound, `invoke_remote_tool` (outbound `tools/call`), community-agent catalog sync | **Exists and suffices** for org-level identity; **needs extension** for person-level identity (§3) |
| `mcp_token_authentication.rb` federation arm | Fires only on `X-Federation-Organization`; bcrypt verify; fail-closed (never downgrades to OAuth); pre-bcrypt failure throttle | **Exists and suffices**; gains subject parsing (§3) |
| `Mcp::Principal` `:federation` kind | Default-deny; scoped to `allowed_capabilities`; `DESTRUCTIVE_TOOL_PATTERNS` overlay (no grant can override); restricted door allowlist (tools-only); session machinery principal-scoped (the user:nil hijack class was found and fixed pre-merge) | **Exists and suffices**; `granted_tool_patterns` gains intersection with a per-subject scope (§3 — the sibling `capability_scope` was consumer-free and has since been deleted; see §3.3) |
| `Ai::Tools::FederationTool` (core MCP tool) | `federation_invoke_tool` (gated `ai.federation.invoke`), `federation_list_partners`; restricted principals structurally refused from driving it (no open relay) | **Exists but needs extension**: discovery verb + subject attach (§5) |
| `Api::V1::Ai::FederationController` | Full partner CRUD + verify + sync + discover, gated per-action on code-defined `ai.federation.*` permissions, account-scoped (`current_user.account.federation_partners`) | **Exists and suffices** for partner *management* |
| Frontend `features/ai/community-agents` | `FederationPartnerList/Card`, `CreateFederationPartnerModal`, `AgentDiscovery` | **Exists** for management; **consumption UI genuinely missing** (§6) |

### 1.2 System extension: `System::FederationPeer` — platform↔platform resource/service federation

mTLS-based ("Decentralized Federation" plan), operator-grade, entirely in `extensions/system`:

| Component | What it does | Verdict |
|---|---|---|
| `FederationPeer` | Peer lifecycle (proposed→accepted→enrolled→active→degraded→suspended→revoked), parent/child spawn, heartbeats, per-peer CA trust anchor, `inbound_subject` ("fed:\<id\>", assigned by us — no peer can claim another's identity) | **Exists and suffices** |
| `FederationCapability` | Per-peer, per-resource-kind flow policy (direction, auto/manual, filters, conflict resolution) | **Exists and suffices** |
| `FederationGrant` | Per-`remote_subject`, per-`resource_kind` grant with `permission_scopes` (read/write/admin/migrate), TTL, revoke/archive, HMAC-signed `fgs.` bearer tokens (rotation invalidates all) | **Exists and suffices** — and `remote_subject` is not incidental: it is `null: false` in the baseline migration (`20250101000009_system_baseline.rb:235`) and part of TWO unique indexes (`idx_fed_grants_specific_resource_unique`, `idx_fed_grants_kind_wide_unique`), with seven consumers across services, a controller, and a skill executor. Person-level identity is a **uniqueness key** of the resource stack |
| `Federation::ServiceOffering` / `ServiceSubscription` | Operator catalog of shared services; subscribe → grant + Traefik route + ACME cert | **Exists and suffices** |
| `Federation::InventoryRegistry` | Aggregates each extension's `federation_inventory.yaml` exportable kinds; validates requested capabilities | **Exists and suffices** — this *is* the resource-kind discovery seam |
| `federation_api/` namespace | accept, heartbeat, trust_bundle, `resources/:kind/:id` fetch, migrations ingest, audit_excerpts, service_catalog browse, subscribe/unsubscribe — mTLS per-peer-bound | **Exists and suffices** (peer-facing) |
| `federation/` operator namespace | Offerings CRUD + lifecycle, subscriptions, per-peer catalog browse + remote subscribe, child spawn | **Exists and suffices** (operator-facing API) |
| Services | acceptance, grant review/archival, heartbeat sweep, WORM audit shipments | **Exists and suffices** |

### 1.3 A2A instance peers — same-account only

`system_discover_peers` / `system_authorize_peer_call` / `system_mint_peer_capability_token` /
`system_grant_instance_peer_skills`: Ed25519 short-lived capability tokens, verified offline by
the on-node Go agent. **Same-account instance↔instance — wrong shape for cross-entity, by
design** (confirmed by the cross-plane learning: FederationPartner was built *because* this
stack doesn't fit). **Exists and suffices for its own scope; not a building block here** beyond
being the precedent for short-TTL capability minting.

### 1.4 MCP client routing

`/mcp/fed/<peer>` proxy path, per-route credentials, one thin registration per destination —
**designed (mcp-environment-isolation §12) but not implemented**.

### 1.5 The three real gaps

1. **Person-level identity across the MCP boundary.** The federation arm authenticates an
   *organization*; a call is not attributable to, nor authorizable per, a human. The resource
   stack already keys grants by `remote_subject` (a NOT NULL uniqueness key with seven
   consumers — §1.2); the MCP arm ignores subjects entirely. This work is therefore a
   **bridge between two existing stacks, not new identity infrastructure**: the subject
   concept, its storage shape, and its grant semantics all exist — what is missing is
   carrying the subject across the MCP arm and mapping it to a scoped local principal.
2. **A unified, user-facing discovery/consumption surface.** All the pieces exist
   (service_catalog, peer catalog, InventoryRegistry, community-agent sync, partner list) but
   there is no single "federated resources" browse — not as an MCP verb for a *user*, not as a
   frontend page.
3. **The consumption path itself**: the frontend has management UI but no way to pick an entity,
   see what it shares, and use it (including unreachable-peer / revoked-grant states). The
   `/mcp/fed/<peer>` client route is also unimplemented, but rev 3 finds it is not on the critical
   path — the platform-mediated tools already give a single-connection consumption path (§5.3).

A fourth, structural observation: the core `FederationPartner` and extension `FederationPeer`
stacks are **parallel and unlinked** (different auth — bearer vs mTLS; different subjects — org
vs platform; different payloads — MCP tools vs resources/services). This design does **not**
merge them (§8, open question 1): it puts person-level identity in core where the MCP arm
lives, and bridges discovery through a generic seam so core never references the extension.

---

## 2. The identity problem

`admin@powernode.org` reaching entity B's resources means: entity A's user, authenticated by A,
acting on B, where B has no User row for them. Requirements: attribution of every action to the
person; per-person authorization narrower than the org's; revocation at person, org, and
resource level; no violation of frontend-permissions-only, backend `has_permission?`, extension
isolation, or account scoping; federated peer = lower trust than local (default-deny).

### Options weighed

**A. Org-asserted subject claim + remote-side FederatedIdentity registry** *(recommended)*
Outbound calls carry the acting subject (`X-Federation-Subject: admin@powernode.org`)
alongside the existing org bearer; the receiving side resolves `(partner, remote_subject)` to a
local **`FederationIdentity`** row holding its own capability allowlist; effective scope =
`partner.allowed_capabilities ∩ identity.allowed_capabilities`; audit rows record org + subject.
- *What breaks*: nothing — the header is additive wire format, and the live federation
  population is **empty** (§3.2), so there is no deployed behavior to preserve; strictness
  can be the default from day one rather than phased in.
- *Cost*: one core model + arm changes + admin UI. Smallest delta; maximal reuse
  (`FederationGrant.remote_subject` in the extension stack already speaks this language).
- *Revocation*: deactivate one identity (per person, instant), suspend/revoke partner
  (org-wide), rotate token (org-wide), TTL on extension grants (per resource).
- *Audit*: every `McpToolExecution`/audit row carries `(partner, remote_subject)`.
- *Honest limit*: B trusts A's assertion of *which* of A's users is calling (asserting-party
  model, same as SAML). A compromised peer control plane can impersonate any subject
  *registered for that partner* — blast radius bounded by the identity scopes ⊆ partner scope.
  End-user-held cryptographic proof is out of scope (option C is the upgrade path).

**B. Shadow/guest `User` rows on the remote side** *(rejected)*
Reuses `has_permission?` natively, but pollutes the User table with login-capable,
Doorkeeper-eligible, invitation-visible rows; every `User`-keyed query and mailer becomes a
cross-entity hazard; revocation means account-state surgery. The user:nil session-hijack
incident showed how much machinery keys on User — inserting fake ones inverts that risk rather
than avoiding it.

**C. Full OIDC/SAML trust between entities** *(rejected for now)*
Real cross-IdP identity with user-held proof. Cost: token validation + JWKS/metadata exchange +
clock/rotation operations on every peer; still needs a local mapping + permission scoping layer
(i.e., FederationIdentity anyway); Powernode↔Powernode peers gain little over the org bearer
they already exchange. Revisit when a *non-Powernode* entity federates or when asserting-party
trust becomes insufficient. Option A's `FederationIdentity` is forward-compatible: an OIDC `sub`
can later populate `remote_subject` with the arm verifying a JWT instead of trusting a header.

**D. Per-request capability tokens only** *(rejected as identity; kept as enforcement)*
Minting a short-lived token per resource/action (both precedents exist: `fgs.` grant tokens,
Ed25519 A2A tokens) is a delegation primitive, not a session identity — it cannot carry
"browse what I can reach" for a frontend, and puts a mint round-trip in every call. The
extension's grant tokens remain exactly right for *resource-level* enforcement and stay as-is.

### Recommendation

**Option A.** One new core model, two touched core files on the hot path, everything else
additive. Concretely the principal chain becomes:

```
X-Federation-Organization + Bearer <org token>  → FederationPartner   (org authn — unchanged)
X-Federation-Subject: admin@powernode.org       → FederationIdentity  (person resolution — new)
effective capability scope = partner.allowed_capabilities ∩ identity.allowed_capabilities
DESTRUCTIVE_TOOL_PATTERNS overlay                                      (unchanged, still absolute)
```

---

## 3. Design: the identity layer (core)

### 3.1 `FederationIdentity` model

Core (`server/app/models/federation_identity.rb`) — core-resident because `FederationPartner`,
`Mcp::Principal`, and the auth arm are core; the extension may *reference* it (extension→core
is the allowed direction).

```
federation_identities
  id                   uuid PK (v7)
  account_id           uuid NOT NULL, FK, indexed          -- owning (local) account
  federation_partner_id uuid NOT NULL, FK, indexed
  remote_subject       string(256) NOT NULL                -- what the partner asserts, e.g. admin@powernode.org
  display_name         string, optional
  status               string NOT NULL default 'active'    -- active | suspended | revoked
  allowed_capabilities jsonb NOT NULL default []           -- same shape + non-overbroad validation as partner's
  last_seen_at         datetime
  created_by_id        uuid FK users, optional
  UNIQUE (federation_partner_id, remote_subject)
```

- Reuses `allowed_capabilities_not_overbroad` (extract to a shared concern/validator).
- Empty `allowed_capabilities` = **no narrowing** (identity inherits the full partner scope) —
  chosen over "empty = deny" so registering an identity for attribution alone doesn't silently
  break a partner; denial is expressed by `status: suspended/revoked`, which is explicit.
- All lookups scoped `partner.federation_identities` (partner already account-scoped).

### 3.2 Subject policy: `registered_only`, always

**Population premise — verified, both stacks (2026-08-25).** Rev 2 rested on "the federation
population is empty" but could only demonstrate it for the extension, explicitly flagging the core
`FederationPartner` count as unverified. That was the load-bearing half: `FederationPartner` is
what the MCP arm authenticates, and it is what every "strict default, no grandfathering" decision
below depends on. No tool on the production MCP connector exposes the count
(`federation_list_partners` is advertised on the local connector only, whose database is a fixture
shell), so it was settled with a read-only query against `powernode_production`:

```sql
SELECT count(*) FROM federation_partners;        -- 0
SELECT count(*) FROM system_federation_peers;    -- 0
SELECT count(*) FROM system_federation_grants;   -- 0
```

All three are zero. There is **no deployed federation relationship anywhere in either stack**
whose behavior a permissive default would protect, and no grant whose format a legacy path would
need to honor (which independently confirms §9.5). Strictness is therefore a green-field default,
not a migration, and every increment below is safe to build and revert without operator comms.

**The policy.** One tier, no column:

| Inbound call | Outcome |
|---|---|
| No `X-Federation-Subject` header | **401 `federation_subject_required`** |
| Subject present, no matching active `FederationIdentity` | **403 `federation_subject_unknown`** |
| Subject present, identity active | `partner.allowed_capabilities ∩ identity.allowed_capabilities` |

Rev 2 carried a second `open` tier — org scope without a subject — as an escape hatch for "a peer
control plane that genuinely cannot assert subjects", expected to ship unused. Rev 3 drops it, for
exactly the reason this document gives about a different vestigial permissive path (§9.5): a
weaker path retained to protect nobody is not conservative, it is a second code path that can only
degrade the strong one. Concretely, dropping it removes:

- the `subject_policy` column and its migration — with one policy there is nothing left to vary
  per partner;
- a branch in `authenticate_via_federation_partner`, on the fail-closed auth hot path that this
  document's own stop-conditions single out for adversarial review (§8);
- a reachable state in which a federated call is authorized but unattributable.

**The machine-caller case is not lost** — it is served better by the pattern this design already
preferred: register a **service identity** (`remote_subject: "system@peer.example"`) like any
other. That keeps attribution and per-caller capability narrowing, costs the remote operator one
row, and needs no permissive tier. A peer that cannot send one additional static header is not a
peer that can be authorized per-person at all, which is the entire ask.

Distinct error codes let the calling side's UX say "ask the remote operator to register you"
rather than "credentials invalid".

### 3.3 Auth arm + principal changes

- `authenticate_via_federation_partner`: after partner verification, read
  `X-Federation-Subject`, apply the policy (table above), resolve the identity, touch
  `last_seen_at`, and pass it into the principal:
  `Mcp::Principal.for_federation_partner(partner, identity: identity)`.
- `Mcp::Principal`: carries `federation_identity`; **`granted_tool_patterns` (`principal.rb:275`)
  returns the intersection** when an identity with a non-empty capability list is present.
  `restricted?`, the door allowlist, and the destructive overlay are untouched.

  **Name the right method — verified by execution, 2026-08-25.** Rev 2 said "`capability_scope` /
  `granted_tool_patterns` return the intersection", which reads as though either would do. It is
  not so, and the difference is the whole increment:

  | Method | Line | Consumers |
  |---|---|---|
  | `granted_tool_patterns` | `principal.rb:275` | `may_invoke?` (`:264`) → `filter_tools` → `handle_tools_list` (`streamable_http_controller.rb:577`) and `tools/call` (`:604`). **The live enforcement path.** |
  | `capability_scope` | `principal.rb:247` | **None in production.** Its only references anywhere in the repo are five lines of `spec/models/mcp/principal_spec.rb` (`:29,:49,:55,:137-138`). |

  The two are independent readers of the same source: `granted_tool_patterns:277` reads
  `federation_partner&.allowed_capabilities` **directly**, never calling `capability_scope`.
  An implementer following rev 2 could reasonably patch the method named first, ship green
  model specs (there is even an existing example, `principal_spec.rb:137`, asserting
  "exposes allowed_capabilities as its capability_scope"), and produce a system where **every
  federated identity silently receives the full partner scope**. This was demonstrated, not
  reasoned about: stubbing `capability_scope` to the intersection left `tools/list` completely
  unnarrowed; stubbing `granted_tool_patterns` narrowed it as designed.

  So: patch `granted_tool_patterns`. **`capability_scope` has since been deleted** — the trap is
  gone, and this section is retained as the record of why. Deletion (rather than making it
  delegate) was the right call once a second difference surfaced: for *instance* principals the
  two methods read **different sources with opposite trust** — `capability_scope` returned the
  node's SELF-DECLARED `declared_capabilities`, while enforcement uses the injected
  `tool_grant_resolver`, which defaults to DENY ALL. Its own comment ("an empty list scopes to
  read-shape/introspection tools") misdescribed that default, and a spec asserting instance
  "default-deny" through the self-asserted field was giving false assurance. Those specs now
  assert against the grant resolver, and `spec/requests/api/v1/mcp/
  tools_list_principal_filtering_spec.rb` guards the end-to-end property so the class cannot
  recur. `session_principal_attributes` includes the subject so restricted-session
  ownership stays per-identity (the user:nil lesson: every new principal variation re-audits
  user-keyed and by-token lookups — §7.1).
- A rejected/unknown subject is **still throttled and fail-closed** exactly like a bad org
  token: it never falls through to OAuth.

### 3.4 Outbound: asserting the subject

- `FederationPartner#invoke_remote_tool(tool:, arguments:, subject: nil)` adds the header when
  `subject` is present.
- `Ai::Tools::FederationTool#invoke_tool` passes `subject: @user&.email` automatically — the
  acting local user *is* the subject; a caller never supplies it as a tool argument (the
  destination-identity principle from the isolation doc applies to identity too: never
  model-supplied).
- Restricted principals remain structurally refused from outbound FederationTool (no relay:
  a peer cannot use us to reach a third entity with our credentials).

---

## 4. Discovery and consumption of shared resources

### 4.1 What discovery already exists

- **Peer-facing** (mTLS, extension): `federation_api/service_catalog`, `resources/:kind/:id`,
  InventoryRegistry kinds.
- **Operator-facing** (JWT, extension): `federation/peers/:peer_id/catalog`, offerings and
  subscriptions dashboards' API.
- **Core**: `federation_list_partners` (MCP), partner `discover`/`agents` (REST),
  community-agent sync, network topology graph.

### 4.2 The unifying trick: remote `tools/list` *is* the resource discovery

The remote side's MCP `tools/list` already filters through `Principal#filter_tools` — so a
`tools/list` issued over the federation arm (with a subject) returns **exactly the tool set
that identity may invoke**: correctly scoped, per-person, with zero new authorization code on
the remote side. Discovery = advertisement, and advertisement is already policy-filtered.

**Verified by execution (2026-08-25), not assumed.** Rev 3 initially flagged this as the
design's most load-bearing unproven assumption. It now has four pieces of evidence:

1. **The door admits it.** `RESTRICTED_PRINCIPAL_METHODS` (`streamable_http_controller.rb:361`)
   is `initialize ping tools/list tools/call` — `tools/list` is in the allowlist by name.
2. **The handler filters it.** `handle_tools_list` `:577` runs
   `current_mcp_principal.filter_tools(all_tools)`.
3. **The filter is load-bearing, not incidental.** Mutating `filter_tools` to a passthrough
   makes the existing federation scoping example fail (`spec/requests/api/v1/mcp/
   federation_auth_spec.rb:27` — the mutant is killed, so the oracle is live). The full file is
   12 examples, 0 failures on HEAD, and separately proves the *negative* half: `resources/read`
   and `session/discover` are both refused to a federation principal with "not available to this
   principal".
4. **A subject dimension is sufficient.** Simulating the one change increment 1 makes — having
   the principal return `partner ∩ identity` — narrows `tools/list` to the intersection, and an
   identity naming a capability outside the partner's scope does **not** widen it. No change to
   the door or the handler was needed.

Point 3's mutation is also what exposed the `capability_scope` trap documented in §3.3.

Additions (all core, all additive):

- `FederationTool` gains `federation_discover_resources` (gated `ai.federation.read`):
  for one or all active partners, issue `tools/list` (and `initialize`) over the federation
  arm as the current user's subject; return `{partner, reachable, tools[], fetched_at}`.
- `Federation::CatalogCacheService`: short-TTL cache (per partner+subject) so the frontend
  and repeated MCP calls don't hammer peers; serves stale-with-timestamp when a peer is
  unreachable.
- REST endpoint for the frontend: `GET /api/v1/ai/federation/resources`
  (`ai.federation.read`), returning the same aggregate.

### 4.3 Extension resources without a core→extension dependency

The system extension's service offerings/subscriptions should appear in the same discovery
surface. Core defines a **catalog-provider seam** (mirror of the existing DI seams —
`Principal.instance_resolver`, `MtlsTrust.own_ca_provider`):

```ruby
# core
Ai::Federation::CatalogProviders.register(:services) { |account, user| ... } # extension calls this
```

The extension engine registers a provider that surfaces its `ServiceOffering`/`ServiceSubscription`
catalog; core iterates registered providers, knowing none by name. A stock core install simply
has fewer catalog sections. `core-purity-check.sh` stays green by construction.

---

## 5. The MCP surface

### 5.1 Inbound (serving federated callers)

No new endpoint. The existing streamable-HTTP endpoint + federation arm carry everything; §3
adds subject resolution. Tool authorization, action pinning, nested destructive overlay, and
door gating are all existing machinery.

### 5.2 Outbound (platform-mediated)

`federation_invoke_tool` / `federation_discover_resources`, subject auto-attached (§3.4).
This is how frontend calls and platform agents consume federated tools — the server is the
only holder of outbound tokens.

### 5.3 Client-side: one registered connection, routing done server-side

**The operator's question**: can this work with a *single* registered MCP connection, with routing
to destinations provided by the tool/proxy rather than by N client registrations?

**For federated destinations: yes — and it already exists, with no proxy work at all.** That is
what §5.2 describes. `federation_invoke_tool` / `federation_discover_resources` are ordinary tools
on the *existing* production registration; the server holds every outbound token, applies the
partner's scope, and routes to the peer. One connection, server-side routing, zero new client
config. The subject is attached automatically from the acting user (§3.4), never supplied by the
model.

The companion doc's §8 rates "destination as a per-call tool argument" the **worst** carrier, and
this shape is formally that — `federation_invoke_tool(partner:, tool:, …)`. That rating is correct
for the case it was written about and does not transfer here. Three reasons, stated so the two
documents are not read as contradicting each other:

- **What is at risk differs.** §8 is about the prod↔dev boundary, where mis-picking the
  destination means running a dev-intended mutation against production with the node mTLS key.
  Mis-picking a *federation partner* sends a call to a lower-trust peer that default-denies it,
  scoped by `allowed_capabilities ∩ identity.allowed_capabilities`, with the destructive overlay
  absolute — and never with our node credential, which the federation path does not hold.
- **The prefix signal §8 defends is not available to lose.** Federated tools have no native tool
  prefix in either shape until a per-peer registration exists. The mediated path replaces it with
  an explicit `partner` argument visible in the call itself — strictly more legible than the
  collapsed namespace §8 was rejecting.
- **The companion's §12 Part I is itself unbuilt** (§1.4). The per-peer route depends on the proxy
  becoming a router, which today is a recommendation, not code.

**The real cost of the single-connection shape**, stated plainly: a peer's tools do not appear to
the client as first-class tools with their own schemas. The model reaches them through a generic
envelope and learns schemas from `federation_discover_resources` at call time. That is worse
ergonomics for a Claude Code session and *better* context economy (one tool def instead of N), and
it makes no difference at all to the frontend (§6), which was always calling through the server.

**Consequence for this campaign**: the per-destination proxy route leaves scope. Rev 2's increment
7 becomes a documented future option, not a deliverable (§8). Should it ever be built, the one
extension this design asks of the companion doc still stands: each federation route's static
config gains a `subject` field sent as `X-Federation-Subject`, so the route table becomes
`path → {upstream, credential, subject}` with the subject fixed at registration exactly like the
destination. Nothing in that document needs to change to accommodate it.

## 6. The frontend surface

New feature `frontend/src/features/ai/federation/` (the existing community-agents management UI
stays where it is; the new page links to it). React + TypeScript, Tailwind, theme-aware tokens,
Vitest — per `frontend/CLAUDE.md` and `conventions/frontend-patterns.md`.

**Federated Resources page** (`/app/ai/federation`):

- **Entity picker** (left rail): active partners with status badges
  (`active | suspended | revoked | unreachable`), trust level, last-seen. Data:
  existing partner index + the new resources aggregate.
- **Resource pane** (tabs): **Tools** (from `federation_discover_resources`, showing the
  *subject-scoped* set — "what *you* can do there"), **Agents** (existing community-agent
  data), **Services** (rendered only when the extension's catalog provider contributed a
  section — the frontend mirrors the seam by rendering sections the API returns, never
  importing extension code).
- **Invoke**: a tool detail drawer with a schema-driven argument form posting to
  `federation_invoke_tool`; results inline; every call visibly labeled with the target entity
  (the prefix-confusion lesson, applied to humans).
- **Identity admin** (partner detail): manage *inbound* `FederationIdentity` rows — who from
  that partner may act here, each with status + capability narrowing. Clearly labeled
  direction ("their users → this platform"); outbound registration lives on the peer and the
  UI says so when a peer returns `federation_subject_unknown`.

**Permission gating — permissions only, never roles:**

```typescript
currentUser?.permissions?.includes('ai.federation.read')       // see the page + browse
currentUser?.permissions?.includes('ai.federation.invoke')     // invoke drawer enabled
currentUser?.permissions?.includes('ai.federation.identities_manage') // identity admin
```

New permissions are **code-defined in the catalog** (undefined permissions degrade to
admin-only — a silent-lockout class this repo has hit before). Note the name *shape*: the existing
entry is `resource :federation, actions: %i[read create update delete verify sync invoke]`
(`server/config/permissions.rb:669`), and that DSL emits three-segment `ai.federation.<action>`
names only. A four-segment `ai.federation.identities.manage` is **not expressible through it** and
would silently be an undefined permission — i.e. the exact silent-lockout class named above. Two
valid forms: add `identities_manage` to the `actions:` list (preferred — one word, inherits the
same grant map), or declare it freeform beside the resource as `ai.analytics.global` does at
`permissions.rb:662`. `ai.federation.read` already exists and is reused for browse.

**Degraded/error states (explicit UX contract):**

| Condition | Signal | UX |
|---|---|---|
| Peer unreachable | aggregate row `reachable: false` | badge on entity; cached catalog shown with "as of \<t\>"; invoke disabled |
| Org token rotated / invalid | 401 `federation_invalid` | banner on entity: "credentials need re-issue" + CTA visible only with `ai.federation.update` |
| Subject not registered | 403 `federation_subject_unknown` | "You're not registered with \<entity\> — ask their operator to add `<your email>`" |
| Grant/identity revoked mid-session | 403 on invoke | non-blocking toast; resource stays listed, marked revoked; no retry storm (no auto-retry on 403) |
| Partner pending/suspended | partner status | entity greyed, management link |

---

## 7. Security analysis

### 7.1 Cross-account scoping — the primary risk

This repo's documented history (systemic IDOR sweep; unscoped `.find` in federation/SDWAN
executors; the federation-arm session-enumeration HIGH caught pre-merge) makes tenancy the
first-order concern, not a checklist item:

- Every identity lookup goes through the partner association
  (`partner.federation_identities.find_by(remote_subject:)`); every partner lookup through
  `current_user.account.federation_partners` / the authenticated partner row. No bare
  constant-receiver finders anywhere in the new code; `check-account-scoping.sh` must stay
  clean with zero new baseline entries.
- **Principal-variation audit** (the generalized user:nil lesson): adding identity to the
  federation principal requires re-auditing every user-keyed query and by-token lookup the
  restricted-session machinery touches — `session_principal_attributes`,
  `session_owned_by_current_principal?`, execution-row writes — with request specs asserting
  a subject-A session/row is invisible to subject-B *and* to the bare-org principal.
- The identity's `account_id` is denormalized from the partner and validated to match —
  belt-and-suspenders against a re-parented partner FK.

### 7.2 Trust model and its limits

- **Asserting-party trust, stated plainly**: entity B trusts entity A's claim about which of
  A's users is calling, exactly as B already trusts A's org credential. A compromised A can
  impersonate subjects *registered for A* — never another partner's subjects (unique per
  partner), never unregistered subjects (there is no policy under which an unregistered one is
  accepted — §3.2), and never beyond
  `partner.allowed_capabilities ∩ identity.allowed_capabilities`, with the destructive overlay
  still absolute. The upgrade path to user-held proof is OIDC populating the same
  `remote_subject` (§2, option C).
- **Confused deputy / relay**: unchanged — restricted principals cannot drive outbound
  FederationTool; the SSRF guard on `invoke_remote_tool` stands (the known residual — catalog
  GETs lacking it — is queued separately and is not widened by this design).
- **Default-deny posture**: subject registration is required of every partner (§3.2), and after
  rev 3 there is no permissive tier left to be in, which materially shrinks the asserting-party
  weakness above (impersonation requires a subject the *receiving* operator explicitly
  registered). A new identity with empty capabilities inherits partner scope, so the *partner's*
  default scope carries the weight: **decided** (a green-field default, not a business-policy
  migration — the population is verified empty, §3.2) as read/list-shaped capabilities only;
  mutations are added per-capability by the operator. This must land as a **mechanism, not a
  posture**: a partner created without an explicit `allowed_capabilities` gets a read/list-shaped
  default from the model, beside the existing `allowed_capabilities_not_overbroad` validation,
  with a model spec asserting that a bare `FederationPartner.create` is non-mutating. Prose in a
  design document does not survive the first operator who omits the field.

### 7.3 Revocation

Four independent, immediate levers (no authz decision cached beyond the request):

1. `FederationIdentity` suspend/revoke — one person, one partner, next request.
2. `FederationPartner` suspend/revoke — the org; also kills every identity under it.
3. Org token rotation (`regenerate_token!`) / extension `fgs.` secret rotation — credential-level,
   org-wide (rotation invalidates every outstanding grant token by design).
4. Extension `FederationGrant` revoke/TTL — per resource, per subject.

Mid-session UX for each is specified in §6. Re-issued tokens follow the one-shot in-band reveal
shape — never returned via MCP, never logged.

### 7.4 Attribution and audit

- Every federation-arm `McpToolExecution` and audit row records
  `(federation_partner_id, remote_subject)`; increments land in existing audit sinks.
- Extension WORM audit shipments (`audit_excerpts`) automatically carry the subject once rows
  do — the person is attributable *from both sides* of the boundary.
- The subject is typically an email address crossing an org boundary — PII. Registration is
  operator-consented on both ends (A's operator chooses to assert; B's operator registers),
  which is the sane default; whether a pseudonymous-subject mode is needed is parked (§8).

### 7.5 Abuse resistance

Existing per-org failure throttle covers subject failures (they ride the same arm). Per-partner
rate limiting exists (known non-atomic read-then-write residual is tracked separately).
Per-identity rate limiting is a deliberate non-goal until usage shows a need. The
RequestInspector self-block class (code-bearing payloads) applies to federation MCP traffic
too — the queued exemption fix is a dependency to watch, not part of this design.

---

## 8. Implementation plan, as a campaign

To be created (by the operator / lead — **not by this document**) per
`docs/contributing/conventions/autonomous-campaigns.md`.

**Campaign**: `federated-identity-and-resource-sharing`
**Branch**: `campaign/<id>` (STAGE-only; commit at each passing gate; never push unbidden)
**Scope**: increments 1–5 below, in order; each ends at a passing `scripts/validate.sh` (or its
targeted subset) and is independently revertible.

**`decision_authority`: `trusted`** — the work is dominated by well-precedented, reversible,
test-first server/frontend changes inside machinery that already has strong spec coverage;
`monitored` would park routine forks and waste the run. `trusted` parks precisely the forks
federation genuinely has, and these **will** park:

- any outbound call to a live peer deployment — noting that **no peer deployment exists** in
  either stack (§3.2, verified): live e2e first requires *creating* the second entity;
- minting/re-issuing/distributing a real partner token (live-credential);
- migration application on a live environment (live-pending-migrations rule).

The rev-2 draft also parked "flipping existing partners off `open`", the default-grant scope, and
the proxy's per-peer credential ceremony. All three are gone: there are no partners to flip, the
defaults are decided in-design (§3.2, §7.2), and the proxy route left scope (§5.3).

**`stop_conditions`**:

- 3 failed attempts at the same fix (hard stop-and-ask);
- any diff touching `mcp_token_authentication.rb`, `mcp/principal.rb`, or
  `streamable_http_controller.rb` whose full request-spec suite is not green, or that weakens
  fail-closed/throttle/overlay behavior — stop and flag for adversarial review (two independent
  critics, per the boot-critical review practice);
- `core-purity-check.sh` or `check-account-scoping.sh` failure (no new baselines);
- gitleaks hit / any credential material in a diff;
- `emergency_halt` / account kill switch.

**Increments** (files → proving test → rollback):

1. **Identity, policy, and attribution — as one increment.**
   *Rev 2 split this into "subject attribution (observability first)" then "identity +
   enforcement". The split is wrong: increment 1 would have the auth arm capture
   `X-Federation-Subject` and persist it to execution and audit rows while the registry that
   validates it does not yet exist. Between the two increments any string a partner sent would
   become a durable attribution row with nothing behind it — an audit trail that reads as
   authoritative and is not. Observability-first is a good instinct, but not for the field whose
   entire value is that it was checked. Merged, the increment is larger and has no such window.*
   Files: migration (`federation_identities`; **no `subject_policy` column** — §3.2),
   `federation_identity.rb`, shared non-overbroad validator extracted from
   `federation_partner.rb:415`, read/list-shaped `allowed_capabilities` default (§7.2),
   `mcp_token_authentication.rb` (subject read + policy), `mcp/principal.rb`
   (`for_federation_partner(partner, identity:)`, **`granted_tool_patterns:275` intersection —
   the single live gate; its consumer-free sibling `capability_scope` has been deleted so it can
   no longer be patched by mistake — see §3.3**, plus `session_principal_attributes`),
   `federation_partner.rb`
   (`invoke_remote_tool(…, subject:)`), `ai/tools/federation_tool.rb` (auto-attach `@user&.email`),
   execution/audit row write-through.
   Tests: model specs (uniqueness per partner, non-overbroad, non-mutating default); principal
   specs (intersection narrows, empty identity list inherits partner scope, destructive overlay
   unaffected); request specs for `federation_subject_required` 401,
   `federation_subject_unknown` 403, throttle-and-fail-closed on unknown subject (never falls
   through to OAuth), cross-subject session invisibility and subject-A rows invisible to
   subject-B *and* to a bare-org principal (§7.1); outbound spec asserting the header.
   **One test is mandatory and is not optional coverage**: a request spec asserting that a
   subject-narrowed identity's `tools/list` omits a capability the *partner* holds. That is the
   assertion that fails if the intersection is applied somewhere that does not gate advertisement
   — a model spec on an accessor passes in both worlds and cannot tell them apart. The
   general form of this guard already exists as
   `spec/requests/api/v1/mcp/tools_list_principal_filtering_spec.rb`; extend it with the
   subject dimension rather than writing a new one.
   Rollback: revert migration + code. Trivially safe — the population is verified empty (§3.2),
   so no live relationship depends on either behavior.
2. **Identity management API + permissions.**
   Files: `federation/partners/:id/identities` controller + routes, code-defined
   `ai.federation.identities_manage` added to the `resource :federation` actions list
   (`server/config/permissions.rb:669` — see §6 on why the four-segment name does not work),
   audit events.
   Tests: request specs incl. foreign-account 404s and permission denials.
   Rollback: pure addition; revert.
3. **Discovery seam + aggregate.**
   Files: `federation_tool.rb` (`federation_discover_resources`),
   `federation/catalog_cache_service.rb`, `GET /ai/federation/resources`, core catalog-provider
   registry (§4.3).
   Tests: WebMock'd peer specs — scoped `tools/list` passthrough, unreachable → stale-cache path,
   provider registry with a fake provider.
   **The assumption rev 3 flagged here is now RESOLVED** — the `tools/list` door does admit a
   `:federation` principal, the handler does filter per principal, the filter is load-bearing
   under mutation, and a simulated subject dimension narrows correctly. All four are demonstrated
   in §4.2. This increment inherits a proven premise rather than carrying an open risk; keep the
   passthrough-mutation check in the suite so the premise cannot silently rot.
   Rollback: pure addition; revert.
4. **Frontend: Federated Resources page.**
   Files: `features/ai/federation/` (page, entity rail, tabs, invoke drawer, service, types,
   tests); route registration.
   Gate: `npx tsc --noEmit` + vitest; each state in §6's table has a test.
   Rollback: pure addition; revert.
5. **Frontend: identity admin on partner detail.** Same shape as 4.

**Out of scope, deliberately** (was rev 2's increment 7): the `/mcp/fed/<peer>` client route. §5.3
shows the single-connection, server-routed shape already exists via `federation_invoke_tool`, so
the proxy route buys native tool prefixes and nothing else — and it depends on the companion doc's
§12 Part I, which is unbuilt (§1.4). That is a dependency on unwritten code, not merely a parked
credential, and rev 2 obscured it by listing only the credential steps as parked. Revisit when a
peer entity exists and the ergonomics actually bite.

*(Optional, post-campaign)* Extension bridge: the system extension registers its service-catalog
provider; link `FederationPeer` ↔ `FederationPartner` where both describe one entity (§9.1).

**Are any increments unrunnable given zero live peers?** No. All five are code + spec increments
whose proving tests use WebMock'd/fixture peers; none requires a live counterpart. What is
unrunnable until a peer entity exists is the **live smoke**, which was always an operator step
outside the increments. It sits explicitly last, gated on a peer entity existing — the run must
not be scheduled as if one will appear on its own.

**Parked questions predictable up front** (park at start so the run never stalls on them):

1. **Creating the first peer entity.** Rev 2 asked "which two deployments pair for e2e"; that
   premise was false, and §3.2's query now confirms it on both stacks — nothing is federated with
   anything. The real question is *how a second entity comes to exist*: spawn a child platform
   (the extension's `federation/children` + spawn machinery exists precisely for this), stand up a
   dev-plane deployment, or wait for a real external entity. Operator decision; live credentials
   both ways; everything before it verifies against mocked peers.
2. Subject format: email (human-meaningful, matches the ask, breaks on rename) vs stable UUID +
   display email (survives rename, less legible). Proposed: email as `remote_subject`, with a
   documented rename procedure (deactivate old, register new).
3. PII posture for subjects crossing the boundary (pseudonymous mode needed?).
4. Grant TTL defaults if identity-level expiry is wanted (extension grants have TTL; core
   identities currently do not — add `expires_at`?).

## 9. Open questions (design-level)

1. **Dual-stack linkage.** `FederationPartner` (core, bearer, MCP) and `System::FederationPeer`
   (extension, mTLS, resources/services) can describe the *same* remote entity with no link.
   Recommended: do **not** merge; add an optional extension-side reference
   (`FederationPeer#federation_partner_id`) so operators see one entity, and the discovery
   aggregate can group by entity. Extension→core direction only; core stays ignorant.
2. **Stronger subject binding.** If asserting-party trust ever falls short: per-identity
   derived tokens (HMAC domain-separated per subject, mirroring `fgs.`) or OIDC verification
   on the arm. Designed-for, not built.
3. **Discovery beyond tools.** `resources/:kind/:id` + InventoryRegistry could feed per-kind
   *data* browsing (skills, knowledge) into the resources page; deferred until the tools/
   agents/services surface proves the UX.
4. **`Mcp-Session` semantics for subject-bearing federation calls** are request/response today
   (restricted principals are sessionless in practice); if long-lived federated sessions ever
   appear, the session-ownership audit of §7.1 becomes a standing requirement.
5. **Adjacent finding from the empty-population sweep** (report-only; not in this campaign's
   scope): `FederationGrant`'s legacy raw-PK token grace (`POWERNODE_FEDERATION_LEGACY_TOKEN`,
   default **on**) exists to keep pre-envelope peers working during the `fgs.` rollout. §3.2's
   query now settles this directly rather than by inference: `system_federation_grants` holds
   **zero rows**, so there is not one pre-envelope token in existence for the grace to honor. It
   keeps a weaker, unsigned token format accepted while protecting nobody — the same shape as the
   `open` tier this revision removed, and the precedent rev 3 cites for removing it. Queue
   separately: flip the default off (or delete the legacy path) before the first real peer
   enrols, so the grace never becomes load-bearing.
