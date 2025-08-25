#!/bin/bash
# Rollback script for Powernode Platform
# Usage: ./rollback.sh [environment] [target-version]

set -euo pipefail

ENVIRONMENT=${1:-staging}
TARGET_VERSION=${2:-}
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

# Get stack name
STACK_NAME="powernode-${ENVIRONMENT}"

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        staging|production)
            log_info "Rolling back $ENVIRONMENT environment"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            exit 1
            ;;
    esac
}

# Get deployment history
get_deployment_history() {
    log_info "Getting deployment history..."
    
    # Check if we have deployment tracking
    if docker config ls --format "{{.Name}}" | grep -q "${STACK_NAME}-deployments"; then
        log_info "Deployment history found"
        
        # Get last 5 deployments
        local deployments=$(docker config inspect "${STACK_NAME}-deployments" --format "{{.Spec.Data}}" | base64 -d 2>/dev/null || echo "[]")
        echo "$deployments" | jq -r '.[] | "\(.timestamp) - \(.version) - \(.commit)"' | head -5
    else
        log_warning "No deployment history found"
        
        # Try to get from service labels
        log_info "Checking service labels for version information..."
        docker service ls --filter name="$STACK_NAME" --format "table {{.Name}}\t{{.Image}}\t{{.CreatedAt}}"
    fi
}

# Get current version
get_current_version() {
    local backend_service="${STACK_NAME}_backend"
    local current_image=$(docker service inspect "$backend_service" --format "{{.Spec.TaskTemplate.ContainerSpec.Image}}" 2>/dev/null || echo "")
    
    if [[ -n "$current_image" ]]; then
        echo "$current_image" | sed 's/.*://'
    else
        echo "unknown"
    fi
}

# Get previous stable version
get_previous_version() {
    # Try to get from deployment history
    if docker config ls --format "{{.Name}}" | grep -q "${STACK_NAME}-deployments"; then
        local deployments=$(docker config inspect "${STACK_NAME}-deployments" --format "{{.Spec.Data}}" | base64 -d 2>/dev/null || echo "[]")
        echo "$deployments" | jq -r '.[1].version' 2>/dev/null || echo ""
    fi
}

# Create deployment backup
create_deployment_backup() {
    log_info "Creating deployment backup..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${PROJECT_ROOT}/backups/deployments/${timestamp}"
    
    mkdir -p "$backup_dir"
    
    # Backup current service configurations
    local services=$(docker service ls --filter name="$STACK_NAME" --format "{{.Name}}")
    
    for service in $services; do
        log_info "Backing up service: $service"
        docker service inspect "$service" > "${backup_dir}/${service}.json"
    done
    
    # Backup stack configuration
    if [[ -f "docker/swarm/${ENVIRONMENT}.yml" ]]; then
        cp "docker/swarm/${ENVIRONMENT}.yml" "${backup_dir}/stack-config.yml"
    fi
    
    log_success "Backup created at: $backup_dir"
    echo "$backup_dir" > "/tmp/${STACK_NAME}-rollback-backup"
}

# Perform rollback
perform_rollback() {
    local target_version=$1
    
    log_info "Rolling back to version: $target_version"
    
    # Load environment variables
    local env_file="${PROJECT_ROOT}/.env.${ENVIRONMENT}"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi
    
    # Set version for rollback
    export VERSION="$target_version"
    export REGISTRY_URL=${REGISTRY_URL:-"localhost:5000"}
    
    # Verify target images exist
    local images=("powernode-backend" "powernode-frontend" "powernode-worker")
    for image in "${images[@]}"; do
        if ! docker manifest inspect "${REGISTRY_URL}/${image}:${target_version}" >/dev/null 2>&1; then
            log_error "Target image ${REGISTRY_URL}/${image}:${target_version} not found"
            log_error "Cannot proceed with rollback"
            exit 1
        fi
    done
    
    log_success "All target images verified"
    
    # Perform rollback deployment
    log_info "Deploying rollback version..."
    
    docker stack deploy \
        --compose-file "docker/swarm/${ENVIRONMENT}.yml" \
        --with-registry-auth \
        "$STACK_NAME"
    
    log_success "Rollback deployment initiated"
}

# Wait for rollback completion
wait_for_rollback() {
    log_info "Waiting for rollback to complete..."
    
    local max_wait=600
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local pending_services=$(docker service ls --filter name="$STACK_NAME" --format "{{.Replicas}}" | grep -E "0/|[0-9]+/[0-9]+" | wc -l)
        
        if [[ $pending_services -eq 0 ]]; then
            log_success "Rollback completed"
            return 0
        fi
        
        log_info "Waiting for services to stabilize... ($elapsed/${max_wait}s)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    log_error "Rollback timed out"
    return 1
}

# Verify rollback
verify_rollback() {
    local target_version=$1
    
    log_info "Verifying rollback..."
    
    # Check service versions
    local services=("backend" "frontend" "worker")
    local verification_failed=0
    
    for service in "${services[@]}"; do
        local service_name="${STACK_NAME}_${service}"
        local current_image=$(docker service inspect "$service_name" --format "{{.Spec.TaskTemplate.ContainerSpec.Image}}" 2>/dev/null || echo "")
        
        if echo "$current_image" | grep -q "$target_version"; then
            log_success "✓ Service $service rolled back to $target_version"
        else
            log_error "✗ Service $service rollback verification failed"
            verification_failed=1
        fi
    done
    
    if [[ $verification_failed -eq 0 ]]; then
        log_success "Rollback verification passed"
        
        # Run health checks
        if [[ -f "${SCRIPT_DIR}/health-check.sh" ]]; then
            log_info "Running post-rollback health checks..."
            bash "${SCRIPT_DIR}/health-check.sh" "$STACK_NAME"
        fi
        
        return 0
    else
        log_error "Rollback verification failed"
        return 1
    fi
}

# Update deployment history
update_deployment_history() {
    local rolled_back_version=$1
    
    log_info "Updating deployment history..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local commit_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    # Create deployment record
    local deployment_record=$(jq -n \
        --arg timestamp "$timestamp" \
        --arg version "$rolled_back_version" \
        --arg commit "$commit_sha" \
        --arg type "rollback" \
        --arg user "${USER:-system}" \
        '{
            timestamp: $timestamp,
            version: $version,
            commit: $commit,
            type: $type,
            user: $user
        }')
    
    # Update deployment history config
    local current_history
    if docker config ls --format "{{.Name}}" | grep -q "${STACK_NAME}-deployments"; then
        current_history=$(docker config inspect "${STACK_NAME}-deployments" --format "{{.Spec.Data}}" | base64 -d 2>/dev/null || echo "[]")
    else
        current_history="[]"
    fi
    
    # Add new record and keep last 10
    local updated_history=$(echo "$current_history" | jq --argjson new "$deployment_record" '. = [$new] + . | .[0:10]')
    
    # Remove old config if exists
    docker config rm "${STACK_NAME}-deployments" 2>/dev/null || true
    
    # Create new config
    echo "$updated_history" | docker config create "${STACK_NAME}-deployments" -
    
    log_success "Deployment history updated"
}

# Interactive rollback menu
interactive_rollback() {
    log_info "Interactive rollback mode"
    
    # Get current version
    local current_version=$(get_current_version)
    log_info "Current version: $current_version"
    
    # Get deployment history
    log_info "Recent deployments:"
    get_deployment_history
    
    echo
    read -p "Enter target version for rollback (or 'auto' for previous stable): " target_input
    
    if [[ "$target_input" == "auto" ]]; then
        TARGET_VERSION=$(get_previous_version)
        if [[ -z "$TARGET_VERSION" ]]; then
            log_error "Cannot determine previous version automatically"
            exit 1
        fi
        log_info "Auto-selected target version: $TARGET_VERSION"
    else
        TARGET_VERSION="$target_input"
    fi
    
    if [[ -z "$TARGET_VERSION" ]]; then
        log_error "No target version specified"
        exit 1
    fi
    
    # Confirmation
    echo
    log_warning "ROLLBACK CONFIRMATION"
    log_warning "Environment: $ENVIRONMENT"
    log_warning "Current Version: $current_version"
    log_warning "Target Version: $TARGET_VERSION"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi
}

# Main function
main() {
    log_info "Starting rollback process"
    log_info "Environment: $ENVIRONMENT"
    
    validate_environment
    
    # If no target version specified, run interactive mode
    if [[ -z "$TARGET_VERSION" ]]; then
        interactive_rollback
    fi
    
    log_info "Target version: $TARGET_VERSION"
    
    # Pre-rollback checks
    if ! docker info | grep -q "Swarm: active"; then
        log_error "Docker Swarm is not active"
        exit 1
    fi
    
    # Create backup
    create_deployment_backup
    
    # Perform rollback
    perform_rollback "$TARGET_VERSION"
    
    # Wait for completion
    if wait_for_rollback; then
        if verify_rollback "$TARGET_VERSION"; then
            update_deployment_history "$TARGET_VERSION"
            log_success "Rollback completed successfully!"
            
            # Show final status
            log_info "Final service status:"
            docker service ls --filter name="$STACK_NAME"
        else
            log_error "Rollback verification failed!"
            
            # Check if we should restore from backup
            local backup_path=$(cat "/tmp/${STACK_NAME}-rollback-backup" 2>/dev/null || echo "")
            if [[ -n "$backup_path" ]]; then
                log_warning "Backup available at: $backup_path"
                log_warning "You may need to manually restore if needed"
            fi
            
            exit 1
        fi
    else
        log_error "Rollback failed!"
        exit 1
    fi
}

# Execute main function
main "$@"