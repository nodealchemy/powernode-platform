# AI Platform Audit Report — Round 3

**Date**: 2026-02-13
**Scope**: Full-stack audit of AI platform (backend models, services, controllers, routes, frontend, specs, factories)
**Passes**: Initial sweep → P0 validation → N+1/dead code/API consistency → permissions/SQL injection/race conditions

---

## Executive Summary

| Category | Status | Issues |
|----------|--------|--------|
| Permission enforcement gaps | **P0** | 6 controllers lack permission checks (31+ write actions) |
| Missing model files | **P0** | 8 tables in schema lack model files |
| Race conditions | **P0** | 6 patterns (counter corruption, TOCTOU, unprotected finalization) |
| Dead routes | **P0** | 2 routes to nonexistent actions |
| SQL injection (LIKE) | **P0** | 5 unsanitized ILIKE interpolations |
| N+1 query risks | **P1** | 8 critical/high patterns across serializers |
| Associations | **P1** | 58 missing `foreign_key:` pairings (40 files) |
| API response inconsistency | **P1** | 5+ different index response formats |
| Orphaned frontend pages | **P2** | 2 truly orphaned (7 resolved as tab-routed) |
| Controller size (>300) | **P2** | 9 violations |
| Service size (>500) | **P2** | 18 violations |
| Frontend size (>500) | **P2** | 27 violations |
| Worker job size | **P2** | 1 job at 1,437 lines, 3 more over 500 |
| Dead code | **P2** | 1 unused concern (441 lines) |
| Theme violations | **P2** | 3 hardcoded colors |
| Missing inverse association | **P2** | 1 (TemplateUsageMetric ↔ AgentTemplate) |
| Frontend hooks missing error handling | **P2** | 2 hook files |
| Models without factories | **P2** | 8 models |
| Spec coverage | **P3** | 36 services + 28 controllers uncovered |
| Auth (JWT) | Pass | All controllers protected |
| Frozen string literal | Pass | 0 |
| JSON defaults | Pass | 0 |
| Broken imports | Pass | 0 |
| Console.log | Pass | 0 |
| Unused services | Pass | 0 |

---

## P0 — Critical (Security / Data Integrity / Runtime)

### P0-1: Permission Enforcement Gaps (6 controllers, 31+ write actions)

All controllers have JWT auth, but 6 lack `authorize_action!()` / `validate_permissions` — any authenticated user can access all actions:

| Controller | Write Actions at Risk |
|------------|----------------------|
| **AgentMarketplaceController** | `install`, `uninstall`, `create_review`, `create_publisher`, `compose_team` |
| **CommunityAgentsController** | `create`, `update`, `destroy`, `publish`, `unpublish`, `rate`, `report` |
| **FederationController** | `create`, `update`, `destroy`, `verify`, `sync`, `register_external` |
| **SandboxesController** | `create`, `update`, `destroy`, `activate`, `deactivate` |
| **SandboxScenariosController** | `create_scenario`, `create_mock` |
| **SandboxTestingController** | `create_run`, `execute_run`, `create_benchmark`, `run_benchmark`, `create_ab_test`, `start_ab_test` |

**Fix**: Add `before_action :validate_permissions` with appropriate permission mapping.

### P0-2: Race Conditions (6 patterns)

| Severity | File | Line | Issue |
|----------|------|------|-------|
| **CRITICAL** | `workflows/run_management_service.rb` | 223 | Non-atomic counter: `update!(failed_nodes: (run.failed_nodes \|\| 0) + 1)` — use `increment!` |
| **CRITICAL** | `marketplace/installation_service.rb` | 318-333 | Rating average read-modify-write without lock — concurrent updates corrupt averages |
| **HIGH** | `review_workflow_service.rb` | 51,121,149 | TOCTOU: `task.update!(status: "waiting") if task.status == "completed"` without lock |
| **HIGH** | `agent_team_orchestrator.rb` | 583 | Parallel execution finalization without lock — later write overwrites earlier |
| **MEDIUM** | `autonomy/trust_engine_service.rb` | 220-251 | Trust tier promotion writes agent + trust_score without transaction |
| **MEDIUM** | `workflow_retry_strategy_service.rb` | 173-188 | JSON metadata read-modify-write without transaction |

**Good example**: `circuit_breaker_registry.rb:256-268` correctly uses `with_lock`.

**Root causes**: No `lock_version` columns on any AI models, only 5 uses of `with_lock` across entire AI service layer.

### P0-3: Tables Without Model Files (8)

8 tables exist in `schema.rb` with factories but NO model file. Using factories crashes with `uninitialized constant`.

| Table | Key Associations Needed |
|-------|------------------------|
| `ai_approval_chains` | account, created_by (User), has_many :approval_requests |
| `ai_approval_requests` | account, approval_chain, requested_by (User), polymorphic :source |
| `ai_compliance_audit_entries` | account, user (optional), polymorphic :resource |
| `ai_compliance_policies` | account, created_by (User), has_many :policy_violations |
| `ai_compliance_reports` | account, generated_by (User) |
| `ai_data_classifications` | account, classified_by (User) |
| `ai_policy_violations` | account, policy (CompliancePolicy), polymorphic :source |
| `ai_publisher_accounts` | account (unique), primary_user, has_many :agent_templates |

Full schema definitions with columns, indexes, check constraints, and codebase references gathered — ready for model generation.

### P0-4: Dead Routes (2)

| Route | Line | Issue |
|-------|------|-------|
| `POST /api/v1/ai/marketplace/templates/publish_workflow` | ~1762 | `MarketplaceController#publish_workflow` doesn't exist (has `publish` but not `publish_workflow`) |
| `POST /api/v1/ai/agents/:id/memory/inject` | ~1844 | `AgentMemoryController#inject` doesn't exist |

### P0-5: SQL Injection — Unsanitized ILIKE (5)

All use parameterized `?` (preventing direct SQL injection) but interpolate user input into LIKE patterns without `sanitize_sql_like()`, allowing wildcard manipulation (`%`, `_`):

| File | Line | Unsanitized Variable |
|------|------|---------------------|
| `controllers/ai/agent_cards_controller.rb` | 21 | `params[:query]` |
| `services/ai/acp/protocol_service.rb` | 42 | `filter[:query]` |
| `services/ai/learning/compound_learning_service.rb` | 320 | `filters[:query]` |
| `services/ai/memory/storage_service.rb` | 295 | `pattern` |
| `services/ai/memory/storage_service.rb` | 306 | `query` |

**Fix**: Wrap with `ActiveRecord::Base.sanitize_sql_like()` (already used correctly in `providers_controller.rb:225`, `provider_credentials_controller.rb:233`, `marketplace_service.rb:67`).

---

## P1 — High (Performance / Data Integrity)

### P1-1: N+1 Query Risks (8 patterns)

| Serializer | Issue | Severity | Fix |
|------------|-------|----------|-----|
| `agent_serialization.rb:30-56` | `serialize_agent()` calls `agent.executions` 4x per agent in index | **CRITICAL** | Add `.includes(:executions)` in AgentsController index |
| `resource_serialization.rb:256-261` | Same N+1 via `calculate_agent_success_rate()` | **CRITICAL** | Add `.includes(:executions)` |
| `conversation_serialization.rb:69-86` | Accesses `:participants`, `:messages` not in index includes | **CRITICAL** | Add to ConversationsController `.includes()` |
| `agent_serialization.rb:78-96` | `serialize_execution()` accesses `:agent`, `:user`, `:provider` | **HIGH** | Add includes in TeamExecutionController |
| `provider_serialization.rb:24-27` | `.provider_credentials.count` called 2x per provider | **HIGH** | Use `.size` on preloaded association |
| `workflow_serialization.rb:24-27` | `.nodes.count`, `.edges.count`, `.runs.count` per workflow | **HIGH** | Add `:runs` to WorkflowsController includes |
| `workflow_serialization.rb:214-218` | `log.node_execution.node.name` without include | **MEDIUM** | Include `:node` on log queries |
| `conversations_controller.rb:131-136` | Message duplicate iterates without `.includes(:user, :agent)` | **HIGH** | Add includes before iteration |

### P1-2: `class_name:` Without `foreign_key:` (58 violations, 40 files)

Top violations by file (full list available in detailed audit data):

| File | Count | Associations |
|------|-------|-------------|
| `team_message.rb` | 5 | team_execution, channel, from_role, to_role, in_reply_to |
| `compound_learning.rb` | 4 | ai_agent_team, source_agent, source_execution, superseded_by |
| `performance_benchmark.rb` | 4 | sandbox, target_workflow, target_agent, created_by |
| `ralph_loop.rb` | 4 | default_agent, container_instance, ralph_tasks (has_many), ralph_iterations (has_many) |
| `team_task.rb` | 3 | team_execution, assigned_role, parent_task |
| `knowledge_graph_edge.rb` | 3 | source_node, target_node, source_document |
| `knowledge_graph_node.rb` | 3 | knowledge_base, source_document, merged_into |
| `agent_installation.rb` | 3 | agent_template, installed_agent, installed_by |
| `pipeline_execution.rb` | 3 | devops_installation, workflow_run, triggered_by |
| `task_review.rb` | 3 | team_task, reviewer_role, reviewer_agent |
| 30 more files | 1-2 each | Various |

### P1-3: API Response Format Inconsistency

Index actions use 5+ different wrapper formats:

| Pattern | Example | Controllers Using |
|---------|---------|-------------------|
| `{ items: [], pagination: {} }` | agents, workflows, providers | ~10 (RECOMMENDED) |
| `{ data: [] }` | sandboxes, autonomy, memory, traces | ~8 |
| `{ resource_name: [], pagination: {} }` | skills, prompts, conversations | ~5 |
| `{ resource_name: [] }` (no pagination) | mcp_apps, discovery | ~4 |
| Direct array / custom | agent_teams (meta), memory_pools | ~3 |

---

## P2 — Medium (Code Quality)

### P2-1: Orphaned Frontend Pages (2 truly orphaned)

| Page | Status |
|------|--------|
| `FinOpsPage.tsx` | **ORPHANED** — exported but never imported/routed |
| `McpAppsPage.tsx` | **ORPHANED** — exported but never imported/routed |
| `MemoryExplorerPage.tsx` | **SUPERSEDED** — replaced by KnowledgeMemoryPage |

7 previously flagged pages are properly routed as tabs within container pages (ExecutionPage, KnowledgePage, AIAgentsPage).

### P2-2: Controllers Over 300 Lines (9)

| Controller | Lines |
|------------|-------|
| `workflows_controller.rb` | 326 |
| `workflow_git_triggers_controller.rb` | 326 |
| `agent_teams_controller.rb` | 321 |
| `team_execution_controller.rb` | 319 |
| `agent_marketplace_controller.rb` | 319 |
| `provider_credentials_controller.rb` | 315 |
| `marketplace_controller.rb` | 312 |
| `validation_statistics_controller.rb` | 304 |
| `ralph_loops_controller.rb` | 301 |

### P2-3: Services Over 500 Lines (18)

| Service | Lines |
|---------|-------|
| `provider_client_service.rb` | 1,252 |
| `memory/maintenance_service.rb` | 1,112 |
| `analytics/dashboard_service.rb` | 1,007 |
| `analytics/cost_analysis_service.rb` | 932 |
| `memory/storage_service.rb` | 891 |
| `provider_management_service.rb` | 829 |
| `agent_team_orchestrator.rb` | 784 |
| `debugging_service.rb` | 653 |
| `model_router_service.rb` | 643 |
| `mcp_agent_executor.rb` | 609 |
| `workflow_recovery_service.rb` | 590 |
| `analytics/performance_analysis_service.rb` | 588 |
| `workflows/template_service.rb` | 586 |
| `teams/configuration_service.rb` | 562 |
| `ralph/execution_service.rb` | 555 |
| `monitoring_health_service.rb` | 544 |
| `marketplace/installation_service.rb` | 539 |
| `marketplace/template_discovery_service.rb` | 520 |

### P2-4: Frontend Components Over 500 Lines (27)

Top 10:

| Component | Lines |
|-----------|-------|
| `ralph-loops/components/RalphTaskList.tsx` | 789 |
| `agents/components/EditAgentModal.tsx` | 779 |
| `devops/components/DevopsTemplateFormModal.tsx` | 743 |
| `providers/components/AiProvidersPage.test.tsx` | 731 |
| `ralph-loops/components/RalphTaskExecutorSelect.tsx` | 725 |
| `providers/components/ProviderDetailModal.tsx` | 718 |
| `ralph-loops/components/RalphPrdEditor.tsx` | 714 |
| `agent-teams/components/TeamAnalyticsDashboard.tsx` | 709 |
| `monitoring/components/ProviderHealthDashboard.tsx` | 698 |
| `orchestration/components/EnhancedAIOverview.tsx` | 696 |

Plus 17 more between 500-673 lines.

### P2-5: Worker Jobs Over 500 Lines (4)

| Job | Lines |
|-----|-------|
| `ai_agent_execution_job.rb` | 1,437 |
| `ai_chat_response_job.rb` | 649 |
| `ai_workflow_health_monitoring_job.rb` | 543 |
| `ai_a2a_task_execution_job.rb` | 532 |

Worker architecture is otherwise clean — all jobs inherit BaseJob, use `execute()`, communicate via HTTP API.

### P2-6: Dead Code — Unused Concern

`server/app/controllers/concerns/ai/resource_serialization.rb` (441 lines) is not included by any controller.

### P2-7: Theme Violations (3)

| File | Line | Issue |
|------|------|-------|
| `devops/components/DevopsTemplateFormModal.tsx` | 99 | `focus:ring-blue-500` |
| `components/conversation/MessageList.tsx` | 222 | `divide-gray-300 dark:divide-gray-600` |
| `workflows/pages/ApprovalResponsePage.tsx` | 285 | `focus:ring-purple-500` |

### P2-8: Models Without Factories (8)

| Model | Missing Factory |
|-------|----------------|
| `agent_identity.rb` | `agent_identities.rb` |
| `agent_message.rb` | `agent_messages.rb` |
| `agent_privilege_policy.rb` | `agent_privilege_policies.rb` |
| `agent_short_term_memory.rb` | `agent_short_term_memories.rb` |
| `agent_skill.rb` | `agent_skills.rb` |
| `context_entry.rb` | `context_entries.rb` |
| `rag_query.rb` | `rag_queries.rb` |
| `trajectory.rb` | `trajectories.rb` |

### P2-9: Missing Inverse Association

`Ai::TemplateUsageMetric` has `belongs_to :agent_template` but `Ai::AgentTemplate` is missing `has_many :template_usage_metrics`.

### P2-10: Frontend Hooks Missing Error Handling (2)

| Hook | Issue |
|------|-------|
| `memory/hooks/useAgentMemory.ts:45-62` | `fetchMemory()` calls API without try/catch |
| `prompts/hooks/usePromptTemplates.ts:55-80` | `createTemplate()`, `updateTemplate()`, `deleteTemplate()`, `duplicateTemplate()` lack try/catch |

### P2-11: Bare `render json:` (2)

| File | Line | Context |
|------|------|---------|
| `a2a_controller.rb` | 44 | JSON-RPC protocol response (intentional) |
| `agent_cards_controller.rb` | 50 | A2A agent card response (intentional) |

---

## P3 — Low (Coverage Gaps)

### P3-1: Services Without Specs (36 / 177 = 20%)

Key uncovered services:
- `agents/conversation_service.rb`, `agents/execution_service.rb`, `agents/management_service.rb`
- `acp/protocol_service.rb`, `a2a/dag_executor.rb`
- `code_review/diff_analyzer_service.rb`, `code_review/enhanced_review_service.rb`
- `context/compression_service.rb`, `context/rot_detection_service.rb`
- `discovery/*` (4 services)
- `git/agent_workspace_service.rb`, `git/branch_protection_service.rb`
- `memory/embedding_service.rb`
- `ralph/execution_service.rb`, `ralph/task_executor.rb`
- `workflows/execution_service.rb`, `workflows/run_management_service.rb`, `workflows/template_service.rb`
- `providers/default_config.rb`
- And 17 more

### P3-2: Controllers Without Specs (28 / 69 = 41%)

Key uncovered controllers:
- `a2a_controller.rb`, `acp_controller.rb`
- `autonomy_controller.rb`, `tiered_memory_controller.rb`
- `provider_credentials_controller.rb`, `provider_sync_controller.rb`
- `roi_calculations_controller.rb`
- `sandbox_scenarios_controller.rb`, `sandbox_testing_controller.rb`
- `security/anomaly_detections_controller.rb`, `security/pii_redactions_controller.rb`
- `skills_controller.rb`
- And 16 more

---

## What Passed

- All `.rb` files have `# frozen_string_literal: true`
- All JSON column defaults use lambda syntax
- All controllers protected by JWT auth (via ApplicationController → Authentication)
- No broken frontend imports
- No `console.log` in production code
- No role-based access control violations
- No empty frontend directories
- No `any` types in production TypeScript (only test mocks)
- All concern `include` statements reference existing files
- All service class references from controllers resolve
- All seed files reference valid models
- All migrations use inline indexing for `t.references`
- No hardcoded secrets in initializers
- Worker jobs properly use HTTP API (no direct server model access)
- 0 unused services (all 177 are referenced)
- Worker jobs all inherit BaseJob, use `execute()`, have error handling + retry logic
- `Ai::ExecutionTrace` and `Ai::ExecutionTraceSpan` models DO exist
- `.well-known/agent.json` route is correct (A2A protocol)
- Devops controllers (3) properly use `authorize_action!()` on every action
