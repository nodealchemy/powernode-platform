# AI Orchestration Complete Guide

**Version**: 4.0 | **Last Updated**: April 2026 | **Status**: Production Ready

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

The Powernode AI Orchestration System provides enterprise-grade AI agent execution, governance, and multi-provider integration. As of April 2026, the platform encompasses:

- **132 AI models** in `app/models/ai/` (plus `code_factory/` subdirectory)
- **88 controllers** in `app/controllers/api/v1/ai/` (includes `security/` subdirectory)
- **376 services** in `app/services/ai/` across **52 subdirectories**
- **10 supported providers** (Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere, plus custom)

### Key Capabilities

| Feature | Description |
|---------|-------------|
| **Missions** | End-to-end development pipeline with approval gates |
| **Ralph Loops** | Recursive agentic task execution from PRDs |
| **Code Factory** | Risk-aware code review with evidence-based merge gating |
| **Model Router** | Intelligent provider selection with 7 routing strategies |
| **Agent Autonomy** | Trust tiers (supervised → autonomous) with execution gates, goals, observations, proposals, escalations |
| **Memory System** | 4-tier memory: working (Redis), STM, LTM (pgvector), shared pools |
| **RAG Pipeline** | Hybrid search with vector, keyword, graph, and agentic retrieval |
| **Skill Graph** | Skills registry with versioning, conflicts, and gap detection |
| **Codebase Intelligence** | AST indexing, semantic navigation, blast-radius analysis, static analysis |
| **Data Sources** | Managed external data API integration (NOAA, Open-Meteo, etc.) with quota and credential tracking |
| **Content Linking** | Wikilink extraction from Pages → KG edges, backlinks, page embeddings |
| **Security Guardrails** | Input/output rails, PII detection, prompt injection protection |
| **A2A / ACP / AGUI** | Agent-to-agent, Agent Communication Protocol, Agent GUI state sync |
| **Real-time Updates** | WebSocket channels for mission/team/ralph-loop/code-factory events |

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend Layer                          │
│  React Components → API Services                           │
│  (agents, teams, missions, providers, autonomy, ...)       │
└──────────────────────────┬──────────────────────────────────┘
                           │ RESTful JSON API + WebSocket
┌──────────────────────────▼──────────────────────────────────┐
│                    Backend API Layer                        │
│  88 Controllers (Api::V1::Ai + Admin + Internal)           │
│  Agents, Teams, Missions, Ralph, Code Factory, Providers,  │
│  Model Router, Memory, RAG, Skills, Security, A2A, ACP,    │
│  AGUI, Autonomy, Analytics, Monitoring, Data Sources, ...  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│               Service Layer (376 services / 52 subdirs)     │
│  Orchestration │ Autonomy │ Security │ Memory │ RAG        │
│  Ralph         │ Missions │ Code Factory │ Model Router     │
│  Skill Graph   │ Analytics │ Teams │ Codebase │ Data Sources│
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│               Worker Service (Sidekiq)                      │
│  Mission phase jobs, Ralph iterations, trust decay,         │
│  memory consolidation, skill lifecycle, knowledge sync,     │
│  observation pipeline, daily summaries, data source sync    │
└─────────────────────────────────────────────────────────────┘
```

### Service Layer Pattern

**Root services** (orchestration entry points):
- `AiAgentOrchestrationService` — agent execution orchestrator
- `Ai::Missions::OrchestratorService` — mission lifecycle
- `Ai::Ralph::ExecutionService` — Ralph loop execution
- `Ai::CodeFactory::OrchestratorService` — code review pipeline
- `Ai::ModelRouterService` — intelligent provider routing

**Domain services** (52 subdirectories — notable ones):
- `ai/autonomy/` — trust, execution gates, kill switch, goals, observation sensors, escalations, proposals, duty cycle, shadow mode
- `ai/missions/` — PRD generation, repo analysis, deployment, PR management
- `ai/security/` — security gates, anomaly detection, PII filtering
- `ai/memory/` — working memory, storage, routing, embeddings, consolidation
- `ai/rag/` — hybrid search, graph RAG, agentic RAG
- `ai/skill_graph/` — lifecycle, conflicts, coverage, mutation, evolution
- `ai/code_factory/` — risk classification, remediation, merge gating
- `ai/ralph/` — agentic loop, task execution, git tools
- `ai/codebase/` — AST parsing, semantic search, blast-radius, static analysis
- `ai/teams/` — CRUD, execution, configuration, A2A
- `ai/analytics/` — cost, performance, dashboards
- `ai/tools/` — MCP tool registry + per-subsystem tool classes (50+ classes, 305 actions)

---

## Core Components

### 1. AI Agents

**132 models** covering agents, teams, missions, memory, security, skills, autonomy, knowledge graph, goals, observations, and more.

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
├── Ai::AgentIdentity        # Identity verification
├── Ai::AgentGoal            # Self-directed goals
├── Ai::AgentObservation     # Environmental observations
├── Ai::AgentProposal        # Proposals for human review
├── Ai::AgentEscalation      # Structured escalations
└── Ai::AgentFeedback        # Human-to-agent feedback
```

### 2. Agent Teams

Multi-agent collaboration with configurable execution strategies.

**Execution strategies:** `hierarchical`, `sequential`, `parallel`, `mesh`

**Team models:** `AgentTeam`, `AgentTeamMember`, `TeamRole`, `TeamExecution`, `TeamTask`, `TeamChannel`, `TeamMessage`

### 3. Missions

End-to-end development pipeline with approval gates. See [MISSIONS_GUIDE.md](MISSIONS_GUIDE.md).

**Phases:** `analyzing → awaiting_feature_approval → planning → awaiting_prd_approval → executing → testing → reviewing → awaiting_code_approval → deploying → previewing → merging → completed`

**Approval gates:** `feature_selection`, `prd_review`, `code_review`, `merge_approval`

### 4. AI Providers

Multi-provider support with automatic model sync, rate limiting, and circuit-breaker-backed health checks.

**Provider sync adapters:** Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere, generic

### 5. LLM Adapters

Unified LLM client with provider-specific adapters.

```ruby
# Adapters: AnthropicAdapter, OpenAIAdapter, OllamaAdapter
client = Ai::Llm::Client.new(provider: provider, credential: credential)
response = client.send_message(messages, options)
```

### 6. Codebase Intelligence

AST-indexed knowledge graph of the codebase exposed via 14 MCP tools (`code_context_tree`, `code_semantic_search`, `code_blast_radius`, etc.). See the Codebase Intelligence section in the [MCP Tool Catalog](MCP_TOOL_CATALOG.md).

### 7. Data Sources

Managed integration of external data APIs (NOAA, Open-Meteo, etc.) with quota tracking, credential management, and test-connection probes. See [DATA_SOURCES.md](DATA_SOURCES.md).

### 8. Content Linking

Wikilink extraction from Page content (`[[Title]]` / `[[Title|Display]]`) feeds the knowledge graph with `references` edges and supports backlink panels plus page embeddings. See [CONTENT_LINKING.md](CONTENT_LINKING.md).

---

## Subsystem Guides

| Subsystem | Guide | Description |
|-----------|-------|-------------|
| Missions | [MISSIONS_GUIDE.md](MISSIONS_GUIDE.md) | End-to-end dev pipeline with approval gates |
| Ralph Loops | [RALPH_LOOPS_GUIDE.md](RALPH_LOOPS_GUIDE.md) | Recursive agentic task execution |
| Code Factory | [CODE_FACTORY_GUIDE.md](CODE_FACTORY_GUIDE.md) | Risk-aware code review pipeline |
| Model Router | [MODEL_ROUTER_GUIDE.md](MODEL_ROUTER_GUIDE.md) | Intelligent provider routing |
| Agent Autonomy | [AGENT_AUTONOMY_GUIDE.md](AGENT_AUTONOMY_GUIDE.md) | Trust tiers, goals, observations, proposals, escalations |
| Memory System | [MEMORY_SYSTEM_ARCHITECTURE.md](MEMORY_SYSTEM_ARCHITECTURE.md) | Multi-tier memory architecture |
| Security | [AI_SECURITY_GUARDRAILS.md](AI_SECURITY_GUARDRAILS.md) | Guardrails & security gates |
| RAG System | [RAG_SYSTEM_GUIDE.md](RAG_SYSTEM_GUIDE.md) | Document retrieval pipeline |
| Skill Graph | [SKILL_GRAPH_REFERENCE.md](SKILL_GRAPH_REFERENCE.md) | Skills registry & lifecycle |
| Provider Routing | [AI_PROVIDER_ROUTING.md](AI_PROVIDER_ROUTING.md) | Load balancing & circuit breakers |
| Cost Attribution | [COST_ATTRIBUTION_SYSTEM.md](COST_ATTRIBUTION_SYSTEM.md) | Cost tracking & optimization |
| Content Linking | [CONTENT_LINKING.md](CONTENT_LINKING.md) | Wikilink extraction + backlinks |
| Data Sources | [DATA_SOURCES.md](DATA_SOURCES.md) | External data API management |
| Daily Summaries | [DAILY_SUMMARIES.md](DAILY_SUMMARIES.md) | Auto-generated operational summaries |

---

## Frontend Integration

### API Services

```typescript
import {
  agentsApi, teamsApi, missionsApi,
  providersApi, monitoringApi, analyticsApi
} from '@/shared/services/ai';

// Or use the convenience object
import { aiApi } from '@/shared/services/ai';
```

### WebSocket Channels

| Channel | Purpose |
|---------|---------|
| `MissionChannel` | Mission status, phase, and approval events |
| `CodeFactoryChannel` | Code review pipeline events |
| `AiOrchestrationChannel` | Unified stream for agent executions, Ralph Loops, worktree sessions, circuit breakers, monitoring alerts, system health |
| `TeamChannel` | Team execution events |
| `AiAgentExecutionChannel` | Per-agent execution lifecycle |
| `AiConversationChannel` | Conversation message broadcasts |
| `AiStreamingChannel` | LLM token streaming |

The `AiOrchestrationChannel` accepts subscription types: `account`, `agent`, `monitoring`, `system`, `circuit_breaker`, `ralph_loop`, `worktree_session`.

---

## Security & Permissions

### Permission-Based Access Control

**CRITICAL**: Frontend uses permission-based access control ONLY — never role-based.

```typescript
// CORRECT
currentUser?.permissions?.includes('ai.missions.manage');

// FORBIDDEN
currentUser?.roles?.includes('admin');
```

### AI Permissions

| Permission | Description |
|------------|-------------|
| `ai.agents.create/execute/read/manage` | Agent management and execution |
| `ai.teams.create/execute/read/manage` | Team operations |
| `ai.missions.read/manage` | Mission operations |
| `ai.providers.manage` | Provider management |
| `ai.routing.read/manage/optimize` | Model router |
| `ai.code_factory.read/manage` | Code Factory |
| `ai.monitoring.read` | Monitoring dashboard |
| `ai.analytics.read` | Analytics |
| `ai.autonomy.manage` | Kill switch, intervention policies, duty cycles |
| `ai.knowledge.read/manage` | Knowledge base, learnings, shared knowledge |
| `ai_orchestration.read` | Read access to orchestration streams (WebSocket) |
| `admin.access` | Admin endpoints (daily summaries, maintenance, etc.) |

---

## Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| **This Guide** | System overview & architecture | Everyone |
| [API Reference](AI_ORCHESTRATION_API_REFERENCE.md) | API endpoints & examples | Developers |
| [Operations](AI_ORCHESTRATION_OPERATIONS.md) | Testing & monitoring | QA/DevOps |
| [Quick Start](AI_ORCHESTRATION_QUICK_START.md) | Getting started with AI features | Developers |
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
| [Data Sources](DATA_SOURCES.md) | External data API integration | Developers/Ops |
| [Content Linking](CONTENT_LINKING.md) | Wikilinks & backlinks | Content/Developers |
| [Daily Summaries](DAILY_SUMMARIES.md) | Operational summaries | Admins |
| [MCP Tool Catalog](MCP_TOOL_CATALOG.md) | All 305 MCP tool actions | Everyone |

---

## Key Files Reference

### Backend
- `server/app/models/ai/` — 132 models (+ `code_factory/` subdirectory)
- `server/app/controllers/api/v1/ai/` — 88 controllers (+ `security/` subdirectory)
- `server/app/services/ai/` — 376 services across 52 subdirectories
- `server/app/channels/` — WebSocket channels (Mission, CodeFactory, AiOrchestration, AiAgentExecution, AiConversation, AiStreaming, Team, Analytics)

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

# Regenerate MCP tool catalog (305 actions)
cd server && rails mcp:generate_tool_catalog
```

---

**Document Status**: Production Ready
