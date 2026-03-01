# AI Agent Orchestration Platform - Implementation Roadmap

**Version**: 1.0 | **Date**: February 2026 | **Status**: Review Draft
**Scope**: Transform Powernode into a cutting-edge AI agent orchestration platform

---

## Executive Summary

### Current State
The Powernode platform has a **remarkably extensive** AI foundation:
- **117 database tables** for AI features
- **114 models**, **133 services**, **98 controllers**
- **252+ test files** with parallel test support
- Workflow engine with 11+ node types and DAG execution
- Chat system with 5 platform adapters (Telegram, Discord, Slack, WhatsApp, Mattermost)
- MCP integration with OAuth 2.1 and 14 configured MCP servers
- Compound learning system with pgvector embeddings
- Cost tracking, credit system, and provider management

### Target State
A world-class AI agent orchestration platform where:
- **Autonomous agents** run in Docker microVM sandboxes with full isolation
- **Agents create new agents** -- self-spawning with hierarchical management
- **Tiered autonomy** -- agents earn trust through performance metrics
- **Full Git integration** -- Gitea for dev/test, GitHub for production, via MCP
- **A2A protocol** -- agents discover and communicate with each other
- **4-tier memory** -- working → short-term → long-term → shared knowledge
- **OpenTelemetry** -- full observability with GenAI semantic conventions
- **Comprehensive audit** -- every agent decision, action, and resource usage tracked
- **Centrally managed** -- everything visible and controllable from the platform UI

### Key Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Deployment | Hybrid (platform on bare metal, agents in Docker) | Maximum flexibility |
| Agent Isolation | Docker Sandboxes (microVM) | Strongest isolation, sub-100ms cold starts |
| Git Backend | Gitea (dev/test) + GitHub (production) | Self-hosted control + production reliability |
| LLM Providers | All Major (Anthropic, OpenAI, Ollama, Google, Bedrock) | Maximum flexibility |
| Agent Communication | A2A Protocol (Linux Foundation) | Industry standard for peer-to-peer |
| Autonomy Model | Tiered (supervised → monitored → trusted → autonomous) | Progressive trust building |
| Observability | OpenTelemetry + Grafana Stack | Industry standard, self-hosted |
| Memory Architecture | Full 4-tier hierarchy | Working → Short-term → Long-term → Shared |
| Agent Billing | Hierarchical budgets | Parent allocates to children, escalation on overspend |
| Termination Policy | Configurable per-agent | Cascade, orphan, or graceful -- set at creation |
| Approach | Iterative phases (6 phases) | Each phase is deployable, safest approach |

---

## Audit Findings Summary

### Strengths
- **Architecture**: Clean service layer pattern, 79% controller consolidation achieved
- **Data Model**: Comprehensive with UUIDv7 PKs, JSONB configs, proper indexing
- **Workflow Engine**: Production-grade with versioning, scheduling, approval gates
- **Chat System**: Multi-platform with webhook verification, A2A task linking
- **Security**: Permission-based access control, guardrails pipeline, audit logging
- **Testing**: 252+ spec files, parallel test infrastructure, E2E framework

### Critical Gaps

| Gap | Impact | Phase to Fix |
|-----|--------|-------------|
| No Gitea/GitHub integration | Agents can't manage code | Phase 1 |
| `.env.staging` in git with real credentials | Security breach risk | Phase 1 |
| ProviderClientService has NotImplementedError stubs | Runtime failures | Phase 1 |
| Container deployment scaffolded but not functional | Agents can't run in isolation | Phase 2 |
| No agent self-spawning capability | Core feature missing | Phase 3 |
| No tiered autonomy system | Agents either fully controlled or not | Phase 3 |
| Single PostgreSQL instance (no replication) | Single point of failure | Phase 1 |
| No OpenTelemetry instrumentation | No production observability | Phase 1/5 |
| No CI/CD pipeline (placeholder only) | Manual deployment | Phase 1 |
| Pre-existing test failures (4 specs) | Test suite unreliable | Phase 1 |
| Hardcoded colors in ApprovalResponsePage | Theme violation | Phase 1 |

---

## Phase 1: Foundation & Tech Debt

**Goal**: Secure the platform, fix known issues, establish dual Git integration (Gitea + GitHub), CI/CD pipeline.
**Estimated Effort**: 2-3 weeks
**Dependencies**: None (starting point)

### 1.1 Security Remediation (Day 1-2)

**Remove secrets from git:**
```bash
# Remove .env.staging from git tracking
git rm --cached .env.staging
echo ".env.staging" >> .gitignore
# Rotate ALL exposed credentials:
# - SMTP passwords
# - Slack webhook URLs
# - PagerDuty service keys
# - Any API keys in the file
```

**Files to modify:**
- `.gitignore` -- add `.env.staging`
- `.env.staging` -- remove from git history (consider `git filter-branch` or BFG)
- All exposed credential services -- rotate keys

### 1.2 Fix Pre-existing Issues (Day 2-4)

**Provider stubs (`server/app/services/ai/provider_client_service.rb`):**
- Implement proper adapter routing for all 5 providers
- Add Google Vertex AI and AWS Bedrock adapters
- Each provider adapter handles: text generation, streaming, chat completion
- Graceful degradation when provider doesn't support a capability (return capability_not_supported instead of NotImplementedError)

**Test failures:**
- `server/spec/models/plan_spec.rb:549` -- investigate and fix
- `server/spec/services/ai/ai_workflow_orchestrator_spec.rb:572/583/605` -- investigate and fix

**Theme violation:**
- `frontend/src/features/ai/workflows/pages/ApprovalResponsePage.tsx:172` -- replace `from-purple-600 to-violet-600` with `bg-theme-primary`

**Schema check:**
- Verify if both `ai_message` and `ai_messages` tables exist, consolidate if duplicate

### 1.3 Git Integration: Gitea + GitHub (Day 4-8)

**New files to create:**

```
server/app/services/ai/git/
├── unified_git_service.rb      # Abstraction over Gitea + GitHub
├── gitea_adapter.rb            # Gitea API client
├── github_adapter.rb           # GitHub API client (via Octokit)
├── agent_workspace_service.rb  # Per-agent repo provisioning
└── webhook_handler_service.rb  # Handle Git webhooks for CI triggers
```

**UnifiedGitService API:**
```ruby
module Ai
  module Git
    class UnifiedGitService
      def create_repo(agent:, name:, backend: :gitea)
      def create_branch(repo:, branch_name:, from:)
      def commit_files(repo:, branch:, files:, message:)
      def create_pull_request(repo:, title:, source:, target:)
      def get_file_contents(repo:, path:, ref:)
      def list_repos(account:, backend: nil)
      def delete_repo(repo:)
      def sync_to_github(gitea_repo:, github_repo:)  # Gitea → GitHub sync
    end
  end
end
```

**MCP Server Configuration:**
- Add Gitea MCP server to `docker/docker-compose.mcp.yml`
- Add GitHub MCP server to `docker/docker-compose.mcp.yml`
- Configure both in the platform's MCP management UI

**Database migrations:**
```ruby
# New table: ai_git_repositories
create_table :ai_git_repositories, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :ai_agent, type: :uuid, foreign_key: true  # nullable for team repos
  t.string :name, null: false
  t.string :backend, null: false  # 'gitea' or 'github'
  t.string :remote_id            # ID on the Git platform
  t.string :clone_url
  t.string :web_url
  t.string :default_branch, default: 'main'
  t.jsonb :settings, default: {}
  t.string :status, default: 'active'
  t.timestamps
  t.index [:account_id, :name, :backend], unique: true
end
```

### 1.4 CI/CD Pipeline (Day 8-10)

**Gitea Actions (dev/test):**
```yaml
# .gitea/workflows/test.yml
name: Test Suite
on: [push, pull_request]
jobs:
  backend-tests:
    runs-on: ubuntu-latest
    services:
      postgres: { image: postgres:16 }
      redis: { image: redis:7 }
    steps:
      - uses: actions/checkout@v4
      - run: bundle exec parallel_rspec spec/
  frontend-tests:
    runs-on: ubuntu-latest
    steps:
      - run: CI=true npm test
      - run: npx tsc --noEmit
```

**GitHub Actions (production):**
```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [master]
jobs:
  deploy:
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t powernode-backend ./server
      - run: docker build -t powernode-frontend ./frontend
      - run: docker build -t powernode-worker ./worker
      - run: ./scripts/deployment/deploy.sh production
```

### 1.5 OpenTelemetry Skeleton (Day 10-12)

**Backend (`server/Gemfile`):**
```ruby
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
gem 'opentelemetry-instrumentation-rails'
gem 'opentelemetry-instrumentation-active_record'
gem 'opentelemetry-instrumentation-sidekiq'
gem 'opentelemetry-instrumentation-net_http'
```

**Initializer (`server/config/initializers/opentelemetry.rb`):**
```ruby
require 'opentelemetry/sdk'
require 'opentelemetry-exporter-otlp'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'powernode-backend'
  c.use_all  # Auto-instrument Rails, AR, Net::HTTP
end
```

**Docker Compose addition:**
```yaml
otel-collector:
  image: otel/opentelemetry-collector-contrib:latest
  command: ["--config=/etc/otel-collector-config.yaml"]
  volumes:
    - ./configs/otel/collector.yaml:/etc/otel-collector-config.yaml
  ports:
    - "4317:4317"   # OTLP gRPC
    - "4318:4318"   # OTLP HTTP
```

### 1.6 Database Hardening (Day 12-14)

- Configure PostgreSQL streaming replication
- Set up PgBouncer for connection pooling
- Add automated backup cron job
- Configure read replica for reporting queries

### Phase 1 Deliverables Checklist

- [ ] `.env.staging` removed from git, credentials rotated
- [ ] All ProviderClientService stubs replaced with proper adapters
- [ ] 4 pre-existing test failures fixed
- [ ] ApprovalResponsePage theme violation fixed
- [ ] Gitea MCP server deployed and connected
- [ ] GitHub MCP server deployed and connected
- [ ] `UnifiedGitService` with Gitea + GitHub adapters
- [ ] `ai_git_repositories` table created
- [ ] CI/CD pipeline: Gitea Actions for dev, GitHub Actions for prod
- [ ] OpenTelemetry SDK installed and basic instrumentation active
- [ ] OTel Collector deployed in Docker Compose
- [ ] PostgreSQL replication configured
- [ ] PgBouncer connection pooling active
- [ ] Automated backup scheduling active
- [ ] All existing tests passing

---

## Phase 2: Agent Runtime & Docker Sandbox Execution

**Goal**: Agents execute code in isolated Docker microVM sandboxes with full lifecycle management.
**Estimated Effort**: 3-4 weeks
**Dependencies**: Phase 1 (Git integration, OTel skeleton)

### 2.1 Docker Sandbox Manager

**New files:**
```
server/app/services/ai/runtime/
├── sandbox_manager_service.rb    # Create/destroy/manage sandboxes
├── sandbox_health_service.rb     # Monitor sandbox health
├── sandbox_network_service.rb    # Network isolation config
├── sandbox_resource_service.rb   # Resource limits enforcement
└── mcp_bridge_service.rb         # Platform MCP inside sandbox

server/app/models/ai/
├── agent_sandbox.rb              # Sandbox state tracking

worker/app/jobs/
├── ai_sandbox_provisioning_job.rb
├── ai_sandbox_health_check_job.rb
├── ai_sandbox_cleanup_job.rb
```

**SandboxManagerService API:**
```ruby
module Ai
  module Runtime
    class SandboxManagerService
      # Create a new isolated sandbox for an agent
      def create_sandbox(agent:, config: {})
        # 1. Pull/build agent image
        # 2. Create Docker Sandbox microVM
        # 3. Mount agent's Gitea repo as workspace
        # 4. Inject platform MCP bridge
        # 5. Apply resource limits
        # 6. Start sandbox
        # Returns: Ai::AgentSandbox record
      end

      def destroy_sandbox(sandbox:, graceful: true)
      def pause_sandbox(sandbox:)
      def resume_sandbox(sandbox:)
      def exec_in_sandbox(sandbox:, command:)
      def stream_logs(sandbox:, &block)
      def get_metrics(sandbox:)  # CPU, memory, disk, network
    end
  end
end
```

**AgentSandbox Model:**
```ruby
# Migration
create_table :ai_agent_sandboxes, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :ai_agent, type: :uuid, null: false, foreign_key: true
  t.references :ai_agent_execution, type: :uuid, foreign_key: true
  t.string :container_id          # Docker container/sandbox ID
  t.string :status, null: false, default: 'pending'
    # pending → provisioning → running → paused → stopping → terminated → error
  t.string :image                 # Docker image used
  t.jsonb :resource_limits, default: {}
    # { cpu: "1.0", memory: "512m", disk: "1g", network: "restricted" }
  t.jsonb :resource_usage, default: {}
    # { cpu_percent: 45.2, memory_mb: 256, disk_mb: 100 }
  t.jsonb :network_config, default: {}
    # { mode: "restricted", allowed_hosts: ["api.powernode.local"] }
  t.jsonb :mcp_config, default: {}
    # { bridge_port: 8080, tools_enabled: [...] }
  t.string :workspace_path        # Mounted Gitea repo path
  t.datetime :started_at
  t.datetime :terminated_at
  t.string :termination_reason
  t.integer :restart_count, default: 0
  t.timestamps
  t.index :container_id, unique: true
  t.index [:ai_agent_id, :status]
end
```

### 2.2 Platform MCP Bridge

**Purpose**: Each sandbox runs an MCP server that connects the agent back to the platform.

**Exposed Tools (scoped by agent trust level):**
```
# Always available
platform.memory.read       - Read from memory tiers
platform.memory.write      - Write to working/short-term memory
platform.audit.log         - Log an audit event
platform.status.report     - Report execution progress

# Monitored+ trust level
platform.git.commit        - Commit to agent's repo
platform.git.branch        - Create/switch branches
platform.git.pr            - Create pull requests
platform.tools.execute     - Execute registered MCP tools
platform.chat.send         - Send message in chat channel

# Trusted+ trust level
platform.agent.spawn       - Create a sub-agent
platform.agent.configure   - Modify own configuration
platform.workflow.trigger  - Trigger a workflow
platform.knowledge.share   - Publish to shared knowledge base

# Autonomous only
platform.agent.deploy      - Deploy agent to production
platform.resources.scale   - Request more resources
platform.network.expand    - Request network access
```

### 2.3 Agent Container Lifecycle

**State Machine:**
```
                    ┌──────────────┐
                    │   pending    │
                    └──────┬───────┘
                           │ provision
                    ┌──────▼───────┐
                    │ provisioning │
                    └──────┬───────┘
                           │ start
                    ┌──────▼───────┐
              ┌─────│   running    │─────┐
              │     └──────┬───────┘     │
              │ pause      │ stop        │ error
        ┌─────▼─────┐     │     ┌───────▼──────┐
        │  paused   │     │     │    error     │
        └─────┬─────┘     │     └──────────────┘
              │ resume     │
              └────────────┤
                           │
                    ┌──────▼───────┐
                    │  stopping    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ terminated   │
                    └──────────────┘
```

### 2.4 Real-Time Log Streaming

**New ActionCable Channel: `AgentSandboxChannel`**
```ruby
class AgentSandboxChannel < ApplicationCable::Channel
  def subscribed
    sandbox = Ai::AgentSandbox.find(params[:sandbox_id])
    stream_for sandbox
  end
end

# Broadcasts:
# { type: "log", stream: "stdout", content: "...", timestamp: "..." }
# { type: "log", stream: "stderr", content: "...", timestamp: "..." }
# { type: "metrics", cpu: 45.2, memory_mb: 256, ... }
# { type: "status", status: "running", ... }
```

### 2.5 Frontend Components

**New components:**
```
frontend/src/features/ai/sandboxes/
├── pages/
│   └── SandboxDashboardPage.tsx       # All sandboxes overview
├── components/
│   ├── SandboxList.tsx                # List of running sandboxes
│   ├── SandboxCard.tsx                # Individual sandbox status card
│   ├── SandboxTerminal.tsx            # Real-time terminal into sandbox
│   ├── SandboxMetrics.tsx             # CPU/memory/disk/network charts
│   ├── SandboxLogViewer.tsx           # Streaming log viewer
│   └── SandboxResourceConfig.tsx      # Resource limits configuration
├── hooks/
│   ├── useSandboxes.ts
│   ├── useSandboxLogs.ts              # WebSocket log streaming
│   └── useSandboxMetrics.ts           # Real-time metrics
└── types/
    └── sandbox-types.ts
```

### Phase 2 Deliverables Checklist

- [ ] `SandboxManagerService` with full lifecycle management
- [ ] Docker Sandbox microVM integration tested and working
- [ ] `AgentSandbox` model with state machine
- [ ] Platform MCP Bridge running inside sandboxes
- [ ] Tool access scoped by trust level
- [ ] Git workspace mounted per sandbox (from Gitea)
- [ ] Real-time log streaming via WebSocket
- [ ] Resource limits enforced (CPU, memory, disk, network)
- [ ] Health monitoring with auto-restart
- [ ] Sandbox dashboard UI with terminal, logs, and metrics
- [ ] Cleanup jobs for terminated sandboxes
- [ ] OTel spans on sandbox lifecycle events
- [ ] Comprehensive test coverage

---

## Phase 3: Agent Autonomy & Self-Spawning

**Goal**: Agents create sub-agents, earn trust, and operate at configurable autonomy levels.
**Estimated Effort**: 3-4 weeks
**Dependencies**: Phase 2 (Sandbox runtime)

### 3.1 Agent Factory

**New files:**
```
server/app/services/ai/agents/
├── factory_service.rb             # Create agents programmatically
├── lineage_service.rb             # Track parent-child relationships
├── capability_inheritance.rb      # Capability propagation rules
└── termination_policy_service.rb  # Handle agent termination cascades

server/app/models/ai/
├── agent_lineage.rb               # Parent-child tracking
├── agent_trust_score.rb           # Trust dimensions and composite score
├── agent_budget.rb                # Hierarchical budget allocation
```

**FactoryService API:**
```ruby
module Ai
  module Agents
    class FactoryService
      def spawn(
        parent_agent:,
        name:,
        purpose:,
        capabilities: [],       # Subset of parent's capabilities
        provider: nil,          # Inherit from parent if nil
        model: nil,             # Inherit from parent if nil
        budget: nil,            # Allocated from parent's pool
        termination_policy: :graceful,  # :cascade, :orphan, :graceful
        auto_sandbox: true      # Auto-create sandbox
      )
        # 1. Validate parent has spawn permission (trust level)
        # 2. Validate recursion depth < max (default 5)
        # 3. Validate total agent count < account limit
        # 4. Create agent record with parent_agent_id
        # 5. Create lineage record
        # 6. Allocate budget from parent's pool
        # 7. Inherit capabilities (never exceed parent's)
        # 8. Inherit security constraints
        # 9. Set initial trust level to :supervised
        # 10. Optionally create sandbox
        # 11. Log audit event
        # Returns: Ai::Agent
      end

      def terminate(agent:, reason:, force: false)
        # Apply termination policy:
        # - :cascade → terminate all descendants
        # - :orphan → reassign children to parent's parent
        # - :graceful → give children grace period, then terminate
      end
    end
  end
end
```

**Database Migrations:**
```ruby
# ai_agent_lineage
create_table :ai_agent_lineages, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :parent_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
  t.references :child_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
  t.integer :depth, null: false  # Distance from root agent
  t.string :spawn_reason
  t.jsonb :inherited_capabilities, default: []
  t.jsonb :inherited_constraints, default: {}
  t.timestamps
  t.index [:parent_agent_id, :child_agent_id], unique: true
  t.index :child_agent_id
  t.index :depth
end

# Add to ai_agents
add_column :ai_agents, :parent_agent_id, :uuid
add_column :ai_agents, :trust_level, :string, default: 'supervised'
add_column :ai_agents, :termination_policy, :string, default: 'graceful'
add_column :ai_agents, :max_spawn_depth, :integer, default: 5
add_column :ai_agents, :autonomy_config, :jsonb, default: {}
add_foreign_key :ai_agents, :ai_agents, column: :parent_agent_id

# ai_agent_trust_scores
create_table :ai_agent_trust_scores, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :ai_agent, type: :uuid, null: false, foreign_key: true
  t.float :reliability, default: 0.0      # 0-1: execution success rate
  t.float :cost_efficiency, default: 0.0  # 0-1: actual vs budgeted cost
  t.float :safety, default: 0.0           # 0-1: guardrail compliance
  t.float :quality, default: 0.0          # 0-1: output quality (LLM judge)
  t.float :speed, default: 0.0            # 0-1: execution speed vs expected
  t.float :composite_score, default: 0.0  # Weighted average
  t.string :trust_level, null: false       # supervised/monitored/trusted/autonomous
  t.integer :total_executions, default: 0
  t.integer :successful_executions, default: 0
  t.integer :failed_executions, default: 0
  t.integer :guardrail_violations, default: 0
  t.datetime :last_promotion_at
  t.datetime :last_demotion_at
  t.jsonb :promotion_history, default: []
  t.timestamps
  t.index [:ai_agent_id], unique: true
end

# ai_agent_budgets (hierarchical)
create_table :ai_agent_budgets, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :ai_agent, type: :uuid, null: false, foreign_key: true
  t.references :parent_budget, type: :uuid, foreign_key: { to_table: :ai_agent_budgets }
  t.decimal :allocated_amount, precision: 10, scale: 4, null: false
  t.decimal :spent_amount, precision: 10, scale: 4, default: 0
  t.decimal :reserved_for_children, precision: 10, scale: 4, default: 0
  t.string :currency, default: 'USD'
  t.string :period, default: 'monthly'  # daily, weekly, monthly, total
  t.datetime :period_start
  t.datetime :period_end
  t.boolean :allow_overspend, default: false
  t.decimal :overspend_limit, precision: 10, scale: 4, default: 0
  t.jsonb :alerts, default: {}  # { warn_at: 0.8, critical_at: 0.95 }
  t.timestamps
  t.index [:ai_agent_id, :period_start]
end
```

### 3.2 Trust Engine

**TrustEngineService:**
```ruby
module Ai
  module Autonomy
    class TrustEngineService
      TIER_THRESHOLDS = {
        supervised: 0.0,    # Default for new agents
        monitored: 0.4,     # After 10+ successful executions
        trusted: 0.7,       # After 50+ executions, <5% failure rate
        autonomous: 0.9     # After 200+ executions, <2% failure, 0 violations
      }.freeze

      MIN_EXECUTIONS_FOR_PROMOTION = {
        monitored: 10,
        trusted: 50,
        autonomous: 200
      }.freeze

      def evaluate(agent:)
        # 1. Calculate dimension scores from execution history
        # 2. Compute weighted composite score
        # 3. Check promotion/demotion eligibility
        # 4. Apply changes if threshold crossed
        # 5. Log trust change event
      end

      def force_demote(agent:, reason:, to_level: :supervised)
        # Instant demotion for critical violations
      end

      def promote(agent:, to_level:, approved_by: nil)
        # Manual promotion by human
      end
    end
  end
end
```

### 3.3 Frontend Components

```
frontend/src/features/ai/autonomy/
├── pages/
│   └── AutonomyDashboardPage.tsx
├── components/
│   ├── AgentLineageTree.tsx        # Visual parent-child tree
│   ├── TrustScoreCard.tsx          # Trust dimensions radar chart
│   ├── TrustHistoryTimeline.tsx    # Promotion/demotion history
│   ├── AutonomyConfigPanel.tsx     # Configure trust rules
│   ├── SpawnApprovalQueue.tsx      # Approve/reject spawn requests
│   ├── BudgetAllocationPanel.tsx   # Hierarchical budget view
│   ├── AgentKillSwitch.tsx         # Emergency termination UI
│   └── AutonomyTierBadge.tsx       # Visual trust level indicator
├── hooks/
│   ├── useAgentLineage.ts
│   ├── useTrustScores.ts
│   └── useAgentBudgets.ts
└── types/
    └── autonomy-types.ts
```

### Phase 3 Deliverables Checklist

- [ ] `FactoryService` for programmatic agent spawning
- [ ] Parent-child lineage tracking with depth limits
- [ ] Capability inheritance (child ≤ parent permissions)
- [ ] `TrustEngineService` with 5 dimensions + composite score
- [ ] 4 autonomy tiers: supervised → monitored → trusted → autonomous
- [ ] Automatic promotion/demotion based on configurable rules
- [ ] Instant demotion on critical violations
- [ ] Hierarchical budget system with overspend alerts
- [ ] Configurable termination policies (cascade/orphan/graceful)
- [ ] Kill switch for emergency agent + descendant termination
- [ ] Agent lineage tree visualization
- [ ] Trust score dashboard with history
- [ ] Budget allocation UI
- [ ] Spawn approval queue
- [ ] OTel spans on autonomy events
- [ ] Full test coverage

---

## Phase 4: Full Memory Architecture

**Goal**: 4-tier memory hierarchy with cross-agent knowledge sharing and integrity verification.
**Estimated Effort**: 3-4 weeks
**Dependencies**: Phase 2 (sandbox runtime for working memory), Phase 3 (trust levels for access control)

### 4.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Memory Router                              │
│  Determines which tier to query/write based on context       │
└──────────┬──────────┬──────────┬──────────┬─────────────────┘
           │          │          │          │
    ┌──────▼──┐ ┌─────▼────┐ ┌──▼───────┐ ┌▼──────────────┐
    │ Working │ │Short-term│ │Long-term │ │ Shared         │
    │ Memory  │ │ Memory   │ │ Memory   │ │ Knowledge Base │
    │         │ │          │ │          │ │                │
    │In-proc  │ │ Redis    │ │ pgvector │ │ pgvector + ACL │
    │< 1 exec │ │ < 24h    │ │ Forever  │ │ Cross-agent    │
    │Agent-   │ │ Agent-   │ │ Account- │ │ Platform-wide  │
    │ local   │ │ scoped   │ │ scoped   │ │ with ACL       │
    └─────────┘ └──────────┘ └──────────┘ └────────────────┘
```

### 4.2 New Services

```
server/app/services/ai/memory/
├── router_service.rb              # Query/write routing across tiers
├── working_memory_service.rb      # In-sandbox state management
├── short_term_service.rb          # Redis-backed cross-turn memory
├── long_term_service.rb           # pgvector semantic memory (enhance existing)
├── shared_knowledge_service.rb    # Cross-agent knowledge base
├── integrity_service.rb           # Memory integrity verification
├── consolidation_service.rb       # Promote memories between tiers
└── decay_service.rb               # Age-based memory cleanup
```

### 4.3 Database Migrations

```ruby
# ai_agent_short_term_memories (for persistence/recovery, hot data in Redis)
create_table :ai_agent_short_term_memories, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :ai_agent, type: :uuid, null: false, foreign_key: true
  t.string :session_id, null: false
  t.string :key, null: false
  t.jsonb :value, null: false
  t.string :data_type              # 'scratchpad', 'context', 'tool_result', 'reasoning'
  t.datetime :expires_at
  t.integer :access_count, default: 0
  t.datetime :last_accessed_at
  t.timestamps
  t.index [:ai_agent_id, :session_id, :key], unique: true
  t.index :expires_at
end

# ai_shared_knowledges
create_table :ai_shared_knowledges, id: :uuid do |t|
  t.references :account, type: :uuid, null: false, foreign_key: true
  t.references :created_by_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
  t.string :namespace, null: false   # 'team:{id}', 'account:{id}', 'global'
  t.string :title, null: false
  t.text :content, null: false
  t.string :content_type            # 'insight', 'procedure', 'fact', 'pattern'
  # embedding column added via raw SQL (pgvector)
  t.float :quality_score, default: 0.0
  t.float :trust_score, default: 0.0    # Based on creator's trust level
  t.integer :access_count, default: 0
  t.integer :citation_count, default: 0  # How many agents referenced this
  t.jsonb :provenance, default: {}       # { source_type, source_id, chain_of_custody }
  t.jsonb :access_control, default: {}   # { allowed_agents: [], allowed_teams: [] }
  t.string :integrity_hash              # SHA-256 of content for corruption detection
  t.boolean :verified, default: false
  t.datetime :last_accessed_at
  t.datetime :expires_at
  t.timestamps
  t.index :namespace
  t.index [:namespace, :content_type]
  t.index :quality_score
end
# Add vector column: execute "ALTER TABLE ai_shared_knowledges ADD COLUMN embedding vector(1536)"
# Add HNSW index for cosine similarity search
```

### 4.4 Redis Schema for Short-Term Memory

```
stm:{agent_id}:{session_id}:scratchpad     → JSON (agent notes)
stm:{agent_id}:{session_id}:context        → JSON (conversation context)
stm:{agent_id}:{session_id}:tool_results   → JSON (cached tool outputs)
stm:{agent_id}:{session_id}:reasoning      → JSON (chain-of-thought)
stm:{agent_id}:cross_session:{key}         → JSON (persists across sessions)
stm:metrics:{agent_id}:hit_count           → Integer
stm:metrics:{agent_id}:miss_count          → Integer
```

### 4.5 Memory Integrity (OWASP ASI05)

```ruby
module Ai
  module Memory
    class IntegrityService
      def compute_hash(content)
        Digest::SHA256.hexdigest(content.to_json)
      end

      def verify_integrity(knowledge)
        expected = compute_hash(knowledge.content)
        knowledge.integrity_hash == expected
      end

      def audit_access(knowledge, agent, action)
        # Log every read/write for forensic analysis
      end

      def detect_corruption(scope: :all)
        # Scan all shared knowledge for integrity violations
        # Alert on any mismatches
      end
    end
  end
end
```

### Phase 4 Deliverables Checklist

- [ ] Memory Router with cascading read/write across all 4 tiers
- [ ] Working Memory: checkpoint to Redis on sandbox pause
- [ ] Short-term Memory: Redis-backed with TTL and persistence recovery
- [ ] Long-term Memory: Enhanced compound learning pipeline
- [ ] Shared Knowledge Base with ACL and provenance tracking
- [ ] Memory integrity verification (SHA-256 hashing)
- [ ] Memory consolidation service (promote across tiers)
- [ ] Memory decay service (age-based cleanup)
- [ ] Redis schema for hot-path memory access
- [ ] Memory Explorer UI (browse all 4 tiers)
- [ ] Knowledge sharing UI with access control
- [ ] Memory health dashboard
- [ ] OTel spans on memory operations
- [ ] Full test coverage

---

## Phase 5: Full Observability & A2A Protocol

**Goal**: Complete OpenTelemetry instrumentation with GenAI conventions, Grafana dashboards, and A2A inter-agent protocol.
**Estimated Effort**: 3-4 weeks
**Dependencies**: Phases 1-4

### 5.1 OpenTelemetry Full Instrumentation

**GenAI Semantic Conventions for all LLM calls:**
```ruby
# Custom span attributes per OpenTelemetry GenAI semantic conventions
span.set_attribute('gen_ai.system', 'anthropic')
span.set_attribute('gen_ai.request.model', 'claude-opus-4-6')
span.set_attribute('gen_ai.request.max_tokens', 4096)
span.set_attribute('gen_ai.request.temperature', 0.7)
span.set_attribute('gen_ai.usage.input_tokens', 1500)
span.set_attribute('gen_ai.usage.output_tokens', 800)
span.set_attribute('gen_ai.response.finish_reasons', ['end_turn'])
# Custom attributes
span.set_attribute('powernode.agent.id', agent.id)
span.set_attribute('powernode.agent.trust_level', 'trusted')
span.set_attribute('powernode.cost.usd', 0.0045)
span.set_attribute('powernode.sandbox.id', sandbox.id)
```

**Trace Hierarchy:**
```
Workflow Execution (root span)
  └── Node Execution (child span)
      └── Agent Execution (child span)
          ├── Guardrails: Input Rail (child span)
          ├── Memory: Context Retrieval (child span)
          ├── LLM Call (child span) ← GenAI semantic conventions
          ├── Tool Execution (child span)
          ├── Guardrails: Output Rail (child span)
          └── Memory: Write Results (child span)
```

### 5.2 Grafana Dashboards

**Dashboard List:**
1. **Agent Lifecycle** -- Creation → execution → completion funnel, active agents over time
2. **Cost Attribution** -- Per-agent, per-team, per-provider, per-model costs
3. **Trust & Autonomy** -- Trust score distributions, promotion rates, violation tracking
4. **Memory Health** -- Tier utilization, hit rates, decay rates, corruption alerts
5. **Provider Performance** -- Latency P50/P95/P99, error rates, circuit breaker states
6. **Agent Topology** -- Real-time graph of agent connections and message flow
7. **Sandbox Resources** -- CPU, memory, disk, network across all running sandboxes
8. **A2A Communication** -- Task exchange volumes, success rates, latency

### 5.3 A2A Protocol Implementation

**Build on existing `ai_a2a_tasks` and `ai_a2a_task_events` tables.**

**Agent Card Endpoint:**
```
GET /api/v1/ai/agents/:id/.well-known/agent.json

Response:
{
  "name": "CodeReviewer-Agent-7",
  "description": "Automated code review specialist",
  "url": "https://powernode.local/api/v1/ai/agents/{id}/a2a",
  "provider": { "organization": "Powernode", "url": "..." },
  "version": "1.0.0",
  "capabilities": {
    "streaming": true,
    "pushNotifications": true,
    "stateTransitionHistory": true
  },
  "authentication": {
    "schemes": ["bearer"]
  },
  "defaultInputModes": ["text"],
  "defaultOutputModes": ["text"],
  "skills": [
    { "id": "code-review", "name": "Code Review", "description": "..." },
    { "id": "security-audit", "name": "Security Audit", "description": "..." }
  ]
}
```

**A2A Task Exchange:**
```ruby
module Ai
  module A2a
    class ProtocolService
      def send_task(from_agent:, to_agent:, task:)
        # 1. Validate both agents' capabilities
        # 2. Create A2A task record
        # 3. Route to target agent (local or remote)
        # 4. Stream updates back to caller
      end

      def discover_agents(capabilities: [], account: nil)
        # Search agent registry for matching capabilities
      end

      def publish_agent_card(agent:)
        # Generate and cache agent card JSON
      end
    end
  end
end
```

### Phase 5 Deliverables Checklist

- [ ] Full OTel instrumentation on all AI service calls
- [ ] GenAI semantic conventions on every LLM request
- [ ] Custom Powernode span attributes (agent_id, trust_level, cost, sandbox_id)
- [ ] Trace hierarchy: Workflow → Node → Agent → LLM Call
- [ ] OTel Collector → Prometheus + Loki + Tempo pipeline working
- [ ] 8 Grafana dashboards created and functional
- [ ] A2A Agent Card endpoint for every agent
- [ ] A2A task exchange between agents
- [ ] Agent discovery by capability
- [ ] A2A communication dashboard
- [ ] Full test coverage

---

## Phase 6: Polish, Security & Scale

**Goal**: OWASP compliance, comprehensive audit UI, performance optimization, production hardening.
**Estimated Effort**: 2-3 weeks
**Dependencies**: Phases 1-5

### 6.1 OWASP Agentic Top 10 Compliance

| Risk | Mitigation | Status |
|------|-----------|--------|
| ASI01 - Goal Hijack | Enhanced guardrails with intent verification | Enhance existing |
| ASI02 - Tool Misuse | Tool access audit, anomaly detection per tool | New |
| ASI03 - Privilege Abuse | Least agency via trust tiers, capability inheritance | Phase 3 |
| ASI04 - Cascading Failures | Cross-agent circuit breakers, blast radius limits | Enhance existing |
| ASI05 - Memory Corruption | Integrity hashing on all shared memory | Phase 4 |
| ASI06 - Sensitive Data | PII detection in agent outputs, log redaction | New |
| ASI07 - Input Validation | Enhanced prompt injection detection | Enhance existing |
| ASI08 - Supply Chain | Agent template verification, signed images | New |
| ASI09 - Uncontrolled Scaling | Resource quotas, budget limits, kill switches | Phase 3 |
| ASI10 - Rogue Agents | Behavioral anomaly detection + auto-demotion | New |

### 6.2 Comprehensive Audit UI

**New pages:**
```
frontend/src/features/ai/audit/
├── pages/
│   ├── AgentLifecycleViewerPage.tsx    # Complete agent timeline
│   ├── DecisionAuditTrailPage.tsx      # Every agent decision with reasoning
│   ├── ResourceUsageAuditPage.tsx      # Tokens, API calls, cost, sandbox resources
│   ├── SecurityEventLogPage.tsx        # Violations, trust changes, escalations
│   └── ComplianceReportPage.tsx        # Exportable compliance reports
├── components/
│   ├── AuditTimeline.tsx              # Chronological event viewer
│   ├── DecisionTree.tsx               # Agent reasoning chain visualization
│   ├── ResourceHeatmap.tsx            # Resource usage over time
│   ├── SecurityAlertList.tsx          # Active security alerts
│   ├── ComplianceScorecard.tsx        # OWASP compliance status
│   └── AuditExportButton.tsx          # PDF/CSV export
```

### 6.3 Performance & Scale

- PostgreSQL read replicas for reporting
- Redis clustering for memory tier
- PgBouncer connection pooling
- Agent execution queue optimization (priority queues)
- Frontend code splitting for AI features (lazy loading)
- CDN for static assets

### Phase 6 Deliverables Checklist

- [ ] OWASP Agentic Top 10 compliance audit completed
- [ ] Anomaly detection for tool misuse and rogue behavior
- [ ] PII detection and redaction in agent outputs
- [ ] 5 comprehensive audit UI pages
- [ ] Exportable compliance reports (PDF/CSV)
- [ ] Database read replicas active
- [ ] Redis clustering configured
- [ ] Frontend code splitting implemented
- [ ] CDN configured for static assets
- [ ] Full security audit documentation

---

## Summary: Implementation Order

```
Phase 1 (2-3 weeks): Foundation
  ├── Security fixes (secrets, test failures, theme)
  ├── Git integration (Gitea + GitHub via MCP)
  ├── CI/CD pipeline (Gitea Actions + GitHub Actions)
  ├── OpenTelemetry skeleton
  └── Database hardening

Phase 2 (3-4 weeks): Agent Runtime
  ├── Docker Sandbox microVM integration
  ├── Platform MCP Bridge
  ├── Agent container lifecycle
  ├── Real-time log streaming
  └── Sandbox dashboard UI

Phase 3 (3-4 weeks): Agent Autonomy
  ├── Agent Factory (self-spawning)
  ├── Tiered trust system
  ├── Hierarchical budgets
  ├── Termination policies
  └── Autonomy dashboard UI

Phase 4 (3-4 weeks): Memory Architecture
  ├── Working memory (in-process)
  ├── Short-term memory (Redis)
  ├── Long-term memory (pgvector enhanced)
  ├── Shared knowledge base
  └── Memory integrity + explorer UI

Phase 5 (3-4 weeks): Observability & A2A
  ├── Full OTel instrumentation
  ├── Grafana dashboards (8)
  ├── A2A protocol implementation
  ├── Agent discovery
  └── Communication dashboard

Phase 6 (2-3 weeks): Polish & Security
  ├── OWASP compliance
  ├── Comprehensive audit UI
  ├── Performance optimization
  └── Production hardening

Total Estimated: 16-22 weeks (4-5.5 months)
```

---

## Technical Stack Additions

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Agent Sandbox | Docker Sandboxes (microVM) | Isolated agent execution |
| Git (Dev/Test) | Gitea + Gitea MCP Server | Self-hosted code management |
| Git (Production) | GitHub + GitHub MCP Server | Production code management |
| Agent-to-Agent | A2A Protocol (Linux Foundation) | Inter-agent communication |
| Working Memory | In-process (sandbox) | Single-execution state |
| Short-term Memory | Redis (with TTL) | Cross-turn context |
| Long-term Memory | pgvector (existing) | Semantic memory |
| Shared Knowledge | pgvector + ACL | Cross-agent knowledge |
| Traces | OpenTelemetry + Tempo | Distributed tracing |
| Metrics | OpenTelemetry + Prometheus | Application metrics |
| Logs | OpenTelemetry + Loki | Centralized logging |
| Dashboards | Grafana | Visualization |
| CI/CD (Dev) | Gitea Actions | Development pipeline |
| CI/CD (Prod) | GitHub Actions | Production pipeline |

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Docker Sandbox API changes | Medium | High | Pin SDK version, abstract behind adapter |
| A2A protocol spec changes | Medium | Medium | Build on existing A2A models, minimize protocol coupling |
| Agent runaway costs | High | High | Hierarchical budgets + kill switches (Phase 3) |
| Memory corruption attacks | Low | Critical | Integrity hashing + anomaly detection (Phase 4/6) |
| Rogue agent behavior | Medium | Critical | Tiered trust + instant demotion + kill switch |
| Sandbox escape | Low | Critical | microVM isolation + network restrictions |
| CI/CD pipeline failures | Medium | Medium | Dual pipeline (Gitea + GitHub) provides redundancy |
| OTel overhead | Low | Medium | Sample traces in production (1-10%) |
