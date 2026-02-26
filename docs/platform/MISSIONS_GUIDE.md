# Missions Guide

**End-to-end development mission pipeline with approval gates and real-time updates**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

A Mission is a high-level development lifecycle that takes a feature request from analysis through deployment and merge. It orchestrates repo analysis, PRD generation, Ralph Loop execution, code review, testing, deployment preview, and merge — with human approval gates at key checkpoints.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::Mission` | Core model — tracks status, phase, approvals, and linked resources |
| `Ai::MissionApproval` | Records human approval/rejection decisions at gates |
| `OrchestratorService` | Phase transitions, job dispatching, approval handling |
| `PrdGenerationService` | AI-powered PRD generation from feature descriptions |
| `RepoAnalysisService` | Repository structure analysis and feature suggestion |
| `AppLaunchService` | Preview deployment allocation and cleanup |
| `PrManagementService` | Branch creation and PR management |
| `TestRunnerService` | Test triggering and status checking |
| `MissionChannel` | WebSocket channel for real-time mission updates |

---

## Mission Lifecycle

```
┌─────────┐     ┌───────────┐     ┌────────────────────────┐     ┌──────────┐
│  draft   │────▶│ analyzing │────▶│ awaiting_feature_      │────▶│ planning │
│          │     │           │     │ approval               │     │          │
└─────────┘     └───────────┘     └────────────────────────┘     └────┬─────┘
                                         ▲ reject                     │
                                         │                            ▼
                                  ┌──────┴─────────────────┐   ┌──────────┐
                                  │ awaiting_prd_approval   │◀──│          │
                                  └────────────┬───────────┘   └──────────┘
                                               │ approve
                                               ▼
                                         ┌───────────┐
                                         │ executing  │  ← Ralph Loop runs tasks
                                         └─────┬─────┘
                                               │
                                               ▼
                                         ┌───────────┐
                                         │ testing    │
                                         └─────┬─────┘
                                               │
                                               ▼
                                         ┌───────────┐
                                         │ reviewing  │
                                         └─────┬─────┘
                                               │
                                               ▼
                                  ┌────────────────────────┐
                                  │ awaiting_code_approval  │
                                  └────────────┬───────────┘
                                               │ approve
                                               ▼
                                         ┌───────────┐
                                         │ deploying  │
                                         └─────┬─────┘
                                               │
                                               ▼
                                         ┌───────────┐
                                         │ previewing │  ← User reviews deployed app
                                         └─────┬─────┘
                                               │ approve
                                               ▼
                                         ┌───────────┐
                                         │ merging    │
                                         └─────┬─────┘
                                               │
                                               ▼
                                         ┌───────────┐
                                         │ completed  │
                                         └───────────┘
```

### Mission Types

| Type | Phases | Description |
|------|--------|-------------|
| `development` | Full 12-phase pipeline | Feature implementation with all gates |
| `research` | Subset of phases | Investigation and analysis tasks |
| `operations` | Subset of phases | Infrastructure and operational tasks |

### Approval Gates

| Gate | Phase | Decision |
|------|-------|----------|
| `feature_selection` | `awaiting_feature_approval` | Approve which feature to build |
| `prd_review` | `awaiting_prd_approval` | Approve the generated PRD |
| `code_review` | `awaiting_code_approval` | Approve the code changes |
| `merge_approval` | `previewing` | Approve merge after preview |

---

## Models

### Ai::Mission

```ruby
MISSION_TYPES = %w[development research operations]
STATUSES = %w[draft active paused completed failed cancelled]
DEVELOPMENT_PHASES = %w[
  analyzing awaiting_feature_approval planning awaiting_prd_approval
  executing testing reviewing awaiting_code_approval
  deploying previewing merging completed
]

belongs_to :account
belongs_to :created_by, class_name: "User"
belongs_to :repository, class_name: "Devops::GitRepository"
belongs_to :team, class_name: "Ai::AgentTeam", optional: true
belongs_to :conversation, class_name: "Ai::Conversation", optional: true
belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract", optional: true
belongs_to :ralph_loop, class_name: "Ai::RalphLoop", optional: true
belongs_to :review_state, class_name: "Ai::CodeFactory::ReviewState", optional: true
has_many :approvals, class_name: "Ai::MissionApproval", dependent: :destroy
```

**Key methods:**
- `awaiting_approval?` — true when current phase is an approval gate
- `current_gate` — returns the gate name for the current phase
- `phase_progress` — returns completion percentage based on phase index
- `mission_summary` / `mission_details` — serialization helpers

**Callbacks:** Broadcasts status/phase changes via `MissionChannel`, posts milestones to linked conversation.

### Ai::MissionApproval

```ruby
GATES = %w[feature_selection prd_review code_review merge_approval]
DECISIONS = %w[approved rejected]

belongs_to :mission
belongs_to :account
belongs_to :user
```

---

## Services

### OrchestratorService

Central coordinator for mission lifecycle transitions.

```ruby
service = Ai::Missions::OrchestratorService.new(mission: mission, account: account)

# Start a mission (creates conversation, dispatches first phase job)
service.start!

# Advance after phase completion
service.advance!(result: { ... }, expected_phase: "analyzing")

# Handle approval decisions
service.handle_approval!(
  gate: "prd_review",
  user: current_user,
  decision: "approved",
  prd_modifications: { ... }
)

# Lifecycle controls
service.pause!
service.resume!
service.cancel!(reason: "Requirements changed")
service.retry_phase!
```

**Phase-to-job mapping:**

| Phase | Worker Job |
|-------|-----------|
| `analyzing` | `AiMissionAnalyzeJob` |
| `planning` | `AiMissionPlanJob` |
| `executing` | `AiMissionExecuteJob` |
| `testing` | `AiMissionTestJob` |
| `reviewing` | `AiMissionReviewJob` |
| `deploying` | `AiMissionDeployJob` |
| `merging` | `AiMissionMergeJob` |

Jobs are dispatched via `WorkerJobService` to the `ai_execution` queue.

**Rejection handling:** When an approval is rejected, the orchestrator routes back to the appropriate earlier phase and redispatches the job.

### PrdGenerationService

Generates a PRD from a mission's objective or selected feature using AI.

```ruby
service = Ai::Missions::PrdGenerationService.new(mission: mission, account: account)
service.generate!
```

**Process:**
1. Validates mission has objective or selected feature
2. Resolves AI provider and credential
3. Builds context (tech stack, repo structure, recent commits, open issues)
4. Calls AI provider (4096 max tokens, temperature 0.4)
5. Parses PRD from response (handles JSON in code fences, raw JSON, or single-task fallback)
6. Creates `RalphLoop` with tasks via `ExecutionService.parse_prd`

### Other Services

| Service | Purpose |
|---------|---------|
| `RepoAnalysisService` | Analyzes repository structure, suggests features based on codebase |
| `AppLaunchService` | Allocates ports, launches preview deployments, records deployment results, cleanup |
| `PrManagementService` | Creates feature branches (`feature/<mission-name>`) and pull requests |
| `TestRunnerService` | Triggers test execution and checks status |

---

## WebSocket Channel

**Channel**: `MissionChannel`

### Subscription

```javascript
// Subscribe to a specific mission
cable.subscriptions.create({
  channel: "MissionChannel",
  type: "mission",
  id: missionId
});

// Subscribe to all account missions
cable.subscriptions.create({
  channel: "MissionChannel",
  type: "account",
  id: accountId
});
```

### Events

| Event | Payload | Description |
|-------|---------|-------------|
| `status_changed` | `{ mission_id, status, current_phase }` | Mission status transition |
| `phase_changed` | `{ mission_id, current_phase, previous_phase, progress }` | Phase progression |
| `approval_required` | `{ mission_id, gate, phase }` | Human approval needed |
| `approval_resolved` | `{ mission_id, gate, decision }` | Approval decision made |
| `error` | `{ mission_id, error, phase }` | Phase execution error |

### Broadcasting

```ruby
# Broadcast to mission subscribers
MissionChannel.broadcast_mission_event(mission.id, "phase_changed", {
  mission_id: mission.id,
  current_phase: "executing",
  progress: 45
})

# Broadcast to account subscribers
MissionChannel.broadcast_to_account(account.id, event: "status_changed", payload: { ... })
```

---

## API Endpoints

**Controller**: `Api::V1::Ai::MissionsController`

### Mission CRUD

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `GET` | `/api/v1/ai/missions` | `ai.missions.read` | List missions (filter by status, type) |
| `POST` | `/api/v1/ai/missions` | `ai.missions.manage` | Create mission |
| `GET` | `/api/v1/ai/missions/:id` | `ai.missions.read` | Show mission |
| `PATCH` | `/api/v1/ai/missions/:id` | `ai.missions.manage` | Update mission |
| `DELETE` | `/api/v1/ai/missions/:id` | `ai.missions.manage` | Delete mission |

### Lifecycle

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/missions/:id/start` | `ai.missions.manage` | Start mission |
| `POST` | `/api/v1/ai/missions/:id/approve` | `ai.missions.manage` | Approve gate |
| `POST` | `/api/v1/ai/missions/:id/reject` | `ai.missions.manage` | Reject gate |
| `POST` | `/api/v1/ai/missions/:id/pause` | `ai.missions.manage` | Pause mission |
| `POST` | `/api/v1/ai/missions/:id/resume` | `ai.missions.manage` | Resume mission |
| `POST` | `/api/v1/ai/missions/:id/cancel` | `ai.missions.manage` | Cancel mission |
| `POST` | `/api/v1/ai/missions/:id/retry_phase` | `ai.missions.manage` | Retry current phase |

### Pipeline Operations

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/missions/:id/analyze_repo` | `ai.missions.manage` | Analyze repository |
| `POST` | `/api/v1/ai/missions/:id/generate_prd` | `ai.missions.manage` | Generate PRD |
| `POST` | `/api/v1/ai/missions/:id/create_branch` | `ai.missions.manage` | Create feature branch |
| `POST` | `/api/v1/ai/missions/:id/run_tests` | `ai.missions.manage` | Trigger tests |
| `GET` | `/api/v1/ai/missions/:id/test_status` | `ai.missions.read` | Check test status |
| `POST` | `/api/v1/ai/missions/:id/deploy` | `ai.missions.manage` | Deploy preview |
| `POST` | `/api/v1/ai/missions/:id/create_pr` | `ai.missions.manage` | Create pull request |
| `POST` | `/api/v1/ai/missions/:id/cleanup_deployment` | `ai.missions.manage` | Cleanup deployment |
| `POST` | `/api/v1/ai/missions/:id/deploy_callback` | `ai.missions.manage` | Deployment result callback |
| `POST` | `/api/v1/ai/missions/:id/advance` | `ai.missions.manage` | Manual phase advance |

---

## Key Files

| File | Path |
|------|------|
| Mission Model | `server/app/models/ai/mission.rb` |
| Approval Model | `server/app/models/ai/mission_approval.rb` |
| Orchestrator | `server/app/services/ai/missions/orchestrator_service.rb` |
| PRD Generation | `server/app/services/ai/missions/prd_generation_service.rb` |
| Repo Analysis | `server/app/services/ai/missions/repo_analysis_service.rb` |
| App Launch | `server/app/services/ai/missions/app_launch_service.rb` |
| PR Management | `server/app/services/ai/missions/pr_management_service.rb` |
| Test Runner | `server/app/services/ai/missions/test_runner_service.rb` |
| Controller | `server/app/controllers/api/v1/ai/missions_controller.rb` |
| WebSocket | `server/app/channels/mission_channel.rb` |
