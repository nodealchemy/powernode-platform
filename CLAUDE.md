# CLAUDE.md

Development guidance for **Powernode**: open-source mission control for AI agent fleets.
This file is the **outage-safe core** — only global, high-stakes rules that must hold even if the
MCP server is down. Situational rules live in hooks, `scripts/pattern-validation.sh`, and
[docs/contributing/conventions/](docs/contributing/conventions/) (recalled MCP-first). See
[Where guidance lives](#where-guidance-lives).

## Project Overview

Control plane for production AI agent fleets — knowledge graph, governance, swarm coordination,
MCP-native runtime, and the fleet substrate (bare-metal / VM / container lifecycle). MIT.

- **Backend**: Rails 8 API (`./server`) — JWT auth, UUIDv7 PKs. Does **NOT** run Sidekiq.
- **Frontend**: React TypeScript (`./frontend`) — theme-aware, Tailwind.
- **Worker**: Sidekiq standalone (`./worker`) — API-only communication.
- **Public extensions** (git submodules, MIT on GitHub): `./extensions/system`, `./extensions/marketing`, `./extensions/supply-chain`.
- **Private extensions** (remote-only, not in public clones; added by maintainers): under `./extensions/private/*`. The platform runs in **core mode** when absent — single-user self-hosted, all core capabilities unlocked, no billing/SaaS.
- **Database**: PostgreSQL (native UUID) + pgvector.

**Project Status**: [docs/reference/auto/todo.md](docs/reference/auto/todo.md) (auto-generated — do not edit).

### Core Models
```
Account → User (many), Agent (many), Skill (many)
User → Roles, Permissions, Invitations
Agent → Conversations, Tasks, Goals, ApprovalRequests
```

## Where guidance lives

Rules are routed by **trigger shape** — the mechanism that surfaces or enforces each one when relevant:

| Rule shape | Home | Surfaces / enforces via |
|---|---|---|
| Always + high-stakes + not checkable | **this file (core)** | always loaded |
| Mechanically checkable | **`.claude/hooks/*.sh`** + `scripts/pattern-validation.sh` | edit-time hook / adherence scan |
| Reusable pattern / procedure | **[conventions/](docs/contributing/conventions/)** + platform knowledge | MCP-first queries + SessionStart digest |
| Subsystem-scoped | **nested `server//frontend//worker/ CLAUDE.md`** | loads when editing that tree |
| Decision / incident / preference | **auto-memory** (`~/.claude/.../memory/MEMORY.md`) | harness relevance injection |
| Crypto / private-extension logic | **extension only** (never core) | `core-purity-check.sh` (blocking) |

## Memory & Knowledge

- **Auto-memory** (`MEMORY.md` index, loaded each session) records operational decisions, incidents, and your working preferences. Consult it; it reflects what was true when written — verify file/flag references before acting.
- **MCP-first** is mandatory for non-trivial work: query `platform.query_learnings` / `search_knowledge` / `code_semantic_search` before changing code (full protocol: [conventions/mcp-first-workflow.md](docs/contributing/conventions/mcp-first-workflow.md)). Contribute back after (`create_learning` / `create_knowledge`).
- Migrated convention rules are tagged `guidance-*` in platform knowledge and digested at session start. The SessionStart digest is **Claude-only**; non-Claude executors receive `guidance-*` via the loop guardrails payload (`dev_next_task`) and the `Ai::Agent` `BASE_GUARDRAILS` baseline, both of which instruct every executor to query `search_knowledge tag:guidance-*` before implementing. Query the **production** connector (`mcp__powernode__*`) for this — a sandbox/dev MCP connector (e.g. `mcp__powernode-local__*`) can hold an unseeded, empty knowledge store, where `search_knowledge` legitimately returns zero `guidance-*` results (`success:true`, `count:0`) with no error; that is an empty-store signal, not evidence the guidance doesn't exist, and is expected rather than informative.

---

## Critical Rules (always-on)

### Git
- **NEVER** commit unless explicitly requested. **NEVER** include AI attribution (any executor — Claude/Grok/Codex/Gemini/etc.) in commits — no "Generated with" / "Co-Authored-By" from any model.
- Branch: `develop` → `feature/*` → `release/*` → `master`. Tags/release branches: **NO "v" prefix** (`0.2.0`, `release/0.2.0`).
- **Staged commits**: group changes into logical commits by concern — never one monolithic commit. (also `guidance-git-conventions`)

### Permission-Based Access Control (CRITICAL)
**Frontend MUST use permissions ONLY — NEVER roles for access control.**
```typescript
currentUser?.permissions?.includes('users.manage')   // ✅ CORRECT
currentUser?.roles?.includes('admin')                 // ❌ FORBIDDEN
user.role === 'manager'                               // ❌ FORBIDDEN
```
**Backend**: `current_user.has_permission?('name')` — NEVER `permissions.include?()` (returns objects).
Backstopped by `permission-not-roles-check.sh` (advisory) + `pattern-validation.sh` (scan) + recall `guidance-permissions-not-roles`.

### Cryptographic Material Safety (ABSOLUTE)
Generic key-handling principles — apply to ALL key material. Private-extension specifics (audit sinks, wallet/signing internals) live in the extension / `CLAUDE.local.md`, never here. The full table below is also carried model-agnostically (in `guidance-crypto-material-safety` + agent `BASE_GUARDRAILS`) so all executors carry it; it stays in core because it is outage-safe/absolute.

| Rule | Details |
|------|---------|
| No key output | **NEVER** output, log, display, echo, or transmit private keys, API secrets, seed phrases, mnemonics, or signing material in any form |
| No keys in code | **NEVER** store keys/secrets/credentials in source, scripts, configs, env files, or docs |
| No CLI key generation | **NEVER** generate private keys via CLI (rails runner, rake, irb) where they could hit shell history |
| Vault-only storage | ALL key generation MUST happen inside Vault or the platform's Vault-backed key service (stores directly to Vault) |
| Audit all key ops | ALL key operations (generate, import, revoke, sign) MUST be logged to the audit log. TODO(verify: confirm core audit-log sink) |
| No key args in logs | **NEVER** pass keys as function arguments that could appear in logs/errors/traces |
| Guide, don't handle | When assisting with wallet/key setup, guide through the UI/API — never handle key material directly |

### Backend (high-stakes — full conventions in [backend-patterns.md](docs/contributing/conventions/backend-patterns.md))
- **Eager Loading**: always `.includes()` when iterating associations — never bare `.all` then `.map`/`.each` accessing relations. (Nudge: `n-plus-one-check.sh`.)
- **Webhook Receivers**: inbound webhooks MUST return 200/202 on processing errors — NEVER 500 (provider retry storms). (Nudge: `webhook-500-check.sh`.)
- Everything else (namespacing, FK prefixes, JSON lambda defaults, `t.references` indexes, controller size, frozen-string, `render_success`) is hook/scan-enforced — see the doc.

### Worker Architecture (CRITICAL)
- **server** (`server/`) is a Rails API — it does **NOT** run Sidekiq.
- **worker** (`worker/`) is standalone Sidekiq — talks to server via HTTP API only.
- **NEVER** create job classes in `server/app/jobs/`; **NEVER** add Sidekiq gems to `server/Gemfile`. Keep the server/worker boundary clean (server stays Sidekiq-free; cross-app comms via the HTTP API). `worker/` **MAY** be modified when a change genuinely belongs there — there is no blanket prohibition on touching it.

### Bulk Operation Safety
- **State the count** before ANY bulk operation: "This will affect N items."
- Operations affecting **more than 5 items** require explicit user confirmation; show the first 3 and last 1.
- **Never batch-approve** training decisions, permission grants, financial operations, or **auto-discovered code changes** — review individually. (also `guidance-bulk-op-safety` + agent `BASE_GUARDRAILS` + loop guardrails so all executors carry it)

### Design Principles
- **Reuse First**: `platform.discover_skills` + `search_knowledge` + `code_semantic_search` before proposing anything new — never greenfield when infrastructure exists. (also `guidance-reuse-first` + agent `BASE_GUARDRAILS`)
- **Stop & Ask** (HARD): after 3 failed attempts at the same fix, STOP and ask. No 4th approach, no workarounds.
- **Surface Assumptions**: state assumptions before implementing ambiguous requests; if multiple valid interpretations exist, present and ask.
- **Audit = report only**: when asked to audit/review/analyze, save findings to `docs/`; do NOT implement unless told to fix.
  - _(these governance rules also live in platform knowledge for all executors — recall `guidance-audit-report-only`, `guidance-surface-assumptions`, `guidance-trace-to-request`, `guidance-plan-before-multifile`, `guidance-dead-reference-cleanup`; audit-report-only + surface-assumptions also carried in agent `BASE_GUARDRAILS`)_
- **Test-First Bug Reproduction**: write a failing test reproducing the bug before the fix.
- **Trace Changes to Request**: every changed line traces to the request; revert adjacent "improvements" (scope creep).
- **Plan Before Multi-File**: changes touching 3+ files — outline files + data flow, get approval before writing.
- **Dead Reference Cleanup**: after deleting a file, `grep -r` for references and remove them (scope: orphans your changes created).
- **Completion Gate**: before reporting work done, run the verification gate — `scripts/validate.sh` (model-agnostic; specs + tsc + pattern-validation + gitleaks) or its targeted subset for what you changed. `/verify` is the Claude-only convenience wrapper; non-Claude executors use the gate directly (also `guidance-verification-gate` + loop guardrails).
- **Quality Gates**: `cd frontend && npx tsc --noEmit` after TS; Ruby syntax + related spec after `.rb`; `rails db:seed` after seeds — the authoritative home is the gate `scripts/validate.sh` (run by the pre-commit hook and any committer).

### Architecture Principles
- **Pull, Never Push**: downstream managers pull from upstream; upstream never pushes downstream. When unsure of data-flow direction, ask.
- **Extension Isolation**: each `extensions/*` is self-contained. Extensions depend on core; **core NEVER depends on extensions**. Enforced by the blocking `core-purity-check.sh` **and** a model-agnostic `scripts/pattern-validation.sh` scan mirror (not just the Claude hook) — core source must not reference a private extension by name (its `Namespace::`, submodule path, or import alias); both derive the forbidden names dynamically from `extensions/private/*`. Route through a generic seam instead.
- **Service Boundaries**: cross-namespace communication goes through service interfaces, never direct model access.

_These three invariants are also in the cross-executor `guidance-architecture-invariants` knowledge entry (recalled by any executor via `search_knowledge tag:guidance-*`), stated generically for all models._

### Submodule Safety (CRITICAL)
- Submodules: public `extensions/{system,marketing,supply-chain}` + private `extensions/private/*`. **Do NOT run `git submodule sync`** on the public ones (drops the private upstream remote). (also `guidance-submodule-safety`)
- **CWD verification**: before EVERY `git add`/`git commit`, run `git rev-parse --show-toplevel` and confirm the repo.
- **Survey both statuses**: `git status` in root AND `git -C extensions/<name> status` — submodule changes are invisible to the parent.
- **Never commit extension files from parent**; commit **inside** the submodule FIRST, then update the pointer in the parent.
- Maintainer-local detail (private extensions, audit sinks) lives in `CLAUDE.local.md` — never the public repo.

### File Organization
**NEVER save files to project root.** Use `docs/{getting-started,concepts,guides,reference,operations,contributing}/`. `docs/reference/auto/` is auto-generated — do not edit. (also `guidance-file-organization`; enforced by `pattern-validation.sh`)

### Terminology
| Term | Means | Not |
|------|-------|-----|
| `server/` | Rails app directory | "backend directory" |
| `powernode-backend` | the Rails **service** (unit name below) | "rails service" |
| `worker/` | standalone Sidekiq app | "job runner" |
| `powernode-worker` | the Sidekiq **service** (unit name below) | "sidekiq service" |

**systemd unit names — NEVER guess them.** On module-composed nodes the agent
generates `powernode-<moduleID>-<serviceName>.service`
(`agent/internal/lifecycle/service.go`), where `<moduleID>` is the module's UUID
and `<serviceName>` is a `services:` entry in its manifest. So Rails is
`powernode-019f7cb5-3858-…-rails.service`, and sidekiq/worker-web share one UUID
because both ship in `powernode-hub-worker`. **Always discover, never assume:**

```bash
systemctl list-units 'powernode-*-rails.service' --no-pager --no-legend   # or -sidekiq/-worker-web
```

A guessed name (`powernode-backend@default`, `rails.service`) does **not** error —
`systemctl restart` on a nonexistent unit fails silently in a `||` chain, leaving
new code on disk while the old image keeps running, which looks exactly like a
successful deploy. Verify with `systemctl is-active` on the discovered unit.
The `@default` template form appears throughout `extensions/system/docs/runbooks/`
but is installed on neither dev-cell nor ops-hub — `systemctl list-unit-files
'powernode*'` shows no `@` template at all. Treat those references as stale.

After a Rails restart `/up` returns **502 for ~30s** while it boots; that is not a
failed deploy.

---

## Specialists & Documentation

Use `platform.discover_skills` with a task description to find the right specialist. **Query MCP first**; these files are the fallback:

| Topic | MCP Query | File Fallback |
|-------|-----------|---------------|
| Conventions (backend/frontend/testing/ops) | `search_knowledge` tag `guidance-*` | [docs/contributing/conventions/](docs/contributing/conventions/) |
| MCP config & workflow | `discover_skills` | [conventions/mcp-first-workflow.md](docs/contributing/conventions/mcp-first-workflow.md) |
| Knowledge lifecycle | — | [conventions/knowledge-lifecycle.md](docs/contributing/conventions/knowledge-lifecycle.md) |
| Service mgmt & ops | — | [conventions/service-and-ops.md](docs/contributing/conventions/service-and-ops.md) |
| MCP tool catalog | — | [docs/reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md) (auto-generated) |
| Permissions / Theme / API / UUID / Architecture | `search_knowledge` / `search_knowledge_graph` | [docs/concepts/](docs/concepts/), [docs/reference/](docs/reference/) |
| Learnings & patterns | `query_learnings` | [docs/reference/auto/learnings.md](docs/reference/auto/learnings.md) |

Per-subsystem rules also live in nested `server/CLAUDE.md`, `frontend/CLAUDE.md`, `worker/CLAUDE.md` (load automatically when editing those trees).
