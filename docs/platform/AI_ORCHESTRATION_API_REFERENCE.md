# AI Orchestration API Reference

**Complete API endpoints for 88 controllers across the AI platform**

**Version**: 4.0 | **Last Updated**: April 2026

---

## API Overview

**Base Path**: `/api/v1/ai`
**Authentication**: JWT Bearer token required
**Authorization**: Permission-based (see permissions per endpoint group)
**Total Controllers**: 88 (`app/controllers/api/v1/ai/` including the `security/` subdirectory)

### Response Format

```json
// Success
{ "success": true, "data": { ... }, "message": "Optional message" }

// Error
{ "success": false, "error": "Error message", "errors": ["Detail 1"] }
```

---

## Controller Index

### Core Agent & Team Management

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
| `AgentCardsController` | `/ai/agent_cards` | Agent card management |
| `CommunityAgentsController` | `/ai/community_agents` | Community registry |

### Missions & Ralph Loops

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `MissionsController` | `/ai/missions` | Mission pipeline (see [MISSIONS_GUIDE](MISSIONS_GUIDE.md)) |
| `RalphLoopsController` | `/ai/ralph_loops` | Agentic loops (see [RALPH_LOOPS_GUIDE](RALPH_LOOPS_GUIDE.md)) |
| `RalphLoopsSchedulingController` | `/ai/ralph_loops_scheduling` | Scheduling config |
| `RalphLoopWebhooksController` | `/ai/ralph_loops/webhook/:token` | Webhook handling |

### Memory & Context

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AgentMemoryController` | `/ai/agent_memory` | Agent memory ops |
| `TieredMemoryController` | `/ai/tiered_memory` | Tiered memory management |
| `MemoryPoolsController` | `/ai/memory_pools` | Pool CRUD |
| `ContextsController` | `/ai/contexts` | Context management |
| `ContextEntriesController` | `/ai/context_entries` | Context entry ops |

### Knowledge & Learning

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `KnowledgeGraphController` | `/ai/knowledge_graph` | Graph operations, search |
| `LearningController` | `/ai/learning` | Compound learnings (paginated, sort/filter, merged metrics) |
| `SkillGraphController` | `/ai/skill_graph` | Skill graph visualization |
| `SkillsController` | `/ai/skills` | Skill CRUD |

### Code Factory & Codebase Intelligence

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `CodeFactoryController` | `/ai/code_factory` | Code review pipeline (see [CODE_FACTORY_GUIDE](CODE_FACTORY_GUIDE.md)) |
| `CodebaseController` | `/ai/codebase` | AST index, semantic search, blast radius |

### Autonomy, Governance & Safety

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AutonomyController` | `/ai/autonomy` | Autonomy settings, kill switch, pricing |
| `AgentGoalsController` | `/ai/agent_goals` | Self-directed goals |
| `AgentObservationsController` | `/ai/agent_observations` | Observation pipeline events |
| `AgentProposalsController` | `/ai/agent_proposals` | Proposals for human review |
| `AgentEscalationsController` | `/ai/agent_escalations` | Structured escalations |
| `InterventionPoliciesController` | `/ai/intervention_policies` | Policy configuration |

### Security (`/ai/security/`)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `AgentIdentityController` | `/ai/security/agent_identity` | Identity verification |
| `AnomalyDetectionsController` | `/ai/security/anomaly_detections` | Anomaly detection |
| `PiiRedactionsController` | `/ai/security/pii_redactions` | PII redaction |
| `QuarantineController` | `/ai/security/quarantine` | Agent quarantine |

### Providers & Model Routing

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `ProvidersController` | `/ai/providers` | Provider CRUD, rate limiting, health metrics |
| `ProviderCredentialsController` | `/ai/provider_credentials` | Credential management |
| `ProviderSyncController` | `/ai/provider_sync` | Model sync |
| `ModelRouterController` | `/ai/model_router` | Routing rules (see [MODEL_ROUTER_GUIDE](MODEL_ROUTER_GUIDE.md)) |
| `ModelRouterAnalyticsController` | `/ai/model_router` | Analytics & optimization |

### Data Sources (External API Integrations)

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `DataSourcesController` | `/ai/data_sources` | CRUD, `:quota_status`, `:test_connection` (see [DATA_SOURCES](DATA_SOURCES.md)) |
| `DataSourceCredentialsController` | `/ai/data_sources/:id/credentials` | Credential CRUD, `:test`, `:make_default` |

### Execution & Tracing

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `ExecutionTracesController` | `/ai/execution_traces` | Trace logging |
| `ExecutionResourcesController` | `/ai/execution_resources` | Resource tracking |
| `DevopsExecutionsController` | `/ai/devops_executions` | DevOps execution runs |

### Advanced Protocols

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `A2aController` | `/ai/a2a` | Agent-to-Agent protocol |
| `A2aTasksController` | `/ai/a2a_tasks` | A2A task management |
| `AcpController` | `/ai/acp` | Agent Communication Protocol |
| `AguiController` | `/ai/agui` | Agent GUI protocol |
| `FederationController` | `/ai/federation` | Agent federation |
| `DiscoveryController` | `/ai/discovery` | Agent discovery |
| `RagController` | `/ai/rag` | RAG retrieval |
| `ApiReferenceController` | `/ai/api_reference` | API reference data |
| `McpAppsController` | `/ai/mcp_apps` | MCP app management |
| `SandboxTestingController` | `/ai/sandbox_testing` | Sandbox testing |

### Monitoring & Analytics

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
| `RoiController` | `/ai/roi` | ROI calculations |
| `RoiCalculationsController` | `/ai/roi_calculations` | Detailed ROI data |

### Sandbox & Testing

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `SandboxesController` | `/ai/sandboxes` | Sandbox management |
| `ContainerSandboxesController` | `/ai/container_sandboxes` | Container sandboxes |
| `SandboxScenariosController` | `/ai/sandbox_scenarios` | Scenario management |

### Other

| Controller | Path Prefix | Key Endpoints |
|-----------|-------------|---------------|
| `PromptTemplatesController` | `/ai/prompt_templates` | Prompt management |
| `WorktreeSessionsController` | `/ai/worktree_sessions` | Worktree sessions |
| `WorkspacesController` | `/ai/workspaces` | Workspace management |

---

## Non-`/ai` Endpoints Worth Knowing

| Controller | Path | Purpose |
|-----------|------|---------|
| `Api::V1::Admin::DailySummariesController` | `/api/v1/admin/daily_summaries` | Auto-generated daily operational summaries (see [DAILY_SUMMARIES](DAILY_SUMMARIES.md)) |
| `Api::V1::Admin::PagesController` | `/api/v1/admin/pages` | Page CRUD (feeds content-linking / backlinks) |

---

## Core Endpoint Details

### Mission Endpoints

```http
GET    /api/v1/ai/missions                     # List missions
GET    /api/v1/ai/missions/:id                 # Get mission
POST   /api/v1/ai/missions                     # Create mission
PATCH  /api/v1/ai/missions/:id                 # Update mission
DELETE /api/v1/ai/missions/:id                 # Delete mission
POST   /api/v1/ai/missions/:id/start           # Start mission
POST   /api/v1/ai/missions/:id/approve         # Approve gate
POST   /api/v1/ai/missions/:id/reject          # Reject gate
POST   /api/v1/ai/missions/:id/pause           # Pause
POST   /api/v1/ai/missions/:id/resume          # Resume
POST   /api/v1/ai/missions/:id/cancel          # Cancel
POST   /api/v1/ai/missions/:id/retry_phase     # Retry current phase
POST   /api/v1/ai/missions/:id/analyze_repo    # Analyze repository
POST   /api/v1/ai/missions/:id/generate_prd    # Generate PRD
POST   /api/v1/ai/missions/:id/create_branch   # Create feature branch
POST   /api/v1/ai/missions/:id/run_tests       # Trigger tests
GET    /api/v1/ai/missions/:id/test_status     # Check test status
POST   /api/v1/ai/missions/:id/deploy          # Deploy preview
POST   /api/v1/ai/missions/:id/create_pr       # Create pull request
```

**Permissions**: `ai.missions.read`, `ai.missions.manage`

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
GET    /api/v1/internal/ai/providers/:id/health  # Health check (wrapped in data:)
```

**Permission**: `ai.providers.manage`

### Data Source Endpoints

```http
GET    /api/v1/ai/data_sources                 # List
GET    /api/v1/ai/data_sources/:id             # Show
POST   /api/v1/ai/data_sources                 # Create
PATCH  /api/v1/ai/data_sources/:id             # Update
DELETE /api/v1/ai/data_sources/:id             # Delete
GET    /api/v1/ai/data_sources/:id/quota_status        # Quota status
POST   /api/v1/ai/data_sources/:id/test_connection     # Test connection
GET    /api/v1/ai/data_sources/:id/credentials         # List credentials
POST   /api/v1/ai/data_sources/:id/credentials         # Create credential
POST   /api/v1/ai/data_sources/:id/credentials/:cid/test          # Test credential
POST   /api/v1/ai/data_sources/:id/credentials/:cid/make_default  # Make default
```

### Daily Summary Endpoints (Admin)

```http
GET    /api/v1/admin/daily_summaries             # List (paginated)
GET    /api/v1/admin/daily_summaries/latest      # Latest summary
POST   /api/v1/admin/daily_summaries/generate    # Generate (params: date)
```

**Permission**: `admin.access`

---

## Permission Requirements Summary

| Feature | Read Permission | Manage Permission |
|---------|----------------|-------------------|
| Agents | `ai.agents.read` | `ai.agents.create/manage` |
| Teams | `ai.teams.read` | `ai.teams.manage` |
| Missions | `ai.missions.read` | `ai.missions.manage` |
| Ralph Loops | `ai.ralph.read` / `ai.missions.read` | `ai.ralph.manage` |
| Code Factory | `ai.code_factory.read` | `ai.code_factory.manage` |
| Providers | `ai.providers.manage` | `ai.providers.manage` |
| Model Router | `ai.routing.read` | `ai.routing.manage` / `ai.routing.optimize` |
| Monitoring | `ai.monitoring.read` | N/A |
| Analytics | `ai.analytics.read` | N/A |
| Autonomy | `ai.autonomy.read` | `ai.autonomy.manage` |
| Data Sources | `ai.data_sources.read` | `ai.data_sources.manage` |
| Daily Summaries | `admin.access` | `admin.access` |
| Orchestration Streams | `ai_orchestration.read` | N/A |

---

## WebSocket Channels

| Channel | Stream Format | Events |
|---------|--------------|--------|
| `MissionChannel` | `mission:{type}:{id}` | status_changed, phase_changed, approval_required, approval_resolved, error |
| `CodeFactoryChannel` | varies | preflight_complete, review_clean/dirty, evidence_validated |
| `AiOrchestrationChannel` | `ai_orchestration:{type}:{id}` | agent.*, ralph_loop.*, worktree_session.*, worktree.*, circuit_breaker.*, monitoring.alert.triggered, system.health.changed |
| `TeamChannel` | varies | team execution updates |
| `AiAgentExecutionChannel` | per-agent | agent.execution.started/completed/failed |
| `AiConversationChannel` | per-conversation | conversation.message.added |
| `AiStreamingChannel` | per-execution | LLM token stream |

---

**Document Status**: Complete
