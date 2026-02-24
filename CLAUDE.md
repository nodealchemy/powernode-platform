# CLAUDE.md

Development guidance for **Powernode** subscription platform.

## Project Overview

**Powernode** - Subscription lifecycle management platform:
- **Backend**: Rails 8 API (`./server`) - JWT auth, UUIDv7 primary keys
- **Frontend**: React TypeScript (`./frontend`) - Theme-aware, Tailwind CSS
- **Worker**: Sidekiq standalone (`./worker`) - API-only communication
- **Enterprise**: Git submodule (`./extensions/enterprise`) - proprietary features (billing, BaaS, reseller, AI publisher)
- **Database**: PostgreSQL with native UUID schema
- **Payments**: Stripe, PayPal with PCI compliance (enterprise only)

**Project Status**: See [docs/TODO.md](docs/TODO.md)

### Core Models
```
Account → User (many), Subscription (one)
Subscription → Plan, Payments, Invoices
User → Roles, Permissions, Invitations
```

---

## Specialists

Use `platform.discover_skills` with a task description to find the right specialist capability. Fallback: [MCP_CONFIGURATION.md](docs/platform/MCP_CONFIGURATION.md).

---

## Quick Reference - Critical Rules

### Git Rules
- **NEVER** commit unless explicitly requested
- **NEVER** include Claude attribution in commits
- Branch strategy: `develop` → `feature/*` → `release/*` → `master`
- Tag naming: **NO "v" prefix** - use `0.2.0` not `v0.2.0`
- Release branches: `release/0.2.0` (no "v" prefix)
- **Staged commits**: Group changes into logical commits by concern (models, services, controllers, frontend, tests, config) — never one monolithic commit

### Enterprise Submodule (`./extensions/enterprise`)
- **Separate git repo** at `extensions/enterprise/` — has its own branch, commits, and remote (`git@git.ipnode.net:powernode/powernode-enterprise.git`)
- **Always check both repos**: `git status` in root AND `git -C extensions/enterprise status` — changes in `extensions/enterprise/` are invisible to the parent repo's `git status`
- **Commit order**: Commit inside `extensions/enterprise/` first, then update the submodule pointer in the parent repo
- **Path aliases**: Enterprise frontend uses `@enterprise/` for intra-enterprise imports, `@/` for core shared imports
- **Core mode**: When enterprise submodule is absent, the app runs as single-user self-hosted (all features unlocked, no billing/SaaS)
- **Feature gating**: `Shared::FeatureGateService.enterprise_loaded?` (backend), `__ENTERPRISE__` build flag (frontend), `enterpriseOnly: true` on nav items

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
| Service Restart | After API endpoint changes, restart: `sudo systemctl restart powernode-backend@default` |
| Associations | Always pair `class_name:` with `foreign_key:` — e.g. `belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"` |
| Foreign Keys | Namespaced FK prefixes: `Ai::` → `ai_` (`ai_agent_id`), `Devops::` → `ci_cd_` (`ci_cd_pipeline_id`), `BaaS::` → `baas_` (`baas_customer_id`). Others: use explicit FK or omit if unambiguous |
| JSON Columns | Always use lambda defaults: `attribute :config, :json, default: -> { {} }` — never `default: {}` |
| Controller Size | Controllers MUST stay under 300 lines — extract query logic to services, serialization to concerns |
| Eager Loading | Always use `.includes()` when iterating associations — never bare `.all` followed by `.map`/`.each` accessing relations |
| Webhook Receivers | Inbound webhooks MUST return 200/202 on processing errors — NEVER 500 (causes provider retry storms) |

### Design Principles
| Principle | Rule |
|-----------|------|
| Reuse First | `platform.discover_skills` + `platform.search_knowledge` before proposing anything new — never standalone/greenfield when infrastructure exists |
| Quality Gates | Run `cd frontend && npx tsc --noEmit` after TS changes, verify Ruby syntax after .rb changes |
| Verify Seeds | After seed modifications: `cd server && rails db:seed` — watch for association/validation errors |
| Stop & Ask | **HARD RULE**: After 3 failed attempts at the same fix, STOP immediately and ask the user. Do NOT try a 4th approach, do NOT continue iterating, do NOT try workarounds. Present what you tried and ask for guidance |
| Audit Sessions | When asked to audit/review/analyze code, save findings to `docs/` and do NOT implement changes. Audit = report only, unless the user explicitly says to fix |

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
| MCP Configuration | `platform.discover_skills` | [MCP_CONFIGURATION.md](docs/platform/MCP_CONFIGURATION.md) |
| Permission System | `platform.search_knowledge` query: "permission system" | [PERMISSION_SYSTEM_REFERENCE.md](docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |
| Theme System | `platform.search_knowledge` query: "theme system" | [THEME_SYSTEM_REFERENCE.md](docs/platform/THEME_SYSTEM_REFERENCE.md) |
| API Standards | `platform.search_knowledge` query: "API response standards" | [API_RESPONSE_STANDARDS.md](docs/platform/API_RESPONSE_STANDARDS.md) |
| UUID System | `platform.search_knowledge` query: "UUID system" | [UUID_SYSTEM_IMPLEMENTATION.md](docs/platform/UUID_SYSTEM_IMPLEMENTATION.md) |
| Workflow System | `platform.search_knowledge` query: "workflow system" | [WORKFLOW_SYSTEM_STANDARDS.md](docs/platform/WORKFLOW_SYSTEM_STANDARDS.md) |
| Architecture | `platform.search_knowledge_graph` query: "platform architecture" | [DEVELOPMENT.md](docs/DEVELOPMENT.md) |
| Learnings & Patterns | `platform.query_learnings` | [LEARNINGS.md](docs/platform/knowledge/LEARNINGS.md) |
| Shared Knowledge | `platform.search_knowledge` | [KNOWLEDGE.md](docs/platform/knowledge/KNOWLEDGE.md) |
| Skills Registry | `platform.discover_skills` | [SKILLS.md](docs/platform/knowledge/SKILLS.md) |
| Knowledge Graph | `platform.search_knowledge_graph` | [GRAPH.md](docs/platform/knowledge/GRAPH.md) |

---

## MCP-First Development Workflow

The Powernode MCP server (`platform.*` tools) is the **primary knowledge source**. File scanning is the fallback. **MCP queries are NOT optional** — they are mandatory protocol steps.

### SESSION START Protocol (MANDATORY — every session)

1. Run `platform.knowledge_health` — establish baseline, identify stale/conflicting knowledge
2. Run `platform.learning_metrics` — check active learnings count, recent contributions
3. If stale_count > 0 or conflicts detected, note them for resolution during the session

### BEFORE EVERY CODE CHANGE (MANDATORY)

1. **Search existing knowledge** for the area being modified — not optional, not "when convenient":
   - `platform.query_learnings` — established patterns, anti-patterns, failure modes for this area
   - `platform.search_knowledge` — procedures, code snippets, reference material
   - `platform.search_knowledge_graph` — entity relationships, architecture decisions
   - `platform.discover_skills` — reusable capabilities matching the task
2. **Apply discovered knowledge** to your implementation approach
3. **Fall back to file scanning** only when MCP returns no relevant results
4. **Feed file-scan discoveries back** into MCP (see "After Every Task")

### DURING WORK (Active Reinforcement)

- **When relying on a learning**: Call `platform.reinforce_learning` with its ID immediately — this prevents decay and boosts confidence
- **When using shared knowledge**: Call `platform.rate_knowledge` (4-5 if helpful, 1-2 if outdated) — this feeds quality scores
- **Pattern verification**: Before introducing a new pattern, check `platform.query_learnings`
- **Architecture context**: Before cross-cutting changes, check `platform.search_knowledge_graph`
- **Memory context**: Use `platform.search_memory` to retrieve agent working memory relevant to the current task
- **API context**: Use `platform.get_api_reference` to look up endpoint contracts before writing integration code
- **Conflict resolution**: If you find two conflicting learnings, resolve with `platform.resolve_contradiction` immediately

### AFTER EVERY TASK (MANDATORY — zero exceptions for non-trivial work)

Contribute at least one of:

| When you... | Do this |
|-------------|---------|
| Solved a non-trivial bug | `platform.create_learning` (category: `discovery` or `failure_mode`) |
| Established/confirmed a pattern | `platform.create_learning` (category: `pattern` or `best_practice`) |
| Documented a procedure or guide | `platform.create_knowledge` (content_type: `procedure`) |
| Found entity relationships | `platform.extract_to_knowledge_graph` |
| Implemented a reusable capability | `platform.create_skill` |

**Self-check**: "Did I create learnings for the critical findings in this task?" If no, do it now.

### Skip Contributions For
- Trivial fixes (typos, simple renames, formatting)
- Speculative or unverified analysis
- Knowledge that already exists in MCP (always search first)

### MCP Helper (Claude Code Sessions)

Claude Code can invoke MCP tools via the Powernode MCP endpoint. The workspace SSE daemon (`/.claude/hooks/workspace-sse-daemon.sh`) manages OAuth tokens and sessions. Helper functions are available via `source .claude/hooks/mcp-helper.sh`:

```bash
# Get/cache an OAuth token
mcp_token

# Invoke any platform.* tool
mcp_call "platform.knowledge_health" '{}'
mcp_call "platform.query_learnings" '{"category": "pattern", "query": "memory access"}'
mcp_call "platform.create_learning" '{"title": "...", "content": "...", "category": "discovery"}'
```

---

## MCP Tool Catalog

All `platform.*` tools organized by development task. Full parameter docs: [MCP_TOOL_CATALOG.md](docs/platform/MCP_TOOL_CATALOG.md).

### Discovery & Context (10 tools)
| Tool | Description |
|------|-------------|
| `search_knowledge` | Semantic search across shared knowledge entries |
| `query_learnings` | Query compound learnings by category, status, or text |
| `search_knowledge_graph` | Semantic search over knowledge graph nodes |
| `reason_knowledge_graph` | Multi-hop reasoning across graph relationships |
| `discover_skills` | Find reusable skills matching a task description |
| `get_skill_context` | Get full execution context for a specific skill |
| `search_memory` | Search agent working/shared memory pools |
| `search_documents` | Search RAG document chunks by query |
| `query_knowledge_base` | Query a specific knowledge base with RAG |
| `get_api_reference` | Look up API endpoint contracts and schemas |

### Knowledge Contribution (7 tools)
| Tool | Description |
|------|-------------|
| `create_learning` | Create a compound learning (categories: `pattern`, `best_practice`, `discovery`, `failure_mode`) |
| `create_knowledge` | Create a shared knowledge entry (content_types: `procedure`, `reference`, `guide`) |
| `update_knowledge` | Update an existing shared knowledge entry |
| `promote_knowledge` | Promote knowledge for cross-team visibility |
| `extract_to_knowledge_graph` | Extract entities and relationships to the knowledge graph |
| `create_skill` | Register a reusable skill with execution context |
| `update_skill` | Update an existing skill definition |

### Quality & Reinforcement (9 tools)
| Tool | Description |
|------|-------------|
| `verify_learning` | Verify a learning as accurate (boosts confidence) |
| `dispute_learning` | Dispute an inaccurate learning with reason |
| `resolve_contradiction` | Pick a winner between two conflicting learnings |
| `rate_knowledge` | Rate shared knowledge quality (1-5 scale) |
| `reinforce_learning` | Reinforce a learning that was used successfully |
| `knowledge_health` | Cross-system health report (learnings + knowledge + graph) |
| `learning_metrics` | Compound learning statistics and trends |
| `skill_health` | Skill system health and conflict report |
| `skill_metrics` | Skill usage statistics and effectiveness |

### Agent Management (5 tools)
| Tool | Description |
|------|-------------|
| `create_agent` | Create a new AI agent with provider and model config |
| `list_agents` | List agents (filterable by status, provider) |
| `get_agent` | Get full agent details including trust score |
| `update_agent` | Update agent configuration |
| `execute_agent` | Execute an agent with a prompt and optional tools |

### Team Management (6 tools)
| Tool | Description |
|------|-------------|
| `create_team` | Create an agent team with composition rules |
| `list_teams` | List teams (filterable by status) |
| `get_team` | Get team details including members and roles |
| `update_team` | Update team configuration |
| `add_team_member` | Add an agent to a team with a role |
| `execute_team` | Execute a team task with orchestration |

### Workflow Management (5 tools)
| Tool | Description |
|------|-------------|
| `create_workflow` | Create an AI workflow with nodes and edges |
| `list_workflows` | List workflows (filterable by status, trigger type) |
| `get_workflow` | Get workflow details including node graph |
| `update_workflow` | Update workflow definition |
| `execute_workflow` | Trigger a workflow run with input parameters |

### Knowledge Graph Exploration (7 tools)
| Tool | Description |
|------|-------------|
| `search_knowledge_graph` | Semantic search over graph nodes |
| `reason_knowledge_graph` | Multi-hop reasoning across relationships |
| `get_graph_node` | Get a specific node with its relationships |
| `list_graph_nodes` | List graph nodes (filterable by type, label) |
| `get_graph_neighbors` | Get connected nodes within N hops |
| `graph_statistics` | Graph-wide statistics (node/edge counts, density) |
| `get_subgraph` | Extract a subgraph around a focal node |

### Memory Management (6 tools)
| Tool | Description |
|------|-------------|
| `write_shared_memory` | Write to a shared memory pool (key-value with TTL) |
| `read_shared_memory` | Read from a shared memory pool by key |
| `search_memory` | Semantic search across memory entries |
| `consolidate_memory` | Trigger memory tier consolidation (STM→LTM) |
| `memory_stats` | Memory usage statistics per tier |
| `list_pools` | List available memory pools for an agent/team |

### RAG & Documents (7 tools)
| Tool | Description |
|------|-------------|
| `query_knowledge_base` | Query a knowledge base using RAG retrieval |
| `list_knowledge_bases` | List available knowledge bases |
| `create_knowledge_base` | Create a new knowledge base |
| `add_document` | Add a document to a knowledge base |
| `process_document` | Trigger document chunking and embedding |
| `search_documents` | Search document chunks by semantic query |
| `delete_document` | Remove a document from a knowledge base |

### Content Management (8 tools)
| Tool | Description |
|------|-------------|
| `list_kb_articles` | List knowledge base articles |
| `get_kb_article` | Get article content and metadata |
| `create_kb_article` | Create a new KB article |
| `update_kb_article` | Update an existing KB article |
| `list_pages` | List content pages |
| `get_page` | Get page content and metadata |
| `create_page` | Create a new content page |
| `update_page` | Update an existing content page |

### Skill Administration (4 tools)
| Tool | Description |
|------|-------------|
| `list_skills` | List skills with pagination and filters |
| `get_skill` | Get full skill definition and execution context |
| `delete_skill` | Remove a skill |
| `toggle_skill` | Enable or disable a skill |

### DevOps & CI/CD (5 tools)
| Tool | Description |
|------|-------------|
| `create_gitea_repository` | Create a Gitea repository with default settings |
| `dispatch_to_runner` | Dispatch a job to a Git runner (GitHub/Gitea) |
| `trigger_pipeline` | Trigger a CI/CD pipeline run |
| `list_pipelines` | List pipelines (filterable by status) |
| `get_pipeline_status` | Get pipeline run status and step details |

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

### Manual (Claude Code responsibilities)
| Trigger | Action | Tool |
|---------|--------|------|
| Used a learning successfully | Reinforce it | `platform.reinforce_learning` |
| Used a learning that was wrong | Dispute it | `platform.dispute_learning` |
| Found two conflicting learnings | Resolve the conflict | `platform.resolve_contradiction` |
| Read useful shared knowledge | Rate it 4-5 | `platform.rate_knowledge` |
| Read outdated shared knowledge | Rate it 1-2, create corrected version | `platform.rate_knowledge` + `platform.create_knowledge` |
| Periodic health check | Run diagnostics | `platform.knowledge_health` + `platform.skill_health` |
| Found stale/wrong code patterns | Fix code, then document the fix | Fix → `platform.create_learning` (category: `discovery`) |
| Removed deprecated code | Document removal | `platform.create_learning` (category: `pattern`) |

### Proactive Maintenance (during sessions)
- **Before starting work**: Run `platform.knowledge_health` if last check was >24h ago
- **When encountering bugs**: Always search `platform.query_learnings` for existing fix — if found, `reinforce_learning`; if not, fix and `create_learning`
- **When removing stale code**: Create a learning documenting what was removed and why
- **When fixing documentation**: Update `platform.update_knowledge` to correct the source entry

---

## Tool Evolution

All `platform.*` tools are defined in `server/app/services/ai/tools/platform_api_tool_registry.rb`.
When tools are added/modified, run `cd server && rails mcp:generate_tool_catalog` to regenerate `docs/platform/MCP_TOOL_CATALOG.md`.
When MCP knowledge is updated significantly, run `cd server && rails mcp:sync_docs` to regenerate fallback docs in `docs/platform/knowledge/`.
Knowledge sync runs automatically daily at 5:30 AM UTC via `AiKnowledgeDocSyncJob`.

### Adding a New Tool
1. Create tool class in `server/app/services/ai/tools/`
2. Add action→class mapping to `PlatformApiToolRegistry::TOOLS`
3. Add `action_definitions` with descriptions and parameter schemas
4. Run `rails mcp:generate_tool_catalog` → updates `docs/platform/MCP_TOOL_CATALOG.md`
5. Update relevant CLAUDE.md component file(s) with the new tool
6. Create learning: `platform.create_learning` category: `pattern` documenting the new tool

### Deprecating a Tool
1. Add deprecation notice to `action_definitions` description
2. Create learning: `platform.create_learning` category: `best_practice` documenting the replacement
3. Remove from CLAUDE.md after migration period

---

## File Organization

**NEVER save files to project root**. Use:
- `docs/platform/` - Platform architecture
- `docs/backend/` - Backend documentation
- `docs/frontend/` - Frontend documentation
- `docs/testing/` - Testing documentation
- `docs/services/` - Service documentation
- `docs/infrastructure/` - Infrastructure documentation

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
