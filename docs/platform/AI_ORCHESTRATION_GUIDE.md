# AI Orchestration Complete Guide

**Version**: 3.0 | **Last Updated**: February 2026 | **Status**: Production Ready

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Core Components](#core-components)
4. [Subsystem Guides](#subsystem-guides)
5. [Frontend Integration](#frontend-integration)
6. [Security & Permissions](#security--permissions)
7. [Documentation Index](#documentation-index)

---

## System Overview

The Powernode AI Orchestration System provides enterprise-grade AI agent execution, workflow automation, and multi-provider integration. The platform encompasses:

- **135 AI models** in `app/models/ai/` (plus 4 in `code_factory/` subdirectory)
- **73 controllers** in `app/controllers/api/v1/ai/` (69 root + 4 in `security/`)
- **200+ services** in `app/services/ai/` across 40+ subdirectories
- **10 supported providers** (Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere, plus custom)

### Key Capabilities

| Feature | Description |
|---------|-------------|
| **Missions** | End-to-end development pipeline with approval gates |
| **Ralph Loops** | Recursive agentic task execution from PRDs |
| **Code Factory** | Risk-aware code review with evidence-based merge gating |
| **Model Router** | Intelligent provider selection with 7 routing strategies |
| **Agent Autonomy** | Trust tiers (supervised → autonomous) with execution gates |
| **Memory System** | 4-tier memory: working (Redis), STM, LTM (pgvector), shared pools |
| **RAG Pipeline** | Hybrid search with vector, keyword, graph, and agentic retrieval |
| **Skill Graph** | Skills registry with versioning, conflicts, and gap detection |
| **Security Guardrails** | Input/output rails, PII detection, prompt injection protection |
| **AGUI Protocol** | Agent GUI state synchronization |
| **A2A Protocol** | Agent-to-agent task delegation and communication |
| **Real-time Updates** | WebSocket channels for live mission/team/workflow status |

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend Layer                          │
│  React Components → API Services                           │
│  (agents, workflows, missions, teams, providers, ...)      │
└──────────────────────────┬──────────────────────────────────┘
                           │ RESTful JSON API + WebSocket
┌──────────────────────────▼──────────────────────────────────┐
│                    Backend API Layer                        │
│  73 Controllers (Api::V1::Ai namespace)                    │
│  Agents, Teams, Workflows, Missions, Ralph, Code Factory,  │
│  Providers, Model Router, Memory, RAG, Skills, Security,   │
│  A2A, ACP, AGUI, Autonomy, Analytics, Monitoring, ...      │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                  Service Layer (200+ services)              │
│  Orchestration │ Autonomy │ Security │ Memory │ RAG        │
│  Ralph         │ Missions │ Code Factory │ Model Router     │
│  Skill Graph   │ Analytics │ Teams │ Workflows              │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│               Worker Service (Sidekiq)                      │
│  Mission phase jobs, workflow execution, trust decay,       │
│  memory consolidation, skill lifecycle, knowledge sync      │
└─────────────────────────────────────────────────────────────┘
```

### Service Layer Pattern

**Root Services** (orchestration entry points):
- `AiAgentOrchestrationService` — agent execution orchestrator
- `Ai::Missions::OrchestratorService` — mission lifecycle
- `Ai::Ralph::ExecutionService` — Ralph loop execution
- `Ai::CodeFactory::OrchestratorService` — code review pipeline
- `Ai::ModelRouterService` — intelligent provider routing

**Domain Services** (40+ subdirectories):
- `ai/autonomy/` — trust, execution gates, conformance (12 services)
- `ai/security/` — security gates, anomaly detection, PII (8 services)
- `ai/memory/` — working memory, storage, routing (9 services)
- `ai/rag/` — hybrid search, graph RAG, agentic RAG (4 services)
- `ai/skill_graph/` — lifecycle, conflicts, coverage (12 services)
- `ai/code_factory/` — risk classification, remediation (9 services)
- `ai/ralph/` — agentic loop, task execution, git tools (5 services)
- `ai/missions/` — PRD generation, repo analysis, deployment (6 services)
- `ai/analytics/` — cost, performance, dashboard (5+ services)
- `ai/teams/` — CRUD, execution, configuration (5 services)

---

## Core Components

### 1. AI Agents

**135 models** covering agents, teams, workflows, missions, memory, security, skills, autonomy, and more.

**Agent model hierarchy:**
```
Ai::Agent                    # Core agent configuration
├── Ai::AgentExecution       # Execution records
├── Ai::AgentTrustScore      # Trust scoring (5 dimensions)
├── Ai::AgentSkill           # Skill assignments
├── Ai::AgentBudget          # Budget management
├── Ai::AgentShortTermMemory # Short-term memory entries
├── Ai::BehavioralFingerprint # Anomaly baselines
├── Ai::DelegationPolicy     # Delegation rules
└── Ai::AgentIdentity        # Identity verification
```

### 2. Agent Teams

Multi-agent collaboration with configurable execution strategies.

**Execution strategies:** `hierarchical`, `sequential`, `parallel`, `mesh`

**Team models:** `AgentTeam`, `AgentTeamMember`, `TeamRole`, `TeamExecution`, `TeamTask`, `TeamChannel`, `TeamMessage`

### 3. AI Workflows

Visual workflow builder with 45+ node executors across 8 categories.

**Node categories:** Control Flow (8), AI/Agent (2), Integration (9), Content (9), DevOps (13), MCP (4), Utility (3)

### 4. AI Providers

Multi-provider support with automatic model sync.

**Provider sync adapters:** Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere, generic

### 5. LLM Adapters

Unified LLM client with provider-specific adapters.

```ruby
# Adapters: AnthropicAdapter, OpenAIAdapter, OllamaAdapter
client = Ai::Llm::Client.new(provider: provider, credential: credential)
response = client.send_message(messages, options)
```

---

## Subsystem Guides

| Subsystem | Guide | Description |
|-----------|-------|-------------|
| Missions | [MISSIONS_GUIDE.md](MISSIONS_GUIDE.md) | End-to-end dev pipeline with approval gates |
| Ralph Loops | [RALPH_LOOPS_GUIDE.md](RALPH_LOOPS_GUIDE.md) | Recursive agentic task execution |
| Code Factory | [CODE_FACTORY_GUIDE.md](CODE_FACTORY_GUIDE.md) | Risk-aware code review pipeline |
| Model Router | [MODEL_ROUTER_GUIDE.md](MODEL_ROUTER_GUIDE.md) | Intelligent provider routing |
| Agent Autonomy | [AGENT_AUTONOMY_GUIDE.md](AGENT_AUTONOMY_GUIDE.md) | Trust tiers & execution gates |
| Memory System | [MEMORY_SYSTEM_ARCHITECTURE.md](MEMORY_SYSTEM_ARCHITECTURE.md) | Multi-tier memory architecture |
| Security | [AI_SECURITY_GUARDRAILS.md](AI_SECURITY_GUARDRAILS.md) | Guardrails & security gates |
| RAG System | [RAG_SYSTEM_GUIDE.md](RAG_SYSTEM_GUIDE.md) | Document retrieval pipeline |
| Skill Graph | [SKILL_GRAPH_REFERENCE.md](SKILL_GRAPH_REFERENCE.md) | Skills registry & lifecycle |
| Provider Routing | [AI_PROVIDER_ROUTING.md](AI_PROVIDER_ROUTING.md) | Load balancing & circuit breakers |
| Cost Attribution | [COST_ATTRIBUTION_SYSTEM.md](COST_ATTRIBUTION_SYSTEM.md) | Cost tracking & optimization |
| Node Executors | [NODE_EXECUTOR_REFERENCE.md](../backend/NODE_EXECUTOR_REFERENCE.md) | Workflow node executor reference |

---

## Frontend Integration

### API Services

```typescript
import {
  agentsApi, workflowsApi, providersApi,
  monitoringApi, analyticsApi
} from '@/shared/services/ai';

// Or use the convenience object
import { aiApi } from '@/shared/services/ai';
```

### WebSocket Channels

| Channel | Purpose |
|---------|---------|
| `MissionChannel` | Mission status/phase updates |
| `CodeFactoryChannel` | Code review pipeline events |
| `AiOrchestrationChannel` | Workflow/batch execution updates |
| `TeamChannel` | Team execution events |

---

## Security & Permissions

### Permission-Based Access Control

**CRITICAL**: Frontend uses permission-based access control ONLY — never role-based.

```typescript
// CORRECT
currentUser?.permissions?.includes('ai.workflows.execute');

// FORBIDDEN
currentUser?.roles?.includes('admin');
```

### AI Permissions

| Permission | Description |
|------------|-------------|
| `ai.agents.create/execute` | Agent management and execution |
| `ai.workflows.create/execute/read/update/delete` | Workflow operations |
| `ai.providers.manage` | Provider management |
| `ai.missions.read/manage` | Mission operations |
| `ai.routing.read/manage/optimize` | Model router |
| `ai.code_factory.read/manage` | Code Factory |
| `ai.monitoring.read` | Monitoring dashboard |
| `ai.analytics.read` | Analytics |

---

## Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| **This Guide** | System overview & architecture | Everyone |
| [API Reference](AI_ORCHESTRATION_API_REFERENCE.md) | API endpoints & examples | Developers |
| [Operations](AI_ORCHESTRATION_OPERATIONS.md) | Testing & monitoring | QA/DevOps |
| [Missions Guide](MISSIONS_GUIDE.md) | Mission pipeline | Developers |
| [Ralph Loops Guide](RALPH_LOOPS_GUIDE.md) | Agentic execution | Developers |
| [Code Factory Guide](CODE_FACTORY_GUIDE.md) | Code review pipeline | Developers |
| [Model Router Guide](MODEL_ROUTER_GUIDE.md) | Provider routing | Developers/DevOps |
| [Agent Autonomy Guide](AGENT_AUTONOMY_GUIDE.md) | Trust & governance | Security/DevOps |
| [Memory Architecture](MEMORY_SYSTEM_ARCHITECTURE.md) | Memory tiers | Developers |
| [Security Guardrails](AI_SECURITY_GUARDRAILS.md) | AI security | Security |
| [RAG System Guide](RAG_SYSTEM_GUIDE.md) | Document retrieval | Developers |
| [Skill Graph Reference](SKILL_GRAPH_REFERENCE.md) | Skills registry | Developers |
| [Provider Routing](AI_PROVIDER_ROUTING.md) | Load balancing | DevOps |
| [Cost Attribution](COST_ATTRIBUTION_SYSTEM.md) | Cost tracking | FinOps |
| [Node Executor Reference](../backend/NODE_EXECUTOR_REFERENCE.md) | Workflow nodes | Developers |

---

## Key Files Reference

### Backend
- `server/app/models/ai/` — 135 models (+ `code_factory/` subdirectory)
- `server/app/controllers/api/v1/ai/` — 73 controllers (+ `security/` subdirectory)
- `server/app/services/ai/` — 200+ services across 40+ subdirectories
- `server/app/channels/` — WebSocket channels (Mission, CodeFactory, Team, etc.)

### Common Commands

```bash
# Backend tests
cd server && bundle exec rspec spec/

# Frontend type check
cd frontend && npx tsc --noEmit

# Start all services
sudo systemctl start powernode.target

# Database migrations
cd server && rails db:migrate
```

---

**Document Status**: Production Ready
