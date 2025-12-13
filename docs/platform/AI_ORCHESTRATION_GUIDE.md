# AI Orchestration Complete Guide

**Version**: 2.0 | **Last Updated**: December 2025 | **Status**: Production Ready

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Core Components](#core-components)
4. [Frontend Migration](#frontend-migration)
5. [Integration Checklist](#integration-checklist)
6. [Learning Paths](#learning-paths)

---

## System Overview

The Powernode AI Orchestration System provides enterprise-grade AI workflow execution, agent management, and multi-provider integration. Following a comprehensive 5-phase redesign, the system achieved:

- **79% controller reduction** (29 → 6 consolidated controllers)
- **56% code reduction** (12,638 → 5,624 lines)
- **100% type coverage** with full TypeScript support
- **Unified API architecture** with consistent patterns

### Key Capabilities

| Feature | Description |
|---------|-------------|
| AI Workflows | Visual workflow builder with 11+ node types |
| AI Agents | Multi-provider support (OpenAI, Anthropic, Ollama) |
| Batch Execution | Execute multiple workflows concurrently |
| Real-time Monitoring | WebSocket-based live updates |
| Circuit Breakers | Resilience patterns for external services |
| Cost Optimization | Track and optimize AI provider costs |

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend Layer                          │
│  React Components → 6 Consolidated API Services             │
│  (agentsApi, workflowsApi, providersApi, monitoringApi,    │
│   analyticsApi, marketplaceApi)                             │
└──────────────────────────┬──────────────────────────────────┘
                           │ RESTful JSON API
┌──────────────────────────▼──────────────────────────────────┐
│                    Backend API Layer                        │
│  6 Consolidated Controllers (Api::V1::Ai namespace)        │
│  • AgentsController      • WorkflowsController             │
│  • ProvidersController   • MonitoringController            │
│  • AnalyticsController   • MarketplaceController           │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                  Service Layer Pattern                      │
│  Root Facade Services → MCP Core Services                   │
│  • AiAgentOrchestrationService → Mcp::WorkflowOrchestrator │
│  • WorkflowRecoveryService → Mcp::WorkflowCheckpointManager│
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│               Worker Service (Sidekiq)                      │
│  • AiWorkflowExecutionJob                                   │
│  • AiWorkflowNodeExecutionJob                               │
│  • AiAgentExecutionJob                                      │
└─────────────────────────────────────────────────────────────┘
```

### Service Layer Pattern

**Root Facade Services** (Public API):
- `AiAgentOrchestrationService` - Main orchestration entry point
- `WorkflowRecoveryService` - Recovery coordination
- `AiErrorRecoveryService` - Error handling coordination

**MCP Core Services** (Implementation):
- `Mcp::WorkflowOrchestrator` - Actual workflow execution engine
- `Mcp::WorkflowCheckpointManager` - Checkpoint/recovery implementation

---

## Core Components

### 1. AI Agents

**Purpose**: Reusable AI components configured for specific tasks

**Database Models**:
```ruby
AiAgent           # Agent configuration and metadata
AiAgentExecution  # Individual execution records
AiConversation    # Conversation sessions
AiMessage         # Conversation messages
```

**Frontend Service**: `agentsApi` from `@/shared/services/ai`

### 2. AI Workflows

**Purpose**: Visual workflow builder for orchestrating multi-step AI processes

**Node Types**:
- `start`, `end` - Entry/exit points
- `ai_agent` - Execute AI agent
- `api_call` - HTTP API requests
- `webhook` - Send webhooks
- `condition` - Conditional branching
- `loop` - Iteration
- `transform` - Data transformation
- `delay` - Timed delays
- `human_approval` - Human-in-the-loop
- `sub_workflow` - Nested workflows
- `merge`, `split` - Path management

**Frontend Service**: `workflowsApi` from `@/shared/services/ai`

### 3. AI Providers

**Purpose**: Manage connections to external AI services

**Supported Providers**:
- OpenAI (GPT-4, GPT-3.5)
- Anthropic (Claude 3 Opus, Sonnet, Haiku)
- Ollama (Local models)
- Custom providers via MCP protocol

**Frontend Service**: `providersApi` from `@/shared/services/ai`

### 4. Monitoring & Analytics

**Purpose**: Real-time system health and performance tracking

**Frontend Services**:
- `monitoringApi` - System dashboard, circuit breakers
- `analyticsApi` - Metrics, cost breakdown

---

## Frontend Migration

### Quick Import Update

```typescript
// OLD - Don't use these anymore
import { aiAgentApi } from '@/shared/services/aiAgentApi';
import { workflowApi } from '@/shared/services/workflowApi';

// NEW - Use consolidated services
import { agentsApi, workflowsApi, providersApi } from '@/shared/services/ai';

// OR use the aiApi convenience object
import { aiApi } from '@/shared/services/ai';
const agents = await aiApi.agents.getAgents();
```

### Service Migration Map

| Old Service | New Service |
|-------------|-------------|
| `aiAgentApi.ts` | `agentsApi` |
| `aiConversationsApi.ts` | `agentsApi.conversations` |
| `aiProviderApi.ts` | `providersApi` |
| `workflowApi.ts` | `workflowsApi` |
| `workflowMonitoringService.ts` | `monitoringApi` |
| `aiMonitoringService.ts` | `monitoringApi` |

### Response Unwrapping

**Before** (manual unwrapping):
```typescript
const response = await workflowApi.getWorkflows(filters, page, perPage);
const workflows = response.data.data.workflows;
const pagination = response.data.data.pagination;
```

**After** (automatic unwrapping):
```typescript
const { items: workflows, pagination } = await workflowsApi.getWorkflows({
  ...filters,
  page,
  per_page: perPage
});
```

### Conversations API Change

Conversations are now nested under agents:

```typescript
// OLD
const messages = await aiConversationsApi.getMessages(conversationId);

// NEW - requires agentId
const messages = await agentsApi.getMessages(agentId, conversationId);
```

---

## Integration Checklist

### Phase 1: Frontend Foundation

- [ ] Verify TypeScript configuration with path aliases
- [ ] Install dependencies: `recharts`, `lucide-react`, `date-fns`
- [ ] Verify shared components exist (Card, Button, Modal, etc.)
- [ ] Configure permissions in backend
- [ ] Add AI Orchestration to navigation
- [ ] Update routing configuration

### Phase 2: Component Integration

- [ ] Install batch execution components
- [ ] Install streaming execution components
- [ ] Install circuit breaker components
- [ ] Install MCP browser components
- [ ] Install validation components
- [ ] Install cost optimization components
- [ ] Verify theme compatibility

### Phase 3: Backend Implementation

- [ ] Create required database tables (UUIDv7 primary keys)
- [ ] Create models with proper structure
- [ ] Create API controllers (55+ endpoints)
- [ ] Configure routes
- [ ] Create service objects
- [ ] Create background jobs (BaseJob pattern)
- [ ] Implement WebSocket channels

### Phase 4: Testing

- [ ] Model tests (90%+ coverage)
- [ ] Controller tests (80%+ coverage)
- [ ] Service tests (85%+ coverage)
- [ ] Integration tests
- [ ] WebSocket integration tests
- [ ] E2E tests (Cypress)

### Phase 5: Production Deployment

- [ ] Configure environment variables
- [ ] Run database migrations
- [ ] Build frontend production bundle
- [ ] Configure services (Puma, Sidekiq, Redis)
- [ ] Setup monitoring and alerting
- [ ] Load testing
- [ ] Security audit

---

## Learning Paths

### New Frontend Developer

**Day 1**: Read System Overview → Review architecture
**Day 2**: Study Component Examples
**Week 1**: First feature implementation

### New Backend Developer

**Day 1**: Read System Overview → Review API Endpoints
**Day 2**: Study Backend Roadmap Sprint 1
**Week 1**: Implement Sprint 1

### DevOps/SRE Engineer

**Day 1**: Review Monitoring Guide
**Week 1**: Monitoring setup
**Week 2**: Production readiness

### By Task

| Task | Documentation Path |
|------|-------------------|
| Implement batch execution | Component Examples → API Endpoints → Backend Roadmap |
| Setup monitoring | Monitoring Guide → Integration Checklist |
| Understand architecture | This Guide → Quick Reference |
| Troubleshoot issue | Quick Reference → Monitoring Guide |

---

## Security & Permissions

### Permission-Based Access Control

**CRITICAL**: Frontend uses permission-based access control ONLY - never role-based.

```typescript
// ✅ CORRECT - Permission-based
const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute');

// ❌ WRONG - Role-based (never use this)
const canExecute = currentUser?.roles?.includes('admin');
```

### AI-Specific Permissions

| Permission | Description |
|------------|-------------|
| `ai.agents.create` | Create AI agents |
| `ai.agents.execute` | Execute AI agents |
| `ai.workflows.create` | Create workflows |
| `ai.workflows.execute` | Execute workflows |
| `ai.providers.manage` | Manage AI providers |
| `ai.monitoring.read` | View monitoring dashboard |
| `ai.analytics.read` | View analytics |

---

## Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| AI_ORCHESTRATION_GUIDE.md | Complete system guide | Everyone |
| AI_ORCHESTRATION_API_REFERENCE.md | API endpoints & examples | Developers |
| AI_ORCHESTRATION_OPERATIONS.md | Testing & monitoring | QA/DevOps |
| AI_ORCHESTRATION_QUICK_START.md | Quick start & roadmap | New developers |

---

## Key Files Reference

### Backend Services
- `server/app/services/ai_agent_orchestration_service.rb` - Root facade
- `server/app/services/mcp/workflow_orchestrator.rb` - MCP core
- `server/app/controllers/api/v1/ai/workflows_controller.rb` - API

### Frontend Services
- `frontend/src/shared/services/ai/index.ts` - Export barrel
- `frontend/src/shared/services/ai/WorkflowsApiService.ts`
- `frontend/src/shared/types/workflow.ts` - Types

### Workflow Builder
- `frontend/src/shared/components/workflow/WorkflowBuilder.tsx`
- `frontend/src/shared/components/workflow/WorkflowBuilderModal.tsx`

---

## Common Commands

```bash
# Backend tests
cd server && bundle exec rspec spec/services/ai*

# Frontend type check
cd frontend && npm run typecheck

# Start development services
scripts/auto-dev.sh ensure

# Database migrations
cd server && rails db:migrate
```

---

**Document Status**: ✅ Production Ready
**Consolidates**: AI_ORCHESTRATION_INDEX.md, AI_ORCHESTRATION_OVERVIEW.md, AI_ORCHESTRATION_MIGRATION_GUIDE.md, AI_ORCHESTRATION_INTEGRATION_CHECKLIST.md
