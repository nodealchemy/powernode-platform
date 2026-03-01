# Powernode Platform

> **Subscription lifecycle management with integrated AI orchestration, built for scale**

Powernode is a full-stack platform handling authentication, billing, AI agent orchestration, and DevOps automation. Built with Rails 8.1.2, React 19.1 TypeScript, and a standalone Sidekiq worker service.

## Key Features

### Core Platform
- **Enterprise Authentication** - JWT + OAuth 2.0, 2FA, account lockout, rate limiting
- **Payment Processing** - Stripe & PayPal with PCI compliance (enterprise)
- **Smart Analytics** - MRR/ARR, churn analysis, customer health scoring
- **Real-time** - 17 ActionCable WebSocket channels for live updates
- **Modern UI** - React 19.1 with Tailwind CSS v4.1 and theme system
- **Permission-Based Access** - 543+ granular permissions across 30+ categories

### AI & Automation (127 models, 107 MCP tools)
- **AI Agents** - Create, deploy, and manage agents with trust scoring and autonomy tiers
- **Agent Teams** - Multi-agent orchestration (5 strategies: manager_led, consensus, auction, round_robin, priority_based)
- **AI Workflows** - Visual builder with 35+ node types and circuit breakers
- **AI Autonomy** - Kill switch, goals, proposals, escalations, feedback, intervention policies, observations, duty cycle
- **Code Factory** - PRD generation, automated code review, remediation loops
- **Ralph Loops** - Recursive agent learning with 15-round tool calling
- **Model Router** - Cost-optimized provider selection across 10+ providers (Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere)
- **MCP Integration** - 107 platform tools for knowledge, memory, skills, RAG, autonomy, and DevOps
- **A2A Protocol** - Agent-to-Agent communication with agent cards
- **Memory System** - 4-tier architecture (working, STM, LTM, shared) with consolidation
- **Knowledge Graph** - 1,190+ nodes, 1,670+ edges with hybrid search and GraphRAG
- **RAG Pipeline** - Document chunking, pgvector embeddings, agentic retrieval (3-round reformulation)
- **Security Guardrails** - Behavioral fingerprinting, 5 input rails, 7 output rails, quarantine
- **FinOps** - Agent budgets, cost attribution, ROI metrics, optimization logging
- **AI Monitoring** - Execution traces, telemetry events, circuit breakers, performance benchmarks

### DevOps & Infrastructure (41 models)
- **Git Integration** - GitHub, GitLab, Gitea, Jenkins provider support
- **CI/CD Pipelines** - 13 step types including AI-powered steps, approval gates
- **Container Orchestration** - Docker host management, container templates, sandboxed execution
- **Docker Swarm** - Cluster, node, service, and stack management with deployment tracking
- **Integration Framework** - 5 integration types (GitHub Actions, webhooks, MCP servers, REST API, custom)
- **Supply Chain Security** - SBOM generation, attestations, license compliance
- **Secrets Management** - Vault-backed secrets with rotation tracking

### Multi-Platform Chat
- **5 Platforms** - WhatsApp, Telegram, Discord, Slack, Mattermost
- **AI-Powered Routing** - Automatic agent assignment with escalation
- **Prompt Injection Protection** - Content sanitization with delimiter wrapping

### Worker System (181+ jobs, 31 queues)
- **Standalone Sidekiq 7.2** - Fully isolated, API-only communication with backend
- **3 Priority Tiers** - Critical (weight 3), standard (weight 2), background (weight 1)
- **Circuit Breakers** - 600s AI workflows, 120s backend API timeouts
- **36+ Scheduled Jobs** - Maintenance, decay, consolidation, health checks, autonomy

### Enterprise Features (submodule)
- **Billing Engine** - Stripe & PayPal subscription lifecycle
- **BaaS** - Multi-tenancy with usage metering
- **Reseller System** - White-label management
- **AI Publisher** - Agent marketplace with monetization
- **Predictive Analytics** - Churn prediction, revenue forecasting

## Architecture Overview

```
powernode-platform/
├── server/              - Rails 8.1.2 API (327+ models, 293+ controllers, 580+ services)
│   ├── app/models/      - 13 namespaces (Ai, Devops, Chat, KnowledgeBase, ...)
│   ├── app/services/    - 23 service namespaces (580+ files)
│   └── app/channels/    - 17 ActionCable channels
├── frontend/            - React 19.1 TypeScript (11 feature modules)
│   └── src/features/    - account, admin, ai, baas, business, content, delegations,
│                          developer, devops, missions, privacy
├── worker/              - Sidekiq 7.2 (181+ jobs, 41 services, 4 API clients)
├── extensions/          - Enterprise submodule (billing, BaaS, reseller, publisher)
├── docs/                - 131 documentation files
└── scripts/             - 47 automation scripts
```

### Technology Stack

- **Backend**: Rails 8.1.2 | PostgreSQL | UUIDv7 | JWT + OAuth 2.0 | Redis
- **Frontend**: React 19.1 | TypeScript 5.9 | Vite 7.2 | Tailwind CSS v4.1 | Redux Toolkit + React Query
- **Worker**: Sidekiq 7.2 | Redis | Faraday | Circuit breakers
- **AI/ML**: 10+ providers | MCP Protocol | A2A Protocol | pgvector (HNSW)
- **Payments**: Stripe | PayPal | PCI DSS Compliance (enterprise)
- **Testing**: RSpec | Jest 30 | Cypress 15 | 20,600+ tests
- **Database**: 364+ tables | 13 model namespaces | pgvector embeddings

### Prerequisites
- Ruby 3.2.8
- Node.js 18+
- PostgreSQL 15+ (with pgvector extension)
- Redis 7+

## Quick Start

```bash
# Install systemd services (one-time)
sudo scripts/systemd/powernode-installer.sh install

# Start all services
sudo systemctl start powernode.target

# Check status
sudo scripts/systemd/powernode-installer.sh status
```

Services:
- **Frontend**: http://localhost:3001
- **API**: http://localhost:3000
- **Worker Web UI**: http://localhost:4567

## Platform Status

- 20,600+ tests (14,500 backend, 6,100 frontend)
- 95%+ pattern consistency
- 131 documentation files with specialist guides
- 543+ permissions across 30+ categories
- 107 MCP platform tools
- 50 KB articles, 10 content pages
- Knowledge graph: 1,190+ nodes, 1,670+ edges

## Documentation

### Getting Started
- **[Development Guide](docs/DEVELOPMENT.md)** - Architecture, namespaces, setup
- **[Quick Start](docs/QUICKSTART.md)** - Fast setup guide
- **[CLAUDE.md](CLAUDE.md)** - Development patterns and rules
- **[TODO](docs/TODO.md)** - Current status and roadmap

### Backend
- **[Rails Architect](docs/backend/RAILS_ARCHITECT_SPECIALIST.md)** - API architecture (Rails 8.1.2, 13 namespaces)
- **[Data Modeler](docs/backend/DATA_MODELER_SPECIALIST.md)** - Database & ActiveRecord
- **[Database Schema](docs/backend/DATABASE_SCHEMA_REFERENCE.md)** - 354 tables, namespace reference
- **[Service Architecture](docs/backend/BACKEND_SERVICE_ARCHITECTURE.md)** - 570 services, 23 namespaces
- **[Background Jobs](docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)** - Job patterns
- **[Payment Integration](docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md)** - Stripe/PayPal

### Frontend
- **[React Architect](docs/frontend/REACT_ARCHITECT_SPECIALIST.md)** - React 19.1, Vite 7.2, Tailwind v4.1
- **[State Management](docs/frontend/STATE_MANAGEMENT_GUIDE.md)** - Redux Toolkit + React Query
- **[UI Components](docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)** - Design system
- **[Dashboard](docs/frontend/DASHBOARD_SPECIALIST.md)** - Analytics & charts
- **[WebSocket Integration](docs/frontend/WEBSOCKET_INTEGRATION.md)** - Real-time patterns

### AI Platform
- **[AI Orchestration Guide](docs/platform/AI_ORCHESTRATION_GUIDE.md)** - Complete AI system overview
- **[AI API Reference](docs/platform/AI_ORCHESTRATION_API_REFERENCE.md)** - 73 AI controllers
- **[Code Factory](docs/platform/CODE_FACTORY_GUIDE.md)** - PRD generation, code review
- **[Ralph Loops](docs/platform/RALPH_LOOPS_GUIDE.md)** - Recursive agent learning
- **[Missions](docs/platform/MISSIONS_GUIDE.md)** - Mission pipeline, 12 phases
- **[Model Router](docs/platform/MODEL_ROUTER_GUIDE.md)** - Cost-optimized routing
- **[Agent Autonomy](docs/platform/AGENT_AUTONOMY_GUIDE.md)** - Kill switch, goals, proposals, escalations, feedback, intervention policies
- **[Memory System](docs/platform/MEMORY_SYSTEM_ARCHITECTURE.md)** - 4-tier memory architecture
- **[Security Guardrails](docs/platform/AI_SECURITY_GUARDRAILS.md)** - Behavioral fingerprinting
- **[RAG System](docs/platform/RAG_SYSTEM_GUIDE.md)** - Knowledge bases, hybrid search
- **[Skill Graph](docs/platform/SKILL_GRAPH_REFERENCE.md)** - Skills registry, gap detection
- **[Cost Attribution](docs/platform/COST_ATTRIBUTION_SYSTEM.md)** - FinOps, budgets, ROI
- **[Provider Routing](docs/platform/AI_PROVIDER_ROUTING.md)** - Multi-provider management
- **[AI Operations](docs/platform/AI_ORCHESTRATION_OPERATIONS.md)** - Monitoring, incident runbooks

### DevOps & Infrastructure
- **[DevOps Platform](docs/platform/DEVOPS_PLATFORM_GUIDE.md)** - 41 models, pipelines, containers, Swarm
- **[Docker Swarm](docs/infrastructure/DOCKER_SWARM_OPERATIONS.md)** - Cluster operations
- **[Docker Deployment](docs/infrastructure/DOCKER_DEPLOYMENT.md)** - Container setup
- **[Configuration](docs/infrastructure/CONFIGURATION_MANAGEMENT.md)** - Env vars, secrets
- **[Scripts Reference](docs/infrastructure/SCRIPTS_REFERENCE.md)** - 47 automation scripts
- **[DevOps Engineer](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md)** - CI/CD specialist

### Worker
- **[Worker Architecture](docs/worker/WORKER_ARCHITECTURE_OVERVIEW.md)** - Isolation, API clients, circuit breakers
- **[Worker Operations](docs/worker/WORKER_OPERATIONS_GUIDE.md)** - 181+ jobs, 31 queues, scheduling
- **[CI/CD Architecture](docs/worker/CI_CD_ARCHITECTURE.md)** - Pipeline execution
- **[File Processing](docs/worker/FILE_PROCESSING_ARCHITECTURE.md)** - File handling subsystem

### Platform References
- **[Changelog](docs/CHANGELOG.md)** - Release history
- **[Permission System](docs/platform/PERMISSION_SYSTEM_REFERENCE.md)** - 543+ permissions, 30+ categories
- **[WebSocket Channels](docs/platform/ACTIONCABLE_CHANNELS_REFERENCE.md)** - 17 channels reference
- **[Chat System](docs/platform/CHAT_SYSTEM_ARCHITECTURE.md)** - Multi-platform chat
- **[Content Management](docs/platform/CONTENT_MANAGEMENT_GUIDE.md)** - KB articles, pages, CMS
- **[Theme System](docs/platform/THEME_SYSTEM_REFERENCE.md)** - Tailwind v4.1 theming
- **[API Standards](docs/platform/API_RESPONSE_STANDARDS.md)** - API conventions
- **[UUID System](docs/platform/UUID_SYSTEM_IMPLEMENTATION.md)** - UUIDv7 across 327+ models
- **[MCP Configuration](docs/platform/MCP_CONFIGURATION.md)** - MCP server setup and OAuth
- **[MCP Tool Catalog](docs/platform/MCP_TOOL_CATALOG.md)** - 107 platform tools reference
- **[Workflow System](docs/platform/WORKFLOW_SYSTEM_STANDARDS.md)** - Workflow patterns
- **[Node Executors](docs/backend/NODE_EXECUTOR_REFERENCE.md)** - 35+ workflow node types

### Security
- **[Security Quick Start](docs/SECURITY_QUICK_START.md)** - Security setup overview
- **[Security Specialist](docs/infrastructure/SECURITY_SPECIALIST.md)** - Security architecture
- **[Supply Chain Security](docs/platform/SUPPLY_CHAIN_SECURITY.md)** - SBOM, attestations, compliance

### Testing
- **[Backend Testing](docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md)** - RSpec strategies
- **[Frontend Testing](docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md)** - Jest + React Testing Library
- **[E2E Testing](docs/testing/PLAYWRIGHT_E2E_TESTING.md)** - Playwright patterns

### Enterprise
- **[Enterprise Overview](extensions/enterprise/README.md)** - Billing, BaaS, reseller, AI publisher

## Contributing

This platform follows strict architectural patterns. Before contributing:

1. Read **[CLAUDE.md](CLAUDE.md)** for development guidelines
2. Check **[docs/TODO.md](docs/TODO.md)** for current priorities
3. Review specialist documentation for your area
4. Ensure all tests pass before submitting changes

## License

See **[LICENSE](LICENSE)** for licensing information.
