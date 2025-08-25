#!/bin/bash
# Environment setup script for Powernode Platform
# Usage: ./environment-setup.sh [staging|production] [action]

set -euo pipefail

ENVIRONMENT=${1:-production}
ACTION=${2:-setup}  # setup, secrets, validate, teardown
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

# Configuration
STACK_NAME="powernode-${ENVIRONMENT}"
ENV_FILE="${PROJECT_ROOT}/.env.${ENVIRONMENT}"
COMPOSE_FILE="${PROJECT_ROOT}/docker/swarm/${ENVIRONMENT}.yml"

# Docker secrets for environment
declare -A SECRETS=(
    ["${ENVIRONMENT}_db_name"]="powernode_${ENVIRONMENT}"
    ["${ENVIRONMENT}_db_user"]="powernode"
    ["${ENVIRONMENT}_db_password"]=""  # Generated or prompted
    ["${ENVIRONMENT}_redis_password"]=""  # Generated or prompted
    ["${ENVIRONMENT}_rails_master_key"]=""  # From existing file or generated
    ["${ENVIRONMENT}_jwt_secret"]=""  # Generated
    ["${ENVIRONMENT}_stripe_secret_key"]=""  # Prompted
    ["${ENVIRONMENT}_paypal_client_secret"]=""  # Prompted
)

# Generate secure random passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Generate JWT secret
generate_jwt_secret() {
    openssl rand -hex 64
}

# Load environment variables
load_env_vars() {
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Loading environment variables from $ENV_FILE"
        set -a
        source "$ENV_FILE"
        set +a
    else
        log_warning "Environment file $ENV_FILE not found"
        if [[ -f "${ENV_FILE}.example" ]]; then
            log_info "Copying from example file"
            cp "${ENV_FILE}.example" "$ENV_FILE"
            log_warning "Please update $ENV_FILE with your specific values"
        fi
    fi
}

# Validate environment
validate_environment() {
    log_info "Validating $ENVIRONMENT environment..."
    
    # Check required files
    local required_files=(
        "$ENV_FILE"
        "$COMPOSE_FILE"
        "${PROJECT_ROOT}/server/config/master.key"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file missing: $file"
            return 1
        fi
    done
    
    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        return 1
    fi
    
    # Check Docker Swarm
    if ! docker node ls >/dev/null 2>&1; then
        log_error "Docker Swarm is not initialized"
        log_info "Run: docker swarm init"
        return 1
    fi
    
    # Validate environment-specific requirements
    case $ENVIRONMENT in
        production)
            # Check for production secrets
            local prod_secrets=("STRIPE_SECRET_KEY" "PAYPAL_CLIENT_SECRET")
            for secret in "${prod_secrets[@]}"; do
                if [[ -z "${!secret:-}" ]]; then
                    log_warning "Production secret $secret not set"
                fi
            done
            ;;
        staging)
            log_info "Staging environment validation passed"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            return 1
            ;;
    esac
    
    log_success "Environment validation passed"
}

# Setup Docker secrets
setup_secrets() {
    log_info "Setting up Docker secrets for $ENVIRONMENT..."
    
    # Load Rails master key
    if [[ -f "${PROJECT_ROOT}/server/config/master.key" ]]; then
        SECRETS["${ENVIRONMENT}_rails_master_key"]=$(cat "${PROJECT_ROOT}/server/config/master.key")
    else
        log_error "Rails master key not found"
        return 1
    fi
    
    # Generate or prompt for secrets
    for secret_name in "${!SECRETS[@]}"; do
        if docker secret ls --format "{{.Name}}" | grep -q "^${secret_name}$"; then
            log_info "Secret $secret_name already exists"
            continue
        fi
        
        local secret_value="${SECRETS[$secret_name]}"
        
        # Generate values for specific secrets
        case $secret_name in
            *_password)
                if [[ -z "$secret_value" ]]; then
                    secret_value=$(generate_password)
                    log_info "Generated password for $secret_name"
                fi
                ;;
            *_jwt_secret)
                secret_value=$(generate_jwt_secret)
                log_info "Generated JWT secret"
                ;;
            *_stripe_secret_key|*_paypal_client_secret)
                if [[ -z "$secret_value" ]]; then
                    read -rsp "Enter $secret_name: " secret_value
                    echo
                fi
                ;;
        esac
        
        # Create the secret
        if [[ -n "$secret_value" ]]; then
            echo "$secret_value" | docker secret create "$secret_name" -
            log_success "Created secret: $secret_name"
        else
            log_warning "Skipping empty secret: $secret_name"
        fi
    done
}

# Remove Docker secrets
remove_secrets() {
    log_info "Removing Docker secrets for $ENVIRONMENT..."
    
    for secret_name in "${!SECRETS[@]}"; do
        if docker secret ls --format "{{.Name}}" | grep -q "^${secret_name}$"; then
            docker secret rm "$secret_name"
            log_success "Removed secret: $secret_name"
        fi
    done
}

# Setup environment
setup_environment() {
    log_info "Setting up $ENVIRONMENT environment..."
    
    # Validate first
    validate_environment
    
    # Load environment variables
    load_env_vars
    
    # Setup secrets
    setup_secrets
    
    # Create necessary networks
    if ! docker network ls --format "{{.Name}}" | grep -q "powernode_frontend"; then
        docker network create --driver overlay --attachable powernode_frontend
        log_success "Created frontend network"
    fi
    
    if ! docker network ls --format "{{.Name}}" | grep -q "powernode_backend"; then
        docker network create --driver overlay powernode_backend
        log_success "Created backend network"
    fi
    
    # Label nodes if needed
    local node_id=$(docker node ls --format "{{.ID}}" --filter "role=manager" | head -1)
    docker node update --label-add "environment=${ENVIRONMENT}" "$node_id"
    log_success "Labeled manager node with environment=${ENVIRONMENT}"
    
    log_success "Environment setup completed for $ENVIRONMENT"
}

# Teardown environment
teardown_environment() {
    log_warning "Tearing down $ENVIRONMENT environment..."
    
    # Stop and remove stack
    if docker stack ls --format "{{.Name}}" | grep -q "^${STACK_NAME}$"; then
        docker stack rm "$STACK_NAME"
        log_success "Removed stack: $STACK_NAME"
        
        # Wait for services to be removed
        log_info "Waiting for services to be removed..."
        while docker service ls --format "{{.Name}}" | grep -q "${STACK_NAME}"; do
            sleep 5
        done
    fi
    
    # Remove secrets
    remove_secrets
    
    # Clean up volumes (with confirmation)
    read -p "Remove persistent volumes? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local volumes=(
            "${STACK_NAME}_postgres_data"
            "${STACK_NAME}_redis_data"
            "${STACK_NAME}_letsencrypt"
            "${STACK_NAME}_grafana_data"
            "${STACK_NAME}_prometheus_data"
        )
        
        for volume in "${volumes[@]}"; do
            if docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
                docker volume rm "$volume"
                log_success "Removed volume: $volume"
            fi
        done
    fi
    
    log_success "Environment teardown completed"
}

# Show environment status
show_status() {
    log_info "Environment Status: $ENVIRONMENT"
    echo
    
    # Stack status
    echo "=== Stack Status ==="
    if docker stack ls --format "table {{.Name}}\t{{.Services}}\t{{.Orchestrator}}" | grep -q "$STACK_NAME"; then
        docker stack ls --format "table {{.Name}}\t{{.Services}}\t{{.Orchestrator}}" | grep "$STACK_NAME"
        echo
        
        echo "=== Service Status ==="
        docker stack ps "$STACK_NAME" --format "table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}"
        echo
    else
        echo "Stack $STACK_NAME is not running"
        echo
    fi
    
    # Secrets status
    echo "=== Secrets Status ==="
    for secret_name in "${!SECRETS[@]}"; do
        if docker secret ls --format "{{.Name}}" | grep -q "^${secret_name}$"; then
            echo "✓ $secret_name"
        else
            echo "✗ $secret_name"
        fi
    done
    echo
    
    # Network status
    echo "=== Network Status ==="
    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | grep -E "powernode|NAME"
    echo
    
    # Volume status
    echo "=== Volume Status ==="
    docker volume ls --format "table {{.Name}}\t{{.Driver}}" | grep -E "${STACK_NAME}|NAME"
}

# Main execution
main() {
    log_info "Powernode Platform Environment Manager"
    log_info "Environment: $ENVIRONMENT"
    log_info "Action: $ACTION"
    echo
    
    case $ACTION in
        setup)
            setup_environment
            ;;
        secrets)
            setup_secrets
            ;;
        validate)
            validate_environment
            ;;
        teardown)
            teardown_environment
            ;;
        status)
            show_status
            ;;
        *)
            log_error "Invalid action: $ACTION"
            log_info "Valid actions: setup, secrets, validate, teardown, status"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"