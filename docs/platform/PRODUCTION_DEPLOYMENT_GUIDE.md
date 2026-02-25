# Powernode Production Deployment Guide

This guide covers the complete process for deploying Powernode to production.

## Prerequisites

### Infrastructure Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Storage | 50 GB SSD | 100 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

### Required Software

- Docker Engine 24.0+
- Docker Compose v2.20+
- Git
- AWS CLI (for S3 backups)

### Domain Configuration

- Primary domain (e.g., `powernode.example.com`)
- API subdomain (e.g., `api.powernode.example.com`)
- SSL/HTTPS handled automatically by Traefik reverse proxy with Let's Encrypt

---

## Quick Start

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
# Copy environment template
cp .env.example .env

# Edit with your values
nano .env
```

**Required Environment Variables:**

```bash
# Database
POSTGRES_USER=powernode
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=powernode_production

# Redis
REDIS_PASSWORD=<strong-password>

# Application Secrets (generate with: openssl rand -hex 64)
SECRET_KEY_BASE=<64-char-hex>
JWT_SECRET=<64-char-hex>
WORKER_API_KEY=<random-string>

# Domain Configuration
DOMAIN=powernode.example.com
ACME_EMAIL=admin@example.com

# Payment Providers
STRIPE_API_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
PAYPAL_CLIENT_ID=...
PAYPAL_CLIENT_SECRET=...

# Error Tracking
SENTRY_DSN=https://...@sentry.io/...
```

### 4. Deploy

```bash
# Pull images and start services
docker compose -f docker/docker-compose.prod.yml up -d

# Run database migrations
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:migrate

# Seed initial data (first deployment only)
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:seed
```

### 5. Verify Deployment

```bash
# Check service health
curl https://api.powernode.example.com/health

# Check detailed health
curl https://api.powernode.example.com/health/detailed

# Check frontend
curl https://powernode.example.com
```

---

## GitHub Actions CI/CD

### Setup Secrets

Add these secrets to your GitHub repository:

| Secret | Description |
|--------|-------------|
| `DEPLOY_SSH_KEY` | SSH private key for server access |
| `DEPLOY_HOST` | Server hostname or IP |
| `DEPLOY_USER` | SSH username |
| `POSTGRES_USER` | Database username |
| `POSTGRES_PASSWORD` | Database password |
| `POSTGRES_DB` | Database name |
| `REDIS_PASSWORD` | Redis password |
| `SECRET_KEY_BASE` | Rails secret key |
| `JWT_SECRET` | JWT signing secret |
| `WORKER_API_KEY` | Worker authentication key |
| `DOMAIN` | Production domain |
| `VITE_API_URL` | Frontend API URL |
| `VITE_WS_URL` | Frontend WebSocket URL |

### Deployment Workflow

Deployments are automated:

- **Staging**: Push to `develop` branch
- **Production**: Push to `main` branch
- **Manual**: Use GitHub Actions workflow dispatch

### Rollback

To rollback a deployment:

1. Go to Actions → Rollback workflow
2. Click "Run workflow"
3. Select environment (staging/production)
4. Optionally specify target SHA/tag
5. Click "Run workflow"

---

## Database Management

### Automated Backups

Add a cron job for daily backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd ~/powernode && ./scripts/backup/backup-database.sh >> /var/log/powernode-backup.log 2>&1
```

### Manual Backup

```bash
cd ~/powernode

# Set environment
export POSTGRES_HOST=localhost
export POSTGRES_USER=powernode
export POSTGRES_PASSWORD=<password>
export POSTGRES_DB=powernode_production
export BACKUP_DIR=/backups

# Run backup
./scripts/backup/backup-database.sh
```

### Restore from Backup

```bash
# Restore from local backup
./scripts/backup/restore-database.sh /backups/powernode_20260104_120000.sql.gz

# Restore from S3
./scripts/backup/restore-database.sh s3://your-bucket/backups/powernode_20260104_120000.sql.gz
```

---

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

View errors at: https://sentry.io/organizations/your-org/issues/

### Log Access

```bash
# View all logs
docker compose -f docker/docker-compose.prod.yml logs

# View specific service
docker compose -f docker/docker-compose.prod.yml logs backend

# Follow logs in real-time
docker compose -f docker/docker-compose.prod.yml logs -f backend

# Last 100 lines
docker compose -f docker/docker-compose.prod.yml logs --tail=100 backend
```

---

## Scaling

### Horizontal Scaling

```bash
# Scale backend to 3 instances
docker compose -f docker/docker-compose.prod.yml up -d --scale backend=3

# Scale workers
docker compose -f docker/docker-compose.prod.yml up -d --scale worker=5
```

### Resource Limits

Edit `docker/docker-compose.prod.yml` to add resource constraints:

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

---

## Security Checklist

- [ ] Strong passwords for all services
- [ ] SSL/TLS enabled (via Traefik)
- [ ] Firewall configured (only ports 80, 443 open)
- [ ] SSH key-based authentication only
- [ ] Regular security updates
- [ ] Database backups encrypted
- [ ] Secrets not committed to git
- [ ] Rate limiting enabled
- [ ] CORS properly configured

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker compose -f docker/docker-compose.prod.yml logs <service>

# Check container status
docker compose -f docker/docker-compose.prod.yml ps

# Restart service
docker compose -f docker/docker-compose.prod.yml restart <service>
```

### Database Connection Issues

```bash
# Test database connectivity
docker compose -f docker/docker-compose.prod.yml exec backend \
  bundle exec rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1')"
```

### Redis Connection Issues

```bash
# Test Redis connectivity
docker compose -f docker/docker-compose.prod.yml exec backend \
  bundle exec rails runner "puts Redis.new(url: ENV['REDIS_URL']).ping"
```

### Out of Disk Space

```bash
# Clean up Docker
docker system prune -af
docker volume prune -f

# Check backup directory
du -sh /backups/*
```

---

## Maintenance

### Updating

```bash
cd ~/powernode

# Pull latest changes
git pull origin main

# Pull new images
docker compose -f docker/docker-compose.prod.yml pull

# Deploy with zero-downtime
docker compose -f docker/docker-compose.prod.yml up -d --remove-orphans

# Run migrations
docker compose -f docker/docker-compose.prod.yml exec backend bundle exec rails db:migrate

# Clean old images
docker image prune -f
```

### Scheduled Maintenance

For planned maintenance:

1. Enable maintenance mode (if implemented)
2. Create database backup
3. Perform updates
4. Verify deployment
5. Disable maintenance mode

---

## Support

- **Documentation**: `/docs` directory
- **Issues**: GitHub Issues
- **Logs**: Check container logs
- **Health**: `/health/detailed` endpoint
