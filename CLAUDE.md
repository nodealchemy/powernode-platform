# CLAUDE.md

Development guidance for **Powernode**: open-source mission control for AI agent fleets.

## Project Overview

**Powernode** is the control plane for production AI agent fleets — knowledge graph,
governance, swarm coordination, MCP-native runtime, and the fleet substrate
(bare-metal / VM / container lifecycle) underneath. Open-source under MIT.

- **Backend**: Rails 8 API (`./server`) — JWT auth, UUIDv7 primary keys, 558 MCP tool actions across 63 classes
- **Frontend**: React TypeScript (`./frontend`) — theme-aware, Tailwind CSS
- **Worker**: Sidekiq standalone (`./worker`) — API-only communication
- **System**: Git submodule (`./extensions/system`) — node lifecycle, module CRUD, fleet autonomy, on-node Go agent, initramfs, SDWAN, federation. **Public on GitHub** (MIT) at `nodealchemy/powernode-system`, private on Gitea.
- **Marketing**: Git submodule (`./extensions/marketing`) — public-facing site + campaign management. **Public on GitHub** (MIT) at `nodealchemy/powernode-marketing`.
- **Supply chain**: Git submodule (`./extensions/supply-chain`) — SBOM + cosign + attestations. **Public on GitHub** (MIT) at `nodealchemy/powernode-supply-chain`.
- **Database**: PostgreSQL with native UUID schema + pgvector for embeddings

Additional private submodules (added manually by maintainers; not in the public repo) provide SaaS features. The platform runs in **core mode** when those aren't present — single-user self-hosted with all core capabilities unlocked.

**Project Status**: See [docs/reference/auto/todo.md](docs/reference/auto/todo.md) (auto-generated from shared knowledge — do not edit manually)

### Core Models
```
Account → User (many), Agent (many), Skill (many)
User → Roles, Permissions, Invitations
Agent → Conversations, Tasks, Goals, ApprovalRequests
```

---

## Specialists

Use `platform.discover_skills` with a task description to find the right specialist capability. Fallback: [concepts/mcp-and-tools.md](docs/concepts/mcp-and-tools.md).

---

## Quick Reference - Critical Rules

### Git Rules
- **NEVER** commit unless explicitly requested
- **NEVER** include Claude attribution in commits
- Branch strategy: `develop` → `feature/*` → `release/*` → `master`
- Tag naming: **NO "v" prefix** - use `0.2.0` not `v0.2.0`
- Release branches: `release/0.2.0` (no "v" prefix)
- **Staged commits**: Group changes into logical commits by concern (models, services, controllers, frontend, tests, config) — never one monolithic commit

### Business Submodule (`./extensions/business`)
Private remote-only (not committed to public repo). **Path aliases**: `@business/` for intra-business imports, `@/` for core shared imports. **Core mode** when absent: single-user self-hosted, all features unlocked, no billing/SaaS. **Feature gating**: `Shared::FeatureGateService.business_loaded?` (backend), `__EXTENSIONS__.includes('business')` build-time gate (frontend, also drives nav visibility). For git/commit rules see [Submodule Safety](#submodule-safety-critical).

### Permission-Based Access Control (CRITICAL)
**Frontend MUST use permissions ONLY - NEVER roles for access control**

```typescript
// ✅ CORRECT
currentUser?.permissions?.includes('users.manage')

// ❌ FORBIDDEN
currentUser?.roles?.includes('admin')
user.role === 'manager'
```

**Backend**: Use `current_user.has_permission?('name')` - NEVER `permissions.include?()` (returns objects)

### Frontend Patterns
| Pattern | Rule |
|---------|------|
| Colors | Theme classes only: `bg-theme-*`, `text-theme-*` |
| Navigation | Flat structure - no submenus |
| Actions | ALL in PageContainer - none in page content |
| State | Global notifications only - no local success/error |
| Imports | Path aliases for cross-feature: `@/shared/`, `@/features/` |
| Logging | No `console.log` in production — use `import { logger } from '@/shared/utils/logger'` instead |
| Types | No `any` - proper TypeScript types required |

### Backend Patterns
| Pattern | Rule |
|---------|------|
| Controllers | `Api::V1` namespace, inherit ApplicationController |
| Responses | MANDATORY: `render_success()`, `render_error()` |
| Worker Jobs | Inherit BaseJob, use `execute()` method, API-only |
| Ruby Files | `# frozen_string_literal: true` pragma required |
| Logging | `Rails.logger` - no `puts`/`print` |
| Migrations | `t.references` automatically creates an index — **NEVER** use `add_index` for reference columns. Customize via the declaration itself: `t.references :account, index: { unique: true }` |
| Namespaces | ALL namespaced models MUST use `::` separator in `class_name:` — e.g., `Ai::AgentTeam` not `AiAgentTeam`, `Devops::Pipeline` not `DevopsPipeline`, `BaaS::Tenant` not `BaaSTenant` |
| Seeds | After modifying seeds, run `cd server && rails db:seed` and verify completion |
| Associations | Always pair `class_name:` with `foreign_key:` — e.g. `belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"` |
| Foreign Keys | Namespaced FK prefixes: `Ai::` → `ai_` (`ai_agent_id`), `Devops::` → `devops_` (`devops_pipeline_id`), `BaaS::` → `baas_` (`baas_customer_id`). Others: use explicit FK or omit if unambiguous |
| JSON Columns | Always use lambda defaults: `attribute :config, :json, default: -> { {} }` — never `default: {}` |
| Controller Size | Controllers MUST stay under 300 lines — extract query logic to services, serialization to concerns |
| Eager Loading | Always use `.includes()` when iterating associations — never bare `.all` followed by `.map`/`.each` accessing relations |
| Webhook Receivers | Inbound webhooks MUST return 200/202 on processing errors — NEVER 500 (causes provider retry storms) |

### Cryptographic Material Safety (ABSOLUTE RULES)
| Rule | Details |
|------|---------|
| No key output | **NEVER** output, log, display, echo, or transmit private keys, API secrets, seed phrases, mnemonics, or signing material in any form |
| No keys in code | **NEVER** store keys, secrets, or credentials in source code files, scripts, configs, environment files, or documentation |
| No CLI key generation | **NEVER** generate private keys via CLI commands (rails runner, rake, irb) where they could appear in shell history |
| Vault-only storage | ALL key generation MUST happen inside Vault or WalletKeyService (which stores directly to Vault) |
| Audit all key ops | ALL key operations (generate, import, revoke, sign) MUST be logged to the audit log. TODO(verify: confirm core audit-log sink) |
| No key arguments in logs | **NEVER** pass private keys as function arguments that could appear in logs, error messages, or exception traces |
| Guide, don't handle | When assisting with wallet setup, guide the user through the UI/API — never handle key material directly |

### Design Principles
| Principle | Rule |
|-----------|------|
| Reuse First | `platform.discover_skills` + `platform.search_knowledge` + `platform.code_semantic_search` before proposing anything new — never standalone/greenfield when infrastructure exists |
| Quality Gates | Run `cd frontend && npx tsc --noEmit` after TS changes, verify Ruby syntax after .rb changes |
| Verify Seeds | After seed modifications: `cd server && rails db:seed` — watch for association/validation errors |
| Stop & Ask | **HARD RULE**: After 3 failed attempts at the same fix, STOP immediately and ask the user. Do NOT try a 4th approach, do NOT continue iterating, do NOT try workarounds. Present what you tried and ask for guidance |
| Surface Assumptions | Before implementing ambiguous requests, state your assumptions explicitly. If multiple valid interpretations exist, present them and ask — never silently pick. Preemptive counterpart to **Stop & Ask** — addresses ambiguity *before* failure, not after |
| Audit Sessions | When asked to audit/review/analyze code, save findings to `docs/` and do NOT implement changes. Audit = report only, unless the user explicitly says to fix |
| Verify Changes | Ruby: syntax check + related spec. TypeScript: `tsc --noEmit`. Migrations: `rails db:migrate:status`. Seeds: `rails db:seed`. Use `/verify` for targeted checks |
| Test-First Bug Reproduction | For bug fixes, write a failing test that reproduces the bug BEFORE writing the fix. Confirms the bug exists, prevents regression, and forces understanding of the root cause |
| Verify CWD | Before git operations on submodules, always `git rev-parse --show-toplevel` to confirm you're in the right repo |
| Completion Gate | Before reporting work as done, run `/verify` on changed files. Never mark a task complete with unverified changes |
| Verify Per Step | For multi-step tasks, state a brief plan with explicit verification for each step ("Step → verify: <check>"). Finer-grained than **Completion Gate** — catch drift mid-task rather than only at the end |
| Dead Reference Cleanup | After deleting any file, `grep -r` for all import/require references to it across the codebase and remove them before committing. **Scope**: applies to orphans YOUR changes created. Pre-existing dead code: mention if noticed, don't delete unless explicitly asked |
| Trace Changes to Request | Every changed line should trace directly to the user's request. If you can't justify a hunk against the original task, revert it. Adjacent "improvements" during a bug fix count as scope creep |
| Plan Before Multi-File | Changes touching **3+ files**: outline which files will change and data flow direction, then wait for user approval before writing code. Single-file fixes can proceed directly |
| Parallel Investigation | When debugging spans backend + frontend or 3+ services, spawn parallel sub-agents: one per layer/service. Merge findings before proposing a fix — never serialize investigation across layers |

### Architecture Principles
| Principle | Rule |
|-----------|------|
| Pull, Never Push | Downstream managers always **pull** from upstream sources — upstream services NEVER push to downstream. When unsure about data flow direction, ask before implementing |
| Extension Isolation | Each extension (`extensions/*`) is self-contained. Extensions depend on core, core NEVER depends on extensions |
| Service Boundaries | Cross-namespace communication goes through service interfaces, never direct model access across namespaces |

### Bulk Operation Safety
| Rule | Details |
|------|---------|
| State the count | Before ANY bulk operation (approve, reject, delete, update), always state the exact count: "This will affect N items" |
| Confirmation threshold | Operations affecting **more than 5 items** require explicit user confirmation |
| Show samples | For bulk operations, show the first 3 and last 1 items for verification |
| Never batch-approve | Training decisions, permission grants, and financial operations MUST be reviewed individually |

### Submodule Safety (CRITICAL)
- **Submodules** (all git submodules): `extensions/business` (private remote-only) plus the public-on-GitHub `extensions/system`, `extensions/supply-chain`, and `extensions/marketing`. Maintainers may add further private extensions locally (see CLAUDE.local.md).
- **System and supply-chain extensions** are publicly mirrored on GitHub — `.gitmodules` advertises `https://github.com/nodealchemy/powernode-system.git` and `https://github.com/nodealchemy/powernode-supply-chain.git`. Maintainer's local checkout has `origin` = the public GitHub mirror and `ipnode` = the private upstream (added manually). Push to **both** remotes on every push to a shared branch (e.g. `develop`) — keep the public mirror continuously in sync, not only at release time. **Do NOT run `git submodule sync`** on these submodules — it would overwrite local config and drop the private upstream remote.
- **The business extension** (and any other private extension) is not committed to the public repo (gitignored in the parent's tree; not present in `.gitmodules`). Maintainers with access add it locally via `git submodule add <private-url> extensions/business`; its commits go to the private upstream only and never appear in public clones.
- **CWD verification**: Before EVERY `git add`/`git commit`, run `git rev-parse --show-toplevel` and verify it matches the intended repo
- **Survey both git statuses**: When checking state, run `git status` in root AND `git -C extensions/<name> status` for each submodule — changes inside a submodule are invisible to the parent repo's `git status`
- **Never commit extension files from parent**: Files under `extensions/*/` MUST be committed from within the submodule. Running `git add extensions/business/...` from parent only stages a pointer change
- **Commit order**: Commit inside each submodule FIRST, then update pointers in parent

### Terminology
| Term | Meaning | Don't Confuse With |
|------|---------|-------------------|
| `server/` | Rails app directory on disk | Not "backend directory" |
| `powernode-backend` | Systemd service name (`powernode-backend@default`) | Not "server service" or "rails service" |
| `worker/` | Standalone Sidekiq app directory | Not "job runner" |
| `powernode-worker` | Systemd service name (`powernode-worker@default`) | Not "sidekiq service" |

---

## Service Management

```bash
# Systemd services (requires initial install: sudo scripts/systemd/powernode-installer.sh install)
sudo systemctl start powernode.target           # Start all services
sudo systemctl stop powernode.target            # Stop all services
sudo systemctl restart powernode-backend@default  # Restart individual service
sudo scripts/systemd/powernode-installer.sh status  # Show all service status
journalctl -u powernode-backend@default -f      # Tail service logs
```

**NEVER** use manual commands (`rails server`, `sidekiq`, `npm start`)

### Service Operations Reference
| Service | Unit Name | Port | Restart Behavior |
|---------|-----------|------|-----------------|
| Rails API | `powernode-backend@default` | 3000 | SIGUSR2 reload (~30ms) via `scripts/reload-backend.sh`. Auto-reloaded by Stop hook after `.rb` edits |
| Sidekiq | `powernode-worker@default` | — | Full restart (~28s drain). **Wait 30s** before checking status — "deactivating" is normal during drain |
| Worker HTTP API | `powernode-worker-web@default` | 4567 | If port 4567 refused, restart THIS service, not `powernode-worker` |
| Frontend | `powernode-frontend@default` | 3001 | Full restart |

**Stuck worker**: If worker is draining >30s, use `sudo systemctl stop powernode-worker@default && sudo systemctl start powernode-worker@default` (stop+start, not restart)
**Never restart worker multiple times** in quick succession — batch code changes, ONE restart at end
**After restart**: Verify with `sudo scripts/systemd/powernode-installer.sh status`

---

## Test Execution

**RSpec**:
```bash
cd server && bundle exec rspec --format progress    # Full suite
cd server && bundle exec rspec spec/path_spec.rb    # Single file
```

**Frontend tests** - always use CI=true:
```bash
cd frontend && CI=true npm test
```

### Multi-Agent Test Rules
- Uses `DatabaseCleaner` with `:deletion` strategy — avoids `TRUNCATE` deadlocks between concurrent processes.
- Do NOT run multiple single-process rspec instances simultaneously on the same database.
- Frontend tests (`CI=true npm test`) and TypeScript checks (`npx tsc --noEmit`) are always safe to run concurrently.

### Worker Architecture (CRITICAL)
- The **server** (`server/`) is a Rails API — it does **NOT** run Sidekiq
- The **worker** (`worker/`) is a standalone Sidekiq process — it communicates with server via HTTP API only
- **NEVER** create job classes in `server/app/jobs/` — jobs belong in `worker/app/jobs/`
- **NEVER** add Sidekiq gems to `server/Gemfile`
- **NEVER** modify `worker/` files when fixing server issues

### Test Patterns Reference
| Pattern | Rule |
|---------|------|
| Factories | `spec/factories/` — use existing factories with traits (`:active`, `:paused`, `:archived`). AI factories in `spec/factories/ai/` |
| User Setup | `user_with_permissions('perm.name')` from `permission_test_helpers.rb` — never create users manually |
| Auth Headers | `auth_headers_for(user)` returns `{ Authorization: Bearer ... }` — use in all request specs |
| Response Helpers | `json_response`, `json_response_data`, `expect_success_response(data)`, `expect_error_response(msg, status)` |
| Shared Examples | `include_examples 'requires authentication'`, `'requires permission'`, `'scopes to current account'` — see `spec/support/shared_examples/` |
| AI Matchers | `be_a_valid_ai_response`, `have_execution_status(:status)`, `create_audit_log(:action)` — see `spec/support/ai_matchers.rb` |
| AI Helpers | `ProviderHelpers`, `AgentHelpers`, `WorkflowHelpers`, `SecurityHelpers` — see `spec/support/ai_test_helpers.rb` |
| E2E Pages | Page objects in `e2e/pages/` — always use existing page objects, check `e2e/pages/ai/` for AI features |
| E2E Selectors | `data-testid` first, then `class*="pattern"`, then `getByRole` — add `data-testid` to new components |
| E2E Guards | `page.on('pageerror', () => {})` in beforeEach, `if (await el.count() > 0)` for optional elements |

---

## Key Platform Documentation

**Query MCP first** — these files are the fallback when MCP returns no results:

| Topic | MCP Query | File Fallback |
|-------|-----------|---------------|
| MCP Configuration | `platform.discover_skills` | [concepts/mcp-and-tools.md](docs/concepts/mcp-and-tools.md) |
| Permission System | `platform.search_knowledge` query: "permission system" | [concepts/permissions.md](docs/concepts/permissions.md) |
| Theme System | `platform.search_knowledge` query: "theme system" | [reference/theme-system.md](docs/reference/theme-system.md) |
| API Standards | `platform.search_knowledge` query: "API response standards" | [reference/api/overview.md](docs/reference/api/overview.md) |
| UUID System | `platform.search_knowledge` query: "UUID system" | [concepts/data-model.md](docs/concepts/data-model.md) |
| Architecture | `platform.search_knowledge_graph` query: "platform architecture" | [concepts/architecture.md](docs/concepts/architecture.md) |
| Codebase Structure | `platform.code_context_tree` / `platform.code_semantic_search` | [reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md) |
| Learnings & Patterns | `platform.query_learnings` | [reference/auto/learnings.md](docs/reference/auto/learnings.md) |
| Shared Knowledge | `platform.search_knowledge` | [reference/auto/knowledge-base.md](docs/reference/auto/knowledge-base.md) |
| Skills Registry | `platform.discover_skills` | [reference/auto/skills.md](docs/reference/auto/skills.md) |
| Knowledge Graph | `platform.search_knowledge_graph` | [reference/auto/knowledge-graph.md](docs/reference/auto/knowledge-graph.md) |

---

## MCP-First Development Workflow

The Powernode MCP server (`platform.*` tools) is the **primary knowledge source**. File scanning is the fallback. **MCP queries are NOT optional** — they are mandatory protocol steps.

### SESSION START Protocol (MANDATORY — every session)

1. Run `platform.knowledge_health` — establish baseline, identify stale/conflicting knowledge
2. Run `platform.learning_metrics` — check active learnings count, recent contributions
3. If stale_count > 0 or conflicts detected, note them for resolution during the session
4. Run `platform.code_index_status` with `repository_id: "powernode-platform"` — check codebase index freshness and stale file count

### BEFORE EVERY CODE CHANGE (MANDATORY)

1. **Search existing knowledge** for the area being modified — not optional, not "when convenient":
   - `platform.query_learnings` — established patterns, anti-patterns, failure modes for this area
   - `platform.search_knowledge` — procedures, code snippets, reference material
   - `platform.search_knowledge_graph` — entity relationships, architecture decisions
   - `platform.discover_skills` — reusable capabilities matching the task
   - `platform.code_semantic_search` — find related code by meaning (e.g., "authentication middleware")
   - `platform.code_identifier_search` — find specific classes/methods/functions by name
2. **Understand impact** before modifying:
   - `platform.code_blast_radius` — trace every file affected by changing a symbol
   - `platform.code_file_skeleton` — review structure of files you're about to modify
3. **Apply discovered knowledge** to your implementation approach
4. **Fall back to file scanning** only when MCP returns no relevant results
5. **Feed file-scan discoveries back** into MCP (see "After Every Task")

### DURING WORK (Active Reinforcement)

- **When relying on a learning**: Call `platform.reinforce_learning` with its ID immediately — this prevents decay and boosts confidence
- **When using shared knowledge**: Call `platform.rate_knowledge` (4-5 if helpful, 1-2 if outdated) — this feeds quality scores
- **Pattern verification**: Before introducing a new pattern, check `platform.query_learnings`
- **Architecture context**: Before cross-cutting changes, check `platform.search_knowledge_graph`
- **Code structure**: Use `platform.code_context_tree` to understand directory layout before adding files
- **Impact analysis**: Use `platform.code_blast_radius` before renaming or refactoring shared symbols
- **Memory context**: Use `platform.search_memory` to retrieve agent working memory relevant to the current task
- **API context**: Use `platform.get_api_reference` to look up endpoint contracts before writing integration code
- **Conflict resolution**: If you find two conflicting learnings, resolve with `platform.resolve_contradiction` immediately

### AFTER EVERY TASK (MANDATORY — zero exceptions for non-trivial work)

Contribute via the manual responsibilities table in [Knowledge Quality Lifecycle](#knowledge-quality-lifecycle). **Skip** for trivial fixes (typos, renames, formatting), speculative/unverified analysis, or knowledge that already exists in MCP. **Self-check** at task end: "Did I create learnings for the critical findings?" — if no, do it now.

### MCP Tool Invocation

Claude Code invokes `platform.*` tools directly via the streamable-http MCP server registered in `.claude/settings.json` (`powernode` entry pointing at `http://localhost:3000/api/v1/mcp/message`). No external daemon, no helper scripts — just call the tool by name.

---

## MCP Tool Catalog

All `platform.*` tools by area — see [reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md) for descriptions and parameters.

- **Discovery & Context** (10): `search_knowledge`, `query_learnings`, `search_knowledge_graph`, `reason_knowledge_graph`, `discover_skills`, `get_skill_context`, `search_memory`, `search_documents`, `query_knowledge_base`, `get_api_reference`
- **Knowledge Contribution** (7): `create_learning`, `create_knowledge`, `update_knowledge`, `promote_knowledge`, `extract_to_knowledge_graph`, `create_skill`, `update_skill`
- **Quality & Reinforcement** (9): `verify_learning`, `dispute_learning`, `resolve_contradiction`, `rate_knowledge`, `reinforce_learning`, `knowledge_health`, `learning_metrics`, `skill_health`, `skill_metrics`
- **Agent Management** (5): `create_agent`, `list_agents`, `get_agent`, `update_agent`, `execute_agent`
- **Team Management** (6): `create_team`, `list_teams`, `get_team`, `update_team`, `add_team_member`, `execute_team`
- **Knowledge Graph Exploration** (7): `search_knowledge_graph`, `reason_knowledge_graph`, `get_graph_node`, `list_graph_nodes`, `get_graph_neighbors`, `graph_statistics`, `get_subgraph`
- **Memory Management** (6): `write_shared_memory`, `read_shared_memory`, `search_memory`, `consolidate_memory`, `memory_stats`, `list_pools`
- **RAG & Documents** (7): `query_knowledge_base`, `list_knowledge_bases`, `create_knowledge_base`, `add_document`, `process_document`, `search_documents`, `delete_document`
- **Content Management** (8): `list_kb_articles`, `get_kb_article`, `create_kb_article`, `update_kb_article`, `list_pages`, `get_page`, `create_page`, `update_page`
- **Skill Administration** (4): `list_skills`, `get_skill`, `delete_skill`, `toggle_skill`
- **AI Autonomy & Safety** (16): `emergency_halt`, `emergency_resume`, `kill_switch_status`, `create_agent_goal`, `list_agent_goals`, `update_agent_goal`, `agent_introspect`, `propose_feature`, `send_proactive_notification`, `discover_claude_sessions`, `request_code_change`, `create_proposal`, `escalate`, `request_feedback`, `report_issue`
- **Codebase Intelligence** (14): `code_context_tree`, `code_file_skeleton`, `code_semantic_search`, `code_identifier_search`, `code_semantic_navigate`, `code_feature_hub`, `code_blast_radius`, `code_static_analysis`, `code_index_status`, `code_upsert_node`, `code_create_relation`, `code_search_graph`, `code_prune_stale`, `code_bulk_index`
- **DevOps & CI/CD** (6): `create_gitea_repository`, `update_gitea_repository`, `dispatch_to_runner`, `trigger_pipeline`, `list_pipelines`, `get_pipeline_status`
- **Dev Loop Bridge** (2): `dev_next_task`, `dev_complete_task` — pull-based Ralph Loop task queue for loop executors (Claude Code sessions, future container agents)
- **Storage Ownership** (4): `system_assign_storage_owner`, `system_list_storage_assignments_by_owner`, `system_storage_chown_status`, `system_storage_chown_retry`
- **System Fleet** (3): `system_get_task`, `system_revert_disk_image`, `system_update_module_assignment`

### Docker Management (52 tools)
Grouped by area — see [reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md) for full per-tool params.
- **Containers** (10): `docker_{list,get,create,start,stop,restart,delete}_container`, `docker_container_{logs,stats,exec}`
- **Services** (9): `docker_{list,get,create,update,scale,rollback,delete}_service`, `docker_service_{logs,tasks}`
- **Stacks** (5): `docker_{list,get,deploy,delete,adopt}_stack`
- **Clusters & Nodes** (8): `docker_{list,get}_cluster`, `docker_cluster_health`, `docker_list_nodes`, `docker_node_{promote,demote,drain,activate}`
- **Secrets & Configs** (6): `docker_{list,create,delete}_{secret,config}`
- **Hosts** (4): `docker_{list,get,sync,test}_host`
- **Images** (4): `docker_{list,pull,delete,tag}_image`
- **Networks** (3): `docker_{list,create,delete}_network`
- **Volumes** (3): `docker_{list,create,delete}_volume`

---

## Knowledge Quality Lifecycle

The platform runs automated maintenance (see `worker/config/sidekiq.yml`). Claude Code participates in the quality loop:

### Automated (background jobs)
| Job | Schedule | Effect |
|-----|----------|--------|
| Compound learning decay | 3:45 AM daily | `importance_score` decays exponentially on stale learnings |
| Memory consolidation | 4:00 AM daily | Promotes STM→long-term (access>=3), deduplicates (similarity>=0.92) |
| Rot detection | 4:00 AM daily | Auto-archives context entries with staleness>=0.9 |
| Trust score decay | 2:00 AM daily | Decays idle agent trust scores |
| Skill lifecycle | 4:15 AM daily / 5 AM weekly / 3 AM monthly | Conflict scan, stale decay, re-embedding, gap detection |
| Shared knowledge maintenance | Daily | Import from learnings, recalculate quality scores, audit stale entries |
| Escalation timeout | Every 15 min | Auto-escalate overdue escalations |
| Goal maintenance | Every 6 hours | Auto-abandon stale goals |
| Intervention policy tuning | Weekly | Analyze approval patterns and suggest policy adjustments |
| Observation pipeline | Every 30 min | Collect sensor data for autonomous agents |
| Observation cleanup | Daily | Delete expired and old processed observations |
| Proposal expiry | Every hour | Expire overdue unreviewed proposals |

### Manual (Claude Code responsibilities)
| Trigger | Tool |
|---------|------|
| Solved a non-trivial bug | `create_learning` (category: `discovery` / `failure_mode`) |
| Established/confirmed a pattern | `create_learning` (category: `pattern` / `best_practice`) |
| Documented a procedure or guide | `create_knowledge` (content_type: `procedure`) |
| Found entity relationships | `extract_to_knowledge_graph` |
| Implemented a reusable capability | `create_skill` |
| Used a learning successfully | `reinforce_learning` |
| Used a learning that was wrong | `dispute_learning` |
| Found two conflicting learnings | `resolve_contradiction` |
| Read useful shared knowledge | `rate_knowledge` (4-5) |
| Read outdated shared knowledge | `rate_knowledge` (1-2) + `create_knowledge` (corrected version) |
| Removed deprecated code | `create_learning` (category: `pattern`) documenting the removal |
| Encountering a bug | Search `query_learnings` first — `reinforce_learning` if found, fix + `create_learning` if not |
| Fixing documentation drift | `update_knowledge` on the source entry |
| Before starting work (>24h since last) | `knowledge_health` + `skill_health` |

---

## Tool Evolution

`platform.*` tools live in `server/app/services/ai/tools/platform_api_tool_registry.rb` (tool class + `TOOLS` map + `action_definitions`). After adding or modifying, run `rails mcp:generate_tool_catalog` to refresh `docs/reference/auto/mcp-tools.md`; `rails mcp:sync_docs` regenerates the broader fallback docs (also runs nightly at 5:30 AM UTC via `AiKnowledgeDocSyncJob`). For **new** tools, also add the tool name to the MCP Tool Catalog list above and create a `pattern` learning. For **deprecations**, add a deprecation note in the action definition, create a `best_practice` learning pointing at the replacement, and remove the entry from the catalog list after the migration period.

---

## File Organization

**NEVER save files to project root**. Use:
- `docs/getting-started/` - Tutorials for first-time users
- `docs/concepts/` - Architecture, agents, knowledge/memory, permissions, data model, MCP, chat, cost
- `docs/guides/` - Role-themed how-to (backend, frontend, testing, devops, security, extensions, etc.)
- `docs/reference/` - API contracts, schema, scripts, theme system
- `docs/reference/auto/` - **Auto-generated** (MCP tools, skills, knowledge graph, learnings) — do not edit
- `docs/operations/` - Production runbooks (deployment, swarm, AI ops, worker, perf)
- `docs/contributing/` - Dev setup, conventions, GitHub workflow, doc conventions, release process

---

## Automation Scripts

```bash
# Code quality
./scripts/pre-commit-quality-check.sh    # Run all checks
./scripts/fix-hardcoded-colors.sh        # Fix theme violations
./scripts/cleanup-all-console-logs.sh    # Remove console.log
./scripts/convert-relative-imports.sh    # Fix import paths

# Pattern validation
./scripts/pattern-validation.sh          # Full audit
./scripts/quick-pattern-check.sh         # Quick check

# Pre-push validation
./scripts/validate.sh                    # Run all checks (specs + TS + patterns)
./scripts/validate.sh --skip-tests       # Skip RSpec, run TS + patterns only

# Service management (systemd)
sudo scripts/systemd/powernode-installer.sh install           # Install units + configs
sudo scripts/systemd/powernode-installer.sh add-instance backend api2  # Add instance
sudo scripts/systemd/powernode-installer.sh status            # Show all services
```
