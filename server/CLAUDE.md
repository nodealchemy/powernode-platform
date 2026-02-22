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

**Always query MCP before writing backend code.** Use domain-specific queries:

### Before Creating/Modifying

| Task | MCP Query |
|------|-----------|
| Models or migrations | `platform.search_knowledge_graph` — entity relationships, column conventions, FK patterns |
| Services | `platform.discover_skills` + `platform.search_knowledge` — existing service patterns, reusable capabilities |
| Controllers or API endpoints | `platform.query_learnings` — API anti-patterns, response format gotchas |
| MCP tools or actions | `platform.search_knowledge` query: "MCP tool schema" |
| Permission logic | `platform.search_knowledge` query: "permission system" |
| AI agent features | `platform.search_knowledge_graph` query: "AI orchestration" |
| Billing/payments | `platform.search_knowledge` query: "billing" or "payment integration" |
| Agent/team/workflow resources | `platform.list_agents` / `platform.list_teams` / `platform.list_workflows` — inspect existing resources |
| Memory tier operations | `platform.search_memory` + `platform.memory_stats` — understand current memory state |
| RAG / knowledge bases | `platform.list_knowledge_bases` + `platform.search_documents` — check existing document stores |
| Pipeline / CI/CD | `platform.list_pipelines` + `platform.get_pipeline_status` — verify pipeline state |
| Content (KB articles / pages) | `platform.list_kb_articles` / `platform.list_pages` — check existing content |

### During Work

- **Before new associations**: `platform.search_knowledge_graph` for existing entity relationships to avoid duplication
- **Before new service patterns**: `platform.query_learnings` category: `pattern` — check if the pattern is established or has known issues
- **Before adding gems**: `platform.query_learnings` query: "gem name" — check for known integration gotchas

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
| `app/services/mcp/*` | `platform.search_knowledge` query: "MCP tool" | [MCP_CONFIGURATION.md](../docs/platform/MCP_CONFIGURATION.md) |
| `app/models/ai/*` | `platform.search_knowledge_graph` query: "AI model" | [AI_ORCHESTRATION_GUIDE.md](../docs/platform/AI_ORCHESTRATION_GUIDE.md) |
| `app/controllers/api/v1/*` | `platform.search_knowledge` query: "API standards" | [API_RESPONSE_STANDARDS.md](../docs/platform/API_RESPONSE_STANDARDS.md) |
| `app/services/billing/*` | `platform.search_knowledge` query: "billing engine" | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) |
| `app/services/payments/*` | `platform.search_knowledge` query: "payment integration" | [PAYMENT_INTEGRATION_SPECIALIST.md](../docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md) |
| `db/migrate/*` | `platform.search_knowledge` query: "UUID migration" | [UUID_SYSTEM_IMPLEMENTATION.md](../docs/platform/UUID_SYSTEM_IMPLEMENTATION.md) |
| Permission models/services | `platform.search_knowledge` query: "permission system" | [PERMISSION_SYSTEM_REFERENCE.md](../docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |

## Backend MCP Tool Reference

All 79 actions grouped by subsystem. Full parameter docs: [MCP_TOOL_CATALOG.md](../docs/platform/MCP_TOOL_CATALOG.md).

| Subsystem | Tools (all `platform.*`) |
|-----------|--------------------------|
| Agents | `create_agent`, `list_agents`, `get_agent`, `update_agent`, `execute_agent` |
| Teams | `create_team`, `list_teams`, `get_team`, `update_team`, `add_team_member`, `execute_team` |
| Workflows | `create_workflow`, `list_workflows`, `get_workflow`, `update_workflow`, `execute_workflow` |
| Pipelines | `trigger_pipeline`, `list_pipelines`, `get_pipeline_status` |
| Memory | `write_shared_memory`, `read_shared_memory`, `search_memory`, `consolidate_memory`, `memory_stats`, `list_pools` |
| RAG | `query_knowledge_base`, `list_knowledge_bases`, `create_knowledge_base`, `add_document`, `process_document`, `search_documents`, `delete_document` |
| KB Articles | `list_kb_articles`, `get_kb_article`, `create_kb_article`, `update_kb_article` |
| Pages | `list_pages`, `get_page`, `create_page`, `update_page` |
| Knowledge | `search_knowledge`, `create_knowledge`, `update_knowledge`, `promote_knowledge` |
| Learnings | `query_learnings`, `create_learning`, `reinforce_learning`, `learning_metrics` |
| Quality | `verify_learning`, `dispute_learning`, `resolve_contradiction`, `rate_knowledge`, `knowledge_health` |
| Skills | `list_skills`, `get_skill`, `discover_skills`, `get_skill_context`, `skill_health`, `skill_metrics`, `create_skill`, `update_skill`, `delete_skill`, `toggle_skill` |
| Graph | `search_knowledge_graph`, `reason_knowledge_graph`, `get_graph_node`, `list_graph_nodes`, `get_graph_neighbors`, `graph_statistics`, `get_subgraph`, `extract_to_knowledge_graph` |
| DevOps | `create_gitea_repository`, `dispatch_to_runner`, `get_api_reference` |

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

Use `platform.discover_skills` with your task description first. File fallbacks:

- [Rails Architect](../docs/backend/RAILS_ARCHITECT_SPECIALIST.md)
- [API Developer](../docs/backend/API_DEVELOPER_SPECIALIST.md)
- [Data Modeler](../docs/backend/DATA_MODELER_SPECIALIST.md)
- [Background Job Engineer](../docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)
