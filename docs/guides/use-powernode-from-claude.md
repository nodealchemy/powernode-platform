# Use Powernode From an External MCP Client

> Status: active

> Connect an external Model Context Protocol (MCP) client — Claude Code, Claude
> Desktop, or any MCP-compliant client — to a running Powernode instance over
> the platform's streamable-HTTP MCP server.

Powernode exposes its control-plane surface as an MCP server. Once connected, a
client can drive the platform through `platform.*` tool calls: manage agents and
teams, run fleet and container operations, query the knowledge graph and memory,
trigger CI/CD, and more — all gated by the same permissions and audit trail the
rest of the platform uses.

This guide covers what the server exposes, the prerequisites, the exact client
configuration, how authentication works, a first-call smoke test, the A2A
discovery surface, and troubleshooting.

## Table of contents

- [What the MCP server exposes](#what-the-mcp-server-exposes)
- [Prerequisites](#prerequisites)
- [The endpoint](#the-endpoint)
- [Authentication](#authentication)
- [Client configuration](#client-configuration)
  - [Claude Code](#claude-code)
  - [Claude Desktop](#claude-desktop)
  - [Other MCP clients](#other-mcp-clients)
- [First-call smoke test](#first-call-smoke-test)
- [A2A discovery (agent cards)](#a2a-discovery-agent-cards)
- [Platform agents as Claude Code subagents](#platform-agents-as-claude-code-subagents)
- [Troubleshooting](#troubleshooting)
- [Related documentation](#related-documentation)

## What the MCP server exposes

The server publishes a single, unified `platform.*` tool namespace plus a small
set of introspection tools. Tools are organized by domain. The live catalog —
every tool, parameter, and example — is auto-generated at
[`reference/auto/mcp-tools.md`](../reference/auto/mcp-tools.md); that file is the
only source of truth for what is currently registered. The categories below
match the catalog's section headings:

- **Project & CI/CD** — repository and pipeline operations, dispatch to runners.
- **Agent management** — create, list, update, execute AI agents; set autonomy
  and trust levels.
- **Agent containers** — deploy and manage containerized agents; stream logs.
- **Team management** — create teams, add members, execute team runs.
- **Pipeline management** — trigger pipelines and check status.
- **Memory management** — shared-memory read/write, search, consolidation, pools.
- **Knowledge & RAG** — query knowledge bases, add and process documents.
- **KB article and page management** — content CRUD.
- **Compound learning** — query, create, and reinforce learnings.
- **Shared knowledge** — search, create, promote knowledge entries.
- **Skills** — discover, inspect, create, and toggle reusable capabilities.
- **Knowledge quality** — verify, dispute, and reconcile learnings; health.
- **Knowledge graph** — search, reason over, and traverse the graph.
- **AI safety & autonomy** — emergency halt/resume, kill-switch status, goals,
  proposals, and escalations.
- **Activity monitoring** — activity feed, recent events, notifications.
- **System health** — platform and integration health checks.
- **Image generation** — generate and list images.
- **Docker management** — containers, services, stacks, clusters, nodes,
  secrets, configs, networks, and volumes.
- **Conversations & workspaces** — workspace messaging and conversation history.

Two more groups are present depending on what the instance has enabled:

- **System / fleet operations** — node, instance, module, storage, SDWAN, and
  provider lifecycle. These `system_*` tools are available when the system
  extension is enabled.
- **Codebase intelligence** — semantic and identifier search, blast-radius and
  static analysis, and index maintenance over the indexed repositories.

> The exposed tool list is also filtered per principal. A regular user sees the
> full catalog (their per-tool permissions still gate execution); a fleet
> instance authenticating with a node certificate gets a default-deny,
> grant-scoped subset. Verified in
> [`server/app/controllers/api/v1/mcp/streamable_http_controller.rb`](../../server/app/controllers/api/v1/mcp/streamable_http_controller.rb)
> (`handle_tools_list`), 2026-06-12.

Per-agent tools (one tool per AI agent) are intentionally excluded from
`tools/list` to avoid flooding the client. Agents remain callable via
`platform.list_agents` + `platform.execute_agent`.

`tools/list` carries a **one-line description** per tool — the first sentence,
capped at 160 characters — so the full catalog stays small enough to fetch on
every session start. The long-form text (gating, envelope and side-effect
notes) is served on demand: call `platform.describe_tool` with a tool's exact
listed name to get its complete description, `inputSchema`, `outputSchema`,
title and annotations, plus `truncated: true|false` telling you whether the
one-line summary lost text. An unknown name is answered with the nearest
advertised names. `platform.describe_tool` is scoped exactly like `tools/list`:
a restricted (fleet instance or federation) principal can describe only the
tools its grant already advertises, and an ungranted name comes back as unknown.
The auto-generated
[MCP tool catalog](../reference/auto/mcp-tools.md) keeps the full descriptions.

## Prerequisites

1. **A running Powernode instance.** The backend service
   (`powernode-backend@default`) must be up and serving on its API port
   (`3000` in a local install). See
   [`getting-started/01-quickstart.md`](../getting-started/01-quickstart.md).
2. **An MCP-compliant client** that supports the **streamable-HTTP** transport
   and OAuth 2.1 — for example Claude Code or Claude Desktop.
3. **A Powernode user account** on that instance. Authentication binds the MCP
   session to a real `User` and `Account`, and tool execution is gated by that
   user's permissions. No separate "service" credential is required for the
   normal interactive flow.

## The endpoint

The streamable-HTTP MCP endpoint is:

```
POST   http://<host>:3000/api/v1/mcp/message     # JSON-RPC 2.0 messages
GET    http://<host>:3000/api/v1/mcp/message     # opens the SSE event stream
DELETE http://<host>:3000/api/v1/mcp/message     # terminates the session
```

For a local install the base is `http://localhost:3000`. In production, swap in
your host and scheme (`https://...`). The endpoint speaks JSON-RPC 2.0 and
upgrades to Server-Sent Events when the client sends
`Accept: text/event-stream`.

Verified against
[`server/config/routes.rb`](../../server/config/routes.rb) (`namespace :mcp`)
and
[`server/app/controllers/api/v1/mcp/streamable_http_controller.rb`](../../server/app/controllers/api/v1/mcp/streamable_http_controller.rb),
2026-06-12.

## Authentication

Powernode's MCP endpoint authenticates with **OAuth 2.1 bearer tokens** issued
by the platform's own authorization server. For a compliant MCP client this is
**automatic** — you do not mint a token by hand.

The flow follows the MCP authorization spec:

1. The client makes an unauthenticated request to `/api/v1/mcp/message`.
2. The server responds `401 Unauthorized` with a `WWW-Authenticate: Bearer
   resource_metadata="…/.well-known/oauth-protected-resource"` header
   (RFC 9728).
3. The client fetches that protected-resource document, which points it at the
   authorization server, then fetches
   `/.well-known/oauth-authorization-server` (RFC 8414) for the endpoint set.
4. The client performs OAuth 2.1 with PKCE (`S256`). The server supports
   **dynamic client registration** (RFC 7591) at `/api/v1/oauth/register`, so
   the client can register itself with no pre-shared secret (public client,
   `token_endpoint_auth_methods_supported: ["none"]`).
5. You approve the authorization in your browser; the client receives a bearer
   token and sends it as `Authorization: Bearer <token>` on every MCP request.

So the practical client setup is: **point the client at the endpoint URL and
let it run the OAuth flow.** A browser consent step is the only manual action.

The advertised OAuth scopes are `read`, `write`, `workflows`, and `files`.
Beyond scopes, every tool call is additionally gated by the authenticated
user's Powernode permissions — a token does not widen what its owner can do.

Verified against
[`server/app/controllers/concerns/mcp_token_authentication.rb`](../../server/app/controllers/concerns/mcp_token_authentication.rb)
and
[`server/app/controllers/well_known_controller.rb`](../../server/app/controllers/well_known_controller.rb),
2026-06-12.

> **Manual / smoke-test tokens.** If you need a token for a `curl` smoke test or
> a non-interactive client, obtain one through the OAuth flow above (or via an
> OAuth application registered in the platform UI) and pass it as
> `Authorization: Bearer <token>`. Treat it as a secret: do not commit it, log
> it, or paste it into shared channels.

## Client configuration

### Claude Code

Claude Code reads MCP servers from `.claude/settings.json`. Register the
endpoint as a `streamable-http` server. The in-repo configuration for this
platform is the reference example:

```json
{
  "mcpServers": {
    "powernode": {
      "type": "streamable-http",
      "url": "http://localhost:3000/api/v1/mcp/message"
    }
  }
}
```

No auth block is required — Claude Code discovers the OAuth requirement from the
`401` challenge and runs the flow, prompting you to authorize in the browser on
first connect. For a remote instance, replace the URL host/scheme accordingly.

This exact entry is verified in
[`/opt/powernode/.claude/settings.json`](../../.claude/settings.json),
2026-06-12.

### Claude Desktop

Claude Desktop uses the same MCP server model. Add a `streamable-http` (or
remote) server entry pointing at `http://<host>:3000/api/v1/mcp/message` and
authorize when prompted. Configuration-file location and the exact transport key
name vary by client version — consult your client's MCP-server documentation for
the current field names. `TODO(verify)`: Claude Desktop's config path and key
names are client-specific and were not verified against this repo.

### Other MCP clients

Any client that supports streamable-HTTP MCP and OAuth 2.1 (with PKCE and,
ideally, dynamic client registration) can connect using the same endpoint URL.
Clients that cannot perform the OAuth flow must send a valid
`Authorization: Bearer <token>` header obtained out of band (see the manual
token note above).

## First-call smoke test

The MCP handshake is the cleanest smoke test. After your client connects, the
first JSON-RPC call it makes is `initialize`; you can reproduce it manually to
confirm the endpoint, transport, and token are all working.

The unauthenticated probe (confirms the endpoint is live and challenges for
auth — expect `401` with a `WWW-Authenticate` header):

```bash
curl -i -X POST http://localhost:3000/api/v1/mcp/message \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke-test","version":"0"}}}'
```

The authenticated handshake (replace `$TOKEN` with a bearer token from the OAuth
flow). A success returns a JSON-RPC `result` with `protocolVersion`,
`capabilities`, and `serverInfo`, and an `Mcp-Session-Id` response header:

```bash
curl -i -X POST http://localhost:3000/api/v1/mcp/message \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke-test","version":"0"}}}'
```

Once initialized, list the tools to confirm the catalog is reachable:

```bash
curl -s -X POST http://localhost:3000/api/v1/mcp/message \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

A good first tool call from inside the client is a read-only health check —
for example `platform.get_system_health` or `platform.health`. If that returns a
structured result, the connection is fully working.

The handshake method names and the `Mcp-Session-Id` header are verified against
[`server/app/controllers/api/v1/mcp/streamable_http_controller.rb`](../../server/app/controllers/api/v1/mcp/streamable_http_controller.rb)
(`handle_initialize`, `dispatch_method`), 2026-06-12. The protocol version
string shown is the server's advertised version as of that date; a compliant
client negotiates this automatically, so prefer letting the client pick it.

## A2A discovery (agent cards)

Alongside MCP, Powernode publishes an **A2A (Agent-to-Agent) agent card** for
agent discovery at:

```
GET http://<host>:3000/.well-known/agent-card.json
```

The card advertises the platform's A2A endpoint (`/api/v1/a2a`), its protocol
version, capabilities (streaming, push notifications, extended card, state
transition history), supported input/output modes, and the platform skill
surface. Per-agent cards are also available under the A2A namespace. This is the
discovery entry point for A2A-aware clients; MCP clients do not need it to
connect.

Verified against
[`server/app/controllers/well_known_controller.rb`](../../server/app/controllers/well_known_controller.rb)
(`agent_card`) and
[`server/app/services/a2a/agent_card_service.rb`](../../server/app/services/a2a/agent_card_service.rb),
2026-06-12.

## Platform agents as Claude Code subagents

The platform's **canonical agents** — the global, seeded `Ai::Agent` rows (Fleet
Autonomy, SDWAN Manager, CVE Responder, System Concierge, Strategic Planner, …) —
are also native Claude Code subagents. One committed file per agent lives under
[`.claude/agents/powernode/`](../../.claude/agents/powernode/), so any session on
this checkout can delegate to one directly:

```
Agent(subagent_type: "sdwan-manager", prompt: "attach the new peer and refresh the route policies")
```

The `subagent_type` is the agent's **slug** — stable across installs. The platform
stays the single source of truth: the file is a thin bootstrap, never a copy of
the prompt.

**Why the committed files carry no delegation policy.** They must render
byte-identically on every install — the freshness gate diffs them — so the
canonical export reads only globally-scoped rows. Delegation policies,
intervention policies and lineage edges all carry a `NOT NULL account_id`: they
are one account's governance configuration, so committing them would both leak
that account's setup and fail the gate on any install with a second account. The
per-account export (`ACCOUNT_ID=… rails claude:sync_agents`, written to the
gitignored `.claude/agents/powernode-local/`) renders all of them, scoped to that
account. The live delegation authority is always the platform's own — the router
and `Ai::Autonomy::DelegationAuthorityService` read the rows directly.

**What each file carries** (generated by `Ai::ClaudeExport::AgentSkeletonSync`):

| Part | Content | Derived from |
|------|---------|--------------|
| `description` | A **routing description** — `Use this agent when …` with concrete triggers, then `Do not use for … — use `<sibling>` instead` naming the vocabulary-adjacent sibling, plus tier guidance for reasoning/frontier agents | the agent's description, its bound global skills' names/tags, its sibling agents, and (local export only) its intervention-policy domains (`Ai::ClaudeExport::RoutingDescription`) |
| `model` | `haiku` / `sonnet` / `opus` / `fable` | the agent's declared `model_requirements.tier` or pinned model (never this install's provider state) |
| `tools` | `Read, Grep, Glob` (+ `Edit, Write, Bash` for `code_assistant`), the bootstrap verbs (`get_agent`, `get_skill_context`) and the self-report verb, and the platform actions the agent's tool access allows — read verbs only when nothing is scoped; omitted (inherit everything) for `full_registry` agents | `Ai::ClaudeExport::ToolAllowlist`, mirroring `AgentToolBridgeService#scope_to_tool_families` |
| body step 1 | `mcp__powernode__platform_get_agent` with `slug: "<slug>"` — adopts the returned `system_prompt` | override-aware: an account's clone of a canonical wins on that install |
| body step 2 | `mcp__powernode__platform_get_skill_context` with the `id` returned by step 1 | the agent's active skill bindings |
| body last step | `mcp__powernode__platform_record_agent_execution` — the run reports itself back before returning (see [Runs feed the platform's statistics](#runs-feed-the-platforms-statistics)) | the fallback for a checkout with the `SubagentStop` hook disabled; same `run_key` contract as the hook |
| `## Delegation` | `Reports to` (lineage parent), and — in the local export only — `May delegate to`, `Max delegation depth`, `Inheritance` | `parent_agent_id` for the committed set; `Ai::AgentLineage` and `Ai::DelegationPolicy` additionally in the local export (rendered only when they exist) |
| `## Baseline guardrails` | `Ai::Agent::BASE_GUARDRAILS` verbatim | the always-on floor; the fetched prompt already prepends it natively, the body says so |

Claude Code's `Agent` tool chooses a subagent from these descriptions, so **for
platform work prefer these subagents over `general-purpose`**. When unsure which
one, ask the platform — the same router the Concierge uses:

```
platform.route_task(task_description: "triage the new critical CVE", constraints: { delegator_slug: "system-concierge" })
```

It returns the ranked candidates with a reason per dimension (capability, trust,
skill match, policy domain, tier/cost, performance), honours the delegator's
delegation policy, and names the winner's `subagent_type`. The SessionStart
guidance digest prints how many platform subagents the checkout carries.

**Freshness.** The committed set must match the canonical agents as the platform
renders them today. `scripts/check-claude-agents-fresh.sh` (run by
`scripts/pattern-validation.sh`) regenerates into a temp directory with the
public bundle and diffs; a seed change that adds/renames/retiers a canonical
agent, or a renderer change, fails the gate until you regenerate and commit:

```bash
cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 \
  bundle exec rails claude:sync_agents      # or: scripts/sync-claude-agents.sh
```

The export reads the development database, so on an install whose platform agent
seeds never ran it cannot produce the set at all — the check reports that as
**unverifiable** (a WARN, never a PASS). A Stop hook
(`.claude/hooks/claude-agents-sync-marker.sh` / `-apply.sh`) regenerates in the
background whenever a session edits a file under `db/seeds/`.

**Your own agents.** Only canonicals are committed. `ACCOUNT_ID=<uuid> rails
claude:sync_agents` exports an account's *own* agents (clones and local agents)
into the gitignored `.claude/agents/powernode-local/`.

**The reverse path is a proposal.** A hand-authored `.claude/agents/*.md` (any
file *without* the generated header) can be offered to the platform with
`rails claude:import_agents[<file-or-dir>]`. Each file becomes an
`Ai::AgentProposal` of type `agent_create` — attributed to the Platform Architect
agent when one exists, else the concierge — whose payload is the would-be
canonical spec (slug, name, agent type, description, the body as system prompt,
`tools` → tool families, `model` → model tier). Nothing is created directly:
official agents are seeded canonicals, so an operator reviews and approves.

### Runs feed the platform's statistics

A Claude Code run of a platform agent counts. When a platform subagent stops,
the platform receives one execution report and mints one `Ai::AgentExecution`
on that agent — the same row a platform execution produces, transitioned
through the same terminal hooks — so the agent's **execution history, trust
score** (`Ai::Autonomy::TrustEngineService`) and **model statistics**
(`Ai::AgentModelPerformance`, the substrate `Ai::AgentModelSelector` learns
from) all see the run. The executor is recorded as the session's own
`mcp_client` identity, so the row reads "this agent, run by that Claude Code
session".

Two paths deliver the report, and the platform sees **one row** either way
(the verb is idempotent on `run_key`):

| Path | Mechanism | When |
|------|-----------|------|
| **Hook** (automatic) | `.claude/hooks/subagent-report.sh` on the `SubagentStop` event, wired in `.claude/settings.json`. It reports only subagents whose name matches a *generated* skeleton (`.claude/agents/powernode/<slug>.md` or the local export), parses the subagent's transcript for the model, tokens, duration and outcome, and POSTs one `platform.record_agent_execution` call to the MCP endpoint the session already uses (`~/.claude.json` → `powernode`, else `127.0.0.1:18443/mcp`; `POWERNODE_MCP_URL` overrides). Fire-and-forget: 5 s budget, never blocks, never logs a body. | every checkout with hooks enabled |
| **Self-report** (fallback) | The last numbered step of every skeleton body: *before returning, call `mcp__powernode__platform_record_agent_execution`* with the slug, model, outcome, duration, tokens, a ≤500-char digest and `run_key: "<session id>:<slug>:<UTC start time>"`. | hooks disabled |

If both fire, the hook copies the self-report's `run_key` out of the transcript
and the second report updates the first row.

**What the verb does and does not do.** `platform.record_agent_execution`
(`ai.agents.execute`, mutating, *not* autonomy-gated — it records history, it
does not act) resolves `agent_slug` override-aware (an account's clone wins),
redacts the digest through the platform's PII path, and credits the reported
model to the account's **credentialed Anthropic provider** when one exists —
otherwise to the account's synthetic, inactive `claude-code` provider scope
that `Ai::AgentModelSelector` never routes a platform execution to. That scope
is **seeded**, never created by the report: `db/seeds/ai_claude_code_provider_seed.rb`
(baseline) creates one per account, `Setup::FirstAdminService` creates it for the
first account of a fresh install, and `Accounts::ProvisionService` creates it for
a tenant provisioned after first boot. An account without one gets a refusal
naming the seed. A Claude Code run counts toward model
statistics and the trust score and **never** toward autonomy budgets
(`Ai::AgentBudget`), consent ceilings or approval accounting — those are
platform-execution concepts.

**Token convention.** A report's `tokens.input` is the run's **full billed
input footprint** — `input_tokens` + `cache_read` + `cache_creation` — because
that is what the run actually consumed. A long Claude Code session reads a
large prompt cache on every turn, so a Claude Code run's token figures are
**not directly comparable** to a platform execution's, which ran without one;
compare counts and outcomes across executor kinds, not tokens. The hook applies
this convention when it parses the transcript; a self-report should do the same.

**Upgrading an existing install.** `db:seed` runs on FIRST BOOT ONLY, so an
install that predates the scope has accounts without one and every self-report
against them is refused. Backfill once, after deploying:

```bash
rails db:seed:claude_code_provider_scopes   # absence-only, safe to re-run
```

Check first with `platform.record_agent_execution` (or the Rails console) rather
than the `SubagentStop` hook: the hook posts in the background and **discards
the response**, so it prints its usual "Reported platform agent run…" line even
when the platform refused the report.

**Where to see it.** `platform.get_agent` and the agent detail API expose
`execution_stats.by_executor_kind` (`platform` vs `claude_code`); the agent
detail page's **Executions** card renders both counts (its tooltip restates the
token convention), and the Autonomy page's trust tab reflects the rows as it
always has.

## Troubleshooting

**`401 Unauthorized` on every request.** This is expected before
authorization and is the trigger for the OAuth flow — not an error in itself. If
it persists *after* you authorize, the token is missing, expired, or for an
inactive user/account. The response body includes an `error_code`
(`missing_token`, `token_invalid`, `user_inactive`) to disambiguate. Re-run the
client's authorization, and confirm the user and account are active.

**Tools disappear right after a backend restart, then come back.** Immediately
after a backend reload, a freshly forked worker can briefly `404` real routes
(including `/api/v1/mcp/message`) for a second or two before the route table
finishes drawing; many MCP clients treat a `404` as "endpoint gone" and drop the
session. The diagnostic signature is the **same worker returning `404` for a
route and then serving it ~1–2s later**, right after the "booted" log lines.
This race was fixed by drawing routes in Puma's `before_fork` hook
([`server/config/puma.rb`](../../server/config/puma.rb)); if you see it
recurring, confirm that hook is present and that you reloaded with the supported
path (`scripts/reload-backend.sh`). If a client did drop, reconnecting
re-establishes the session.

**`tools/call` returns a permission error (`-32001`).** The endpoint reached the
tool but the authenticated user lacks the permission that tool requires, or (for
a fleet-instance principal) the tool is outside its grant. Grant the needed
permission to the user, or use a user whose role already has it.

**`Method not found` (`-32601`) or `Invalid params` (`-32602`).** The client
sent an unsupported JSON-RPC method or a malformed `tools/call`. Confirm the
client is using a supported MCP method (`initialize`, `tools/list`,
`tools/call`, `resources/list`, `resources/read`, `prompts/list`, `prompts/get`,
`ping`) and that `tools/call` includes a `name`.

**SSE stream connects but no events arrive.** The `GET /api/v1/mcp/message`
stream sends periodic keepalive `ping` events; workspace events only flow when
the session is bound to an agent that belongs to a workspace. A quiet stream
that still emits pings is healthy.

**`Session not found or expired`.** The `Mcp-Session-Id` is stale (sessions have
a finite TTL and are swept daily). Re-run `initialize` to obtain a fresh session
token; well-behaved clients do this automatically on reconnect.

## Related documentation

- [`concepts/mcp-and-tools.md`](../concepts/mcp-and-tools.md) — how the
  `platform.*` registry and MCP server fit together.
- [`reference/auto/mcp-tools.md`](../reference/auto/mcp-tools.md) — the live tool
  catalog (auto-generated source of truth).
- [`contributing/conventions/model-routing-governance.md`](../contributing/conventions/model-routing-governance.md)
  — the tier ladder behind each skeleton's `model:` and the agent-sync usage notes.
- [`getting-started/01-quickstart.md`](../getting-started/01-quickstart.md) —
  standing up a local instance.
- [`guides/devops.md`](./devops.md) — service management and `.claude/settings.json`.

_Last verified: 2026-06-12_
