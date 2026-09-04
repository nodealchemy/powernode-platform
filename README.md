# Powernode Platform

> **Open-source mission control for AI agent fleets — chat to provision, agents to operate, humans to approve.**

Powernode is a control plane where an AI agent fleet provisions and operates real infrastructure — bare metal, VMs, containers, and overlay networks — from a chat interface. An operator describes what's needed, agents plan and execute the provisioning, and a control loop keeps monitoring afterward; every consequential action routes through an approval workflow (intervention policies, approval chains, a kill switch) that the operator configures. The platform performs the underlying operations itself — bare-metal PXE boot, a signed module supply chain, fleet lifecycle, SDWAN overlay networking — rather than sitting on top of infrastructure provisioned elsewhere.

## Demo

<!-- TODO(WS2-T1): replace this placeholder with the 60–90s demo GIF/video produced by the demo-script task (chat → approval queue → PXE boot → live Fleet Dashboard → drift remediation → compliance snapshot). -->

> No demo video yet — see the **[Quick Start](docs/getting-started/01-quickstart.md)** to run the platform locally in about 10 minutes.

## Why Powernode

- **Approval-gated autonomy** — Agents observe, propose, and act inside operator-defined guardrails: intervention policies, consent budgets, approval chains, a kill switch, behavioral fingerprinting, and compliance snapshots make every consequential action reviewable and auditable. Destructive operations get an extra check — for example, the on-node agent hard-refuses to run storage-migration cleanup against an ambiguous (empty) subpath, before any mount, rather than risk deleting the wrong data.
- **Full-substrate provisioning** — Bare metal → VMs → containers → K3s clusters, driven from chat through the [system extension](https://github.com/nodealchemy/powernode-system). PXE/initramfs boot, instance pools, and SDWAN overlay networking are implemented directly in the platform. Exposing a service picks from three mechanisms depending on the traffic — HostSNI-routed TLS passthrough sharing the existing `:443` entrypoint, a site-local TCP forwarder daemon, or per-mapping nftables DNAT with rate limits, connection caps, and source-CIDR allowlists — documented in the [operator decision runbook](extensions/system/docs/runbooks/traefik-tcp-exposure-vs-dnat.md).
- **Core mode ships a working install** — A bare clone with no extensions loaded still serves HTTPS on `:443`: `Core::IngressConfigWriter` generates a self-signed certificate and the four core routers (API, agent, cable, frontend) automatically. The system extension swaps in ACME certificates, mTLS, and federation routing through a provider seam (`Powernode::ExtensionRegistry`) — extending ingress without any change to core code.
- **Signed module supply chain** — On-node agents enforce keyless Cosign signature verification (Sigstore/Fulcio identity pins) and fs-verity root-hash checks before mounting any module; a failed check refuses the mount. Modules are signed in CI via OIDC-bound ephemeral certificates. _(Transparency-log/Rekor integration is not yet wired — see [docs/STABILITY.md](./docs/STABILITY.md).)_
- **Multi-provider LLM routing with FinOps** — Route across multiple LLM providers (Anthropic, OpenAI, Google, Azure, Groq, Mistral, Cohere, Ollama, and more) with cost-optimized selection, per-agent budgets, cost attribution, and ROI tracking.
- **MCP- and A2A-native** — A first-class MCP server exposes 571 actions across 63 tool classes to any MCP client (full catalog: [docs/reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md)); agents coordinate over the A2A protocol with agent cards.

*Built with Rails 8, React 19 + TypeScript, Sidekiq 8, and PostgreSQL + pgvector.*

## Quick Start

> For detailed setup instructions, see the **[Quick Start Guide](docs/getting-started/01-quickstart.md)**.

```bash
# 1. Install dependencies
cd server && bundle install
cd ../frontend && npm install
cd ../worker && bundle install
cd ..

# 2. Setup database
cd server && bundle exec rails db:create db:migrate db:seed
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

### Prerequisites
- Ruby 3.2.8
- Node.js 24+ (LTS; >=24.9 required)
- PostgreSQL with pgvector extension
- Redis 7+

## Open core boundary

Powernode is **open core**. The platform and its public extensions — **platform, system, supply-chain, and marketing** — are MIT-licensed. The **business** extension is a commercial extension available to customers; it is not part of the open-source release.

- **Always free** — Core mode: single-user, self-hosted, with all platform features unlocked. A public clone runs this way out of the box.
- **Commercial** — Multi-tenant SaaS operation, billing, reseller, enterprise compliance packs, and SLAs, delivered via the business extension.

The extension system ships with public examples (system, supply-chain, marketing) plus the commercial business extension. Extensions load dynamically via `FeatureGateService`; when none are present, the platform runs in core mode.

<details>
<summary><strong>Platform breadth</strong> — the full feature surface (click to expand)</summary>

> Powernode is a broad platform. The capabilities below are real and shipped, but they are intentionally not the headline — the wedge above is. This list is for evaluators who want the full surface area. For maturity expectations per subsystem, see [docs/STABILITY.md](./docs/STABILITY.md).

### Core Platform
- **Authentication & Security** — JWT + OAuth 2.0, 2FA, account lockout, rate limiting, CORS, CSP
- **Permission-Based Access** — granular base permissions across many categories, role-to-permission mapping
- **Real-time Communication** — ActionCable WebSocket channels for live updates, cross-tab sync
- **Modern UI** — React 19 with Tailwind CSS 4, theme system, feature-module architecture
- **Content Management** — Knowledge base articles, content pages, CMS
- **Analytics** — Customer health scoring, usage tracking, platform telemetry

### AI & Automation
- **AI Agents** — Create, deploy, and manage agents with trust scoring and autonomy tiers
- **Agent Teams** — Multi-agent orchestration (manager-led, consensus, auction, round-robin, priority-based strategies)
- **AI Autonomy** — Kill switch, goals, proposals, escalations, feedback, intervention policies, observations, duty cycle
- **Code Factory** — PRD generation, automated code review, remediation loops
- **Ralph Loops** — Recursive agent learning with multi-round tool calling
- **Model Router** — Cost-optimized provider selection across multiple LLM providers
- **MCP Integration** — A first-class MCP server spanning knowledge, memory, skills, RAG, autonomy, Docker, and DevOps (full catalog: [docs/reference/auto/mcp-tools.md](docs/reference/auto/mcp-tools.md))
- **A2A Protocol** — Agent-to-Agent communication with agent cards
- **Memory System** — 4-tier architecture (working, STM, LTM, shared) with consolidation
- **Knowledge Graph** — hybrid search + GraphRAG (live node/edge counts via `platform.graph_statistics`)
- **RAG Pipeline** — Document chunking, pgvector embeddings, agentic retrieval (multi-round reformulation)
- **Security Guardrails** — Behavioral fingerprinting, input/output rails, quarantine
- **FinOps** — Agent budgets, cost attribution, ROI metrics, optimization logging
- **AI Monitoring** — Execution traces, telemetry events, circuit breakers, performance benchmarks

### DevOps & Infrastructure
- **Git Integration** — GitHub, GitLab, Gitea, Jenkins provider support
- **CI/CD Pipelines** — Multiple step types including AI-powered steps, approval gates
- **Container Orchestration** — Docker host management, container templates, sandboxed execution
- **Docker Swarm** — Cluster, node, service, and stack management with deployment tracking
- **Integration Framework** — GitHub Actions, webhooks, MCP servers, REST API, and custom integrations
- **Supply Chain Security** — SBOM generation, attestations, license compliance
- **Secrets Management** — Vault-backed secrets with rotation tracking

### Fleet Substrate (system extension)
- **Node lifecycle** — Bare-metal, VM, and container provisioning from PXE/initramfs through to running clusters
- **Multi-arch images** — amd64 + arm64 initramfs, erofs + fs-verity rootfs
- **Signed module supply chain** — keyless Cosign signature **verification** + fs-verity digest checks enforced on-node before mount
- **Container runtimes** — Phase 1 Docker daemon provisioning, Phase 2 K3s clusters
- **Instance pools** — pre-warmed instances for bursty workloads
- **SDWAN overlay** — iBGP/FRR, virtual IPs, federation peering
- **Fleet autonomy** — sensor-driven drift detection, CVE response, rolling upgrades within intervention policies

### Multi-Platform Chat
- **Multiple platforms** — WhatsApp, Telegram, Discord, Slack, Mattermost
- **AI-Powered Routing** — Automatic agent assignment with escalation
- **Prompt Injection Protection** — Content sanitization with delimiter wrapping

### Worker System
- **Standalone Sidekiq 8** — Fully isolated, API-only communication with backend
- **Priority tiers** — critical, standard, and background work separated by weight
- **Circuit Breakers** — long timeouts for long-running AI executions, shorter ones for backend API calls
- **Scheduled jobs** — maintenance, decay, consolidation, health checks, autonomy

### Architecture Overview

```
powernode-platform/
├── server/              - Rails 8 API
│   ├── app/models/      - model namespaces (Ai, Devops, Chat, KnowledgeBase, ...)
│   ├── app/services/    - service namespaces
│   └── app/channels/    - ActionCable channels
├── frontend/            - React 19 + TypeScript (feature modules)
│   └── src/features/    - account, admin, ai, app, business, content, delegations,
│                          developer, devops, governance, missions, onboarding,
│                          privacy, supply-chain, system
├── worker/              - Sidekiq 8 (standalone, API-only)
├── extensions/          - public examples (system, supply-chain, marketing) + commercial business extension
├── docs/                - Documentation (see docs/README.md)
└── scripts/             - automation scripts
```

### Technology Stack

- **Backend**: Rails 8 | PostgreSQL | UUIDv7 | JWT + OAuth 2.0 | Redis
- **Frontend**: React 19 | TypeScript | Vite | Tailwind CSS 4 | Redux Toolkit + React Query
- **Worker**: Sidekiq 8 | Redis | Faraday | Circuit breakers
- **AI/ML**: Multiple LLM providers | MCP Protocol | A2A Protocol | pgvector (HNSW)
- **Testing**: RSpec | Jest | Playwright
- **Database**: PostgreSQL + pgvector | UUIDv7 primary keys

</details>

## Documentation

The full documentation lives in **[docs/](docs/)** — start with [docs/README.md](docs/README.md) for the visitor map.

### Common entry points

- **[Quick Start](docs/getting-started/01-quickstart.md)** — run it locally in 10 minutes
- **[Ship your first agent](docs/getting-started/02-first-agent.md)** — first deployment walkthrough
- **[Architecture](docs/concepts/architecture.md)** — system shape, namespaces, service boundaries
- **[Agents & autonomy](docs/concepts/agents-and-autonomy.md)** — agent orchestration, missions, model routing, autonomy tiers
- **[Platform engineering agents](docs/concepts/platform-engineering-agents.md)** — the Engineering hierarchy that builds the platform: Platform Architect, Platform Developer, Release Manager, the `engineering` policy set
- **[MCP & tools](docs/concepts/mcp-and-tools.md)** — MCP protocol, OAuth, tool catalog conventions
- **[Knowledge & memory](docs/concepts/knowledge-and-memory.md)** — knowledge graph, RAG, 4-tier memory, skills
- **[Permissions](docs/concepts/permissions.md)** — base permissions, role mapping, frontend rules
- **[Data model](docs/concepts/data-model.md)** — UUIDv7 + namespaces + schema conventions
- **[Chat & realtime](docs/concepts/chat-and-realtime.md)** — ActionCable channels, multi-platform chat
- **[Cost & FinOps](docs/concepts/cost-and-finops.md)** — provider pricing, budgets, ROI
- **[Stability tiers](./docs/STABILITY.md)** — what is stable vs. beta vs. experimental, and support expectations

### By task

- **Backend / Frontend / Worker** → [docs/guides/backend.md](docs/guides/backend.md), [docs/guides/frontend.md](docs/guides/frontend.md), [docs/operations/worker-operations.md](docs/operations/worker-operations.md)
- **DevOps + Docker Swarm + CI/CD** → [docs/guides/devops.md](docs/guides/devops.md), [docs/operations/docker-swarm.md](docs/operations/docker-swarm.md)
- **Security + supply chain** → [docs/guides/security.md](docs/guides/security.md)
- **Extensions** → [docs/guides/extensions.md](docs/guides/extensions.md)
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

## Project governance

- **[STABILITY.md](./docs/STABILITY.md)** — stable / beta / experimental tiers and support expectations
- **[ROADMAP.md](./ROADMAP.md)** — what's planned, by quarter
- **[GOVERNANCE.md](./GOVERNANCE.md)** — how decisions are made and the path to maintainership
- **[SECURITY.md](./SECURITY.md)** — security posture and vulnerability disclosure

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

The platform and its public extensions — **platform, system, supply-chain, and marketing** — are released under the **MIT License**; see **[LICENSE](LICENSE)**. The commercial **business** extension is licensed separately and is not part of this repository. See [Open core boundary](#open-core-boundary) for what is free versus commercial.

---

## Community

- **GitHub Discussions** — [nodealchemy/powernode-platform/discussions](https://github.com/nodealchemy/powernode-platform/discussions) for questions, ideas, support, and commercial/enterprise inquiries
- **GitHub Issues** — [nodealchemy/powernode-platform/issues](https://github.com/nodealchemy/powernode-platform/issues) for bugs + feature requests
- **Security vulnerabilities** — [report a private advisory](https://github.com/nodealchemy/powernode-platform/security/advisories/new); see [SECURITY.md](./SECURITY.md)
- **X (@nodealchemy)** — [@nodealchemy](https://x.com/nodealchemy) for updates and informal questions

Open source lives at **[github.com/nodealchemy](https://github.com/nodealchemy)**; commercial offerings at **[nodealchemy.com](https://nodealchemy.com)**.

---

_Last verified: 2026-06-12_
