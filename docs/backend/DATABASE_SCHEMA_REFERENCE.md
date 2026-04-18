# Database Schema Reference

423 tables across 10 model namespaces, all using UUIDv7 primary keys on PostgreSQL.

---

## Model Namespaces

### Top-Level Models (~120)

Core platform models not in a namespace:

| Model | Description |
|-------|-------------|
| `User` | Platform users with authentication and permissions |
| `Account` | Multi-tenant account (one per organization) |
| `Role` | Permission grouping (system.admin, account.manager, etc.) |
| `Permission` | Individual permission (543 total) |
| `RolePermission` | Role-to-permission join table |
| `Plan` | Subscription plan with features/limits |
| `Subscription` | Account subscription (AASM state machine: 8 states) |
| `Invoice` | Billing invoices with line items |
| `Payment` | Payment records (Stripe, PayPal) |
| `Invitation` | User invitations with email workflow |
| `AuditLog` | Comprehensive activity tracking |
| `Notification` | User notifications |
| `ApiKey` / `ApiKeyUsage` | API key management and usage tracking |
| `AdminSetting` | System configuration key-value store |
| `BlacklistedToken` / `JwtBlacklist` | Token revocation |
| `PasswordHistory` | Password reuse prevention |
| `Page` | CMS content pages |
| `OauthApplication` | OAuth2 provider applications |
| `ImpersonationSession` | Admin impersonation tracking |
| `McpServer` / `McpTool` / `McpSession` / `McpToolExecution` | MCP protocol infrastructure |
| `CommunityAgent` / `CommunityAgentRating` / `CommunityAgentReport` | Agent marketplace |
| `ExternalAgent` / `FederationPartner` | A2A external agents |
| `ReportRequest` | Async report generation |
| `EmailDelivery` | Email delivery tracking |
| `BackgroundJob` | Job status tracking |

### Ai:: Namespace (132 models)

The largest namespace — covers the entire AI platform.

| Area | Models | Examples |
|------|--------|----------|
| Agents | 15+ | `Agent`, `AgentExecution`, `AgentExecutionStep`, `AgentCapability`, `AgentConfiguration` |
| Teams | 10+ | `AgentTeam`, `AgentTeamMember`, `TeamExecution`, `TeamChannel`, `TeamMessage` |
| Missions | 2 | `Mission`, `MissionApproval` |
| Ralph | 5+ | `RalphLoop`, `RalphTask`, `RalphIteration`, `RalphLearning` |
| Providers | 8+ | `Provider`, `ProviderModel`, `ModelRoutingRule`, `ProviderHealthCheck` |
| Data Sources | 2 | `DataSource`, `DataSourceCredential` |
| Knowledge | 12+ | `KnowledgeGraphNode`, `KnowledgeGraphEdge`, `CompoundLearning`, `SharedKnowledge` |
| Memory | 8+ | `MemoryEntry`, `MemoryPool`, `ContextEntry`, `ContextGroup`, `AgentShortTermMemory` |
| Skills | 5+ | `Skill`, `SkillExecution`, `AgentSkill`, `SkillMutation`, `SkillChallenge` |
| Tools | 5+ | `Tool`, `ToolExecution`, `ToolCategory` |
| Code Factory | 10+ | `CodeFactoryRun`, `CodeFactoryContract`, `CodeFactoryTask`, `RiskContract`, `ReviewState` |
| Autonomy | 10+ | `AgentTrustScore`, `DelegationPolicy`, `AgentPrivilegePolicy`, `BehavioralFingerprint`, `KillSwitchEvent`, `AgentGoal`, `AgentObservation`, `AgentProposal`, `AgentEscalation`, `InterventionPolicy`, `AgentFeedback` |
| Conversations | 5+ | `Conversation`, `Message`, `Attachment` |
| Monitoring | 5+ | `CostTracking`, `UsageMetric`, `BudgetAlert` |
| Templates | 5+ | `SystemPromptTemplate` |
| Trust & Safety | 5+ | `TrustScore`, `Guardrail`, `GuardrailEvaluation` |
| Worktree | 5+ | `Worktree`, `WorktreeSession`, `WorktreeEvent` |

### Devops:: Namespace (41 models)

| Area | Models | Examples |
|------|--------|----------|
| Pipelines | 10+ | `Pipeline`, `PipelineRun`, `PipelineStep`, `PipelineStepExecution` |
| Git | 10+ | `GitProvider`, `GitRepository`, `GitRunner`, `GitPipelineJob` |
| Docker | 8+ | `DockerHost`, `DockerContainer`, `SwarmService`, `SwarmStack` |
| Deployments | 5+ | `Deployment`, `DeploymentTarget`, `DeploymentEnvironment` |
| Templates | 5+ | `IntegrationTemplate`, `ContainerTemplate` |

### KnowledgeBase:: Namespace (8 models)

| Model | Description |
|-------|-------------|
| `Article` | KB articles with Markdown content |
| `Category` | Article categorization |
| `Tag` | Article tagging |
| `ArticleTag` | Article-to-tag join |
| `Comment` | Article comments |
| `Attachment` | Article file attachments |
| `ArticleView` | View tracking |
| `Workflow` | Article workflow states |

### Chat:: Namespace (5 models)

| Model | Description |
|-------|-------------|
| `Conversation` | Chat conversation container |
| `Message` | Individual messages |
| `Attachment` | Message attachments |
| `Session` | Active chat sessions |
| `Participant` | Conversation participants |

### FileManagement:: Namespace (7 models)

| Model | Description |
|-------|-------------|
| `FileUpload` | Uploaded file records |
| `StorageBackend` | Storage provider configuration |
| `FileVersion` | File versioning |
| `FileShare` | Shared file access |
| `VirusScanResult` | Antivirus scan results |
| `FileQuota` | Storage quota tracking |
| `FileAuditLog` | File access audit trail |

### Account:: Namespace (3 models)

| Model | Description |
|-------|-------------|
| `Delegation` | Cross-account access delegation |
| `Setting` | Account-specific settings |
| `Feature` | Account feature flags |

### DataManagement:: Namespace (3 models)

| Model | Description |
|-------|-------------|
| `RetentionPolicy` | Data retention rules |
| `SanitizationRule` | PII sanitization |
| `DataExport` | GDPR data export records |

### Database:: Namespace (2 models)

| Model | Description |
|-------|-------------|
| `Connection` | External database connections |
| `QueryHistory` | Query execution history |

### Monitoring:: Namespace (2 models)

| Model | Description |
|-------|-------------|
| `HealthCheck` | Service health check records |
| `ServiceStatus` | Service availability status |

### Shared:: Namespace (1 model)

| Model | Description |
|-------|-------------|
| `FeatureGate` | Enterprise feature gating |

---

## Key Relationships

```
Account ──┬── User (many) ──── Role (many) ──── Permission (many)
          ├── Subscription (one) ──── Plan
          ├── Ai::Agent (many) ──── Ai::AgentExecution (many)
          ├── Ai::Mission (many) ──── Ai::MissionApproval (many)
          ├── Ai::RalphLoop (many) ──── Ai::RalphTask (many)
          ├── Ai::AgentTeam (many) ──── Ai::AgentTeamMember (many)
          ├── Ai::KnowledgeGraphNode (many) ──── Ai::KnowledgeGraphEdge (many)
          ├── Devops::Pipeline (many) ──── Devops::PipelineRun (many)
          └── Invoice (many) ──── Payment (many)
```

---

## Database Conventions

- **Primary keys**: UUIDv7 (chronologically sortable)
- **Foreign keys**: `t.references` with type `:uuid` (index included automatically)
- **Namespaced FK prefix**: `Ai::` → `ai_`, `Devops::` → `devops_`, `BaaS::` → `baas_`
- **Timestamps**: `created_at`, `updated_at` on all tables
- **Soft delete**: `discarded_at` on applicable models (using Discard gem)
- **JSON columns**: Lambda defaults (`default: -> { {} }`)
- **Vectors**: pgvector with HNSW indexes for embedding columns
