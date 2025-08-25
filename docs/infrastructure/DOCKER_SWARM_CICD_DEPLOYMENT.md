# Docker Swarm CI/CD Deployment Guide

## Overview

This guide describes the comprehensive CI/CD pipeline for deploying the Powernode Platform to a remote Docker Swarm cluster. The setup includes automated testing, building, deployment, monitoring, and rollback capabilities.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌───────────────────┐
│   Developer     │    │   GitHub         │    │   Docker Swarm    │
│   Push Code     ├───▶│   Actions        ├───▶│   Production      │
└─────────────────┘    │   CI/CD Pipeline │    │   Cluster         │
                       └──────────────────┘    └───────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   Container      │
                       │   Registry       │
                       └──────────────────┘
```

### Components

- **GitHub Actions**: CI/CD pipeline orchestration
- **Docker Swarm**: Container orchestration and deployment
- **Container Registry**: Docker image storage
- **Monitoring Stack**: Prometheus + Grafana + AlertManager
- **Health Checks**: Automated service validation
- **Rollback System**: Automated recovery mechanisms

## Prerequisites

### Docker Swarm Cluster Setup

1. **Initialize Swarm on Manager Node**:
```bash
docker swarm init --advertise-addr <MANAGER-IP>
```

2. **Join Worker Nodes**:
```bash
# Get join token from manager
docker swarm join-token worker

# Run on worker nodes
docker swarm join --token <TOKEN> <MANAGER-IP>:2377
```

3. **Verify Cluster**:
```bash
docker node ls
```

### GitHub Repository Setup

1. **Required Secrets**:
```bash
# Container Registry
DOCKER_REGISTRY_URL=your-registry.com
DOCKER_REGISTRY_USERNAME=username
DOCKER_REGISTRY_PASSWORD=password

# Docker Swarm Access
STAGING_DOCKER_HOST=staging-host
PRODUCTION_DOCKER_HOST=production-host

# Domain Configuration
STAGING_DOMAIN=staging.powernode.io
PRODUCTION_DOMAIN=powernode.io
ACME_EMAIL=admin@powernode.io

# Application URLs
STAGING_URL=https://staging.powernode.io
PRODUCTION_URL=https://powernode.io
```

2. **SSH Key Setup**:
Create SSH keys for deployment access and add public keys to Docker Swarm nodes.

## Docker Swarm Secrets Management

### Creating Required Secrets

```bash
# Database secrets
echo "powernode_production" | docker secret create db_name -
echo "powernode_user" | docker secret create db_user -
echo "$(openssl rand -base64 32)" | docker secret create db_password -

# Redis secret
echo "$(openssl rand -base64 32)" | docker secret create redis_password -

# Rails secrets
echo "$(rails secret)" | docker secret create rails_master_key -
echo "$(openssl rand -base64 64)" | docker secret create jwt_secret -

# Grafana secret
echo "$(openssl rand -base64 16)" | docker secret create grafana_admin_password -
```

### Viewing Secrets

```bash
# List all secrets
docker secret ls

# Inspect secret metadata (not content)
docker secret inspect db_password
```

## CI/CD Pipeline Stages

### 1. Testing Stage

- **Backend Tests**: RSpec with PostgreSQL and Redis
- **Frontend Tests**: Jest unit tests and TypeScript checking
- **Worker Tests**: Sidekiq job validation
- **Security Scanning**: Trivy vulnerability scanning

### 2. Build Stage

- **Multi-stage Docker builds** for optimal image sizes
- **Cross-platform builds** (linux/amd64, linux/arm64)
- **Image caching** with GitHub Actions cache
- **Registry push** with semantic versioning

### 3. Deployment Stage

- **Environment-specific deployment**
- **Zero-downtime rolling updates**
- **Health checks** before marking deployment successful
- **Automatic rollback** on failure

### 4. Monitoring Stage

- **Service health monitoring**
- **Performance metrics collection**
- **Alert notifications**
- **Dashboard visualization**

## Deployment Process

### Automated Deployment

Deployments are triggered automatically:

- **Staging**: On push to `develop` branch
- **Production**: On push to `main` branch
- **Feature Branches**: Build and test only

### Manual Deployment

```bash
# Deploy to staging
./scripts/deployment/deploy.sh staging v1.2.3

# Deploy to production
./scripts/deployment/deploy.sh production v1.2.3
```

### Deployment Verification

The deployment process includes:

1. **Pre-deployment Checks**:
   - Swarm cluster health
   - Image availability
   - Configuration validation

2. **Deployment Execution**:
   - Service updates with rolling strategy
   - Health check monitoring
   - Service readiness validation

3. **Post-deployment Verification**:
   - Health checks across all services
   - Smoke tests for critical functionality
   - Performance baseline validation

## Health Checks and Monitoring

### Service Health Checks

```bash
# Run health checks manually
./scripts/deployment/health-check.sh powernode-production

# Check specific service
docker service ps powernode-production_backend --no-trunc
```

### Monitoring Stack

Access monitoring dashboards:

- **Grafana**: `https://grafana.yourdomain.com`
- **Prometheus**: `https://prometheus.yourdomain.com` 
- **AlertManager**: `https://alerts.yourdomain.com`

### Key Metrics

- **Application Performance**: Response times, throughput
- **System Resources**: CPU, memory, disk usage
- **Service Availability**: Uptime, error rates
- **Business Metrics**: User registrations, API usage

## Rollback Procedures

### Automatic Rollback

Rollback triggers automatically on:
- Health check failures
- Service startup failures
- Critical error thresholds

### Manual Rollback

```bash
# Interactive rollback (shows deployment history)
./scripts/deployment/rollback.sh production

# Direct version rollback
./scripts/deployment/rollback.sh production v1.2.2

# Emergency rollback to last stable
./scripts/deployment/rollback.sh production auto
```

### Rollback Process

1. **Backup Creation**: Current state backup
2. **Version Verification**: Ensure target images exist
3. **Service Update**: Rolling update to previous version
4. **Validation**: Health checks and smoke tests
5. **History Update**: Deployment tracking update

## Troubleshooting

### Common Issues

#### 1. Service Won't Start

```bash
# Check service logs
docker service logs powernode-production_backend

# Check service events
docker service ps powernode-production_backend --no-trunc

# Verify secrets
docker secret ls
```

#### 2. Database Connection Issues

```bash
# Test database connectivity
docker exec $(docker ps -q -f name=powernode-production_backend) rails runner "ActiveRecord::Base.connection.execute('SELECT 1')"

# Check database service
docker service ps powernode-production_postgres
```

#### 3. Load Balancer Issues

```bash
# Check Traefik logs
docker service logs powernode-production_proxy

# Verify service discovery
docker service inspect powernode-production_frontend
```

### Recovery Procedures

#### 1. Complete Stack Recovery

```bash
# Stop all services
docker stack rm powernode-production

# Wait for cleanup
sleep 30

# Redeploy stack
./scripts/deployment/deploy.sh production latest
```

#### 2. Database Recovery

```bash
# Access database container
docker exec -it $(docker ps -q -f name=powernode-production_postgres) psql -U powernode_user -d powernode_production

# Create backup
docker exec $(docker ps -q -f name=powernode-production_postgres) pg_dump -U powernode_user powernode_production > backup.sql
```

#### 3. Secret Recovery

```bash
# Remove corrupted secret
docker secret rm db_password

# Recreate secret
echo "new_password" | docker secret create db_password -

# Update services to use new secret
docker service update --secret-rm db_password --secret-add db_password powernode-production_backend
```

## Security Considerations

### Container Security

- **Non-root Users**: All containers run as non-root users
- **Minimal Images**: Alpine-based images for smaller attack surface
- **Vulnerability Scanning**: Automated Trivy scans
- **Secret Management**: Docker Swarm secrets for sensitive data

### Network Security

- **Internal Networks**: Backend services isolated
- **TLS Termination**: HTTPS with automatic certificates
- **Rate Limiting**: API protection with nginx
- **Security Headers**: XSS, CSRF, clickjacking protection

### Access Control

- **SSH Key Authentication**: Deployment access
- **RBAC**: Role-based access to monitoring
- **Audit Logging**: All deployment actions logged
- **Secret Rotation**: Regular secret updates

## Performance Optimization

### Resource Management

```yaml
# Service resource limits
resources:
  limits:
    memory: 1G
    cpus: '0.5'
  reservations:
    memory: 512M
    cpus: '0.25'
```

### Scaling

```bash
# Scale service replicas
docker service scale powernode-production_backend=4

# Auto-scaling based on metrics (requires external tools)
# Example with Docker Swarm autoscaler
```

### Caching Strategy

- **CDN Integration**: Static asset delivery
- **Redis Caching**: Application-level caching  
- **Docker Layer Caching**: Build optimization
- **Registry Caching**: Image pull optimization

## Maintenance

### Regular Tasks

1. **Weekly**:
   - Review monitoring alerts
   - Check resource usage trends
   - Verify backup integrity

2. **Monthly**:
   - Update base images
   - Rotate secrets
   - Clean up old images
   - Performance review

3. **Quarterly**:
   - Security audit
   - Disaster recovery testing
   - Capacity planning
   - Documentation updates

### Backup Strategy

- **Database Backups**: Daily automated dumps
- **Configuration Backups**: Version-controlled configs
- **Deployment Backups**: State snapshots before changes
- **Monitoring Data**: Prometheus data retention

## Support and Escalation

### Alert Levels

- **INFO**: System events, deployments
- **WARNING**: Performance degradation, minor issues
- **CRITICAL**: Service failures, security incidents

### Escalation Procedures

1. **Level 1**: Automated recovery attempts
2. **Level 2**: On-call engineer notification
3. **Level 3**: Management escalation
4. **Level 4**: All-hands incident response

### Contact Information

- **Primary On-call**: [Contact details]
- **Secondary On-call**: [Contact details]
- **Management**: [Contact details]
- **External Support**: [Vendor contacts]

---

This deployment guide provides comprehensive coverage of the CI/CD pipeline, deployment procedures, monitoring, and troubleshooting for the Powernode Platform on Docker Swarm.