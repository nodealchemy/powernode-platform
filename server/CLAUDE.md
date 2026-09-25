# Server CLAUDE.md

Rails 8 API backend for Powernode.

## Critical Rules

- `# frozen_string_literal: true` pragma in every .rb file
- `Rails.logger` only - no puts/print
- Always use `render_success()`, `render_error()`
- Use `current_user.has_permission?('name')` - NEVER `permissions.include?()`
- Controllers: `Api::V1` namespace, inherit ApplicationController
- Migrations: Index in `t.references` declaration - never separate

## MCP-First Backend Workflow

Query MCP before non-trivial backend changes (full protocol: [conventions/mcp-first-workflow.md](../docs/contributing/conventions/mcp-first-workflow.md)).

### Starting a change

Before writing code for a non-trivial change:
1. `platform.query_learnings` — check for existing patterns/gotchas in the area being modified
2. `platform.search_knowledge` — find relevant procedures/references for the subsystem
3. `platform.search_knowledge_graph` — understand entity relationships that may be affected

### Before Creating/Modifying

| Task | MCP Query |
|------|-----------|
| Models or migrations | `platform.search_knowledge_graph` — entity relationships, column conventions, FK patterns |
| Services | `platform.discover_skills` + `platform.code_semantic_search` — find existing services by meaning before creating new ones |
| Controllers or API endpoints | `platform.query_learnings` — API anti-patterns, response format gotchas |
| Refactoring shared code | `platform.code_blast_radius` — trace all files affected before renaming/moving symbols |
| Understanding unfamiliar code | `platform.code_file_skeleton` + `platform.code_context_tree` — structure without reading every line |
| MCP tools or actions | `platform.search_knowledge` query: "MCP tool schema" |
| Permission logic | `platform.search_knowledge` query: "permission system" |
| AI agent features | `platform.search_knowledge_graph` query: "AI orchestration" |
| Billing/payments | `platform.search_knowledge` query: "billing" or "payment integration" |
| Agent/team resources | `platform.list_agents` / `platform.list_teams` — inspect existing resources |
| Memory tier operations | `platform.search_memory` + `platform.memory_stats` — understand current memory state |
| RAG / knowledge bases | `platform.list_knowledge_bases` + `platform.search_documents` — check existing document stores |
| Pipeline / CI/CD | `platform.list_pipelines` + `platform.get_pipeline_status` — verify pipeline state |
| Content (KB articles / pages) | `platform.list_kb_articles` / `platform.list_pages` — check existing content |
| Autonomy models/services | `platform.search_knowledge` query: "agent autonomy" |
| Kill switch / escalation | `platform.search_knowledge` query: "kill switch" |

### During Work

- **Before new associations**: `platform.search_knowledge_graph` for existing entity relationships to avoid duplication
- **Before new service patterns**: `platform.query_learnings` category: `pattern` + `platform.code_semantic_search` — check if the pattern exists or has known issues
- **Before adding gems**: `platform.query_learnings` query: "gem name" — check for known integration gotchas
- **Before refactoring**: `platform.code_blast_radius` — understand full impact before changing shared symbols
- **Before adding files**: `platform.code_context_tree` — understand directory structure and naming conventions

### After Work (MANDATORY for non-trivial changes)

| Change type | Contribution |
|-------------|-------------|
| New model/migration pattern | `platform.extract_to_knowledge_graph` — entities, relationships, FK conventions |
| Service bug fix | `platform.create_learning` category: `discovery` — root cause + fix |
| New API pattern | `platform.create_learning` category: `best_practice` |
| Reusable service | `platform.create_skill` — codify the approach |

## Context-Aware Documentation (file fallback)

Query MCP first. Use these files when MCP returns no relevant results:

| When working on | MCP Query | File Fallback |
|-----------------|-----------|---------------|
| `app/services/mcp/*` | `platform.search_knowledge` query: "MCP tool" | [concepts/mcp-and-tools.md](../docs/concepts/mcp-and-tools.md) |
| `app/models/ai/*` | `platform.search_knowledge_graph` query: "AI model" | [concepts/agents-and-autonomy.md](../docs/concepts/agents-and-autonomy.md) |
| `app/controllers/api/v1/*` | `platform.search_knowledge` query: "API standards" | [reference/api/overview.md](../docs/reference/api/overview.md) |
| `db/migrate/*` | `platform.search_knowledge` query: "UUID migration" | [concepts/data-model.md](../docs/concepts/data-model.md) |
| Permission models/services | `platform.search_knowledge` query: "permission system" | [concepts/permissions.md](../docs/concepts/permissions.md) |

## Backend MCP Tool Reference

Full tool catalog with parameters: [reference/auto/mcp-tools.md](../docs/reference/auto/mcp-tools.md) (regenerable via `rails mcp:generate_tool_catalog`). To load a tool's schema in a session, use ToolSearch (e.g. `select:mcp__powernode__platform_search_knowledge`).

## Test Execution

```bash
bundle exec rspec spec/                          # Run full suite
bundle exec rspec spec/path_spec.rb              # Run single file
bundle exec rspec spec/path_spec.rb:42           # Run single example
```

- Uses `DatabaseCleaner` with `:deletion` strategy (avoids `TRUNCATE` deadlocks)
- Transactional fixtures enabled — each test rolls back automatically
- Frontend tests and TypeScript checks are always safe to run concurrently

## Worker Architecture

- This server does **NOT** run Sidekiq — the worker is a separate service (`worker/`)
- **NEVER** create job classes in `server/app/jobs/`
- The worker communicates with this server via HTTP API only
- Background work is dispatched to the worker, not run in-process

## Key Specialists

Use `platform.discover_skills` with your task description first. File fallback:

- [Backend guide](../docs/guides/backend.md) — Rails architecture, API patterns, data modeling, background jobs
