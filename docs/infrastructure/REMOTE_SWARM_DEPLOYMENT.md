# Remote Docker Swarm Deployment Guide

Complete guide for deploying Powernode Platform to a remote Docker Swarm cluster from a development machine.

## Prerequisites

### Development Machine Requirements
- Docker CLI (latest version)
- SSH client
- Git repository access
- Container registry access (Docker Hub, AWS ECR, etc.)

### Remote Swarm Requirements
- Docker Swarm cluster initialized
- SSH access to swarm manager node(s)
- Container registry access from swarm nodes
- Firewall rules configured for Docker Swarm ports

## 1. SSH and Docker Context Setup

### Create SSH Key for Deployment
```bash
# Generate dedicated SSH key for deployment
ssh-keygen -t rsa -b 4096 -f ~/.ssh/powernode-deploy -C "powernode-deploy"

# Copy public key to swarm manager
ssh-copy-id -i ~/.ssh/powernode-deploy.pub deploy@swarm-manager.example.com
```

### Configure Docker Context for Remote Swarm
```bash
# Create Docker context for remote swarm
docker context create powernode-production \
  --docker "host=ssh://deploy@swarm-manager.example.com"

# Test connectivity
docker context use powernode-production
docker node ls

# Switch back to local context
docker context use default
```

### Alternative: Docker Context with SSH Config
Create `~/.ssh/config` entry:
```
Host powernode-swarm
    HostName swarm-manager.example.com
    User deploy
    IdentityFile ~/.ssh/powernode-deploy
    Port 22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Then create context:
```bash
docker context create powernode-production --docker "host=ssh://powernode-swarm"
```

## 2. Container Registry Setup

### Private Registry Authentication
```bash
# Login to your container registry locally
docker login your-registry.com

# Copy Docker credentials to remote swarm nodes
# Option 1: Manual copy
scp ~/.docker/config.json deploy@swarm-manager.example.com:~/.docker/

# Option 2: Login on each swarm node
ssh deploy@swarm-manager.example.com 'docker login your-registry.com'
```

### Environment Variables Setup
Create `.env.production` file:
```bash
# Registry Configuration
REGISTRY_URL=your-registry.com/powernode
VERSION=main-latest

# Domain Configuration
DOMAIN=powernode.io
ACME_EMAIL=admin@powernode.io

# URLs
PRODUCTION_URL=https://powernode.io
BACKEND_URL=https://powernode.io/api
FRONTEND_URL=https://powernode.io

# Performance Settings
RAILS_MAX_THREADS=5
WEB_CONCURRENCY=2
SIDEKIQ_CONCURRENCY=10
```

## 3. Remote Deployment Script

Create `scripts/deploy-remote.sh`:
```bash
#!/bin/bash
# Remote Docker Swarm deployment script

set -euo pipefail

ENVIRONMENT=${1:-production}
SWARM_CONTEXT="powernode-${ENVIRONMENT}"
REGISTRY_URL=${REGISTRY_URL:-"your-registry.com/powernode"}
VERSION=${VERSION:-"main-latest"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Switch to remote Docker context
log_info "Switching to Docker context: $SWARM_CONTEXT"
docker context use "$SWARM_CONTEXT"

# Verify swarm connectivity
log_info "Verifying Docker Swarm connectivity..."
if ! docker node ls >/dev/null 2>&1; then
    log_error "Cannot connect to Docker Swarm. Check your context configuration."
    exit 1
fi

log_success "Connected to Docker Swarm"
docker node ls

# Load environment variables
if [[ -f ".env.${ENVIRONMENT}" ]]; then
    log_info "Loading environment variables from .env.${ENVIRONMENT}"
    set -a
    source ".env.${ENVIRONMENT}"
    set +a
else
    log_error "Environment file .env.${ENVIRONMENT} not found"
    exit 1
fi

# Create networks if they don't exist
log_info "Creating Docker networks..."
docker network ls | grep -q powernode_frontend || {
    docker network create --driver overlay --attachable powernode_frontend
    log_success "Created powernode_frontend network"
}

docker network ls | grep -q powernode_backend || {
    docker network create --driver overlay powernode_backend
    log_success "Created powernode_backend network"
}

# Setup secrets (if not exist)
log_info "Setting up Docker secrets..."
./scripts/deployment/setup-secrets.sh "$ENVIRONMENT"

# Deploy monitoring stack first
log_info "Deploying monitoring stack..."
docker stack deploy \
    --compose-file docker/swarm/monitoring.yml \
    --with-registry-auth \
    powernode-monitoring

# Wait for monitoring services
log_info "Waiting for monitoring services to be ready..."
sleep 30

# Deploy main application stack
log_info "Deploying application stack..."
docker stack deploy \
    --compose-file "docker/swarm/${ENVIRONMENT}.yml" \
    --with-registry-auth \
    "powernode-${ENVIRONMENT}"

# Wait for deployment
log_info "Waiting for services to be ready..."
sleep 60

# Health check
log_info "Running health checks..."
if ./scripts/deployment/health-check-remote.sh "powernode-${ENVIRONMENT}"; then
    log_success "Deployment completed successfully!"
else
    log_error "Health checks failed. Check service status."
    exit 1
fi

# Show deployment status
log_info "Deployment status:"
docker service ls --filter name="powernode-${ENVIRONMENT}"

# Switch back to local context
docker context use default
log_info "Switched back to local Docker context"
```

## 4. Secrets Management Script

Create `scripts/deployment/setup-secrets.sh`:
```bash
#!/bin/bash
# Docker secrets setup for remote deployment

ENVIRONMENT=${1:-production}
SECRET_PREFIX="${ENVIRONMENT}"

create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        echo "Secret $secret_name already exists, skipping..."
    else
        echo "$secret_value" | docker secret create "$secret_name" -
        echo "Created secret: $secret_name"
    fi
}

# Database secrets
create_secret "${SECRET_PREFIX}_db_name" "powernode_${ENVIRONMENT}"
create_secret "${SECRET_PREFIX}_db_user" "powernode"
create_secret "${SECRET_PREFIX}_db_password" "$(openssl rand -base64 32)"

# Redis secrets
create_secret "${SECRET_PREFIX}_redis_password" "$(openssl rand -base64 32)"

# Application secrets
if [[ -f "server/config/master.key" ]]; then
    create_secret "${SECRET_PREFIX}_rails_master_key" "$(cat server/config/master.key)"
else
    echo "Warning: server/config/master.key not found"
fi

create_secret "${SECRET_PREFIX}_jwt_secret" "$(openssl rand -hex 64)"

# Payment gateway secrets (prompt for sensitive data)
read -rsp "Enter Stripe secret key for ${ENVIRONMENT}: " stripe_secret
echo
create_secret "${SECRET_PREFIX}_stripe_secret_key" "$stripe_secret"

read -rsp "Enter PayPal client secret for ${ENVIRONMENT}: " paypal_secret
echo
create_secret "${SECRET_PREFIX}_paypal_client_secret" "$paypal_secret"

# Monitoring secrets
create_secret "grafana_admin_password" "$(openssl rand -base64 16)"

echo "All secrets have been created successfully!"
```

## 5. Remote Health Check Script

Create `scripts/deployment/health-check-remote.sh`:
```bash
#!/bin/bash
# Remote health check script

STACK_NAME=${1:-powernode-production}
MAX_RETRIES=30
RETRY_INTERVAL=10

check_service_health() {
    local service_name="$1"
    local replicas_running=$(docker service ls --filter name="$service_name" --format "{{.Replicas}}" | grep -o '^[0-9]*')
    local replicas_desired=$(docker service ls --filter name="$service_name" --format "{{.Replicas}}" | grep -o '[0-9]*$')
    
    if [[ "$replicas_running" == "$replicas_desired" ]] && [[ "$replicas_running" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Wait for all services to be healthy
echo "Checking service health for stack: $STACK_NAME"

services=(
    "${STACK_NAME}_postgres"
    "${STACK_NAME}_redis" 
    "${STACK_NAME}_backend"
    "${STACK_NAME}_worker"
    "${STACK_NAME}_frontend"
)

for service in "${services[@]}"; do
    echo "Checking $service..."
    retry_count=0
    
    while ! check_service_health "$service"; do
        retry_count=$((retry_count + 1))
        
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "ERROR: $service failed to become healthy within timeout"
            docker service ps "$service"
            exit 1
        fi
        
        echo "Waiting for $service to be healthy... (attempt $retry_count/$MAX_RETRIES)"
        sleep $RETRY_INTERVAL
    done
    
    echo "✓ $service is healthy"
done

echo "All services are healthy!"

# Test API endpoints
if command -v curl >/dev/null 2>&1; then
    echo "Testing API endpoints..."
    
    # Get the actual URL from environment or use default
    API_URL="${BACKEND_URL:-https://powernode.io/api}"
    
    if curl -f -s "${API_URL}/v1/health" >/dev/null; then
        echo "✓ API health check passed"
    else
        echo "⚠ API health check failed"
    fi
fi

exit 0
```

## 6. Deployment Workflow

### One-Time Setup
```bash
# 1. Configure SSH and Docker context
ssh-keygen -t rsa -b 4096 -f ~/.ssh/powernode-deploy
ssh-copy-id -i ~/.ssh/powernode-deploy.pub deploy@swarm-manager.example.com
docker context create powernode-production --docker "host=ssh://deploy@swarm-manager.example.com"

# 2. Build and push images to registry
docker build -t your-registry.com/powernode/backend:main-latest ./server
docker build -t your-registry.com/powernode/frontend:main-latest ./frontend  
docker build -t your-registry.com/powernode/worker:main-latest ./worker

docker push your-registry.com/powernode/backend:main-latest
docker push your-registry.com/powernode/frontend:main-latest
docker push your-registry.com/powernode/worker:main-latest

# 3. Make scripts executable
chmod +x scripts/deploy-remote.sh
chmod +x scripts/deployment/setup-secrets.sh
chmod +x scripts/deployment/health-check-remote.sh
```

### Regular Deployment
```bash
# Deploy to production
./scripts/deploy-remote.sh production

# Deploy to staging
./scripts/deploy-remote.sh staging
```

## 7. CI/CD Integration

For automated deployments, update `.github/workflows/ci-pipeline.yml`:

```yaml
deploy-production:
  name: Deploy to Production
  runs-on: ubuntu-latest
  needs: [build-backend, build-frontend, build-worker]
  if: github.ref == 'refs/heads/main'
  environment: production
  
  steps:
  - name: Checkout code
    uses: actions/checkout@v4
  
  - name: Setup SSH key
    uses: webfactory/ssh-agent@v0.8.0
    with:
      ssh-private-key: ${{ secrets.DEPLOY_SSH_PRIVATE_KEY }}
  
  - name: Create Docker context
    run: |
      docker context create production --docker "host=ssh://deploy@${{ secrets.SWARM_MANAGER_HOST }}"
  
  - name: Deploy to production
    env:
      REGISTRY_URL: ${{ secrets.REGISTRY_URL }}
      VERSION: main-${{ github.sha }}
      DOMAIN: ${{ secrets.PRODUCTION_DOMAIN }}
    run: |
      ./scripts/deploy-remote.sh production
```

## 8. Troubleshooting

### Common Issues

**Context Connection Issues**:
```bash
# Test SSH connectivity
ssh -i ~/.ssh/powernode-deploy deploy@swarm-manager.example.com 'docker node ls'

# Recreate context if needed
docker context rm powernode-production
docker context create powernode-production --docker "host=ssh://deploy@swarm-manager.example.com"
```

**Registry Authentication Issues**:
```bash
# Verify registry login on swarm nodes
docker context use powernode-production
docker login your-registry.com
```

**Service Deployment Failures**:
```bash
# Check service logs remotely
docker context use powernode-production
docker service logs powernode-production_backend

# Inspect failed services
docker service ps powernode-production_backend --no-trunc
```

**Network Connectivity Issues**:
```bash
# Test internal connectivity
docker context use powernode-production
docker run --rm --network powernode_backend alpine:latest ping backend
```

## 9. Security Considerations

### SSH Security
- Use dedicated SSH keys for deployment
- Restrict SSH access to deployment user only
- Consider using SSH bastion hosts for additional security

### Registry Security
- Use private container registries
- Implement image scanning in CI/CD
- Rotate registry credentials regularly

### Secrets Management
- Never commit secrets to version control
- Use Docker secrets for sensitive data
- Consider external secret management (HashiCorp Vault, etc.)

### Network Security
- Use internal networks for backend services
- Implement proper firewall rules
- Consider VPN access for management

This setup provides secure, automated deployment to remote Docker Swarm clusters while maintaining proper separation between development and production environments.