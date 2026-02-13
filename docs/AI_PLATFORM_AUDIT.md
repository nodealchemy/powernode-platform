# AI Platform Audit Report

**Date**: 2026-02-13
**Scope**: Full-stack AI functionality across backend, frontend, and worker layers

---

## 1. Executive Summary

| Layer | Metric | Count |
|-------|--------|-------|
| Backend | Models | 109 |
| Backend | Services | 187 (176 core + 11 enterprise) |
| Backend | Controllers | 53 (49 main + 4 security) |
| Backend | AI tables | 134 core + 24 enterprise |
| Backend | Route lines | 1,293 |
| Frontend | Feature modules | 37 |
| Frontend | API services | 31 |
| Frontend | Pages | 46 (35 routed, 11 content tabs) |
| Frontend | Components | 260 TSX + 99 TS files |
| Worker | Jobs | 48 |
| Worker | Scheduled jobs | 16 |
| Worker | Queues (AI-specific) | 10 |

**Overall health**: Production-scale, well-architected platform with mature cross-layer integration. Primary concerns are controller size violations (9 controllers exceed 300-line limit) and service spec coverage at 48% (90/187).

---

## 2. Critical Issues (P0)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 1 | **9 controllers exceed 300-line limit** — `providers_controller` (1,029), `teams_controller` (833), `marketplace_controller` (660), `analytics_controller` (529), `ralph_loops_controller` (521), `devops_controller` (495), `sandboxes_controller` (488), `workflows_controller` (483), `model_router_controller` (466) | `server/app/controllers/api/v1/ai/` | Violates project rules, maintenance risk |
| 2 | **97 services have no specs** — 0% coverage in workflow validators (10), devops (5), learning/eval (8/9), tools/MCP (15/17); low coverage in providers (30%), specialized (37%) | `server/spec/services/ai/` | No test coverage for significant infrastructure |
| 3 | **2 pages were orphaned from routing** (now wired) — DevOpsTemplatesPage (`/ai/devops/templates`), WorkflowAnalyticsPage (`/ai/analytics/workflows`). The remaining 11 pages are **not orphaned**: 9 are Content components used as tabs in wrapper pages (ExecutionPage, KnowledgePage, InfrastructurePage, AiBillingPage) and 2 are standalone alternatives (AgentCardsPage, AgentMarketplacePage) providing PageContainer wrappers around feature modules already routed via AIAgentsPage | `frontend/src/pages/app/ai/` | Resolved |

---

## 3. High-Priority Issues (P1)

| # | Issue | Location |
|---|-------|----------|
| 4 | **A2A route collision** — two `scope :a2a` blocks map to same URL prefix `/api/v1/ai/a2a/tasks` with different controllers (`a2a_tasks_controller` REST vs `a2a_controller` JSON-RPC) | `server/config/routes.rb` (~lines 2093, 2113) |
| 5 | **Duplicate memory routes** — 3 separate agent memory route handlers: `agent_memory_controller`, tiered memory scope, and memory injection scope | `server/config/routes.rb` |
| 6 | **Conversation route duplication** — nested under agents AND global scope, two separate controller implementations | `server/config/routes.rb` (~lines 1583, 1651) |
| 7 | **Service spec coverage at 48.1%** (90/187) — security (100%) and memory (86%) good; validators (0%), devops (0%), learning (11%), tools (12%) weak | `server/spec/services/ai/` |
| 8 | **Empty/minimal frontend modules** — `publisher/` removed, `devops/` (1 file), `roi/` (2 files), `aiops/` (2 files), `conversations/` (3 files, used by AIConversationsPage), `code-review/` (3 files) | `frontend/src/features/ai/` |

---

## 4. Backend Inventory

### 4.1 Models (109 total)

| Domain | Count | Key Models |
|--------|-------|------------|
| Core | 9 | Agent, Provider, ProviderCredential, Skill, AgentSkill, Conversation, Message, AgentMessage, ProviderMetric |
| Autonomy & Trust | 4 | AgentTrustScore, AgentBudget, AgentLineage, AgentIdentity |
| Memory & Learning | 6 | AgentShortTermMemory, SharedKnowledge, CompoundLearning, ContextEntry, PersistentContext, ContextAccessLog |
| Team Orchestration | 8 | AgentTeam, AgentTeamMember, TeamRole, TeamTask, TeamMessage, TeamChannel, TeamExecution, RoleProfile |
| Workflow Orchestration | 11 | Workflow, WorkflowNode (39 types), WorkflowEdge, WorkflowVariable, WorkflowTrigger, WorkflowRun, WorkflowNodeExecution, WorkflowRunLog, WorkflowCheckpoint, WorkflowCompensation, WorkflowApprovalToken |
| Workflow Management | 4 | WorkflowTemplate, WorkflowSchedule, WorkflowValidation, DAGExecution |
| Security & Audit | 5 | SecurityAuditTrail, AgentPrivilegePolicy, DataDetection, AgentAnomalyDetection, QuarantineRecord |
| Execution & Runtime | 7 | AgentExecution, Sandbox, Worktree, WorktreeSession, ExecutionTrace, ExecutionTraceSpan, ExecutionEvent |
| Knowledge & RAG | 6 | KnowledgeBase, Document, DocumentChunk, RagQuery, KnowledgeGraphNode, KnowledgeGraphEdge |
| Code Review & QA | 4 | CodeReview, CodeReviewComment, TaskReview, TaskComplexityAssessment |
| A2A Protocol | 3 | A2aTask, A2aTaskEvent, AgentCard |
| Testing & QA | 6 | TestScenario, TestRun, TestResult, MockResponse, RecordedInteraction, PerformanceBenchmark |
| DevOps Integration | 4 | DevopsTemplate, DevopsTemplateInstallation, PipelineExecution, RunnerDispatch |
| Learning & Evaluation | 4 | EvaluationResult, ImprovementRecommendation, Trajectory, TrajectoryChapter |
| Ralph Loops | 3 | RalphLoop, RalphIteration, RalphTask |
| Prompt & Routing | 4 | PromptTemplate, ModelRoutingRule, RoutingDecision, HybridSearchResult |
| Monitoring & Metrics | 6 | CostAttribution, CostOptimizationLog, TemplateUsageMetric, RoiMetric, ProviderMetric, RemediationLog |
| Infrastructure & Config | 7 | McpApp, McpAppInstance, DataConnector, GuardrailConfig, MemoryPool, SharedContextPool, AgentInstallation |
| Specialized | 7 | MergeOperation, FileLock, EncryptedMessage, DiscoveryResult, AgentConnection, DecayService, WorkflowApprovalToken |
| GUI & Sessions | 2 | AguiSession, AguiEvent |
| Utilities | 1 | Constants |

**Key architectural patterns**: pgvector embeddings (5 models with `has_neighbors`), tiered memory (Redis TTL → PG → pgvector), A2A JSON-RPC 2.0, 39 workflow node types, trust tiers (supervised→monitored→trusted→autonomous).

### 4.2 Services (187 total, ~41,570 LOC)

| Tier | Domain | Services | Specs | Coverage |
|------|--------|----------|-------|----------|
| 1 | Orchestration & Execution | 29 | 16 | 55% |
| 2 | Memory Systems | 7 | 6 | 86% |
| 3 | Security & Compliance | 7 | 7 | **100%** |
| 4 | Knowledge & RAG | 8 | 7 | 88% |
| 5 | Provider & LLM Management | 23 | 7 | 30% |
| 6 | A2A Protocol & Federation | 4 | 3 | 75% |
| 7 | Workflow Validators | 10 | 0 | **0%** |
| 8 | Monitoring & Health | 4 | 3 | 75% |
| 9 | Tools & MCP | 17 | 2 | 12% |
| 10 | Runtime & Sandbox | 5 | 4 | 80% |
| 11 | DevOps Integration | 5 | 0 | **0%** |
| 12 | Learning & Evaluation | 9 | 1 | 11% |
| 13 | Git Operations | 5 | 3 | 60% |
| 14 | Specialized | 56 | 21 | 38% |
| 15 | Enterprise | 11 | 7 | 64% |
| — | Utilities | 1 | 1 | 100% |
| | **Total** | **187** | **90** | **48.1%** |

**Largest services**: `provider_client_service.rb` (1,252 lines), `memory/maintenance_service.rb` (1,112 lines), `analytics/dashboard_service.rb` (1,007 lines).

**Smallest service**: `cost_optimization_service.rb` (28 lines).

### 4.3 Controllers (53 total, ~14,914 LOC)

**Oversized controllers (>300 lines)**:

| Controller | Lines | Excess |
|------------|-------|--------|
| `providers_controller.rb` | 1,029 | 3.4x limit |
| `teams_controller.rb` | 833 | 2.8x limit |
| `marketplace_controller.rb` | 660 | 2.2x limit |
| `analytics_controller.rb` | 529 | 1.8x limit |
| `ralph_loops_controller.rb` | 521 | 1.7x limit |
| `devops_controller.rb` | 495 | 1.7x limit |
| `sandboxes_controller.rb` | 488 | 1.6x limit |
| `workflows_controller.rb` | 483 | 1.6x limit |
| `model_router_controller.rb` | 466 | 1.6x limit |

**Near-limit controllers** (200-300 lines): `roi_controller` (441), `agents_controller` (365), `conversations_controller` (355), `workflow_git_triggers_controller` (326), `agent_marketplace_controller` (319), `agent_teams_controller` (319), `validation_statistics_controller` (304), `a2a_tasks_controller` (298).

**Security subsystem**: 4 controllers (443 lines total) — `agent_identity_controller` (128), `quarantine_controller` (149), `anomaly_detections_controller` (89), `pii_redactions_controller` (77).

### 4.4 Routes

- **AI namespace**: Lines 1390–2682 in `routes.rb` (1,293 lines)
- **Resource/scope blocks**: 37+
- **RESTful resources**: 12+
- **Custom scope blocks**: 25+

**Route issues identified**:
- A2A protocol: Two overlapping scopes (`as: :a2a` and `as: :a2a_protocol`) both mapping to `/api/v1/ai/a2a/tasks`
- Agent memory: 3 separate route handlers (general, tiered, injection)
- Conversations: Nested under agents AND global scope with separate controllers
- Marketplace: 40+ custom route lines instead of RESTful resources

### 4.5 Concerns (12 total, 1,750 LOC)

| Concern | Lines | Used By |
|---------|-------|---------|
| `audit_logging.rb` | 354 | All AI controllers |
| `authentication.rb` | 255 | All controllers |
| `api_response.rb` | 253 | All controllers (`render_success`/`render_error`) |
| `two_factor_enforcement.rb` | 198 | Sensitive operations |
| `activatable_resource.rb` | 113 | Resource lifecycle |
| `analytics_queryable.rb` | 106 | Analytics controllers |
| `secure_params.rb` | 105 | Parameter validation |
| `user_serialization.rb` | 94 | User/account responses |
| `paginatable.rb` | 86 | List endpoints |
| `csrf_protection.rb` | 71 | CSRF protection |
| `searchable_controller.rb` | 60 | Search endpoints |
| `rate_limiting.rb` | 55 | API rate limits |

### 4.6 Seeds (15 files, ~5,955 lines)

| Seed File | Lines | Purpose |
|-----------|-------|---------|
| `ai_workflow_seeds.rb` | 2,481 | Workflow templates & examples |
| `ai_todo_team_seed.rb` | 783 | TODO tracking agent team |
| `ai_workflow_showcase_seeds.rb` | 646 | Visual workflow showcases |
| `ai_devops_templates_seed.rb` | 619 | DevOps pipeline templates |
| `ai_skills_seed.rb` | 437 | Built-in agent skills |
| `ai_model_routing_rules_seed.rb` | 420 | Model routing rules |
| `ai_teams_seed.rb` | 384 | Example agent teams |
| `ai_devops_configs_seed.rb` | 185 | DevOps defaults |
| `comprehensive_ai_providers_seed.rb` | — | Default AI providers |
| `devops_pipeline_showcase_seeds.rb` | — | Pipeline examples |
| `devops_container_templates.rb` | — | Container templates |
| `devops_comprehensive_workflows.rb` | — | DevOps workflows |
| `mcp_container_templates_seed.rb` | — | MCP container templates |
| `supply_chain_licenses.rb` | — | License templates |
| `supply_chain_questionnaire_templates.rb` | — | Questionnaire templates |

---

## 5. Frontend Inventory

### 5.1 Feature Modules (37 total, 369 files)

| Module | Files | TSX | TS | Tests | Status |
|--------|-------|-----|----|----|--------|
| chat | 36 | 25 | 5 | 6 | Mature |
| workflows | 33 | 23 | 9 | 4 | Mature |
| agent-teams | 29 | 23 | 5 | 1 | Mature |
| memory | 25 | 17 | 8 | 0 | Mature |
| parallel-execution | 20 | 15 | 5 | 0 | Mature |
| execution-resources | 19 | 15 | 4 | 0 | Mature |
| agents | 15 | 11 | 4 | 3 | Mature |
| ralph-loops | 15 | 13 | 2 | 0 | Active |
| providers | 14 | 13 | 1 | 2 | Mature |
| monitoring | 15 | 11 | 4 | 1 | Mature |
| chat-channels | 13 | 9 | 1 | 4 | Active |
| components | 12 | 12 | 0 | 3 | Utility |
| security | 10 | 7 | 3 | 0 | Active |
| knowledge-graph | 9 | 6 | 3 | 0 | Active |
| agui | 9 | 6 | 3 | 0 | Active |
| audit | 9 | 5 | 4 | 0 | Active |
| finops | 9 | 6 | 3 | 0 | Active |
| orchestration | 9 | 8 | 1 | 4 | Active |
| agent-cards | 8 | 4 | 1 | 3 | Active |
| autonomy | 7 | 4 | 3 | 0 | Active |
| community-agents | 7 | 6 | 1 | 1 | Active |
| evaluation | 7 | 4 | 3 | 0 | Active |
| mcp-apps | 7 | 4 | 3 | 0 | Active |
| sandboxes | 7 | 4 | 3 | 0 | Active |
| skills | 7 | 4 | 3 | 0 | Active |
| a2a-tasks | 7 | 3 | 1 | 3 | Active |
| learning | 5 | 4 | 1 | 0 | Active |
| prompts | 5 | 1 | 4 | 0 | Active |
| debugging | 4 | 3 | 1 | 1 | Minimal |
| conversations | 3 | 3 | 0 | 0 | Minimal |
| code-review | 3 | 2 | 1 | 0 | Stub |
| self-healing | 3 | 3 | 0 | 0 | Minimal |
| aiops | 2 | 1 | 1 | 0 | Minimal |
| roi | 2 | 1 | 1 | 0 | **Minimal** |
| devops | 1 | 1 | 0 | 0 | **Minimal** |
| publisher | — | — | — | — | **Removed** |

### 5.2 API Services (31 total, ~12,277 LOC)

| Service | Lines | Purpose |
|---------|-------|---------|
| TeamsApiService.ts | 888 | Agent team orchestration |
| McpApiService.ts | 845 | MCP server discovery & tooling |
| AgentsApiService.ts | 714 | Agent CRUD, execution, conversations |
| MonitoringApiService.ts | 650 | Metrics, dashboards, circuit breakers |
| index.ts | 569 | Central exports |
| RoiApiService.ts | 506 | ROI metrics, cost analysis |
| AiOpsApiService.ts | 455 | DevOps metrics, health checks |
| BaseApiService.ts | 434 | Base class (pagination, errors) |
| WorkflowsApiService.ts | 432 | Workflow CRUD, execution, scheduling |
| MarketplaceApiService.ts | 428 | Marketplace items, templates |
| ProvidersApiService.ts | 418 | Provider configuration |
| ModelRouterApiService.ts | 402 | Model routing |
| AnalyticsApiService.ts | 401 | Analytics & reporting |
| OutcomeBillingApiService.ts | 378 | Outcome-based billing |
| SandboxApiService.ts | 370 | Sandbox execution |
| RagApiService.ts | 323 | RAG system |
| GovernanceApiService.ts | 322 | Governance/compliance |
| McpHostingApiService.ts | 320 | MCP hosting |
| ChatChannelsApiService.ts | 304 | Chat channels |
| DevopsApiService.ts | 289 | DevOps integration |
| ConversationsApiService.ts | — | Conversation management |
| MemoryApiService.ts | — | Consolidated memory |
| ValidationApiService.ts | — | Workflow validation |
| CreditsApiService.ts | — | Credits/billing |
| A2aTasksApiService.ts | — | A2A protocol |
| AgentCardsApiService.ts | — | Agent cards |
| AgentMarketplaceApiService.ts | — | Agent marketplace |
| CommunityAgentsApiService.ts | — | Community agents |
| ContainerExecutionApiService.ts | — | Container sandbox |
| CircuitBreakerApiService.ts | — | Circuit breakers |
| PluginsApiService.ts | — | Plugin management |
| RalphLoopsApiService.ts | — | Ralph loops |

### 5.3 Pages & Routes

**Routed pages (35)**: AIOverviewPage, AIAgentsPage, WorkflowsPage, AIConversationsPage, AIMonitoringPage, GovernancePage, SandboxPage, ExecutionPage, KnowledgePage, InfrastructurePage, AiBillingPage, AIProvidersPage, CreateWorkflowPage, AIDebugPage, AgentDetailPage, WorkflowDetailPage, WorkflowImportPage, WorkflowMonitoringPage, WorkflowValidationStatisticsPage, AIAnalyticsPage, WorkflowAnalyticsPage, AgentMemoryPage, ContextDetailPage, ChatChannelsPage, SandboxDashboardPage, AutonomyDashboardPage, KnowledgeMemoryPage, CompoundLearningPage, AuditDashboardPage, SecurityDashboardPage, EvaluationDashboardPage, SelfHealingDashboard, RecommendationsDashboard, TrajectoryInsights, TeamsPage, DevOpsTemplatesPage.

**Content tab pages (9)**: A2aTasksPage, ContextsPage, CreditsPage, ExecutionResourcesPage, McpBrowserPage, ModelRouterPage, OutcomeBillingPage, RagPage, SkillsPage — these are Content components rendered as tabs inside wrapper pages (ExecutionPage, KnowledgePage, InfrastructurePage, AiBillingPage), not standalone routes.

**Standalone alternatives (2)**: AgentCardsPage, AgentMarketplacePage — provide PageContainer wrappers around feature modules already accessible via AIAgentsPage sub-routes.

### 5.4 Chat System Architecture

- **Components**: 23 TSX files (ChatWindow, ChatInput, ChatMessage, ConversationSidebar, SplitPanelContainer, etc.)
- **State management**: React Context + Reducer pattern (`ChatWindowContext`, `chatWindowReducer`)
- **Persistence**: localStorage sync for window state and conversation history
- **Streaming**: `ChatStreamingRenderer` for real-time message rendering
- **Window modes**: Floating, maximized, tabbed, split-panel
- **Tests**: 6 test files with comprehensive coverage

### 5.5 Type Safety

- **Production code**: Zero `: any` violations
- **Test files**: 78 instances (acceptable for mock definitions)
- **Theme compliance**: 100% — all components use `bg-theme-*`/`text-theme-*` classes

---

## 6. Worker Inventory

### 6.1 Jobs (48 total)

| Category | Count | Key Jobs |
|----------|-------|----------|
| Orchestration/Workflow | 15 | AiWorkflowExecutionJob, AiWorkflowNodeExecutionJob, AiAgentTeamExecutionJob, AiAgentExecutionJob, AiA2aTaskExecutionJob |
| Memory/Learning | 7 | AiMemoryConsolidationJob, AiMemoryDecayJob, AiCompoundLearningMaintenanceJob, AiSharedKnowledgeMaintenanceJob |
| Cleanup/Maintenance | 6 | AiWorkflowMonthlyCleanupJob, AiExecutionTimeoutCleanupJob, ChatSessionCleanupJob, AiTeamMessageCleanupJob |
| Analytics/Metrics | 5 | AiWorkflowAnalyticsCacheWarmupJob, AiWorkflowCostMonitoringJob, AiWorkflowHealthMonitoringJob, AiMonitoringAnalysisJob |
| Miscellaneous | 5 | AiWebhookDeliveryJob, AiPredictiveMonitorJob, AiTemplateUpdateJob, AiChatAttachmentProcessingJob, OllamaConnectivityTestJob |
| Provider/Model | 3 | AiProviderHealthCheckJob, AiProviderModelSyncJob, AiSkillSyncJob |
| Notification/Evaluation | 3 | AiNotificationDigestJob, AiGuardrailEvaluationJob, AiReviewAnalysisJob |
| Chat/Communication | 2 | AiChatResponseJob, AiChatContextBuilderJob |
| Approval | 2 | AiWorkflow::ApprovalExpiryJob, AiWorkflow::ApprovalNotificationJob |

### 6.2 Queue Configuration (10 AI queues)

| Queue | Priority | Job Count | Purpose |
|-------|----------|-----------|---------|
| `ai_cancellations` | 3 (Critical) | 1 | Immediate execution cancellation |
| `ai_workflows` | 2 | 1 | Main workflow execution |
| `ai_agents` | 2 | 7 | Agent execution & webhooks |
| `ai_conversations` | 2 | 2 | Chat responses & context |
| `ai_orchestration` | 2 | 16 | Team orchestration & maintenance |
| `ai_workflow_health` | 2 | 5 | Health & cost monitoring |
| `ai_workflow_schedules` | 2 | 1 | Scheduled triggers |
| `ai_workflow_nodes` | 2 | 1 | Node-level execution |
| `ai_testing` | 2 | 1 | Ollama connectivity testing |
| `file_processing` | 2 | 1 | Chat attachment processing |

### 6.3 Circuit Breakers (3 profiles)

| Profile | Timeout | Recovery | Used By |
|---------|---------|----------|---------|
| Workflow Execution | 600s | 120s | 3 workflow jobs |
| AI Provider | 600s | 120s | 10 agent/provider jobs |
| Backend API | 120s | 60s | ~30 orchestration/maintenance jobs |

All breakers: 5-failure threshold, CLOSED → OPEN → HALF_OPEN state machine.

### 6.4 Scheduled Jobs (16 recurring)

| Job | Schedule | Purpose |
|-----|----------|---------|
| AiMonitoringHealthCheckJob | Every 30s (self-rescheduling) | Real-time metrics broadcast |
| AiWorkflowHealthMonitoringJob | Every 5 min | System health checks |
| AiProviderHealthCheckJob | Every 10 min | Provider connectivity |
| AiWorkflowAnalyticsCacheWarmupJob | Every 15 min | Dashboard cache warmup |
| AiWorkflowApprovalExpiryJob | Hourly (minute 15) | Expire stale approvals |
| AiWorkflowCostMonitoringJob | Hourly | Cost spike detection |
| ChatSessionCleanupJob | Every 6 hours | Stale session cleanup |
| AiProviderModelSyncJob | Every 6 hours | Model list & pricing sync |
| AiMemoryPoolCleanupJob | Daily 3:30 AM UTC | Expired memory pools |
| AiCompoundLearningMaintenanceJob | Daily 3:45 AM UTC | Learning decay & promotion |
| AiTeamMessageCleanupJob | Daily 4:00 AM UTC | Old team messages |
| AiSharedKnowledgeMaintenanceJob | Daily | pgvector maintenance |
| AiMemoryConsolidationJob | Daily | Memory tier promotion |
| AiMemoryDecayJob | Daily | Temporal decay |
| AiWorkflowWeeklyReportJob | Sunday 6:00 AM UTC | Weekly summary |
| AiWorkflowMonthlyCleanupJob | 1st of month midnight | Data retention & archival |

### 6.5 Base Job Features

All AI jobs inherit shared infrastructure:
- **Exponential backoff**: Custom retry intervals per error type
- **Runaway loop detection**: >5 executions in 60s triggers abort
- **Idempotency keys**: Prevents duplicate processing
- **Structured logging**: `log_info`/`log_error`/`log_warn` with metadata
- **Metrics tracking**: Counters, performance metrics, error tracking
- **API retry helper**: `with_api_retry(max_attempts: 3)`

---

## 7. Cross-Layer Integration

| Integration | Status | Details |
|-------------|--------|---------|
| Backend → Worker | **PASS** | All dispatched jobs verified via `WorkerJobService`. 48 jobs exist with matching queue assignments. |
| Frontend → Backend | **PASS** | 31 API services with 191+ REST endpoints. All services inherit `BaseApiService` for consistent patterns. |
| Backend Models → Schema | **PASS** | 134 core + 24 enterprise AI tables verified in `schema.rb`. |
| Enterprise Integration | **PASS** | Clean modular separation. `FeatureGateService.enterprise_loaded?` (backend), `__ENTERPRISE__` build flag (frontend). 24 enterprise models, 11 services, 1 worker job. |
| Seeds → Models | **PASS** | 15 seed files (~5,955 lines) covering providers, workflows, teams, skills, devops, routing rules. |

---

## 8. Recommendations

### P0 — Critical (do now)

1. **Split oversized controllers** — Start with `providers_controller` (1,029 lines): extract credentials management to `ProviderCredentialsController`, sync operations to `ProviderSyncController`. Apply same pattern to `teams_controller` (roles, channels, executions) and `marketplace_controller` (templates, installations, search).

2. **~~Add routes for orphaned pages~~** — RESOLVED. Only 2 pages were truly orphaned (DevOpsTemplatesPage, WorkflowAnalyticsPage) — now wired. The remaining 11 are content tabs or standalone alternatives, not orphaned.

3. **Add specs for 0%-coverage tiers** — Prioritize workflow validators (10 services, 818 lines) and devops bridge (5 services, 806 lines) as they have zero test coverage.

### P1 — High (this sprint)

4. **Refactor remaining oversized controllers** — `analytics_controller` (529), `ralph_loops_controller` (521), `devops_controller` (495), `sandboxes_controller` (488), `workflows_controller` (483), `model_router_controller` (466).

5. **Resolve A2A route collision** — Rename one scope (e.g., `scope :a2a_rpc` for JSON-RPC) or use controller-level HTTP method differentiation.

6. **Consolidate memory routes** — Unify 3 separate agent memory route handlers into a single structured resource block.

7. **Add error context to controller rescue blocks** — Multiple controllers use bare `rescue => e` patterns that lose exception details.

### P2 — Medium (next sprint)

8. **Increase service spec coverage to 70%+** — Focus on tools/MCP (12% → 70%), learning/evaluation (11% → 70%), provider adapters (30% → 70%).

9. **Clean up empty/minimal frontend modules** — `publisher/` (empty) removed. Decide on `devops/` (1 file), `roi/` (2 files), `aiops/` (2 files) — implement or remove.

10. **Add missing model validations** — Verify workflow→agent references, agent→skill associations, team composition constraints at the model level.

11. **Convert marketplace to RESTful resources** — Replace 40+ custom route lines with Rails `resources` DSL for cleaner routing.

### P3 — Low (tech debt)

12. **Audit unused services** — Verify whether `cost_optimization_service` (28 lines), `debugging_service` (653 lines), and `tracing_service` (482 lines) are actively used or candidates for removal.

13. **Consolidate seed files** — 15 files across ~5,955 lines; consider grouping by feature domain.

14. **Add JSDoc to large API services** — `AgentsApiService` (714 lines), `TeamsApiService` (888 lines), `McpApiService` (845 lines) would benefit from method documentation.

15. **Frontend test coverage** — Multiple active modules (knowledge-graph, finops, security, evaluation, mcp-apps, sandboxes) have zero test files.
