# Worker CLAUDE.md

Sidekiq standalone worker for Powernode.

## Critical Rules

- Jobs inherit from `BaseJob`, implement `execute()` method
- API-only communication with server (mTLS for `/api/v1/internal/*`; ActionCable WebSocket still uses JWT)
- `Rails.logger` - no puts/print
- `# frozen_string_literal: true` pragma required
- All AI execution jobs MUST include `AiSuspensionCheckConcern` for kill switch compliance (and call `bail_if_ai_suspended!` first in `execute()`; enforced by `scripts/pattern-validation.sh` for any executor — recall `guidance-kill-switch-compliance`)

## MCP-First Worker Workflow

Query MCP before non-trivial worker changes (full protocol: [conventions/mcp-first-workflow.md](../docs/contributing/conventions/mcp-first-workflow.md)), using domain-specific queries:

### Before Creating/Modifying

| Task | MCP Query |
|------|-----------|
| New job class | `platform.discover_skills` + `platform.search_knowledge` query: "background job patterns" |
| MCP-related jobs | `platform.search_knowledge` query: "MCP job" |
| Billing/payment jobs | `platform.search_knowledge` query: "billing jobs" |
| Job error handling | `platform.query_learnings` query: "Sidekiq error handling" — known failure modes |
| Job scheduling | `platform.query_learnings` query: "job scheduling" — cron patterns, race conditions |
| Autonomy maintenance jobs | `platform.search_knowledge` query: "autonomy jobs" — escalation timeout, goal maintenance, observation pipeline |

### During Work

- **Before new job patterns**: `platform.query_learnings` — check for established patterns and known pitfalls (retry storms, deadlocks, API timeouts)
- **Before job chain dependencies**: `platform.search_knowledge_graph` — understand existing job orchestration flows
- **Before API calls to server**: `platform.search_knowledge` query: "worker API communication" — verify endpoint contracts

### After Work (MANDATORY for non-trivial changes)

| Change type | Contribution |
|-------------|-------------|
| New job pattern | `platform.create_learning` category: `pattern` — document the approach |
| Job failure fix | `platform.create_learning` category: `failure_mode` — root cause + fix |
| Job chain/workflow | `platform.extract_to_knowledge_graph` — job dependencies, trigger conditions |
| Reusable job utility | `platform.create_skill` — codify the approach |

## Context-Aware Documentation (file fallback)

Query MCP first. Use these files when MCP returns no relevant results:

| When working on | MCP Query | File Fallback |
|-----------------|-----------|---------------|
| `app/jobs/*` | `platform.search_knowledge` query: "background jobs" | [guides/backend.md](../docs/guides/backend.md) |
| MCP jobs | `platform.search_knowledge` query: "MCP tools" | [concepts/mcp-and-tools.md](../docs/concepts/mcp-and-tools.md) |

---

## MCP Tool Reference

Full tool catalog with parameters: [reference/auto/mcp-tools.md](../docs/reference/auto/mcp-tools.md). To load a tool's schema in a session, use ToolSearch (e.g. `select:mcp__powernode__platform_search_knowledge`).
