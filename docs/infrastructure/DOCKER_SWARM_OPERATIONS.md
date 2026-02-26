---
Last Updated: 2026-02-26
Platform Version: 0.2.0
---

# Docker Swarm Operations Guide

Operational reference for Docker and Docker Swarm management within the Powernode DevOps platform.

## Architecture

Powernode provides a management layer over Docker hosts and Swarm clusters via API-driven operations. The system supports:

- **Standalone Docker hosts** — Individual Docker daemon management
- **Swarm clusters** — Multi-node cluster orchestration
- **Hybrid deployment** — Mix of standalone and clustered hosts

### Component Stack

```
┌─────────────────────────────────────────────┐
│              Powernode API                   │
│  Controllers → Services → Docker API Client │
├─────────────────────────────────────────────┤
│         Docker Engine API (Remote)           │
│    ┌──────────┬──────────┬──────────┐       │
│    │ Host A   │ Host B   │ Host C   │       │
│    │(Manager) │(Worker)  │(Worker)  │       │
│    └──────────┴──────────┴──────────┘       │
│              Swarm Cluster                   │
└─────────────────────────────────────────────┘
```

---

## Docker Host Management

### Registering a Host

Docker hosts are registered with their API endpoint, TLS credentials, and environment classification.

**Required fields:**
- `name` — Unique per account
- `api_endpoint` — Docker Engine API URL (e.g., `https://docker.example.com:2376`)
- `environment` — `staging`, `production`, `development`, or `custom`

**TLS Configuration:**
- `tls_verify` — Enable TLS verification
- Encrypted TLS credentials stored via `encrypted_tls_credentials`

### Host Sync

Hosts auto-sync on configurable intervals (30s–3600s):
- Container inventory
- Image inventory
- System information (Docker version, OS, architecture, resources)
- Event stream

**Health monitoring:**
- Consecutive failures tracked
- Auto-transitions to `error` status after 5 consecutive failures
- Manual recovery via `record_success!`

### Host Statuses

| Status | Description |
|--------|-------------|
| `pending` | Newly registered, not yet connected |
| `connected` | Active and syncing |
| `disconnected` | Connection lost, not syncing |
| `error` | Multiple consecutive failures |
| `maintenance` | Manually taken offline |

---

## Swarm Cluster Operations

### Cluster Registration

Swarm clusters are registered similarly to Docker hosts but represent the manager node endpoint.

**Auto-sync capabilities:**
- Node inventory and status
- Service definitions and replica counts
- Stack deployments
- Cluster events

### Cluster Resources

**Nodes (`Devops::SwarmNode`):**
- Manager and worker node tracking
- Availability and status monitoring
- Resource capacity reporting

**Services (`Devops::SwarmService`):**
- Service definition management
- Replica scaling
- Update and rollback configuration

**Stacks (`Devops::SwarmStack`):**
- Docker Compose-based stack deployment
- Multi-service orchestration
- Stack-level health monitoring

**Deployments (`Devops::SwarmDeployment`):**
- Deployment history tracking
- Rollback support
- Blue/green and canary deployment strategies

### Deployment Strategies

#### Blue-Green Deployment
`Devops::DeploymentStrategies::BlueGreenStrategy`

1. Deploy new version alongside existing (blue → green)
2. Run health checks on green deployment
3. Switch traffic from blue to green
4. Keep blue available for instant rollback

#### Canary Deployment
`Devops::DeploymentStrategies::CanaryStrategy`

1. Deploy new version to subset of nodes
2. Monitor error rates and performance
3. Gradually increase traffic to new version
4. Full rollout or automatic rollback on failures

---

## Service Layer

### Docker API Client (`Devops::Docker::ApiClient`)

Low-level Docker Engine API communication with TLS support.

### Manager Services

| Service | Operations |
|---------|-----------|
| `ContainerManager` | create, start, stop, restart, remove, logs, exec |
| `HostManager` | register, connect, disconnect, sync, health check |
| `ImageManager` | pull, build, tag, push, remove, inspect |
| `NetworkManager` | create, remove, connect, disconnect, inspect |
| `VolumeManager` | create, remove, inspect, prune |
| `ServiceManager` | create, update, scale, remove, logs |
| `StackManager` | deploy, remove, list services, status |
| `SwarmManager` | init, join, leave, update, inspect |
| `NodeManager` | list, inspect, update, promote, demote |
| `SecretManager` | create, update, remove, inspect |
| `HealthMonitor` | host health, container health, cluster health |

### Container Orchestration Service

`Devops::ContainerOrchestrationService` provides high-level container lifecycle management:
- Template-based container creation
- Resource quota enforcement via `QuotaService`
- Vault token provisioning for secrets
- Execution timeout management
- Cleanup and resource reclamation

---

## API Endpoints

### Docker Endpoints

```
GET    /api/v1/devops/docker/hosts
POST   /api/v1/devops/docker/hosts
GET    /api/v1/devops/docker/hosts/:id
PUT    /api/v1/devops/docker/hosts/:id
DELETE /api/v1/devops/docker/hosts/:id

GET    /api/v1/devops/docker/containers
GET    /api/v1/devops/docker/images
GET    /api/v1/devops/docker/networks
GET    /api/v1/devops/docker/volumes
GET    /api/v1/devops/docker/events
GET    /api/v1/devops/docker/activities
```

### Swarm Endpoints

```
GET    /api/v1/devops/swarm/clusters
POST   /api/v1/devops/swarm/clusters
GET    /api/v1/devops/swarm/clusters/:id
PUT    /api/v1/devops/swarm/clusters/:id
DELETE /api/v1/devops/swarm/clusters/:id

GET    /api/v1/devops/swarm/nodes
GET    /api/v1/devops/swarm/services
GET    /api/v1/devops/swarm/stacks
GET    /api/v1/devops/swarm/deployments
GET    /api/v1/devops/swarm/events
GET    /api/v1/devops/swarm/networks
GET    /api/v1/devops/swarm/volumes
GET    /api/v1/devops/swarm/secrets
GET    /api/v1/devops/swarm/configs
```

---

## Monitoring

### Health Checks

The `HealthMonitor` service performs:
- Docker daemon connectivity checks
- Container health status aggregation
- Resource utilization monitoring
- Swarm cluster quorum verification

### Event Tracking

Events are captured at multiple levels:
- **Docker events** (`Devops::DockerEvent`) — Container, image, network, volume events
- **Docker activities** (`Devops::DockerActivity`) — User-initiated operations
- **Swarm events** (`Devops::SwarmEvent`) — Cluster-level events

### Resource Tracking

Container instances track:
- `memory_used_mb` / `cpu_used_millicores`
- `storage_used_bytes`
- `network_bytes_in` / `network_bytes_out`

Hosts track:
- `container_count` / `image_count`
- `memory_bytes` / `cpu_count` / `storage_bytes`
- Docker version, OS type, architecture

---

## Security

### TLS Communication

All Docker API communication supports TLS with:
- Encrypted credential storage
- Certificate verification toggle
- Per-host TLS configuration

### Vault Integration

Container instances integrate with HashiCorp Vault:
- Token provisioning on container creation
- Automatic token revocation on completion
- `cleanup_vault_token!` for manual cleanup

### Security Violations

Container instances record security violations:
- Violation details with detection timestamps
- `has_security_violations?` check
- Violations accessible via instance details API

### Secrets Management

- Docker Swarm secrets via `SecretManager`
- `Devops::SecretReference` for secret tracking
- Encrypted credential storage for integrations

---

## Operational Patterns

### Adding a New Docker Host

1. Register host via API with endpoint and TLS credentials
2. System verifies connectivity (status → `connected`)
3. Initial sync pulls container/image inventory
4. Auto-sync begins at configured interval

### Deploying to Swarm

1. Register Swarm cluster with manager node endpoint
2. System discovers nodes, services, and stacks
3. Deploy stack via API or pipeline step
4. Monitor deployment via events and service status

### Container Execution Lifecycle

1. Create `ContainerInstance` from template or direct config
2. `pending` → Vault token provisioned → `provisioning`
3. Container started on target host → `running`
4. Resource usage tracked during execution
5. On completion: output captured, Vault token revoked → `completed`/`failed`
6. Linked A2A tasks updated with results
