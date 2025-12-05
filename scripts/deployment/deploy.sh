#!/bin/bash
# Main deployment script for Powernode Platform
# Usage: ./deploy.sh [environment] [version]

set -euo pipefail

# Configuration
ENVIRONMENT=${1:-staging}
VERSION=${2:-latest}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        staging|production)
            log_info "Deploying to $ENVIRONMENT environment"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Must be 'staging' or 'production'"
            exit 1
            ;;
    esac
}

# Load environment variables
load_env_vars() {
    local env_file="${PROJECT_ROOT}/.env.${ENVIRONMENT}"
    
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment variables from $env_file"
        # Export variables for use in docker-compose
        set -a
        source "$env_file"
        set +a
    else
        log_warning "Environment file $env_file not found"
    fi
    
    # Set required environment variables
    export REGISTRY_URL=${REGISTRY_URL:-"localhost:5000"}
    export VERSION="$VERSION"
    export COMPOSE_PROJECT_NAME="powernode-${ENVIRONMENT}"
}

# Pre-deployment checks
pre_deployment_checks() {
    log_info "Running pre-deployment checks..."
    
    # Check Docker Swarm status
    if ! docker info | grep -q "Swarm: active"; then
        log_error "Docker Swarm is not active"
        exit 1
    fi
    
    # Check if images exist
    local images=("powernode-backend" "powernode-frontend" "powernode-worker")
    for image in "${images[@]}"; do
        if ! docker manifest inspect "${REGISTRY_URL}/${image}:${VERSION}" >/dev/null 2>&1; then
            log_warning "Image ${REGISTRY_URL}/${image}:${VERSION} not found in registry"
        else
            log_info "✓ Image ${image}:${VERSION} found"
        fi
    done
    
    # Validate stack configuration
    if ! docker stack config -c "docker/swarm/${ENVIRONMENT}.yml" >/dev/null 2>&1; then
        log_error "Invalid stack configuration for $ENVIRONMENT"
        exit 1
    fi
    
    log_success "Pre-deployment checks passed"
}

# Create or update secrets
manage_secrets() {
    log_info "Managing Docker secrets..."
    
    local secrets=("db_name" "db_user" "db_password" "redis_password" "rails_master_key" "jwt_secret")
    
    for secret in "${secrets[@]}"; do
        if ! docker secret inspect "$secret" >/dev/null 2>&1; then
            log_warning "Secret '$secret' not found. Please create it manually:"
            log_warning "  echo 'secret-value' | docker secret create $secret -"
        else
            log_info "✓ Secret '$secret' exists"
        fi
    done
}

# Deploy stack
deploy_stack() {
    local stack_name="powernode-${ENVIRONMENT}"
    
    log_info "Deploying stack: $stack_name"
    log_info "Version: $VERSION"
    log_info "Registry: $REGISTRY_URL"
    
    # Deploy the stack
    docker stack deploy \
        --compose-file "docker/swarm/${ENVIRONMENT}.yml" \
        --with-registry-auth \
        "$stack_name"
    
    log_success "Stack deployment initiated"
}

# Wait for deployment to complete
wait_for_deployment() {
    local stack_name="powernode-${ENVIRONMENT}"
    local max_wait=600  # 10 minutes
    local elapsed=0
    
    log_info "Waiting for deployment to complete..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local pending_services=$(docker service ls --filter name="${stack_name}" --format "{{.Name}} {{.Replicas}}" | grep -E "0/|[0-9]+/[0-9]+" | wc -l)
        
        if [[ $pending_services -eq 0 ]]; then
            log_success "All services are running"
            return 0
        fi
        
        log_info "Waiting for services to start... ($elapsed/${max_wait}s)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log_error "Deployment timed out after ${max_wait}s"
    return 1
}

# Run health checks
run_health_checks() {
    log_info "Running health checks..."
    
    if [[ -f "${SCRIPT_DIR}/health-check.sh" ]]; then
        bash "${SCRIPT_DIR}/health-check.sh" "powernode-${ENVIRONMENT}"
    else
        log_warning "Health check script not found"
    fi
}

# Run smoke tests
run_smoke_tests() {
    log_info "Running smoke tests..."
    
    if [[ -f "${SCRIPT_DIR}/smoke-tests.sh" ]]; then
        local app_url
        case $ENVIRONMENT in
            production)
                app_url="${PRODUCTION_URL:-https://app.powernode.io}"
                ;;
            staging)
                app_url="${STAGING_URL:-https://staging.powernode.io}"
                ;;
        esac
        
        bash "${SCRIPT_DIR}/smoke-tests.sh" "$app_url"
    else
        log_warning "Smoke tests script not found"
    fi
}

# Main deployment function
main() {
    log_info "Starting deployment of Powernode Platform"
    log_info "Environment: $ENVIRONMENT"
    log_info "Version: $VERSION"
    
    validate_environment
    load_env_vars
    pre_deployment_checks
    manage_secrets
    deploy_stack
    
    if wait_for_deployment; then
        run_health_checks
        run_smoke_tests
        log_success "Deployment completed successfully!"
    else
        log_error "Deployment failed!"
        exit 1
    fi
}

# Execute main function
main "$@"