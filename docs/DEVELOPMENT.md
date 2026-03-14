# Development Guide

Development reference for the Powernode platform.

## Quick Start

### Recommended: Systemd Services

```bash
# First-time setup (installs units and config to /etc/powernode/)
sudo scripts/systemd/powernode-installer.sh install

# Start all services
sudo systemctl start powernode.target

# Check service status
sudo scripts/systemd/powernode-installer.sh status

# Stop all services
sudo systemctl stop powernode.target

# Restart a specific service
sudo systemctl restart powernode-backend@default
```

### Individual Service Control

```bash
# Start/stop/restart individual services
sudo systemctl start powernode-backend@default
sudo systemctl start powernode-worker@default
sudo systemctl start powernode-worker-web@default
sudo systemctl start powernode-frontend@default

# View logs for a specific service
journalctl -u powernode-backend@default -f
journalctl -u powernode-worker@default -f
journalctl -u powernode-frontend@default -f

# View all Powernode logs
journalctl -u 'powernode-*' --since "5 min ago"
```

---

## Platform Architecture

### At a Glance

| Component | Technology | Location |
|-----------|------------|----------|
| Backend API | Rails 8 (API-only) | `server/` |
| Frontend | React + TypeScript + Tailwind | `frontend/` |
| Worker | Sidekiq (standalone) | `worker/` |
| Business | Git submodule | `extensions/business/` |
| Database | PostgreSQL (UUIDv7 PKs) | 396 tables |
| Cache/Queues | Redis | DB 0 (cache), DB 1 (Sidekiq) |

### Codebase Scale

| Layer | Count | Location |
|-------|-------|----------|
| Models | 340 | `server/app/models/` |
| Controllers | 311 | `server/app/controllers/` |
| Services | 634 | `server/app/services/` |
| Worker Jobs | 220 | `worker/app/jobs/` |
| WebSocket Channels | 17 | `server/app/channels/` |
| Database Tables | 396 | `server/db/migrate/` |
| MCP Tools | 194 | `server/app/services/ai/tools/` |
| Permissions | 543 | `server/db/seeds/` |
| Scripts | 48 | `scripts/` |

---

## Model Namespaces (10)

| Namespace | Models | Description |
|-----------|--------|-------------|
| `Account` | 3 | Multi-tenant account hierarchy, delegations |
| `Ai` | 145 | Agents, teams, workflows, memory, knowledge graph, providers, skills, tools, autonomy, observations, AGI (experience replay, goal decomposition, stigmergic coordination, pressure fields, governance, self-improvement) |
| `Chat` | 5 | Conversations, messages, attachments, sessions |
| `Database` | 2 | Database connections, query history |
| `DataManagement` | 3 | Data sanitization, retention policies |
| `Devops` | 43 | Pipelines, runners, repositories, deployments, Docker, Git providers |
| `FileManagement` | 7 | File uploads, storage backends, virus scanning |
| `KnowledgeBase` | 8 | Articles, categories, tags, comments, attachments |
| `Monitoring` | 2 | Health checks, service status |
| `Shared` | 1 | Feature gate service, shared utilities |
| Top-level | 120+ | User, Role, Permission, Plan, Subscription, Invoice, Payment, etc. |

---

## Controller Namespaces (15)

All controllers are under `Api::V1`.

| Namespace | Controllers | Scope |
|-----------|-------------|-------|
| `admin/` | Admin panel endpoints | Account/system administration |
| `ai/` | AI feature endpoints | Agents, teams, workflows, memory, knowledge |
| `ai_workflows/` | Workflow management | Workflow CRUD and execution |
| `auth/` | Authentication | Login, register, password, 2FA, OAuth |
| `chat/` | Chat endpoints | Conversations, messages, streaming |
| `devops/` | DevOps endpoints | Pipelines, runners, deployments |
| `git/` | Git operations | Repositories, providers, webhooks |
| `integrations/` | Third-party | External service connectors |
| `internal/` | Internal APIs | Worker-to-server communication |
| `kb/` | Knowledge base | Articles, categories, tags |
| `mcp/` | MCP protocol | Tool execution, server management |
| `oauth/` | OAuth provider | Token grants, application management |
| `public/` | Public endpoints | Unauthenticated access |
| `webhooks/` | Webhook receivers | Stripe, PayPal, Git providers |
| `worker/` | Worker API | Job dispatch, status reporting |

Plus 40 top-level controllers (accounts, users, plans, subscriptions, etc.).

---

## Service Namespaces (22+)

| Namespace | Files | Description |
|-----------|-------|-------------|
| `ai/` | 356 | Agent orchestration, providers, workflows, cost optimization, memory, knowledge, autonomy, AGI |
| `mcp/` | 101 | Node executors (50+), orchestration, conditional evaluation |
| `devops/` | 45 | CI/CD, Git operations, deployment, registry, Docker |
| `a2a/` | 17 | Agent-to-Agent protocol services |
| `chat/` | 10 | Conversation management, context building |
| `security/` | 11 | Authentication, authorization, encryption |
| `orchestration/` | 8 | Workflow orchestration coordination |
| `cost_optimization/` | 7 | Budget management, cost analysis, recommendations |
| `storage_providers/` | 7 | S3, GCS, Local, NFS, SMB storage backends |
| `concerns/` | 7 | Shared service concerns (circuit breaker, broadcasting) |
| `provider_testing/` | 6 | Connection testing, health checks, load testing |
| `shared/` | 4 | Cross-cutting utilities |
| `billing/` | 2 | Subscription lifecycle, payment processing |
| `data_management/` | 2 | Data sanitization, retention |
| `monitoring/` | 2 | Health monitoring, metrics |
| `permissions/` | 2 | Permission management |
| `rate_limiting/` | 2 | Request rate limiting |
| `audit/` | 2 | Audit log services |
| `admin/` | 2 | Admin panel services |
| `auth/` | 1 | Authentication services |
| `accounts/` | 1 | Account management |
| Others | 5 | Analytics, notifications, marketplace |

---

## AI Subsystem Map

The AI platform is the largest subsystem (356 services, 145 models).

### Core Systems

| System | Purpose | Key Files |
|--------|---------|-----------|
| **Agent Orchestration** | Execute AI agents with provider fallback | `ai/agent_orchestration_service.rb` |
| **Code Factory** | Automated code generation pipeline (PRD → tasks → code → review) | `ai/code_factory/` |
| **Ralph Loops** | Mission lifecycle (analyze → plan → execute → test → review → deploy → merge) | `ai_mission_*_job.rb` |
| **AGUI (Agent GUI)** | Chat-based agent interaction with streaming | `ai_conversation_channel.rb`, `chat/` |
| **Model Router** | Load balancing, circuit breaking, cost optimization across providers | `ai/provider_load_balancer_service.rb` |
| **Knowledge Graph** | Entity-relationship graph with multi-hop reasoning | `ai/knowledge_graph/` |
| **Compound Learning** | Pattern/discovery/best-practice learning with decay and reinforcement | `ai/compound_learning/` |
| **Memory Tiers** | STM → Working → LTM with consolidation and decay | `ai/memory/` |
| **MCP Protocol** | 194-tool Model Context Protocol for agent capabilities | `mcp/` |
| **A2A Protocol** | Agent-to-Agent communication and task delegation | `a2a/` |
| **Skill Registry** | Reusable agent capabilities with lifecycle management | `ai/skills/` |
| **Team Execution** | Multi-agent orchestration with role-based coordination | `ai/team_execution/` |
| **Agent Autonomy** | Kill switch, goals, proposals, escalations, observation pipeline, intervention policies | `ai/autonomy/` |
| **Experience Replay** | Execution history analysis and pattern extraction | `ai/agi/` |
| **Goal Decomposition** | Hierarchical goal breakdown and planning | `ai/agi/` |
| **Stigmergic Coordination** | Environment-mediated multi-agent coordination | `ai/agi/` |
| **Pressure Fields** | Gradient-based resource allocation and task prioritization | `ai/agi/` |
| **Governance** | Monitoring, collusion detection, behavioral analysis | `ai/agi/` |
| **Self-Improvement** | Autonomous capability enhancement and reflexion | `ai/agi/` |
| **Self-Healing** | Automated error recovery and system repair | `ai/agi/` |

### Workflow System

50 node executors in `mcp/node_executors/`:
- **Control flow**: start, end, condition, loop, split, merge, delay, scheduler
- **AI**: ai_agent, sub_workflow
- **Integration**: api_call, webhook, notification, email, database, file operations
- **Content**: page and KB article CRUD
- **DevOps**: CI/CD, Git operations, deployment
- **MCP**: tool, prompt, resource execution

---

## Frontend Feature Modules (10)

| Module | Path | Description |
|--------|------|-------------|
| `account` | `frontend/src/features/account/` | Account settings, profile management |
| `admin` | `frontend/src/features/admin/` | Admin panel, system management |
| `ai` | `frontend/src/features/ai/` | AI agents, workflows, chat, knowledge |
| `business` | `frontend/src/features/business/` | Billing, subscriptions, invoices |
| `content` | `frontend/src/features/content/` | CMS pages, KB articles |
| `delegations` | `frontend/src/features/delegations/` | Cross-account access delegation |
| `developer` | `frontend/src/features/developer/` | API keys, webhooks, developer tools |
| `devops` | `frontend/src/features/devops/` | Pipelines, repositories, deployments |
| `missions` | `frontend/src/features/missions/` | AI mission control (Ralph) |
| `privacy` | `frontend/src/features/privacy/` | GDPR, data export, consent |

---

## Worker Job Categories (220 jobs)

The worker is a standalone Sidekiq process that communicates with the server via HTTP API.

| Category | Jobs | Queue | Description |
|----------|------|-------|-------------|
| AI (top-level) | 74 | `ai_agents`, `ai_workflows`, `ai_orchestration` | Agent execution, workflows, memory, knowledge, missions |
| AGI | 13 | `ai_orchestration`, `ai_agents` | Experience replay, goal decomposition, stigmergic coordination, pressure fields, governance, self-improvement, self-healing |
| AI Workflow | 2 | `ai_workflows` | Approval expiry, notifications |
| Analytics | 3 | `analytics` | Metrics aggregation, live metrics, recalculation |
| Compliance | 4 | `compliance` | GDPR data deletion, export, retention, account termination |
| DevOps | 9 | `devops_default`, `devops_high` | Pipeline steps, deployment, sync, approvals |
| Docker | 3 | `maintenance` | Health checks, host sync, event cleanup |
| File Processing | 1 | `file_processing` | Virus scanning |
| Git | 9 | `devops_default` | Repository sync, pipeline sync, webhooks, runners |
| Integrations | 3 | `integrations` | Execution, health checks, credential rotation |
| Maintenance | 5 | `maintenance` | Database backup/restore, scheduled tasks, cleanup |
| Marketing | 4 | `marketing` | Campaigns, email batches, social media |
| MCP | 10 | `mcp` | Tool execution, server health, discovery, cache |
| Notifications | 6 | `notifications`, `email` | Email, SMS, push, bulk, transactional |
| Reports | 2 | `reports` | Report generation, scheduled reports |
| Services | 5 | `services` | Health checks, service discovery, config generation |
| Swarm | 5 | `maintenance` | Docker Swarm cluster sync, stack deploy, health |
| Trading | 9 | `trading` | Strategy execution, portfolio updates, risk monitoring, evolution |
| Webhooks | 6 | `webhooks` | Stripe/PayPal processing, delivery, retry |

33 queues configured in `worker/config/sidekiq.yml` with weighted priorities (1-3).

---

## WebSocket Channels (17)

All channels use ActionCable with JWT authentication.

| Channel | Subscription Params | Purpose |
|---------|-------------------|---------|
| `AiAgentExecutionChannel` | `execution_id` | Agent execution monitoring |
| `AiConversationChannel` | `conversation_id` | AI chat messaging and streaming |
| `AiOrchestrationChannel` | `type`, `id` | Unified AI orchestration events |
| `AiStreamingChannel` | `execution_id` or `conversation_id` | Token-by-token AI response streaming |
| `AiWorkflowMonitoringChannel` | `workflow_id` (optional) | Workflow monitoring and analytics |
| `AiWorkflowOrchestrationChannel` | — | Account-level workflow events |
| `AnalyticsChannel` | `account_id` | Real-time analytics updates |
| `CodeFactoryChannel` | `type`, `id` | Code Factory run updates and reviews |
| `CustomerChannel` | `account_id` | Customer data updates (admin) |
| `DevopsPipelineChannel` | `account_id`, `pipeline_id` | CI/CD pipeline status |
| `GitJobLogsChannel` | `repository_id`, `pipeline_id`, `job_id` | Live pipeline job log streaming |
| `McpChannel` | — | MCP protocol WebSocket transport |
| `MissionChannel` | `type`, `id` | Mission (Ralph) progress updates |
| `NotificationChannel` | `account_id` | Real-time notifications |
| `SubscriptionChannel` | `account_id` | Subscription status changes |
| `TeamChannelChannel` | `channel_id` | Team channel messaging |
| `TeamExecutionChannel` | `team_id` | Multi-agent team execution monitoring |

---

## Network Access

### Local Development

| Service | URL | Port |
|---------|-----|------|
| Backend API | http://localhost:3000 | 3000 |
| Frontend | http://localhost:3001 | 3001 |
| Sidekiq Web | http://localhost:4567 | 4567 |

### Domain Access

Add to `/etc/hosts`:
```
127.0.0.1 powernode.dev
```

- **Backend API**: http://powernode.dev:3000
- **Frontend**: http://powernode.dev:3001

---

## Configuration

### Service Configuration

| Service | Config File | Key Settings |
|---------|-------------|--------------|
| Global | `/etc/powernode/powernode.conf` | Base path, RVM/nvm paths, Ruby/Node versions |
| Backend | `/etc/powernode/backend-default.conf` | Port, binding, CORS |
| Worker | `/etc/powernode/worker-default.conf` | Redis URL, concurrency |
| Worker Web | `/etc/powernode/worker-web-default.conf` | Dashboard port |
| Frontend | `/etc/powernode/frontend-default.conf` | API URL, binding |

### Multi-Instance Support

```bash
# Add a second backend instance
sudo scripts/systemd/powernode-installer.sh add-instance backend api2
# Edit /etc/powernode/backend-api2.conf → set PORT=3002
sudo systemctl enable --now powernode-backend@api2

# Add a high-concurrency worker for AI workloads
sudo scripts/systemd/powernode-installer.sh add-instance worker ai-heavy
# Edit /etc/powernode/worker-ai-heavy.conf → set WORKER_CONCURRENCY=15
sudo systemctl enable --now powernode-worker@ai-heavy
```

---

## Development Commands

```bash
# Database operations
cd server && rails db:migrate db:seed

# Backend tests
cd server && bundle exec rspec --format progress

# Frontend tests
cd frontend && CI=true npm test

# Type checking
cd frontend && npm run typecheck

# Pattern validation
./scripts/quick-pattern-check.sh

# Full validation (specs + TS + patterns)
./scripts/validate.sh
```

---

## Troubleshooting

### Services Won't Start

```bash
journalctl -u powernode-backend@default --since "5 min ago" --no-pager
sudo systemctl reset-failed 'powernode-*'
sudo systemctl start powernode.target
```

### Port Conflicts

```bash
ss -tlnp | grep :3000
# Change ports in /etc/powernode/backend-default.conf
sudo systemctl daemon-reload && sudo systemctl restart powernode-backend@default
```

### CORS Issues

- Backend CORS is configured for localhost and powernode.dev domains
- Check browser developer tools for specific errors
- Ensure the API URL in frontend matches your setup

---

## Reference

- [CLAUDE.md](../CLAUDE.md) — Service management, testing, code quality, git workflow
- [API Response Standards](platform/API_RESPONSE_STANDARDS.md) — Unified API format
- [Permission System](platform/PERMISSION_SYSTEM_REFERENCE.md) — Access control reference
- [Theme System](platform/THEME_SYSTEM_REFERENCE.md) — Frontend styling guide
- [Backend Services](backend/BACKEND_SERVICE_ARCHITECTURE.md) — Service layer architecture
- [WebSocket Architecture](platform/WEBSOCKET_AND_REALTIME.md) — Real-time communication
