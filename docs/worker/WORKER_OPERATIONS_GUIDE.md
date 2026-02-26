# Worker Operations Guide

The Powernode worker is a standalone Sidekiq process (175 jobs) that communicates with the server exclusively via HTTP API. It does NOT share a database connection with the Rails backend.

---

## Architecture

```
┌─────────────────────┐     HTTP API     ┌─────────────────────┐
│  Worker (Sidekiq)   │ ───────────────> │  Server (Rails 8)   │
│  175 jobs           │ <─────────────── │  285 controllers    │
│  32 queues          │                  │  570 services       │
│  Redis DB 1         │                  │  PostgreSQL         │
└─────────────────────┘                  └─────────────────────┘
```

**Critical rules:**
- Jobs belong in `worker/app/jobs/` — NEVER `server/app/jobs/`
- Worker communicates via HTTP API only — no direct DB access
- Never add Sidekiq gems to `server/Gemfile`

---

## Job Categories by Namespace

### AI Jobs (74 top-level + 2 namespaced = 76)

The largest category — covers the entire AI platform.

| Job | Queue | Description |
|-----|-------|-------------|
| `AiAgentExecutionJob` | `ai_agents` | Execute AI agent with provider orchestration |
| `AiTeamExecutionJob` | `ai_execution` | Multi-agent team orchestration |
| `AiWorkflowExecutionJob` | `ai_workflows` | Workflow run execution |
| `AiWorkflowNodeExecutionJob` | `ai_workflow_nodes` | Individual node execution |
| `AiChatResponseJob` | `ai_conversations` | AI conversation response generation |
| `AiChatAttachmentProcessingJob` | `ai_conversations` | Process chat attachments |
| `AiChatContextBuilderJob` | `ai_conversations` | Build conversation context |
| `AiStreamingChannel` (via job) | `ai_agents` | Token streaming to WebSocket |
| `AiCodeFactoryRunJob` | `ai_agents` | Code Factory pipeline run |
| `AiCodeFactoryPrdJob` | `ai_agents` | PRD generation |
| `AiCodeFactoryTaskGenJob` | `ai_agents` | Task generation from PRD |
| `AiCodeFactoryRemediationJob` | `ai_agents` | Code remediation |
| `AiCodeFactoryEvidenceJob` | `ai_agents` | Evidence collection |
| `AiCodeFactoryHarnessGapJob` | `ai_agents` | Test harness gap analysis |
| `AiCodeReviewJob` | `ai_agents` | Automated code review |
| `AiMissionAnalyzeJob` | `ai_agents` | Mission analysis stage (Ralph) |
| `AiMissionPlanJob` | `ai_agents` | Mission planning stage |
| `AiMissionExecuteJob` | `ai_agents` | Mission execution stage |
| `AiMissionTestJob` | `ai_agents` | Mission testing stage |
| `AiMissionReviewJob` | `ai_agents` | Mission review stage |
| `AiMissionDeployJob` | `ai_agents` | Mission deployment stage |
| `AiMissionMergeJob` | `ai_agents` | Mission merge stage |
| `AiMissionCleanupJob` | `ai_agents` | Mission cleanup |
| `AiMemoryConsolidationJob` | `ai_orchestration` | STM→LTM memory promotion |
| `AiMemoryDecayJob` | `ai_orchestration` | Memory importance decay |
| `AiMemoryMaintenanceJob` | `ai_orchestration` | Memory pool maintenance |
| `AiMemoryPoolCleanupJob` | `ai_orchestration` | Pool cleanup |
| `AiConsolidateMemoryEntryJob` | `ai_orchestration` | Individual entry consolidation |
| `AiCompoundLearningMaintenanceJob` | `ai_orchestration` | Learning decay and maintenance |
| `AiDedupLearningJob` | `ai_orchestration` | Learning deduplication |
| `AiPromoteLearningJob` | `ai_orchestration` | Learning promotion to shared |
| `AiSharedKnowledgeMaintenanceJob` | `ai_orchestration` | Shared knowledge quality maintenance |
| `AiKnowledgeDocSyncJob` | `ai_orchestration` | Knowledge → doc sync |
| `AiKnowledgeGraphMaintenanceJob` | `ai_orchestration` | Graph maintenance |
| `AiUpdateGraphNodeJob` | `ai_orchestration` | Graph node updates |
| `AiSkillSyncJob` | `ai_orchestration` | Skill synchronization |
| `AiSkillConflictCheckJob` | `ai_orchestration` | Skill conflict detection |
| `AiSkillLifecycleMaintenanceJob` | `ai_orchestration` | Skill decay and re-embedding |
| `AiToolDiscoveryIndexJob` | `ai_orchestration` | Tool discovery indexing |
| `AiToolHealthCheckJob` | `ai_orchestration` | Tool health checks |
| `AiDiscoveryScanJob` | `ai_orchestration` | Agent discovery scanning |
| `AiProviderHealthCheckJob` | `ai_orchestration` | Provider health monitoring |
| `AiProviderModelSyncJob` | `ai_orchestration` | Provider model sync |
| `AiPricingSyncJob` | `ai_orchestration` | Model pricing sync |
| `AiTrustDecayJob` | `ai_orchestration` | Agent trust score decay |
| `AiContextCompressionJob` | `ai_orchestration` | Context compression |
| `AiContextRotDetectionJob` | `ai_orchestration` | Stale context detection |
| `AiGuardrailEvaluationJob` | `ai_orchestration` | Safety guardrail evaluation |
| `AiMonitoringAnalysisJob` | `ai_orchestration` | AI usage analysis |
| `AiMonitoringHealthCheckJob` | `ai_orchestration` | AI health monitoring |
| `AiPredictiveMonitorJob` | `ai_orchestration` | Predictive monitoring |
| `AiNotificationDigestJob` | `ai_orchestration` | AI notification digest |
| `AiReviewAnalysisJob` | `ai_orchestration` | Review analysis |
| `AiTaskReviewProcessJob` | `ai_orchestration` | Task review processing |
| `AiTeamMessageCleanupJob` | `ai_orchestration` | Team message cleanup |
| `AiTeamOptimizeJob` | `ai_orchestration` | Team optimization |
| `AiTemplateUpdateJob` | `ai_orchestration` | Template updates |
| `AiTrajectoryBuildJob` | `ai_orchestration` | Execution trajectory building |
| `AiA2aExternalTaskJob` | `ai_agents` | A2A external task handling |
| `AiA2aTaskExecutionJob` | `ai_agents` | A2A task execution |
| `AiBudgetReconciliationJob` | `ai_orchestration` | Cost budget reconciliation |
| `AiBudgetRolloverJob` | `ai_orchestration` | Monthly budget rollover |
| `AiContainerAgentJob` | `ai_agents` | Containerized agent execution |
| `AiExecutionCancellationJob` | `ai_cancellations` | Fast execution cancellation |
| `AiExecutionTimeoutCleanupJob` | `ai_orchestration` | Timeout cleanup |
| `AiWebhookDeliveryJob` | `ai_orchestration` | AI webhook delivery |
| `AiWorkflowAnalyticsCacheWarmupJob` | `ai_workflow_health` | Analytics cache warmup |
| `AiWorkflowCostMonitoringJob` | `ai_workflow_health` | Workflow cost monitoring |
| `AiWorkflowHealthMonitoringJob` | `ai_workflow_health` | Workflow health checks |
| `AiWorkflowMonthlyCleanupJob` | `ai_workflows` | Monthly workflow cleanup |
| `AiWorkflowScheduleJob` | `ai_workflow_schedules` | Scheduled workflow triggers |
| `AiWorkflowWeeklyReportJob` | `ai_workflows` | Weekly workflow reports |
| `AiWorkspaceResponseJob` | `ai_conversations` | Workspace response handling |
| `AiWorkflow::ApprovalExpiryJob` | `ai_workflows` | Approval expiration |
| `AiWorkflow::ApprovalNotificationJob` | `ai_workflows` | Approval notifications |

### Analytics (3 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Analytics::LiveMetricsJob` | `analytics` | Real-time metrics updates |
| `Analytics::MetricsAggregationJob` | `analytics` | Periodic metrics aggregation |
| `Analytics::RecalculateAnalyticsJob` | `analytics` | Full analytics recalculation |

### Compliance (4 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Compliance::AccountTerminationJob` | `compliance` | GDPR account termination |
| `Compliance::DataDeletionJob` | `compliance` | Right to be forgotten |
| `Compliance::DataExportJob` | `compliance` | Data portability export |
| `Compliance::DataRetentionEnforcementJob` | `compliance` | Retention policy enforcement |

### DevOps (9 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Devops::ApprovalExpiryJob` | `devops_high` | Deployment approval expiry |
| `Devops::ApprovalNotificationJob` | `devops_high` | Deployment approval notification |
| `Devops::ClaudeInvokeJob` | `devops_default` | Claude Code invocation |
| `Devops::DeploymentJob` | `devops_high` | Deployment execution |
| `Devops::ProviderSyncJob` | `devops_default` | Provider synchronization |
| `Devops::ScheduleTriggerJob` | `devops_default` | Scheduled pipeline triggers |
| `Devops::SecurityScanJob` | `devops_default` | Security scanning |
| `Devops::StepExecutionJob` | `devops_default` | Pipeline step execution |
| `Devops::WebhookHandlerJob` | `devops_webhooks` | DevOps webhook processing |

### Docker (3 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Docker::EventCleanupJob` | `maintenance` | Docker event cleanup |
| `Docker::HealthCheckJob` | `maintenance` | Docker host health checks |
| `Docker::HostSyncJob` | `maintenance` | Docker host synchronization |

### Git (9 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Git::CredentialSetupJob` | `devops_default` | Git credential provisioning |
| `Git::JobLogsSyncJob` | `devops_default` | Pipeline job log sync |
| `Git::PipelineApprovalExpiryJob` | `devops_default` | Pipeline approval timeout |
| `Git::PipelineSyncJob` | `devops_default` | Pipeline state sync |
| `Git::RepositorySyncJob` | `devops_default` | Repository metadata sync |
| `Git::RunnerHealthCheckJob` | `devops_default` | Runner health monitoring |
| `Git::RunnerSyncJob` | `devops_default` | Runner state sync |
| `Git::ScheduledPipelineJob` | `devops_default` | Cron-triggered pipelines |
| `Git::WebhookProcessingJob` | `devops_webhooks` | Git webhook processing |

### MCP (10 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Mcp::McpDatabaseExecutionJob` | `mcp` | Database node execution |
| `Mcp::McpEmailExecutionJob` | `mcp` | Email node execution |
| `Mcp::McpFileExecutionJob` | `mcp` | File operation execution |
| `Mcp::McpNotificationExecutionJob` | `mcp` | Notification execution |
| `Mcp::McpServerConnectionJob` | `mcp` | MCP server connection |
| `Mcp::McpServerHealthCheckJob` | `mcp` | Server health monitoring |
| `Mcp::McpToolCacheRefreshJob` | `mcp` | Tool cache refresh |
| `Mcp::McpToolDiscoveryJob` | `mcp` | Tool discovery |
| `Mcp::McpToolExecutionJob` | `mcp` | Tool execution |
| `Mcp::McpWorkflowResumeJob` | `mcp` | Workflow resume after pause |

### Notifications (6 jobs)

| Job | Queue | Description |
|-----|-------|-------------|
| `Notifications::BulkEmailJob` | `email` | Bulk email delivery |
| `Notifications::EmailDeliveryJob` | `email` | Individual email delivery |
| `Notifications::PushNotificationJob` | `notifications` | Push notification delivery |
| `Notifications::ReviewNotificationJob` | `notifications` | Review notifications |
| `Notifications::SmsDeliveryJob` | `notifications` | SMS delivery |
| `Notifications::TransactionalEmailJob` | `email` | Transactional email |

### Other Categories

| Category | Jobs | Queue | Description |
|----------|------|-------|-------------|
| File Processing | 1 | `file_processing` | Virus scanning |
| Integrations | 3 | `integrations` | Execution, health, credential rotation |
| Maintenance | 5 | `maintenance` | Database backup/restore, scheduled tasks |
| Marketing | 4 | `marketing` | Campaigns, email batches, social media |
| Reports | 2 | `reports` | Report generation, scheduled reports |
| Services | 5 | `services` | Health checks, service discovery, config |
| Swarm | 5 | `maintenance` | Docker Swarm cluster management |
| Webhooks | 6 | `webhooks` | Stripe/PayPal webhook processing, delivery |

---

## Queue Configuration

32 queues with weighted priorities (from `worker/config/sidekiq.yml`):

| Priority | Queues |
|----------|--------|
| **3 (Critical)** | `critical`, `high`, `workflow_high_priority`, `subscription_lifecycle`, `ai_cancellations`, `devops_high` |
| **2 (Standard)** | `ai_workflows`, `ai_agents`, `ai_conversations`, `ai_execution`, `ai_orchestration`, `ai_workflow_health`, `ai_workflow_schedules`, `ai_workflow_nodes`, `ai_testing`, `devops_default`, `devops_webhooks`, `file_processing`, `services`, `billing`, `billing_scheduler`, `compliance`, `email`, `reports`, `integrations`, `mcp` |
| **1 (Low)** | `notifications`, `analytics`, `schedules`, `webhooks`, `maintenance`, `default` |

### Configuration

```yaml
concurrency: 5  # Default, override with WORKER_CONCURRENCY env var
timeout: 300    # 5 minutes global timeout
redis: redis://localhost:6379/1
```

Jobs requiring longer timeouts use circuit breakers:
- AI workflows: 600s (`with_workflow_execution_circuit_breaker`)
- AI providers: 600s (`with_ai_provider_circuit_breaker`)
- Backend API: 120s (`with_backend_api_circuit_breaker`)

---

## Service Management

```bash
# Start/stop worker
sudo systemctl start powernode-worker@default
sudo systemctl stop powernode-worker@default

# View worker logs
journalctl -u powernode-worker@default -f

# Sidekiq Web dashboard
sudo systemctl start powernode-worker-web@default
# Access at http://localhost:4567

# Add high-concurrency AI worker
sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy
# Edit /etc/powernode/worker-ai-heavy.conf → WORKER_CONCURRENCY=15
```

---

## Scheduled Jobs (sidekiq-scheduler)

All cron schedules are defined in `worker/config/sidekiq.yml`.

| Schedule | Job | Queue | Description |
|----------|-----|-------|-------------|
| Every minute | `Docker::HostSyncJob` | `devops_default` | Sync Docker host state |
| Every minute | `Swarm::ClusterSyncJob` | `devops_default` | Sync Swarm cluster state |
| Every 5m | `Docker::HealthCheckJob` | `devops_default` | Docker host health |
| Every 5m | `Swarm::HealthCheckJob` | `devops_default` | Swarm cluster health |
| Every 5m | `Git::RunnerHealthCheckJob` | `devops_default` | Git runner health |
| Every 10m | `AiProviderHealthCheckJob` | `ai_workflow_health` | AI provider health |
| Hourly :00 | `Devops::ApprovalExpiryJob` | `default` | Expire DevOps approvals |
| Hourly :15 | `AiWorkflow::ApprovalExpiryJob` | `default` | Expire AI workflow approvals |
| Hourly | `AiBudgetRolloverJob` | `ai_orchestration` | Roll over expired budgets |
| Every 6h | `AiProviderModelSyncJob` | `ai_workflow_health` | Sync provider models |
| Every 6h | `Compliance::AccountTerminationJob` | `compliance` | Process account terminations |
| Every 6h | `ChatSessionCleanupJob` | `maintenance` | Clean stale chat sessions |
| Daily 1 AM | `AiPricingSyncJob` | `ai_orchestration` | Sync model pricing |
| Daily 2 AM | `AiTrustDecayJob` | `ai_orchestration` | Decay idle agent trust scores |
| Daily 2 AM | `Maintenance::ScheduledBackupJob` (full) | `maintenance` | Full database backup |
| Daily 2 AM | `Compliance::DataRetentionEnforcementJob` | `compliance` | Enforce retention policies |
| Daily 3:30 AM | `AiMemoryPoolCleanupJob` | `ai_orchestration` | Clean expired memory pools |
| Daily 3:45 AM | `AiCompoundLearningMaintenanceJob` | `ai_orchestration` | Learning decay/promotion |
| Daily 4:00 AM | `AiMemoryMaintenanceJob` | `ai_orchestration` | Memory consolidation, decay, rot detection |
| Daily 4:00 AM | `AiTeamMessageCleanupJob` | `ai_orchestration` | Team message cleanup |
| Daily 4:00 AM | `AiBudgetReconciliationJob` | `ai_orchestration` | Budget reconciliation |
| Daily 4:00 AM | `Maintenance::BackupCleanupJob` | `maintenance` | Remove expired backups |
| Daily 4:15 AM | `AiSkillLifecycleMaintenanceJob` (daily) | `ai_orchestration` | Skill conflict scan, stale decay |
| Daily 4:30 AM | `AiSharedKnowledgeMaintenanceJob` | `ai_orchestration` | Knowledge quality maintenance |
| Daily 4:45 AM | `AiKnowledgeGraphMaintenanceJob` | `ai_orchestration` | Graph confidence decay |
| Daily 5:00 AM | `Swarm::EventCleanupJob` | `maintenance` | Clean Swarm events |
| Daily 5:15 AM | `Docker::EventCleanupJob` | `maintenance` | Clean Docker events |
| Daily 5:30 AM | `AiKnowledgeDocSyncJob` | `maintenance` | Sync knowledge to markdown |
| Sunday 3 AM | `Maintenance::ScheduledBackupJob` (schema) | `maintenance` | Weekly schema backup |
| Sunday 5 AM | `AiSkillLifecycleMaintenanceJob` (weekly) | `ai_orchestration` | Prompt refinement, gap detection |
| 1st of month 3 AM | `AiSkillLifecycleMaintenanceJob` (monthly) | `ai_orchestration` | Re-embed skills, health report |

---

## Worker Services (41 files)

The worker has its own service layer for processing logic.

### API Clients

| Service | Purpose |
|---------|---------|
| `BackendApiClient` | Primary server HTTP client (all CRUD, AI, DevOps) |
| `ApiClient` | Base HTTP client for analytics/reporting |
| `WebAuthApiClient` | Sidekiq Web auth (separate circuit breaker) |
| `LlmProxyClient` | AI model proxy through server LLM endpoints |

### Core Services

| Service | Purpose |
|---------|---------|
| `BaseWorkerService` | Base class for worker services |
| `WorkerJwt` | JWT token generation for service auth |
| `PrimaryServiceAuth` | Standard service authentication |
| `SystemWorkerAuth` | Elevated system-level auth |
| `McpSecurityService` | MCP credential decryption |

### Domain Services

| Service | Purpose |
|---------|---------|
| `EmailDeliveryWorkerService` | Email delivery |
| `EmailConfigurationService` | Email provider config |
| `AnalyticsWorkerService` | Analytics processing |
| `AnalyticsNotificationService` | Analytics-based notifications |
| `FileProcessingService` | File upload processing |
| `PdfReportWorkerService` | PDF report generation |
| `FirebaseService` | Push notifications (Firebase) |
| `TwilioService` | SMS delivery (Twilio) |
| `AiWorkflowErrorTrackingService` | AI error classification |

### DevOps Services (16 files)

| Service | Purpose |
|---------|---------|
| `Devops::DeploymentService` | Deployment execution |
| `Devops::GitOperationsService` | Git operations |
| `Devops::GitProviders::BaseProvider` | Base Git provider |
| `Devops::GitProviders::GiteaProvider` | Gitea API client |
| `Devops::GitProviders::GithubProvider` | GitHub API client |
| `Devops::GitProviders::GitlabProvider` | GitLab API client |
| `Devops::GitProviders::ProviderFactory` | Provider instantiation |
| `Devops::GitProviders::WebhookNormalizer` | Cross-provider webhook normalization |
| `Devops::StepHandlers::*` (12) | Pipeline step handlers: checkout, deploy, create PR, post comment, run command, Claude execute, policy gate, SBOM, vulnerability scan, sign artifact, upload artifact, generic |

---

## Job Pattern

All jobs inherit from `BaseJob`:

```ruby
class MyJob < BaseJob
  sidekiq_options queue: 'default', retry: 3

  def execute(*args)
    # Implementation — communicates with server via HTTP API
    result = api_client.get("/api/v1/resource/#{args[0]}")
    api_client.post("/api/v1/resource", { data: result })
  end
end
```

Shared concerns in `worker/app/jobs/concerns/` (12 files) provide:
- `ai_jobs_concern.rb` — Common AI job helpers
- `ai_llm_proxy_concern.rb` — LLM proxy integration
- `ai_cost_calculation_concern.rb` — AI cost tracking
- `chat_streaming_concern.rb` — Chat response streaming
- `health_check_steps_concern.rb` / `health_data_fetchers_concern.rb` — Health check helpers
- `metrics_tracking.rb` — Metrics collection
- `reports/*.rb` — CSV, PDF, XLSX report generation concerns

---

## See Also

- [Worker Architecture Overview](WORKER_ARCHITECTURE_OVERVIEW.md) — Isolation model, API clients, BaseJob internals, circuit breakers
- [CI/CD Architecture](CI_CD_ARCHITECTURE.md) — DevOps pipeline execution
- [File Processing Architecture](FILE_PROCESSING_ARCHITECTURE.md) — File upload processing
