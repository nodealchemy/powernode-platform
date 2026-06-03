# Powernode Platform

> **Open-source mission control for AI agent fleets — chat to provision, agents to operate, humans to approve.**

Powernode turns AI agents into accountable operators of real infrastructure. Describe what you need in plain English, an agent fleet provisions it, and an autonomous control loop keeps it healthy — with every consequential action gated through an approval workflow you configure.

It's the full operational substrate underneath: authentication, permissions, multi-provider LLM routing, knowledge graph reasoning, real-time communication, DevOps pipelines, container orchestration, and a fleet sensor + intervention policy framework that lets agents observe, propose, and act within safety guardrails you define. Every component is designed to work together: agents share memory, learn from execution history, and operate within boundaries that keep them auditable.

### Why Powernode

- **AI Agent Orchestration** — Deploy agents with trust scoring, autonomy tiers, and 5 team strategies. Kill switch, goal tracking, proposals, escalations, and behavioral fingerprinting keep agents operating within defined boundaries.
- **Multi-Provider LLM Routing** — 10+ providers (Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere), cost-optimized selection with per-agent budgets and ROI tracking.
- **Knowledge Infrastructure** — GraphRAG over a hybrid knowledge graph (live node/edge counts via `platform.graph_statistics`), 4-tier memory system (working → STM → LTM → shared), compound learning with decay and reinforcement, RAG pipeline with pgvector embeddings and 3-round agentic retrieval.
- **MCP-Native Platform** — 546 tool actions across 62 tool classes spanning knowledge, memory, skills, autonomy, DevOps, Docker, codebase intelligence, and content management (full catalog: [docs/reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md)). Full A2A protocol support for agent-to-agent communication.
- **Fleet Substrate** — Bare-metal, VM, and container lifecycle via the System extension. Multi-arch initramfs (amd64 + arm64), composefs + fs-verity rootfs, Cosign + SLSA L3+ signed module supply chain, instance pools, SDWAN overlay with iBGP/FRR + virtual IPs + federation peering.
- **DevOps Automation** — CI/CD pipelines with 13 step types (including AI-powered), Docker Swarm orchestration, multi-provider Git integration (GitHub, GitLab, Gitea), supply chain security with SBOM generation.
- **Production Foundation** — 367 granular base permissions (extension-inclusive count is higher at runtime), 19 WebSocket channels, JWT + OAuth 2.0 authentication, and a deep test suite (713 backend spec files, 230 frontend test files).

*Built with Rails 8, React 19 + TypeScript, Sidekiq 8, and PostgreSQL + pgvector.*

## Key Features

### Core Platform
- **Authentication & Security** - JWT + OAuth 2.0, 2FA, account lockout, rate limiting, CORS, CSP
- **Permission-Based Access** - 367 granular base permissions across 30+ categories, role-to-permission mapping
- **Real-time Communication** - 19 ActionCable WebSocket channels for live updates, cross-tab sync
- **Modern UI** - React 19 with Tailwind CSS 4, theme system, 15 feature modules
- **Content Management** - Knowledge base articles, content pages, CMS
- **Analytics** - Customer health scoring, usage tracking, platform telemetry

### AI & Automation (546 MCP tool actions across 62 tool classes)
- **AI Agents** - Create, deploy, and manage agents with trust scoring and autonomy tiers
- **Agent Teams** - Multi-agent orchestration (5 strategies: manager_led, consensus, auction, round_robin, priority_based)
- **AI Workflows** - Visual builder with 35+ node types and circuit breakers
- **AI Autonomy** - Kill switch, goals, proposals, escalations, feedback, intervention policies, observations, duty cycle
- **Code Factory** - PRD generation, automated code review, remediation loops
- **Ralph Loops** - Recursive agent learning with 15-round tool calling
- **Model Router** - Cost-optimized provider selection across 10+ providers (Anthropic, OpenAI, Ollama, Azure, Google, Groq, Grok, Mistral, Cohere)
- **MCP Integration** - 546 tool actions for knowledge, memory, skills, RAG, autonomy, Docker, and DevOps
- **A2A Protocol** - Agent-to-Agent communication with agent cards
- **Memory System** - 4-tier architecture (working, STM, LTM, shared) with consolidation
- **Knowledge Graph** - hybrid search + GraphRAG (live node/edge counts via `platform.graph_statistics`)
- **RAG Pipeline** - Document chunking, pgvector embeddings, agentic retrieval (3-round reformulation)
- **Security Guardrails** - Behavioral fingerprinting, 5 input rails, 7 output rails, quarantine
- **FinOps** - Agent budgets, cost attribution, ROI metrics, optimization logging
- **AI Monitoring** - Execution traces, telemetry events, circuit breakers, performance benchmarks

### DevOps & Infrastructure
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

### Worker System (238 jobs, 31 queues)
- **Standalone Sidekiq 8** - Fully isolated, API-only communication with backend
- **3 Priority Tiers** - Critical (weight 3), standard (weight 2), background (weight 1)
- **Circuit Breakers** - 600s AI workflows, 120s backend API timeouts
- **53 Scheduled Jobs** - Maintenance, decay, consolidation, health checks, autonomy (the code-intel pipeline runs in a dedicated isolated capsule, excluded from the 31 queues)

### Extensions (4 modules)

Extensions are loaded dynamically via `FeatureGateService`. When no extensions are present, Powernode runs in core mode — single-user self-hosted with all platform features unlocked.

- **Business** (`extensions/business/`) - Billing engine (Stripe/PayPal), BaaS multi-tenancy, reseller system, AI publisher marketplace, predictive analytics
- **Trading** (`extensions/trading/`) - Algorithmic trading with strategies, portfolios, risk monitoring, and evolution
- **Supply Chain** (`extensions/supply-chain/`) - Supply chain management and logistics
- **Marketing** (`extensions/marketing/`) - Campaign management and marketing automation

### Distribution & Cloning

Powernode is **MIT-licensed throughout**. Publicly available components:

- **`powernode-platform`** (this repo) — core platform
- **`powernode-system`** ([github.com/nodealchemy/powernode-system](https://github.com/nodealchemy/powernode-system)) — fleet, mesh, signed module supply chain, on-node Go agent. Mounted at `extensions/system/`.
- **`powernode-supply-chain`** ([github.com/nodealchemy/powernode-supply-chain](https://github.com/nodealchemy/powernode-supply-chain)) — supply-chain security extension (SBOM workflows, attestations). Mounted at `extensions/supply-chain/`.
- **`powernode-marketing`** ([github.com/nodealchemy/powernode-marketing](https://github.com/nodealchemy/powernode-marketing)) — marketing extension (campaigns, calendar, email lists, social, public landing pages). Mounted at `extensions/marketing/`.

The `business` and `trading` extensions are MIT-licensed but currently maintained in private repositories. Public clones run in **core mode** — single-user self-hosted, all platform features unlocked — without those extensions.

```bash
# Public clone with all public submodules initialized
git clone <repo-url>
cd powernode-platform
git submodule update --init extensions/system extensions/supply-chain extensions/marketing
```

Running `git submodule update --init` without the path arguments will additionally attempt to clone the private extensions (`business`, `trading`) and produce permission-denied errors. These are safe to ignore if you only need core mode.

## Architecture Overview

```
powernode-platform/
├── server/              - Rails 8 API (352 models, 336 controllers, 590 services)
│   ├── app/models/      - 13 model namespaces (Ai, Devops, Chat, KnowledgeBase, ...)
│   ├── app/services/    - 23 service namespaces (590 files)
│   └── app/channels/    - 19 ActionCable channels
├── frontend/            - React 19 + TypeScript (15 feature modules)
│   └── src/features/    - account, admin, ai, app, business, content, delegations,
│                          developer, devops, governance, missions, onboarding,
│                          privacy, supply-chain, system
├── worker/              - Sidekiq 8 (238 jobs, 31 queues)
├── extensions/          - 5 extensions (system, supply-chain, marketing; business, trading)
├── docs/                - Documentation (see docs/README.md)
└── scripts/             - 48 automation scripts
```

### Technology Stack

- **Backend**: Rails 8 | PostgreSQL | UUIDv7 | JWT + OAuth 2.0 | Redis
- **Frontend**: React 19 | TypeScript 6 | Vite 7 | Tailwind CSS 4 | Redux Toolkit + React Query
- **Worker**: Sidekiq 8 | Redis | Faraday | Circuit breakers
- **AI/ML**: 10+ providers | MCP Protocol | A2A Protocol | pgvector (HNSW)
- **Testing**: RSpec | Jest 30 | Cypress 15 | 713 backend spec files, 230 frontend test files
- **Database**: PostgreSQL + pgvector | 13 model namespaces | UUIDv7 primary keys

### Prerequisites
- Ruby 3.2.8
- Node.js 18+
- PostgreSQL with pgvector extension
- Redis 7+

## Quick Start

> For detailed setup instructions, see the **[Quick Start Guide](docs/getting-started/01-quickstart.md)**.

```bash
# 1. Install dependencies
cd server && bundle install
cd ../frontend && npm install
cd ../worker && bundle install
cd ..

# 2. Setup database
cd server && rails db:create db:migrate db:seed
cd ..

# 3. Install systemd services (one-time)
sudo scripts/systemd/powernode-installer.sh install

# 4. Start all services
sudo systemctl start powernode.target

# 5. Check status
sudo scripts/systemd/powernode-installer.sh status
```

Services:
- **Frontend**: http://localhost:3001
- **API**: http://localhost:3000
- **Worker Web UI**: http://localhost:4567

## Documentation

The full documentation lives in **[docs/](docs/)** — start with [docs/README.md](docs/README.md) for the visitor map.

### Common entry points

- **[Quick Start](docs/getting-started/01-quickstart.md)** — run it locally in 10 minutes
- **[Ship your first agent](docs/getting-started/02-first-agent.md)** — first deployment walkthrough
- **[Architecture](docs/concepts/architecture.md)** — system shape, namespaces, service boundaries
- **[Agents & autonomy](docs/concepts/agents-and-autonomy.md)** — agent orchestration, missions, model routing, autonomy tiers
- **[MCP & tools](docs/concepts/mcp-and-tools.md)** — MCP protocol, OAuth, tool catalog conventions
- **[Knowledge & memory](docs/concepts/knowledge-and-memory.md)** — knowledge graph, RAG, 4-tier memory, skills
- **[Permissions](docs/concepts/permissions.md)** — 367 base permissions, role mapping, frontend rules
- **[Data model](docs/concepts/data-model.md)** — UUIDv7 + namespaces + schema conventions
- **[Chat & realtime](docs/concepts/chat-and-realtime.md)** — 19 ActionCable channels, multi-platform chat
- **[Cost & FinOps](docs/concepts/cost-and-finops.md)** — provider pricing, budgets, ROI

### By task

- **Backend / Frontend / Worker** → [docs/guides/backend.md](docs/guides/backend.md), [docs/guides/frontend.md](docs/guides/frontend.md), [docs/operations/worker-operations.md](docs/operations/worker-operations.md)
- **DevOps + Docker Swarm + CI/CD** → [docs/guides/devops.md](docs/guides/devops.md), [docs/operations/docker-swarm.md](docs/operations/docker-swarm.md)
- **Security + supply chain** → [docs/guides/security.md](docs/guides/security.md)
- **Extensions (business, trading, supply-chain, marketing)** → [docs/guides/extensions.md](docs/guides/extensions.md)
- **Testing (Backend + Frontend + E2E)** → [docs/guides/testing.md](docs/guides/testing.md), [docs/guides/e2e-testing.md](docs/guides/e2e-testing.md)
- **Production operations** → [docs/operations/production-deployment.md](docs/operations/production-deployment.md), [docs/operations/ai-operations.md](docs/operations/ai-operations.md), [docs/operations/performance-tuning.md](docs/operations/performance-tuning.md)
- **Contributing** → [docs/contributing/development-setup.md](docs/contributing/development-setup.md), [CONTRIBUTING.md](CONTRIBUTING.md)

### Reference

- **[API overview](docs/reference/api/overview.md)** — response standards, conventions
- **[Database schema](docs/reference/database-schema.md)** — tables + namespace reference
- **[Theme system](docs/reference/theme-system.md)**, **[Scripts](docs/reference/scripts.md)**
- **[MCP tools (auto-generated)](docs/reference/auto/mcp-tools.md)** — full action catalog
- **[Skills / Knowledge / Learnings / Graph (auto-generated)](docs/reference/auto/)**
- **[TODO (auto-generated)](docs/reference/auto/todo.md)** — current status and roadmap
- **[Changelog](CHANGELOG.md)** — release history

### Development guide for AI assistants

- **[CLAUDE.md](CLAUDE.md)** — development patterns, MCP-first workflow, conventions

## Contributing

Powernode follows strict architectural patterns and enforces them through automated tooling.

### Getting Oriented
1. Read **[CLAUDE.md](CLAUDE.md)** for development guidelines and conventions
2. Check **[docs/reference/auto/todo.md](docs/reference/auto/todo.md)** for current priorities (auto-generated from MCP shared knowledge)
3. Review the relevant guide or concept doc for your area (see [Documentation](#documentation) above)

### Branch Strategy
```
develop → feature/* → release/* → master
```
- Create feature branches from `develop`
- Release branches follow `release/x.y.z` naming (no "v" prefix)
- Tags use bare semver: `0.2.0`, not `v0.2.0`

### Before Submitting
```bash
# Backend: run specs
cd server && bundle exec rspec --format progress

# Frontend: run tests + type check
cd frontend && CI=true npm test
cd frontend && npx tsc --noEmit

# Full validation (specs + TS + pattern checks)
./scripts/validate.sh
```

All tests must pass. Permissions must use the permission system (never role-based checks). Frontend must use theme classes (`bg-theme-*`, `text-theme-*`) — no hardcoded colors.

## License

MIT License — see **[LICENSE](LICENSE)** for full text.

---

## Community

**Text channels**

- **GitHub issues** — [nodealchemy/powernode-platform/issues](https://github.com/nodealchemy/powernode-platform/issues) for bugs + feature requests
- **X / Twitter** — [@nodealchemy](https://x.com/nodealchemy) for general updates and informal questions

**Email**

- [contact@nodealchemy.com](mailto:contact@nodealchemy.com) — general inquiries
- [support@nodealchemy.com](mailto:support@nodealchemy.com) — technical support
- [sales@nodealchemy.com](mailto:sales@nodealchemy.com) — commercial + enterprise-tier inquiries
- [security@nodealchemy.com](mailto:security@nodealchemy.com) — security vulnerabilities; see [SECURITY.md](./SECURITY.md)

---

_Last verified: 2026-06-03_
