# Worker CLAUDE.md

Sidekiq standalone worker for Powernode.

## Critical Rules

- Jobs inherit from `BaseJob`, implement `execute()` method
- API-only communication with server
- `Rails.logger` - no puts/print
- `# frozen_string_literal: true` pragma required

## MCP-First Worker Workflow

**Always query MCP before writing worker code.** Use domain-specific queries:

### Before Creating/Modifying

| Task | MCP Query |
|------|-----------|
| New job class | `platform.discover_skills` + `platform.search_knowledge` query: "background job patterns" |
| AI workflow jobs | `platform.search_knowledge_graph` query: "AI workflow" — entity relationships, job chains |
| MCP-related jobs | `platform.search_knowledge` query: "MCP job" |
| Billing/payment jobs | `platform.search_knowledge` query: "billing jobs" |
| Job error handling | `platform.query_learnings` query: "Sidekiq error handling" — known failure modes |
| Job scheduling | `platform.query_learnings` query: "job scheduling" — cron patterns, race conditions |

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
| `app/jobs/*` | `platform.search_knowledge` query: "background jobs" | [BACKGROUND_JOB_ENGINEER_SPECIALIST.md](../docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) |
| AI workflow jobs | `platform.search_knowledge_graph` query: "AI workflow jobs" | [WORKFLOW_SYSTEM_STANDARDS.md](../docs/platform/WORKFLOW_SYSTEM_STANDARDS.md) |
| MCP jobs | `platform.search_knowledge` query: "MCP tools" | [MCP_CONFIGURATION.md](../docs/platform/MCP_CONFIGURATION.md) |
| Billing jobs | `platform.search_knowledge` query: "billing engine" | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) |

---

## Worker-Relevant MCP Tools

Scoped to tools workers actually need. Full catalog: [MCP_TOOL_CATALOG.md](../docs/platform/MCP_TOOL_CATALOG.md).

### Job Context & Discovery
| Tool | Use Case |
|------|----------|
| `search_knowledge` | Find procedures and patterns relevant to the job being built |
| `query_learnings` | Check for known failure modes before implementing retry logic |
| `discover_skills` | Find reusable capabilities matching the job's task |
| `get_api_reference` | Look up server API endpoint contracts before making HTTP calls |
| `search_knowledge_graph` | Understand entity relationships for job orchestration flows |

### Execution & Dispatch
| Tool | Use Case |
|------|----------|
| `execute_agent` | Execute an AI agent with a prompt (used by AI workflow jobs) |
| `get_agent` | Get agent config before execution (provider, model, trust score) |
| `execute_team` | Execute a team task with multi-agent orchestration |
| `execute_workflow` | Trigger a workflow run with input parameters |
| `get_workflow` | Get workflow definition including node graph |
| `list_workflows` | List workflows to find scheduled/triggered ones |
| `dispatch_to_runner` | Dispatch a job to a Git runner (GitHub/Gitea) |
| `trigger_pipeline` | Trigger a CI/CD pipeline run |
| `list_pipelines` | List pipelines for status monitoring |
| `get_pipeline_status` | Get pipeline run status and step details |

### Memory & RAG Processing
| Tool | Use Case |
|------|----------|
| `consolidate_memory` | Trigger memory tier promotion (STM→LTM) — used by maintenance jobs |
| `memory_stats` | Memory usage per tier — used by health check jobs |
| `write_shared_memory` | Write results to shared memory pools |
| `read_shared_memory` | Read from shared memory pools by key |
| `search_memory` | Semantic search across memory entries |
| `list_pools` | List available memory pools for cleanup jobs |
| `process_document` | Trigger document chunking and embedding |
| `search_documents` | Search RAG document chunks |

### Knowledge Contribution
| Tool | Use Case |
|------|----------|
| `create_learning` | Document job failure modes and patterns |
| `create_skill` | Register reusable job utilities as skills |
| `extract_to_knowledge_graph` | Record job chain dependencies and orchestration flows |

**Excluded**: Content management (KB articles, pages), agent/team/workflow admin CRUD, skill admin, knowledge curation — these are server/frontend concerns, not worker operations.
