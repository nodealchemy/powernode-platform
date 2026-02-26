---
Last Updated: 2026-02-26
Platform Version: 0.2.0
---

# DevOps Platform Guide

Comprehensive reference for Powernode's DevOps subsystem — CI/CD pipelines, container orchestration, Docker Swarm management, git integrations, and deployment automation.

## Architecture Overview

The DevOps platform is a fully integrated subsystem within Powernode, providing:
- **CI/CD Pipelines**: Multi-step pipelines with AI-powered steps, approval gates, and scheduling
- **Container Orchestration**: Docker host management, container templates, resource quotas
- **Docker Swarm**: Cluster management, service deployment, stack orchestration
- **Git Integration**: Multi-provider support (GitHub, GitLab, Gitea, Bitbucket) with webhooks and runners
- **Integration Framework**: Templated integrations for CI/CD, monitoring, notifications, and more

### Model Inventory (41 models)

All models live in the `Devops::` namespace under `server/app/models/devops/`.

| Category | Models |
|----------|--------|
| **Pipelines** | `Pipeline`, `PipelineStep`, `PipelineRun`, `PipelineTemplate`, `PipelineRepository`, `Schedule`, `StepExecution`, `StepApprovalToken` |
| **Containers** | `ContainerInstance`, `ContainerTemplate`, `ResourceQuota`, `SecretReference` |
| **Docker** | `DockerHost`, `DockerContainer`, `DockerImage`, `DockerEvent`, `DockerActivity` |
| **Swarm** | `SwarmCluster`, `SwarmNode`, `SwarmService`, `SwarmStack`, `SwarmDeployment`, `SwarmEvent` |
| **Git** | `GitProvider`, `GitProviderCredential`, `GitRepository`, `GitRunner`, `GitPipeline`, `GitPipelineJob`, `GitPipelineSchedule`, `GitPipelineApproval`, `GitWebhookEvent`, `GitWorkflowTrigger`, `AccountGitWebhookConfig` |
| **Integrations** | `IntegrationTemplate`, `IntegrationInstance`, `IntegrationExecution`, `IntegrationCredential` |
| **Other** | `Provider`, `Repository`, `AiConfig` |

---

## CI/CD Pipeline System

### Pipeline Model (`Devops::Pipeline`)

Pipelines define CI/CD workflows with trigger configuration, ordered steps, and execution settings.

**Key attributes:**
- `pipeline_type`: `review`, `implement`, `security`, `deploy`, `custom`
- `triggers`: JSON configuration for event-based triggering
- `is_system`: System pipelines are immutable
- `allow_concurrent`: Whether multiple runs can execute simultaneously
- `timeout_minutes`: Max 360 minutes
- `runner_labels`: Target runner selection
- `features`: Feature flags for pipeline capabilities

**Trigger types supported:**
- `pull_request` — PR opened/closed/synchronized
- `push` — Branch push with glob pattern matching
- `issue` / `issue_comment` — Issue lifecycle events
- `release` — Release creation/publication
- `schedule` — Cron-based scheduling
- `manual` / `workflow_dispatch` — User-initiated runs

### Pipeline Steps (`Devops::PipelineStep`)

Steps execute sequentially within a pipeline run. Each step has a type, position, inputs, outputs, and conditional execution.

**Step types:**
| Type | Description |
|------|-------------|
| `checkout` | Clone/checkout repository code |
| `claude_execute` | AI-powered step using prompt templates |
| `ai_workflow` | Execute an AI workflow |
| `post_comment` | Post a comment to PR/issue |
| `create_pr` | Create a pull request |
| `create_branch` | Create a new branch |
| `upload_artifact` / `download_artifact` | Artifact management |
| `run_tests` | Execute test suites |
| `deploy` | Deployment step |
| `notify` | Send notifications |
| `code_factory_gate` | Code Factory approval gate |
| `custom` | Custom step handler |

**Expression references:** Steps can reference outputs from previous steps using `${{ steps.previous.outputs.result }}` syntax.

**Approval gates:** Steps can require approval via `requires_approval`, with configurable timeout, recipients, and comment requirements.

### Pipeline Runs (`Devops::PipelineRun`)

Execution records tracking status, timing, and outputs.

**Statuses:** `pending` → `queued` → `running` → `success` / `failure` / `cancelled`

**Trigger types:** `manual`, `pull_request`, `issue`, `issue_comment`, `push`, `release`, `schedule`, `webhook`, `workflow_dispatch`

Runs broadcast real-time updates via `DevopsPipelineChannel`.

### Pipeline Templates (`Devops::PipelineTemplate`)

Reusable pipeline definitions for the marketplace with versioning, ratings, and publishing.

- **Categories:** `review`, `implement`, `security`, `deploy`, `docs`, `custom`
- **Difficulty levels:** `beginner`, `intermediate`, `advanced`, `expert`
- **Statuses:** `draft` → `published` → `archived`
- **Marketplace:** Public templates discoverable by other accounts
- Supports semantic versioning and installation counts

---

## Container Orchestration

### Container Instances (`Devops::ContainerInstance`)

Tracks individual container executions with full lifecycle management.

**Statuses:** `pending` → `provisioning` → `running` → `completed` / `failed` / `cancelled` / `timeout`

**Features:**
- Vault token integration for secrets
- A2A task linking (container results update linked AI tasks)
- Resource tracking (CPU, memory, storage, network)
- Security violation recording
- Log streaming with 100KB truncation
- Artifact collection

### Container Templates (`Devops::ContainerTemplate`)

Reusable container configurations defining image, resources, environment, and security settings.

### Resource Quotas (`Devops::ResourceQuota`)

Per-account resource limits for container orchestration.

---

## Docker Host Management

### Docker Hosts (`Devops::DockerHost`)

Managed Docker daemon endpoints with TLS support and auto-sync.

**Environments:** `staging`, `production`, `development`, `custom`
**Statuses:** `pending`, `connected`, `disconnected`, `error`, `maintenance`

**Features:**
- Encrypted TLS credentials
- Auto-sync with configurable intervals (30s–3600s)
- Health tracking with consecutive failure detection (auto-error after 5 failures)
- Container, image, event, and activity tracking per host
- System metrics: Docker version, OS, architecture, kernel, memory, CPU, storage

### Docker Service Layer

Services in `server/app/services/devops/docker/`:

| Service | Purpose |
|---------|---------|
| `ApiClient` | Docker Engine API communication |
| `ContainerManager` | Container lifecycle (create, start, stop, remove) |
| `HostManager` | Docker host registration and monitoring |
| `ImageManager` | Image pull, build, tag, remove |
| `NetworkManager` | Network creation and management |
| `VolumeManager` | Volume lifecycle |
| `HealthMonitor` | Host and container health checks |
| `RegistryService` | Container registry operations |
| `SecretManager` | Docker secret management |
| `ServiceManager` | Docker service operations |
| `StackManager` | Docker stack deployment |
| `SwarmManager` | Swarm cluster operations |
| `NodeManager` | Swarm node management |

---

## Docker Swarm Management

### Swarm Clusters (`Devops::SwarmCluster`)

Docker Swarm cluster endpoints with full lifecycle management.

**Features:**
- TLS-encrypted API communication
- Environment-tagged clusters (staging/production/development)
- Auto-sync with configurable intervals
- Health monitoring with failure tracking
- Child resource management: nodes, services, stacks, deployments, events

### Swarm Resources

| Model | Description |
|-------|-------------|
| `SwarmNode` | Individual nodes in a Swarm cluster |
| `SwarmService` | Swarm services with scaling configuration |
| `SwarmStack` | Docker Compose-based stack deployments |
| `SwarmDeployment` | Deployment tracking for services |
| `SwarmEvent` | Cluster and service event log |

### Deployment Strategies

Services in `server/app/services/devops/deployment_strategies/`:

- `BlueGreenStrategy` — Zero-downtime blue/green deployments
- `CanaryStrategy` — Gradual canary rollouts

---

## Git Integration

### Git Providers (`Devops::GitProvider`)

Provider definitions supporting multiple Git platforms.

**Provider types:** `github`, `gitlab`, `gitea`, `bitbucket`

**Capabilities per provider:**
| Provider | Capabilities |
|----------|-------------|
| GitHub | repos, branches, commits, pull_requests, issues, webhooks, devops |
| GitLab | repos, branches, commits, merge_requests, issues, webhooks, devops |
| Gitea | repos, branches, commits, pull_requests, issues, webhooks, devops, act_runner |
| Bitbucket | repos, branches, commits, pull_requests, issues, webhooks, pipelines |

### Git Repositories (`Devops::GitRepository`)

Synced repository records with webhook management and branch filtering.

**Branch filter types:** `none`, `exact`, `wildcard`, `regex`

**Features:**
- Auto-webhook configuration and management
- Language detection and topic tracking
- Pipeline statistics (success rate, counts)
- Event history tracking
- Fork and archive awareness

### Git API Clients

Services in `server/app/services/devops/git/`:

| Service | Purpose |
|---------|---------|
| `ApiClient` | Factory for provider-specific clients |
| `GithubApiClient` | GitHub API v3 integration |
| `GitlabApiClient` | GitLab API v4 integration |
| `GiteaApiClient` | Gitea API integration |
| `OAuthService` | OAuth flow for git providers |
| `ProviderManagementService` | Provider CRUD and configuration |
| `ProviderTestService` | Connection testing and validation |

### Git Runners (`Devops::GitRunner`)

Managed CI/CD runners with health monitoring and job dispatch.

---

## Integration Framework

### Integration Templates (`Devops::IntegrationTemplate`)

Marketplace-ready integration definitions with schema validation.

**Integration types:** `github_action`, `webhook`, `mcp_server`, `rest_api`, `custom`
**Categories:** `ci_cd`, `notifications`, `monitoring`, `deployment`, `security`, `analytics`, `testing`

**Features:**
- JSON Schema-based configuration validation
- Credential requirement definitions
- Input/output schema definitions
- Usage and installation tracking
- Featured/public marketplace listing

### Integration Instances (`Devops::IntegrationInstance`)

Active installations of integration templates within an account.

### Integration Executions (`Devops::IntegrationExecution`)

Execution records for integration runs.

---

## API Endpoints

### Controllers (`server/app/controllers/api/v1/devops/`)

| Controller | Endpoints |
|-----------|-----------|
| `PipelinesController` | CRUD + trigger, clone, export, import |
| `PipelineRunsController` | List, show, cancel, retry, logs |
| `RepositoriesController` | CRUD + sync, webhook management |
| `ProvidersController` | CRUD + test connection |
| `SchedulesController` | CRUD for pipeline schedules |
| `ContainersController` | List, show, cancel container instances |
| `ContainerTemplatesController` | CRUD for container templates |
| `ContainerQuotasController` | Resource quota management |
| `IntegrationTemplatesController` | Template marketplace |
| `IntegrationInstancesController` | Instance management |
| `IntegrationExecutionsController` | Execution history |
| `IntegrationCredentialsController` | Credential management |
| `AiConfigsController` | AI configuration for DevOps |
| `ApprovalTokensController` | Pipeline step approvals |
| `PromptTemplatesController` | Prompt templates for AI steps |

### Docker Controllers (`server/app/controllers/api/v1/devops/docker/`)

| Controller | Purpose |
|-----------|---------|
| `HostsController` | Docker host management |
| `ContainersController` | Container operations |
| `ImagesController` | Image management |
| `NetworksController` | Network operations |
| `VolumesController` | Volume management |
| `EventsController` | Event history |
| `ActivitiesController` | Activity log |

### Swarm Controllers (`server/app/controllers/api/v1/devops/swarm/`)

| Controller | Purpose |
|-----------|---------|
| `ClustersController` | Swarm cluster management |
| `NodesController` | Node operations |
| `ServicesController` | Service management |
| `StacksController` | Stack deployment |
| `DeploymentsController` | Deployment tracking |
| `EventsController` | Cluster events |
| `NetworksController` | Swarm networks |
| `VolumesController` | Swarm volumes |
| `SecretsController` | Swarm secrets |
| `ConfigsController` | Swarm configs |

---

## Service Layer

### Core Services (`server/app/services/devops/`)

| Service | Purpose |
|---------|---------|
| `BaseExecutor` | Base class for pipeline step executors |
| `ExecutionService` | Pipeline run orchestration |
| `ContainerOrchestrationService` | Container lifecycle management |
| `ProviderClient` | DevOps provider API communication |
| `RegistryService` | Container registry integration |
| `QuotaService` | Resource quota enforcement |
| `PromptRenderer` | AI prompt template rendering |
| `WorkflowGenerator` | Generate workflow YAML from pipeline definitions |
| `GithubActionExecutor` | Execute GitHub Actions |
| `McpServerExecutor` | Execute via MCP server |
| `RestApiExecutor` | Execute REST API calls |
| `WebhookExecutor` | Execute webhooks |
| `AiWorkflowTriggerService` | Bridge between DevOps and AI workflows |
| `RunnerHealthService` | Runner health monitoring |
| `RunnerLifecycleService` | Runner registration and lifecycle |

### Step Handlers (`server/app/services/devops/step_handlers/`)

Extensible step handler system with `StepHandlerRegistry` for dynamic type registration.

- `CodeFactoryGateHandler` — Code Factory approval gate implementation

---

## Real-Time Communication

### DevOps Pipeline Channel

`DevopsPipelineChannel` broadcasts real-time updates for pipeline runs:
- `run_created` — New pipeline run started
- `run_updated` — Run status/progress changed
- `run_completed` — Run finished (success/failure/cancelled)

### Git Job Logs Channel

`GitJobLogsChannel` streams real-time log output from git pipeline jobs.

---

## Key Patterns

### Pipeline Trigger Flow
1. Webhook event → `AccountGitWebhookConfig` routes to pipelines
2. `Pipeline#matches_trigger?` evaluates trigger conditions
3. `Pipeline#trigger_run!` creates a `PipelineRun`
4. `PipelineRun#enqueue_execution` dispatches to worker
5. Worker executes steps sequentially via `ExecutionService`
6. Each step creates a `StepExecution` record
7. Real-time updates broadcast via ActionCable

### Container Execution Flow
1. `ContainerInstance` created with template configuration
2. Status transitions: `pending` → `provisioning` → `running` → `completed`
3. Resource usage recorded during execution
4. Vault tokens provisioned/revoked automatically
5. Linked A2A tasks updated on completion

### Multi-Provider Git Integration
1. `GitProvider` defines platform capabilities
2. `GitProviderCredential` stores encrypted per-account credentials
3. `Git::ApiClient.for(credential)` returns provider-specific client
4. Webhooks auto-configured on repository sync
5. Branch filters control which events trigger pipelines
