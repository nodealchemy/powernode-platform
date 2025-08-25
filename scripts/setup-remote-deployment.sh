#!/bin/bash
# Quick setup script for remote Docker Swarm deployment
# Usage: ./scripts/setup-remote-deployment.sh [swarm-manager-host] [environment]

set -euo pipefail

SWARM_HOST=${1:-"swarm-manager.example.com"}
ENVIRONMENT=${2:-"production"}
DEPLOY_USER=${3:-"deploy"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Setting up remote Docker Swarm deployment"
log_info "Swarm Host: $SWARM_HOST"
log_info "Environment: $ENVIRONMENT"
log_info "Deploy User: $DEPLOY_USER"

# Step 1: Generate SSH key if it doesn't exist
SSH_KEY="$HOME/.ssh/powernode-deploy"
if [[ ! -f "$SSH_KEY" ]]; then
    log_info "Generating SSH key for deployment..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -C "powernode-deploy-$(whoami)@$(hostname)" -N ""
    log_success "Generated SSH key: $SSH_KEY"
else
    log_info "SSH key already exists: $SSH_KEY"
fi

# Step 2: Copy SSH key to remote host
log_info "Copying SSH key to remote host..."
if ssh-copy-id -i "${SSH_KEY}.pub" "${DEPLOY_USER}@${SWARM_HOST}"; then
    log_success "SSH key copied to remote host"
else
    log_error "Failed to copy SSH key. Please ensure:"
    log_error "1. The remote host is accessible"
    log_error "2. The deploy user exists and has appropriate permissions"
    log_error "3. Password authentication is enabled (temporarily)"
    exit 1
fi

# Step 3: Test SSH connectivity
log_info "Testing SSH connectivity..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${DEPLOY_USER}@${SWARM_HOST}" 'echo "SSH connection successful"'; then
    log_success "SSH connectivity verified"
else
    log_error "SSH connection failed"
    exit 1
fi

# Step 4: Test Docker access on remote host
log_info "Testing Docker access on remote host..."
if ssh -i "$SSH_KEY" "${DEPLOY_USER}@${SWARM_HOST}" 'docker --version && docker node ls'; then
    log_success "Docker Swarm access verified"
else
    log_error "Docker access failed. Please ensure:"
    log_error "1. Docker is installed on the remote host"
    log_error "2. Docker Swarm is initialized"
    log_error "3. The deploy user is in the docker group"
    exit 1
fi

# Step 5: Create Docker context
CONTEXT_NAME="powernode-${ENVIRONMENT}"
log_info "Creating Docker context: $CONTEXT_NAME"

# Remove existing context if it exists
if docker context ls --format "{{.Name}}" | grep -q "^${CONTEXT_NAME}$"; then
    docker context rm "$CONTEXT_NAME"
    log_info "Removed existing context"
fi

if docker context create "$CONTEXT_NAME" --docker "host=ssh://${DEPLOY_USER}@${SWARM_HOST}"; then
    log_success "Created Docker context: $CONTEXT_NAME"
else
    log_error "Failed to create Docker context"
    exit 1
fi

# Step 6: Test Docker context
log_info "Testing Docker context..."
if docker context use "$CONTEXT_NAME" && docker node ls; then
    log_success "Docker context is working"
    docker context use default
else
    log_error "Docker context test failed"
    exit 1
fi

# Step 7: Create environment file if it doesn't exist
ENV_FILE=".env.${ENVIRONMENT}"
if [[ ! -f "$ENV_FILE" ]]; then
    log_info "Creating environment file: $ENV_FILE"
    
    # Create from example or template
    if [[ -f ".env.${ENVIRONMENT}.example" ]]; then
        cp ".env.${ENVIRONMENT}.example" "$ENV_FILE"
        log_success "Created $ENV_FILE from example file"
    else
        # Create basic template
        cat > "$ENV_FILE" << EOF
# ${ENVIRONMENT^} Environment Configuration
ENVIRONMENT=${ENVIRONMENT}
RAILS_ENV=${ENVIRONMENT}
NODE_ENV=production

# Registry Configuration (UPDATE REQUIRED)
REGISTRY_URL=your-registry.com/powernode
VERSION=main-latest

# Domain Configuration (UPDATE REQUIRED)
DOMAIN=powernode.io
ACME_EMAIL=admin@powernode.io

# URLs
${ENVIRONMENT^^}_URL=https://powernode.io
BACKEND_URL=https://powernode.io/api
FRONTEND_URL=https://powernode.io

# Performance Settings
RAILS_MAX_THREADS=5
WEB_CONCURRENCY=2
SIDEKIQ_CONCURRENCY=10

# Security
FORCE_SSL=true
RAILS_LOG_LEVEL=info
EOF
        log_success "Created basic $ENV_FILE template"
    fi
    
    log_warning "Please edit $ENV_FILE with your specific configuration!"
else
    log_info "Environment file already exists: $ENV_FILE"
fi

# Step 8: Verify deployment scripts
log_info "Verifying deployment scripts..."
required_scripts=(
    "scripts/deploy-remote.sh"
    "scripts/deployment/setup-secrets.sh"
    "scripts/deployment/health-check-remote.sh"
)

for script in "${required_scripts[@]}"; do
    if [[ -f "$script" && -x "$script" ]]; then
        log_success "✓ $script"
    else
        log_error "✗ $script (missing or not executable)"
    fi
done

# Step 9: Show next steps
echo
log_success "Remote deployment setup completed!"
echo
log_info "=== Next Steps ==="
echo
log_info "1. Update your environment configuration:"
log_info "   vi $ENV_FILE"
echo
log_info "2. Build and push your Docker images to registry:"
log_info "   docker build -t YOUR_REGISTRY/powernode-backend:main-latest ./server"
log_info "   docker build -t YOUR_REGISTRY/powernode-frontend:main-latest ./frontend"
log_info "   docker build -t YOUR_REGISTRY/powernode-worker:main-latest ./worker"
log_info "   docker push YOUR_REGISTRY/powernode-backend:main-latest"
log_info "   docker push YOUR_REGISTRY/powernode-frontend:main-latest"
log_info "   docker push YOUR_REGISTRY/powernode-worker:main-latest"
echo
log_info "3. Deploy to remote swarm:"
log_info "   ./scripts/deploy-remote.sh $ENVIRONMENT"
echo
log_info "=== Configuration Summary ==="
log_info "SSH Key: $SSH_KEY"
log_info "Docker Context: $CONTEXT_NAME"
log_info "Environment File: $ENV_FILE"
log_info "Swarm Host: $SWARM_HOST"
echo
log_info "=== Testing Commands ==="
log_info "Test SSH: ssh -i $SSH_KEY $DEPLOY_USER@$SWARM_HOST"
log_info "Test Docker Context: docker context use $CONTEXT_NAME && docker node ls"
log_info "Switch back to local: docker context use default"
echo
log_warning "Remember to:"
log_warning "• Update $ENV_FILE with your actual configuration"
log_warning "• Ensure your container registry is accessible from the swarm"  
log_warning "• Have your payment gateway credentials ready for secrets setup"