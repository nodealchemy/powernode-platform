# Ralph Loops Guide

**Recursive Agent Learning & Planning Harness — agentic task execution pipeline**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

Ralph (Recursive Agent Learning & Planning Harness) is the core agentic execution engine. A Ralph Loop takes a PRD (Product Requirements Document), decomposes it into tasks, and executes each task using agents, workflows, pipelines, or human reviewers. Each iteration produces learnings that feed back into the system.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::RalphLoop` | The loop container — holds tasks, iterations, configuration |
| `Ai::RalphTask` | Individual task within a loop — with dependencies and executor routing |
| `Ai::RalphIteration` | Single execution attempt of a task — records output, tokens, learnings |
| `ExecutionService` | Orchestrates loop lifecycle and iteration execution |
| `TaskExecutor` | Routes tasks to the appropriate executor (agent, workflow, pipeline, etc.) |
| `AgenticLoop` | Tool-calling agent loop with git operations and MCP tool support |

---

## Architecture

```
PRD (JSON)
    │
    ▼
┌──────────────────────────┐
│     RalphLoop            │  status: pending → running → completed
│     parse_prd()          │
└────────────┬─────────────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
RalphTask #1      RalphTask #2     ...
(depends: [])     (depends: [#1])
    │
    ▼
┌──────────────────────────┐
│     TaskExecutor         │
│     execute()            │
└────────────┬─────────────┘
             │
    ┌────────┼────────┬──────────┬──────────┐
    ▼        ▼        ▼          ▼          ▼
  Agent   Workflow  Pipeline   A2A Task  Human
    │
    ▼
┌──────────────────────────┐
│    AgenticLoop           │  max 15 tool rounds
│    execute(messages)     │
└────────────┬─────────────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
GitToolExecutor    MCP Tools
(file ops, git)    (platform.*)
```

---

## Models

### Ai::RalphLoop

The container for a set of tasks derived from a PRD.

```ruby
STATUSES = %w[pending running paused completed failed cancelled]
SCHEDULING_MODES = %w[manual scheduled continuous event_triggered]

belongs_to :account
belongs_to :default_agent, class_name: "Ai::Agent", optional: true
belongs_to :container_instance, class_name: "Devops::ContainerInstance", optional: true
belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract", optional: true
belongs_to :mission, class_name: "Ai::Mission", optional: true
has_many :ralph_tasks, dependent: :destroy
has_many :ralph_iterations, dependent: :destroy
```

**Scheduling modes:**
- `manual` — triggered by user or API call
- `scheduled` — runs on a cron schedule
- `continuous` — re-runs automatically on completion
- `event_triggered` — runs in response to external events

**Scopes:** `pending`, `running`, `paused`, `active`, `due_for_execution`, `scheduled`, `event_triggered`

### Ai::RalphTask

Individual task within a loop, with dependency tracking and executor routing.

```ruby
STATUSES = %w[pending in_progress passed failed blocked skipped]
EXECUTION_TYPES = %w[agent workflow pipeline a2a_task container human community]
CAPABILITY_STRATEGIES = %w[all any weighted]

belongs_to :ralph_loop
belongs_to :executor, polymorphic: true, optional: true
has_many :ralph_iterations, dependent: :nullify
```

**Key methods:**
- `dependencies_satisfied?` — checks if all dependent tasks have passed
- `blocking_dependencies` — returns list of unresolved dependency task keys
- `find_matching_executor` — routes by `execution_type` to find the right agent/workflow/pipeline
- `record_execution_attempt!(executor)` — increments attempt counter
- `has_fallback?` — checks if fallback configuration exists

**State machine:** `start!` → `pass!(iteration_number:)` | `fail!(error_message:)` | `block!(reason:)` | `skip!(reason:)` | `reset!()`

### Ai::RalphIteration

Records a single execution attempt of a task.

```ruby
STATUSES = %w[pending running completed failed skipped]

belongs_to :ralph_loop
belongs_to :ralph_task, optional: true
```

**Key methods:**
- `start!` — sets status to running
- `complete!(output:, checks_passed:, commit_sha:, learning:)` — records success with optional learning
- `fail!(error_message:, error_code:, error_details:)` — records failure
- `record_token_usage(input:, output:, cost:)` — tracks LLM token usage

---

## Services

### ExecutionService

Orchestrates the lifecycle of a Ralph Loop — starting, iterating, and completing.

```ruby
service = Ai::Ralph::ExecutionService.new(ralph_loop: loop, account: account, user: user)
```

**Included modules:**
- `LoopLifecycle` — start, pause, resume, cancel, complete
- `IterationExecution` — execute individual iterations, handle success/failure
- `PrdAndBroadcasting` — PRD parsing, WebSocket broadcasts

**Code Factory integration:**
- `code_factory_preflight_check(changed_files:)` — runs preflight gate via `PreflightGateService`
- `code_factory_evidence_satisfied?` — checks if review state evidence requirements are met

### TaskExecutor

Routes tasks to the appropriate executor based on `execution_type`.

```ruby
executor = Ai::Ralph::TaskExecutor.new(task: task, ralph_loop: loop, account: account)
result = executor.execute
```

**Execution routes:**

| Type | Executor | Description |
|------|----------|-------------|
| `agent` | `AgenticLoop` | Tool-calling agent with git + MCP tools |
| `workflow` | `WorkflowRun` | Creates and enqueues workflow execution |
| `pipeline` | `PipelineExecution` | Triggers CI/CD pipeline |
| `a2a_task` | `A2A::Service` | Agent-to-agent task submission |
| `container` | `ContainerOrchestrationService` | Container-based execution |
| `human` | Notification | Creates notification for human review |
| `community` | A2A external | External agent federation |

**Executor resolution priority:**
1. Explicit executor on the task
2. Loop's default agent
3. Capability-based matching (`find_matching_executor`)

**Prompt construction:** The executor builds prompts including:
- Task description and acceptance criteria
- PRD overview (title, description)
- Repository context (structure, recent commits)
- Git instructions (worktree, branch, commit conventions)

### AgenticLoop

The core tool-calling loop that executes agent tasks with iterative tool use.

```ruby
loop = Ai::Ralph::AgenticLoop.new(
  client: provider_client,
  provider_type: "anthropic",
  account: account,
  git_tool_executor: git_executor,
  mcp_tools: mcp_tool_definitions
)

result = loop.execute(messages, options)
# => { success: true, content: "...", file_changes: [...], last_commit_sha: "...", tool_calls_log: [...] }
```

**Behavior:**
- Calls `client.send_message` iteratively (max 15 rounds)
- Extracts tool calls from response
- Routes git tools to `GitToolExecutor`, MCP tools to `Mcp::SyncExecutionService`
- Accumulates text content and tool results
- Returns aggregated result with file changes

### GitToolExecutor

Handles repository operations within a worktree.

**Available tools (3 categories):**

| Category | Tools |
|----------|-------|
| `file_ops` | `read_file`, `write_file`, `delete_file`, `list_files` |
| `code_intel` | `search_code`, `get_file_info` |
| `repo_context` | `get_repo_info`, `list_branches`, `get_branch_diff`, `list_commits` |

**Provider-aware formatting:**
- Anthropic: `{ name:, description:, input_schema: }`
- OpenAI/Ollama: `{ type: "function", function: { name:, description:, parameters: } }`

**File operations commit automatically** — `write_file` and `delete_file` create git commits with the provided message.

---

## API Endpoints

**Controller**: `Api::V1::Ai::RalphLoopsController`

### Loop CRUD

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `GET` | `/api/v1/ai/ralph_loops` | `ai.workflows.read` | List loops (filter by status/agent) |
| `POST` | `/api/v1/ai/ralph_loops` | `ai.workflows.create` | Create loop (optionally parse PRD) |
| `GET` | `/api/v1/ai/ralph_loops/:id` | `ai.workflows.read` | Show loop details |
| `PATCH` | `/api/v1/ai/ralph_loops/:id` | `ai.workflows.update` | Update loop |
| `DELETE` | `/api/v1/ai/ralph_loops/:id` | `ai.workflows.delete` | Delete (terminal/pending only) |

### Execution Control

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/ralph_loops/:id/start` | `ai.workflows.execute` | Start loop |
| `POST` | `/api/v1/ai/ralph_loops/:id/pause` | `ai.workflows.execute` | Pause loop |
| `POST` | `/api/v1/ai/ralph_loops/:id/resume` | `ai.workflows.execute` | Resume loop |
| `POST` | `/api/v1/ai/ralph_loops/:id/cancel` | `ai.workflows.execute` | Cancel loop |
| `POST` | `/api/v1/ai/ralph_loops/:id/reset` | `ai.workflows.execute` | Reset loop |

### Tasks & Iterations

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `GET` | `/api/v1/ai/ralph_loops/:id/tasks` | `ai.workflows.read` | List tasks (filter by status) |
| `GET` | `/api/v1/ai/ralph_loops/:id/tasks/:key` | `ai.workflows.read` | Get task by key or ID |
| `PATCH` | `/api/v1/ai/ralph_loops/:id/tasks/:key` | `ai.workflows.update` | Update task |
| `GET` | `/api/v1/ai/ralph_loops/:id/iterations` | `ai.workflows.read` | List iterations |
| `GET` | `/api/v1/ai/ralph_loops/:id/iterations/:num` | `ai.workflows.read` | Get iteration |

### Monitoring

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `GET` | `/api/v1/ai/ralph_loops/:id/progress` | `ai.workflows.read` | Progress + recent commits |
| `GET` | `/api/v1/ai/ralph_loops/:id/learnings` | `ai.workflows.read` | Extracted learnings |
| `GET` | `/api/v1/ai/ralph_loops/:id/statistics` | `ai.workflows.read` | Aggregate stats |

---

## PRD Format

Ralph Loops are typically created from a PRD JSON structure:

```json
{
  "title": "Add User Profile Page",
  "description": "Create a user profile page with avatar upload and settings",
  "tasks": [
    {
      "key": "task_1",
      "name": "Create User Profile Model",
      "description": "Add profile fields to User model with migration",
      "priority": 1,
      "acceptance_criteria": "Migration runs, model validates presence of display_name",
      "dependencies": [],
      "execution_type": "agent"
    },
    {
      "key": "task_2",
      "name": "Create Profile API Endpoint",
      "description": "Add GET/PATCH /api/v1/profile endpoint",
      "priority": 2,
      "acceptance_criteria": "Returns profile data, updates display_name and bio",
      "dependencies": ["task_1"],
      "execution_type": "agent"
    }
  ]
}
```

---

## Key Files

| File | Path |
|------|------|
| Models | `server/app/models/ai/ralph_loop.rb`, `ralph_task.rb`, `ralph_iteration.rb` |
| Execution | `server/app/services/ai/ralph/execution_service.rb` |
| Task Routing | `server/app/services/ai/ralph/task_executor.rb` |
| Agentic Loop | `server/app/services/ai/ralph/agentic_loop.rb` |
| Git Tools | `server/app/services/ai/ralph/git_tool_executor.rb`, `git_tool_definitions.rb` |
| Controller | `server/app/controllers/api/v1/ai/ralph_loops_controller.rb` |
