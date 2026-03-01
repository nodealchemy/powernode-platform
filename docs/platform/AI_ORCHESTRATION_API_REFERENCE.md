# AI Orchestration API Reference

**Complete API endpoints for 73 controllers across the AI platform**

**Version**: 3.0 | **Last Updated**: February 2026

---

## API Overview

**Base Path**: `/api/v1/ai`
**Authentication**: JWT Bearer token required
**Authorization**: Permission-based (see permissions per endpoint group)
**Total Controllers**: 73 (69 root + 4 in `security/`)

### Response Format

```json
// Success
{ "success": true, "data": { ... }, "message": "Optional message" }

// Error
{ "success": false, "error": "Error message", "errors": ["Detail 1"] }
```

---

## Controller Index

### Core Agent & Team Management (9 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AgentsController` | `/ai/agents` | CRUD, execute, conversations |
| `AgentTeamsController` | `/ai/agent_teams` | Team CRUD, members |
| `TeamsController` | `/ai/teams` | Alternative team endpoints |
| `AgentTeamExecutionsController` | `/ai/agent_team_executions` | Team execution runs |
| `TeamExecutionController` | `/ai/team_execution` | Execution management |
| `TeamRolesChannelsController` | `/ai/team_roles_channels` | Role-based channels |
| `TeamChannelMessagesController` | `/ai/team_channel_messages` | Channel messaging |
| `TeamTemplatesReviewsController` | `/ai/team_templates_reviews` | Template reviews |
| `AgentContainersController` | `/ai/agent_containers` | Container management |

### Workflow & Automation (8 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `WorkflowsController` | `/ai/workflows` | CRUD, execute, runs |
| `WorkflowTemplatesController` | `/ai/workflow_templates` | Template management |
| `WorkflowValidationsController` | `/ai/workflow_validations` | Validation & auto-fix |
| `WorkflowGitTriggersController` | `/ai/workflow_git_triggers` | Git-based triggers |
| `MissionsController` | `/ai/missions` | Mission pipeline (see [MISSIONS_GUIDE](MISSIONS_GUIDE.md)) |
| `RalphLoopsController` | `/ai/ralph_loops` | Agentic loops (see [RALPH_LOOPS_GUIDE](RALPH_LOOPS_GUIDE.md)) |
| `RalphLoopsSchedulingController` | `/ai/ralph_loops_scheduling` | Scheduling config |
| `RalphLoopWebhooksController` | `/ai/ralph_loop_webhooks` | Webhook handling |

### Memory & Context (5 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AgentMemoryController` | `/ai/agent_memory` | Agent memory ops |
| `TieredMemoryController` | `/ai/tiered_memory` | Tiered memory management |
| `MemoryPoolsController` | `/ai/memory_pools` | Pool CRUD |
| `ContextsController` | `/ai/contexts` | Context management |
| `ContextEntriesController` | `/ai/context_entries` | Context entry ops |

### Knowledge & Learning (3 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `KnowledgeGraphController` | `/ai/knowledge_graph` | Graph operations, search |
| `LearningController` | `/ai/learning` | Compound learnings |
| `SkillGraphController` | `/ai/skill_graph` | Skill graph visualization |

### Skills & Code Factory (2 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `SkillsController` | `/ai/skills` | Skill CRUD |
| `CodeFactoryController` | `/ai/code_factory` | Code review pipeline (see [CODE_FACTORY_GUIDE](CODE_FACTORY_GUIDE.md)) |

### Security (4 controllers in `security/`)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AgentIdentityController` | `/ai/security/agent_identity` | Identity verification |
| `AnomalyDetectionsController` | `/ai/security/anomaly_detections` | Anomaly detection |
| `PiiRedactionsController` | `/ai/security/pii_redactions` | PII redaction |
| `QuarantineController` | `/ai/security/quarantine` | Agent quarantine |

### Providers & Model Routing (5 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `ProvidersController` | `/ai/providers` | Provider CRUD |
| `ProviderCredentialsController` | `/ai/provider_credentials` | Credential management |
| `ProviderSyncController` | `/ai/provider_sync` | Model sync |
| `ModelRouterController` | `/ai/model_router` | Routing rules (see [MODEL_ROUTER_GUIDE](MODEL_ROUTER_GUIDE.md)) |
| `ModelRouterAnalyticsController` | `/ai/model_router` | Analytics & optimization |

### Execution & Tracing (3 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `ExecutionTracesController` | `/ai/execution_traces` | Trace logging |
| `ExecutionResourcesController` | `/ai/execution_resources` | Resource tracking |
| `DevopsExecutionsController` | `/ai/devops_executions` | DevOps execution runs |

### Advanced Protocols (11 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `A2aController` | `/ai/a2a` | Agent-to-Agent protocol |
| `A2aTasksController` | `/ai/a2a_tasks` | A2A task management |
| `AcpController` | `/ai/acp` | Agent Control Protocol |
| `AguiController` | `/ai/agui` | Agent GUI protocol |
| `AutonomyController` | `/ai/autonomy` | Autonomy settings |
| `FederationController` | `/ai/federation` | Agent federation |
| `DiscoveryController` | `/ai/discovery` | Agent discovery |
| `RagController` | `/ai/rag` | RAG retrieval |
| `ApiReferenceController` | `/ai/api_reference` | API reference data |
| `McpAppsController` | `/ai/mcp_apps` | MCP app management |
| `SandboxTestingController` | `/ai/sandbox_testing` | Sandbox testing |

### Monitoring & Analytics (8 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AiOpsController` | `/ai/ai_ops` | AI operations |
| `MonitoringController` | `/ai/monitoring` | System health |
| `AnalyticsController` | `/ai/analytics` | Metrics |
| `AnalyticsReportsController` | `/ai/analytics_reports` | Report generation |
| `ValidationStatisticsController` | `/ai/validation_statistics` | Validation stats |
| `DevopsRiskReviewController` | `/ai/devops_risk_review` | Risk assessment |
| `SelfHealingController` | `/ai/self_healing` | Self-healing ops |
| `FinopsController` | `/ai/finops` | Financial operations |

### Sandbox & Testing (4 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `SandboxesController` | `/ai/sandboxes` | Sandbox management |
| `ContainerSandboxesController` | `/ai/container_sandboxes` | Container sandboxes |
| `SandboxScenariosController` | `/ai/sandbox_scenarios` | Scenario management |
| `AgentCardsController` | `/ai/agent_cards` | Agent card management |

### ROI & Cost (2 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `RoiController` | `/ai/roi` | ROI calculations |
| `RoiCalculationsController` | `/ai/roi_calculations` | Detailed ROI data |

### Other (4 controllers)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `PromptTemplatesController` | `/ai/prompt_templates` | Prompt management |
| `WorktreeSessionsController` | `/ai/worktree_sessions` | Worktree sessions |
| `WorkspacesController` | `/ai/workspaces` | Workspace management |
| `CommunityAgentsController` | `/ai/community_agents` | Community registry |

---

## Core Endpoint Details

### Workflow Endpoints

```http
GET    /api/v1/ai/workflows                    # List workflows
GET    /api/v1/ai/workflows/:id                # Get workflow
POST   /api/v1/ai/workflows                    # Create workflow
PATCH  /api/v1/ai/workflows/:id                # Update workflow
DELETE /api/v1/ai/workflows/:id                # Delete workflow
POST   /api/v1/ai/workflows/:id/execute        # Execute workflow
GET    /api/v1/ai/workflows/:id/runs           # List runs
POST   /api/v1/ai/workflows/:id/runs/:run_id/cancel  # Cancel run
```

**Permissions**: `ai.workflows.read`, `ai.workflows.create`, `ai.workflows.update`, `ai.workflows.delete`, `ai.workflows.execute`

### Agent Endpoints

```http
GET    /api/v1/ai/agents                       # List agents
GET    /api/v1/ai/agents/:id                   # Get agent
POST   /api/v1/ai/agents                       # Create agent
PATCH  /api/v1/ai/agents/:id                   # Update agent
DELETE /api/v1/ai/agents/:id                   # Delete agent
POST   /api/v1/ai/agents/:id/execute           # Execute agent
```

**Permissions**: `ai.agents.create`, `ai.agents.execute`

### Provider Endpoints

```http
GET    /api/v1/ai/providers                    # List providers
GET    /api/v1/ai/providers/:id                # Get provider
POST   /api/v1/ai/providers                    # Create provider
PATCH  /api/v1/ai/providers/:id                # Update provider
DELETE /api/v1/ai/providers/:id                # Delete provider
POST   /api/v1/ai/providers/:id/sync           # Sync models
```

**Permission**: `ai.providers.manage`

---

## Permission Requirements Summary

| Feature | Read Permission | Manage Permission |
|---------|----------------|-------------------|
| Agents | `ai.agents.read` | `ai.agents.create` |
| Workflows | `ai.workflows.read` | `ai.workflows.create/update/delete/execute` |
| Missions | `ai.missions.read` | `ai.missions.manage` |
| Ralph Loops | `ai.workflows.read` | `ai.workflows.create/execute` |
| Code Factory | `ai.code_factory.read` | `ai.code_factory.manage` |
| Providers | `ai.providers.manage` | `ai.providers.manage` |
| Model Router | `ai.routing.read` | `ai.routing.manage` / `ai.routing.optimize` |
| Monitoring | `ai.monitoring.read` | N/A |
| Analytics | `ai.analytics.read` | N/A |

---

## WebSocket Channels

| Channel | Stream Format | Events |
|---------|--------------|--------|
| `MissionChannel` | `mission:{type}:{id}` | status_changed, phase_changed, approval_required |
| `CodeFactoryChannel` | varies | preflight_complete, review_clean/dirty, evidence_validated |
| `AiOrchestrationChannel` | `ai_orchestration:{type}:{id}` | batch progress, circuit breaker state |
| `TeamChannel` | varies | team execution updates |

---

**Document Status**: Complete
