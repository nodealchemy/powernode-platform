# Production Deployment

> Status: active
>
> When to use this runbook: deploying Powernode to a production server for the first time, or performing a release deployment to an existing production environment.
>
> **Docker Compose path note:** this runbook documents the Docker Compose deployment, which is **deprecated by 2026-08-01** in favour of the systemd installer path. For new single-node installs prefer [`single-node-bootstrap.md`](single-node-bootstrap.md).

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Procedure](#procedure)
- [Local Storage Setup](#local-storage-setup)
- [Database Management](#database-management)
- [Monitoring](#monitoring)
- [Scaling](#scaling)
- [Verification](#verification)
- [Rollback](#rollback)
- [Production Readiness Checklist](#production-readiness-checklist)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Infrastructure

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Storage | 50 GB SSD | 100 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |

### Required Software

- Docker Engine 24.0+
- Docker Compose v2.20+
- Git
- AWS CLI (for S3 backups, optional)

### Domain Configuration

- Primary domain (e.g. `powernode.example.com`)
- API subdomain (e.g. `api.powernode.example.com`)
- SSL / HTTPS handled automatically by Traefik reverse proxy with Let's Encrypt

### Permissions

- SSH access to the target server
- `admin.access` permission on the Powernode admin user for post-deploy verification
- Sudo privileges on the server for systemd service installation

## When to use this

- First-time production install on a fresh Ubuntu host
- Cutover from staging to production after a release
- Disaster-recovery rebuild against a fresh server
- Migrating between hosting providers

## Procedure

### 1. Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose-plugin

# Create deployment directory
mkdir -p ~/powernode
cd ~/powernode
```

### 2. Clone Repository

```bash
git clone https://github.com/your-org/powernode-platform.git .
```

### 3. Configure Environment

```bash
cp .env.example .env
nano .env
```

**Required environment variables:**

```bash
# Database
POSTGRES_USER=powernode
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=powernode_production

# Redis
REDIS_PASSWORD=<strong-password>

# Application secrets — generate each via: openssl rand -hex 64
SECRET_KEY_BASE=<64-char-hex>
JWT_SECRET=<64-char-hex>
WORKER_API_KEY=<random-string>

# Domain configuration
DOMAIN=powernode.example.com
ACME_EMAIL=admin@example.com

# Payment providers (only if business extension is loaded)
STRIPE_API_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
PAYPAL_CLIENT_ID=...
PAYPAL_CLIENT_SECRET=...

# Error tracking
SENTRY_DSN=https://...@sentry.io/...
```

> **Crypto material safety:** Never commit `.env` to git. Generate secrets server-side. The `STRIPE_*` and `PAYPAL_*` variables are only relevant when the `business` extension is loaded; core deployments can omit them.

### 4. Deploy

```bash
# Pull images and start services
docker compose -f docker/docker-compose.prod.yml up -d

# Run database migrations
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:migrate

# Seed initial data (first deployment only)
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:seed
```

### 5. CI / CD Deployment (Optional)

Add these secrets to your Git provider's CI secret store:

| Secret | Description |
|--------|-------------|
| `DEPLOY_SSH_KEY` | SSH private key for server access |
| `DEPLOY_HOST` | Server hostname or IP |
| `DEPLOY_USER` | SSH username |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Database credentials |
| `REDIS_PASSWORD` | Redis password |
| `SECRET_KEY_BASE` | Rails secret key |
| `JWT_SECRET` | JWT signing secret |
| `WORKER_API_KEY` | Worker authentication key |
| `DOMAIN` | Production domain |
| `VITE_API_URL` | Frontend API URL |
| `VITE_WS_URL` | Frontend WebSocket URL |

Branch strategy:

- **Staging** — push to `develop`
- **Production** — push to `master`
- **Manual** — workflow dispatch

## Local Storage Setup

By default Powernode provisions per-account local storage providers under `server/storage/files/`. Each account is created with:

- **Provider type:** `local`
- **Default quota:** 10 GB
- **Path:** `server/storage/files/<account_id>/`
- **Default capability set:**

```ruby
{
  'max_file_size'     => 100.megabytes,
  'supported_formats' => ['image/*', 'application/pdf', 'text/*', 'video/*', 'audio/*'],
  'features'          => ['versioning', 'sharing', 'tagging', 'processing']
}
```

The configuration is created during account creation; a one-off bootstrap script exists at `server/lib/tasks/create_default_storage.rb` for retroactively adding storage to accounts that were created before the feature:

```bash
cd server
bundle exec rails runner lib/tasks/create_default_storage.rb
```

Frontend storage management lives at `/system/storage` and requires `admin.storage.read` or `admin.storage.manage`. Cloud providers (S3, GCS, Azure) are configurable via the same UI; configuration values are encrypted automatically via `AiCredentialEncryptionService` with the `encrypted:` prefix. Sensitive keys protected: `access_key_id`, `secret_access_key`, `password`, `api_key`, `credentials`.

Status values:
- `active` — operational
- `inactive` — disabled
- `maintenance` — manually offline
- `failed` — failed health checks

Key methods:

```ruby
storage.perform_health_check!     # returns true if healthy
storage.quota_percentage_used     # current % used
storage.available_space_bytes
storage.has_space_for?(size_bytes)
storage.quota_exceeded?
storage.near_quota_limit?(80)
storage.add_file_size(bytes)
storage.remove_file_size(bytes)
```

## Database Management

### Automated Backups

```bash
crontab -e

# Daily backup at 2 AM
0 2 * * * cd ~/powernode && ./scripts/backup/backup-database.sh >> /var/log/powernode-backup.log 2>&1
```

### Manual Backup

```bash
cd ~/powernode
export POSTGRES_HOST=localhost
export POSTGRES_USER=powernode
export POSTGRES_PASSWORD=<password>
export POSTGRES_DB=powernode_production
export BACKUP_DIR=/backups
./scripts/backup/backup-database.sh
```

### Restore

```bash
# From local backup
./scripts/backup/restore-database.sh /backups/powernode_20260104_120000.sql.gz

# From S3
./scripts/backup/restore-database.sh s3://your-bucket/backups/powernode_20260104_120000.sql.gz
```

## Monitoring

### Health Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/health` | Basic health check (load balancer) |
| `/health/detailed` | Detailed component status |
| `/health/ready` | Kubernetes readiness probe |
| `/health/live` | Kubernetes liveness probe |
| `/up` | Rails native health check |

### Sentry Error Tracking

Errors are automatically reported to Sentry when `SENTRY_DSN` is configured.

### Log Access

```bash
docker compose -f docker/docker-compose.prod.yml logs                # all
docker compose -f docker/docker-compose.prod.yml logs backend        # one service
docker compose -f docker/docker-compose.prod.yml logs -f backend     # tail
docker compose -f docker/docker-compose.prod.yml logs --tail=100 backend
```

## Scaling

### Horizontal

```bash
docker compose -f docker/docker-compose.prod.yml up -d --scale backend=3
docker compose -f docker/docker-compose.prod.yml up -d --scale worker=5
```

### Resource Limits

Edit `docker/docker-compose.prod.yml`:

```yaml
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
```

## Verification

```bash
# Basic service health
curl https://api.powernode.example.com/health

# Detailed component status
curl https://api.powernode.example.com/health/detailed

# Frontend loads
curl -I https://powernode.example.com
```

Verify storage providers were created for each account:

```bash
cd server
bundle exec rails runner "
FileStorage.includes(:account).find_each do |storage|
  puts \"#{storage.account.name}: #{storage.name} - #{storage.is_default ? 'DEFAULT' : 'Secondary'}\"
end
"
ls -la server/storage/files/
```

## Rollback

To rollback a deployment, redeploy a known-good Git ref:

1. Identify the previous good commit / tag
2. Run the deployment workflow against that ref (CI: rollback workflow → run workflow → select environment → optional target SHA / tag)
3. Apply the matching DB migration state if the rollback crosses a migration boundary:

```bash
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:migrate:status
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:rollback STEP=N
```

4. Confirm via `/health/detailed`

## Production Readiness Checklist

### Infrastructure

- [ ] Production hosting environment configured and tested
- [ ] Production PostgreSQL with replication configured
- [ ] Redis for background jobs and caching configured
- [ ] SSL certificates installed (Let's Encrypt via Traefik)
- [ ] CDN configured for static assets

### Database Scaling

- [ ] PostgreSQL connection pooling configured (PgBouncer)
- [ ] Read replicas configured for analytics queries
- [ ] Automated daily backups verified
- [ ] Point-in-time recovery (PITR) tested
- [ ] Critical indexes verified

### CI / CD Pipeline

- [ ] Automated RSpec runs on pull requests
- [ ] Automated frontend test runs on PRs
- [ ] Test coverage reporting (≥ 95%)
- [ ] Automated security scanning (Brakeman, bundle-audit)
- [ ] Blue-green or rolling deployment strategy chosen
- [ ] Automated migrations on deploy
- [ ] Rollback automation tested
- [ ] Post-deployment smoke tests

### Monitoring

- [ ] APM tool configured (New Relic / DataDog / AppSignal)
- [ ] Sentry / Rollbar / Honeybadger error tracking configured
- [ ] Uptime monitoring configured
- [ ] Alert thresholds configured and tested

### Security

- [ ] Strong passwords for all services
- [ ] SSL / TLS enabled (Traefik)
- [ ] Firewall configured (only 80, 443 open)
- [ ] SSH key-based authentication only
- [ ] Regular security updates
- [ ] Database backups encrypted
- [ ] Secrets not committed to git
- [ ] Rate limiting enabled
- [ ] CORS properly configured
- [ ] Security headers configured (CSP, HSTS, X-Frame-Options)
- [ ] Penetration testing completed

### Performance Targets

| Endpoint Type | Target (p95) | Maximum Acceptable |
|---------------|--------------|--------------------|
| Authentication | < 100ms | 200ms |
| User CRUD | < 150ms | 300ms |
| Subscription management | < 200ms | 400ms |
| Analytics / reporting | < 500ms | 1000ms |
| Payment processing | < 2000ms | 5000ms |

| Database metric | Target |
|-----------------|--------|
| Connection pool size | 25-50 |
| Max query time | < 100ms |
| Index coverage | > 95% |
| N+1 queries | 0 |

| Background job metric | Target |
|-----------------------|--------|
| Queue depth | < 100 jobs |
| Job processing time (avg) | < 5 seconds |
| Failed job rate | < 1% |
| Worker concurrency | 10-25 |

## Troubleshooting

### Service Won't Start

```bash
docker compose -f docker/docker-compose.prod.yml logs <service>
docker compose -f docker/docker-compose.prod.yml ps
docker compose -f docker/docker-compose.prod.yml restart <service>
```

### Database Connection Issues

```bash
docker compose -f docker/docker-compose.prod.yml exec backend \
  bundle exec rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1')"
```

### Redis Connection Issues

```bash
docker compose -f docker/docker-compose.prod.yml exec backend \
  bundle exec rails runner "puts Redis.new(url: ENV['REDIS_URL']).ping"
```

### Out of Disk

```bash
docker system prune -af
docker volume prune -f
du -sh /backups/*
```

### Storage Provider Issues

If a per-account storage directory is missing:

```bash
cd server
bundle exec rails runner lib/tasks/create_default_storage.rb
```

If you see "permission denied" creating files: ensure the backend process can write to `server/storage/files/` (chown / chmod accordingly).

---

## Related runbooks

- [docker-swarm.md](docker-swarm.md) — Docker / Swarm cluster operations
- [worker-operations.md](worker-operations.md) — Sidekiq worker procedures
- [ai-operations.md](ai-operations.md) — AI orchestration runbooks
- [performance-tuning.md](performance-tuning.md) — Throughput and latency tuning
- [postgres-backup.md](postgres-backup.md) — PostgreSQL backup and restore procedures

## Materials previously at

- `docs/platform/PRODUCTION_DEPLOYMENT_GUIDE.md`
- `docs/platform/PRODUCTION_READINESS_CHECKLIST.md`
- `docs/platform/DEFAULT_LOCAL_STORAGE_SETUP.md`

_Last verified: 2026-06-03_
