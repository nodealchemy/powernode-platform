# Docker Deployment

Docker Compose deployment for development and production environments.

---

## Container Architecture

```
┌─────────────────────────────────────────────────────┐
│  Traefik (Reverse Proxy)  — Production only         │
├─────────────┬──────────────┬────────────────────────┤
│  Backend    │  Frontend    │  Worker                 │
│  Rails 8    │  React/Vite  │  Sidekiq               │
│  Port 3000  │  Port 3001   │  (no port)             │
├─────────────┴──────────────┴────────────────────────┤
│  PostgreSQL │  Redis                                 │
└─────────────────────────────────────────────────────┘
```

---

## Dockerfiles

Each service has production and development Dockerfiles:

| Service | Production | Development |
|---------|-----------|-------------|
| Backend | `server/Dockerfile` | `server/Dockerfile.dev` |
| Frontend | `frontend/Dockerfile` | `frontend/Dockerfile.dev` |
| Worker | `worker/Dockerfile` | `worker/Dockerfile.dev` |

All production Dockerfiles use multi-stage builds for minimal image size.

### Worker Dockerfile

Includes additional system packages for AI and media processing:
- `ffmpeg` — audio/video processing
- `imagemagick` — image processing

---

## Docker Compose Files

Located in `docker/`:

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Local development |
| `docker-compose.prod.yml` | Production with Traefik reverse proxy |
| `docker-compose.mcp.yml` | MCP server development |

### Development

```bash
cd docker
docker compose up -d
```

Mounts source code as volumes for live reloading.

### Production

```bash
cd docker
docker compose -f docker-compose.prod.yml up -d
```

Includes:
- Traefik reverse proxy with automatic SSL/TLS
- Health checks on all services
- Resource limits
- Log rotation

---

## Docker Build Scripts

Located in `scripts/docker/`:

| Script | Description |
|--------|-------------|
| `powernode-build.sh` | Build all Docker images |
| `powernode-deploy.sh` | Deploy via Docker Compose |
| `powernode-package.sh` | Package images for distribution |

```bash
# Build all images
./scripts/docker/powernode-build.sh

# Deploy to production
./scripts/docker/powernode-deploy.sh
```

---

## Docker Swarm

The `docker/swarm/` directory contains Docker Swarm configuration for multi-node deployment.

Worker jobs manage Swarm operations:
- `Swarm::ClusterSyncJob` — Cluster state synchronization
- `Swarm::StackDeployJob` — Stack deployment
- `Swarm::HealthCheckJob` — Node health monitoring
- `Swarm::ServiceUpdateJob` — Rolling service updates
- `Swarm::EventCleanupJob` — Event log cleanup

---

## Health Checks

All services expose health check endpoints:

| Endpoint | Description |
|----------|-------------|
| `/health` | Basic health check |
| `/health/detailed` | Detailed health with subsystem status |
| `/health/ready` | Readiness probe (for Kubernetes/Swarm) |
| `/health/live` | Liveness probe |

Health checks verify: database connectivity, Redis connectivity, memory usage, disk space.

---

## Environment Configuration

See `.env.example` at the project root for all available environment variables. Copy to `.env` and customize for your deployment.

Key production variables:
- `DATABASE_URL` — PostgreSQL connection string
- `REDIS_URL` — Redis connection string
- `SECRET_KEY_BASE` — Rails secret (generate with `rails secret`)
- `DOMAIN` — Production domain for Traefik SSL
