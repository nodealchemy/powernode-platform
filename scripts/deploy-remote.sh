#!/bin/bash
# Remote Docker Swarm deployment script for Powernode Platform
# Usage: ./scripts/deploy-remote.sh [environment] [version]

set -euo pipefail

ENVIRONMENT=${1:-production}
VERSION=${2:-"main-latest"}
SWARM_CONTEXT="powernode-${ENVIRONMENT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be 'staging' or 'production'"
    exit 1
fi

# Check if required files exist
if [[ ! -f ".env.${ENVIRONMENT}" ]]; then
    log_error "Environment file .env.${ENVIRONMENT} not found"
    log_info "Please create .env.${ENVIRONMENT} with required configuration"
    exit 1
fi

if [[ ! -f "docker/swarm/${ENVIRONMENT}.yml" ]]; then
    log_error "Docker compose file docker/swarm/${ENVIRONMENT}.yml not found"
    exit 1
fi

log_info "Starting deployment to $ENVIRONMENT environment"
log_info "Version: $VERSION"
log_info "Docker Context: $SWARM_CONTEXT"

# Store current context to restore later
ORIGINAL_CONTEXT=$(docker context show)

# Function to restore context on exit
cleanup() {
    log_info "Restoring original Docker context: $ORIGINAL_CONTEXT"
    docker context use "$ORIGINAL_CONTEXT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Switch to remote Docker context
log_info "Switching to Docker context: $SWARM_CONTEXT"
if ! docker context use "$SWARM_CONTEXT"; then
    log_error "Failed to switch to Docker context: $SWARM_CONTEXT"
    log_info "Please ensure the context exists and is configured correctly:"
    log_info "docker context create $SWARM_CONTEXT --docker \"host=ssh://deploy@swarm-manager.example.com\""
    exit 1
fi

# Verify swarm connectivity
log_info "Verifying Docker Swarm connectivity..."
if ! docker node ls >/dev/null 2>&1; then
    log_error "Cannot connect to Docker Swarm. Check your context configuration."
    log_info "Debug steps:"
    log_info "1. Test SSH: ssh deploy@swarm-manager.example.com 'docker node ls'"
    log_info "2. Check context: docker context inspect $SWARM_CONTEXT"
    exit 1
fi

log_success "Connected to Docker Swarm"
docker node ls

# Load environment variables
log_info "Loading environment variables from .env.${ENVIRONMENT}"
set -a
source ".env.${ENVIRONMENT}"
set +a

# Set deployment variables
export REGISTRY_URL="${REGISTRY_URL:-your-registry.com/powernode}"
export VERSION="$VERSION"
export ENVIRONMENT="$ENVIRONMENT"

log_info "Registry: $REGISTRY_URL"
log_info "Domain: ${DOMAIN:-powernode.local}"

# Create networks if they don't exist
log_info "Creating Docker networks..."

create_network() {
    local network_name=$1
    local network_args=${2:-"--driver overlay --attachable"}
    
    if docker network ls --format "{{.Name}}" | grep -q "^${network_name}$"; then
        log_info "Network $network_name already exists"
    else
        eval "docker network create $network_args $network_name"
        log_success "Created network: $network_name"
    fi
}

create_network "powernode_frontend" "--driver overlay --attachable"
create_network "powernode_backend" "--driver overlay"
create_network "powernode_monitoring" "--driver overlay --attachable"

# Setup secrets
log_info "Setting up Docker secrets..."
if [[ -f "$SCRIPT_DIR/deployment/setup-secrets.sh" ]]; then
    "$SCRIPT_DIR/deployment/setup-secrets.sh" "$ENVIRONMENT"
else
    log_warning "Secrets setup script not found. Please ensure secrets are created manually."
fi

# Check if monitoring stack should be deployed
DEPLOY_MONITORING=${DEPLOY_MONITORING:-true}
if [[ "$DEPLOY_MONITORING" == "true" ]] && [[ -f "docker/swarm/monitoring.yml" ]]; then
    log_info "Deploying monitoring stack..."
    
    # Check if monitoring stack already exists
    if docker stack ls --format "{{.Name}}" | grep -q "^powernode-monitoring$"; then
        log_info "Updating existing monitoring stack"
    else
        log_info "Deploying new monitoring stack"
    fi
    
    docker stack deploy \
        --compose-file docker/swarm/monitoring.yml \
        --with-registry-auth \
        powernode-monitoring
    
    log_success "Monitoring stack deployment initiated"
    
    # Wait briefly for monitoring services
    log_info "Waiting for monitoring services to initialize..."
    sleep 30
fi

# Pre-deployment validation
log_info "Running pre-deployment validation..."

# Check if images exist in registry (if possible)
log_info "Validating container images..."

validate_image() {
    local image="$1"
    log_info "Checking image: $image"
    # This will fail if image doesn't exist or if there are registry auth issues
    if docker manifest inspect "$image" >/dev/null 2>&1; then
        log_success "✓ Image available: $image"
    else
        log_warning "⚠ Cannot validate image: $image (may require registry authentication)"
    fi
}

validate_image "${REGISTRY_URL}-backend:${VERSION}"
validate_image "${REGISTRY_URL}-frontend:${VERSION}"
validate_image "${REGISTRY_URL}-worker:${VERSION}"

# Deploy main application stack
log_info "Deploying application stack: powernode-${ENVIRONMENT}"

# Check if stack already exists
if docker stack ls --format "{{.Name}}" | grep -q "^powernode-${ENVIRONMENT}$"; then
    log_info "Updating existing application stack"
else
    log_info "Deploying new application stack"
fi

# Deploy with error handling
if docker stack deploy \
    --compose-file "docker/swarm/${ENVIRONMENT}.yml" \
    --with-registry-auth \
    "powernode-${ENVIRONMENT}"; then
    log_success "Application stack deployment initiated"
else
    log_error "Failed to deploy application stack"
    exit 1
fi

# Wait for services to start
log_info "Waiting for services to initialize..."
sleep 60

# Enhanced health check
log_info "Running health checks..."

# Function to check service health
check_service_health() {
    local service_name="$1"
    local max_retries=${2:-30}
    local retry_interval=${3:-10}
    local retry_count=0
    
    log_info "Checking health of service: $service_name"
    
    while [[ $retry_count -lt $max_retries ]]; do
        # Get service status
        local replicas=$(docker service ls --filter name="$service_name" --format "{{.Replicas}}")
        
        if [[ "$replicas" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            local running="${BASH_REMATCH[1]}"
            local desired="${BASH_REMATCH[2]}"
            
            if [[ "$running" == "$desired" ]] && [[ "$running" -gt 0 ]]; then
                log_success "✓ $service_name is healthy ($replicas)"
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        log_info "Waiting for $service_name... ($retry_count/$max_retries) Current: $replicas"
        
        # Show any failed tasks
        if [[ $retry_count -gt 5 ]]; then
            local failed_tasks=$(docker service ps "$service_name" --filter desired-state=running --format "table {{.Name}}\t{{.CurrentState}}" | grep -c "Failed\|Rejected" || echo "0")
            if [[ "$failed_tasks" -gt 0 ]]; then
                log_warning "$service_name has $failed_tasks failed tasks"
                docker service ps "$service_name" --no-trunc
            fi
        fi
        
        sleep "$retry_interval"
    done
    
    log_error "✗ $service_name failed to become healthy within timeout"
    docker service ps "$service_name" --no-trunc
    return 1
}

# Check critical services
STACK_NAME="powernode-${ENVIRONMENT}"
critical_services=(
    "${STACK_NAME}_postgres"
    "${STACK_NAME}_redis"
    "${STACK_NAME}_backend"
    "${STACK_NAME}_worker"
    "${STACK_NAME}_frontend"
)

health_check_failed=false
for service in "${critical_services[@]}"; do
    if ! check_service_health "$service" 30 10; then
        health_check_failed=true
    fi
done

if [[ "$health_check_failed" == "true" ]]; then
    log_error "One or more services failed health checks"
    log_info "Stack status:"
    docker stack ps "$STACK_NAME"
    exit 1
fi

# API endpoint testing (if curl is available)
if command -v curl >/dev/null 2>&1; then
    log_info "Testing API endpoints..."
    
    API_URL="${BACKEND_URL:-https://${DOMAIN}/api}"
    
    # Test health endpoint with retries
    test_endpoint() {
        local url="$1"
        local max_retries=${2:-5}
        local retry_count=0
        
        while [[ $retry_count -lt $max_retries ]]; do
            if curl -f -s --connect-timeout 10 --max-time 30 "$url" >/dev/null 2>&1; then
                log_success "✓ API endpoint responsive: $url"
                return 0
            fi
            
            retry_count=$((retry_count + 1))
            log_info "Testing API endpoint... ($retry_count/$max_retries)"
            sleep 10
        done
        
        log_warning "⚠ API endpoint not responding: $url"
        return 1
    }
    
    test_endpoint "${API_URL}/v1/health"
    
    # Test frontend if available
    FRONTEND_URL="${FRONTEND_URL:-https://${DOMAIN}}"
    test_endpoint "$FRONTEND_URL"
else
    log_info "curl not available, skipping endpoint testing"
fi

# Final status report
log_success "Deployment completed successfully!"
log_info "=== Deployment Summary ==="
log_info "Environment: $ENVIRONMENT"
log_info "Version: $VERSION"
log_info "Stack: powernode-${ENVIRONMENT}"

echo
log_info "=== Service Status ==="
docker service ls --filter name="powernode-${ENVIRONMENT}"

echo
log_info "=== Stack Tasks ==="
docker stack ps "powernode-${ENVIRONMENT}" --format "table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}"

echo
log_info "=== Access URLs ==="
log_info "Frontend: ${FRONTEND_URL:-https://${DOMAIN}}"
log_info "API: ${BACKEND_URL:-https://${DOMAIN}/api}"
if [[ "$DEPLOY_MONITORING" == "true" ]]; then
    log_info "Grafana: https://grafana.${DOMAIN}"
    log_info "Prometheus: https://prometheus.${DOMAIN}"
fi

log_success "Remote deployment completed successfully!"