#!/bin/bash
# Remote health check script for Docker Swarm deployment
# Usage: ./health-check-remote.sh [stack-name] [max-retries] [retry-interval]

set -euo pipefail

STACK_NAME=${1:-powernode-production}
MAX_RETRIES=${2:-30}
RETRY_INTERVAL=${3:-10}

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

# Function to check if Docker Swarm is accessible
check_swarm_connectivity() {
    log_info "Checking Docker Swarm connectivity..."
    
    if ! docker node ls >/dev/null 2>&1; then
        log_error "Cannot connect to Docker Swarm. Ensure you're using the correct Docker context."
        log_info "Available contexts:"
        docker context ls
        return 1
    fi
    
    log_success "Connected to Docker Swarm"
    return 0
}

# Function to check service health
check_service_health() {
    local service_name="$1"
    local timeout=${2:-$MAX_RETRIES}
    
    log_info "Checking service health: $service_name"
    
    # Check if service exists
    if ! docker service inspect "$service_name" >/dev/null 2>&1; then
        log_error "Service not found: $service_name"
        return 1
    fi
    
    local retry_count=0
    while [[ $retry_count -lt $timeout ]]; do
        # Get service replicas info
        local replicas_info=$(docker service ls --filter name="$service_name" --format "{{.Replicas}}" 2>/dev/null)
        
        if [[ "$replicas_info" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            local running="${BASH_REMATCH[1]}"
            local desired="${BASH_REMATCH[2]}"
            
            if [[ "$running" == "$desired" ]] && [[ "$running" -gt 0 ]]; then
                log_success "✓ $service_name is healthy ($running/$desired replicas)"
                return 0
            elif [[ "$running" -gt 0 ]] && [[ "$running" -lt "$desired" ]]; then
                log_warning "⚠ $service_name is partially healthy ($running/$desired replicas)"
            else
                log_warning "⚠ $service_name is not ready ($running/$desired replicas)"
            fi
        else
            log_warning "⚠ Cannot parse replica status for $service_name: $replicas_info"
        fi
        
        retry_count=$((retry_count + 1))
        
        # Show detailed status every few retries
        if [[ $((retry_count % 5)) -eq 0 ]]; then
            log_info "Detailed status for $service_name (attempt $retry_count/$timeout):"
            docker service ps "$service_name" --format "table {{.Name}}\t{{.Image}}\t{{.CurrentState}}\t{{.Error}}" --no-trunc | head -10
        fi
        
        if [[ $retry_count -lt $timeout ]]; then
            log_info "Retrying in ${RETRY_INTERVAL}s... ($retry_count/$timeout)"
            sleep $RETRY_INTERVAL
        fi
    done
    
    log_error "✗ $service_name failed to become healthy within ${timeout} attempts"
    log_error "Final service status:"
    docker service ps "$service_name" --no-trunc
    return 1
}

# Function to test HTTP endpoint
test_http_endpoint() {
    local url="$1"
    local description="${2:-endpoint}"
    local max_retries="${3:-5}"
    local timeout="${4:-30}"
    
    if ! command -v curl >/dev/null 2>&1; then
        log_warning "curl not available, skipping HTTP endpoint testing"
        return 0
    fi
    
    log_info "Testing $description: $url"
    
    local retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 10 \
            --max-time "$timeout" \
            --retry 0 \
            "$url" 2>/dev/null || echo "000")
        
        if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
            log_success "✓ $description is responding (HTTP $http_code)"
            return 0
        elif [[ "$http_code" == "000" ]]; then
            log_warning "⚠ Cannot connect to $description"
        else
            log_warning "⚠ $description returned HTTP $http_code"
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_info "Retrying $description test... ($retry_count/$max_retries)"
            sleep 5
        fi
    done
    
    log_error "✗ $description is not responding correctly"
    return 1
}

# Function to check database connectivity
check_database_connectivity() {
    local stack_name="$1"
    
    log_info "Testing database connectivity..."
    
    # Try to connect to PostgreSQL through the backend service
    local postgres_service="${stack_name}_postgres"
    local backend_service="${stack_name}_backend"
    
    # Check if services exist
    if ! docker service inspect "$postgres_service" >/dev/null 2>&1; then
        log_warning "PostgreSQL service not found: $postgres_service"
        return 1
    fi
    
    if ! docker service inspect "$backend_service" >/dev/null 2>&1; then
        log_warning "Backend service not found: $backend_service"
        return 1
    fi
    
    # Try to execute a database query through the backend
    log_info "Testing database connection through backend service..."
    
    local container_id
    container_id=$(docker ps --filter name="${backend_service}" --format "{{.ID}}" | head -1)
    
    if [[ -z "$container_id" ]]; then
        log_warning "No running containers found for $backend_service"
        return 1
    fi
    
    # Test database connectivity
    if docker exec "$container_id" bundle exec rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" >/dev/null 2>&1; then
        log_success "✓ Database connectivity test passed"
        return 0
    else
        log_error "✗ Database connectivity test failed"
        return 1
    fi
}

# Function to check Redis connectivity
check_redis_connectivity() {
    local stack_name="$1"
    
    log_info "Testing Redis connectivity..."
    
    local redis_service="${stack_name}_redis"
    
    if ! docker service inspect "$redis_service" >/dev/null 2>&1; then
        log_warning "Redis service not found: $redis_service"
        return 1
    fi
    
    local container_id
    container_id=$(docker ps --filter name="${redis_service}" --format "{{.ID}}" | head -1)
    
    if [[ -z "$container_id" ]]; then
        log_warning "No running containers found for $redis_service"
        return 1
    fi
    
    # Test Redis connectivity (assuming password is available)
    if docker exec "$container_id" redis-cli ping >/dev/null 2>&1; then
        log_success "✓ Redis connectivity test passed"
        return 0
    else
        log_error "✗ Redis connectivity test failed"
        return 1
    fi
}

# Function to get service resource usage
show_resource_usage() {
    local stack_name="$1"
    
    log_info "Service resource usage:"
    
    # Get all containers for the stack
    local containers
    containers=$(docker ps --filter name="$stack_name" --format "{{.Names}}" | head -10)
    
    if [[ -n "$containers" ]]; then
        echo "$containers" | while read -r container; do
            if [[ -n "$container" ]]; then
                local stats
                stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "$container" 2>/dev/null || echo "$container\tN/A\tN/A\tN/A")
                echo "$stats"
            fi
        done
    else
        log_warning "No running containers found for stack: $stack_name"
    fi
}

# Main health check function
main() {
    log_info "Starting comprehensive health check for: $STACK_NAME"
    log_info "Max retries: $MAX_RETRIES, Retry interval: ${RETRY_INTERVAL}s"
    
    # Check Docker Swarm connectivity
    if ! check_swarm_connectivity; then
        exit 1
    fi
    
    # Check if stack exists
    if ! docker stack ls --format "{{.Name}}" | grep -q "^${STACK_NAME}$"; then
        log_error "Stack not found: $STACK_NAME"
        log_info "Available stacks:"
        docker stack ls
        exit 1
    fi
    
    log_success "Found stack: $STACK_NAME"
    
    # Get list of services in the stack
    local services
    services=$(docker service ls --filter name="$STACK_NAME" --format "{{.Name}}" | sort)
    
    if [[ -z "$services" ]]; then
        log_error "No services found for stack: $STACK_NAME"
        exit 1
    fi
    
    log_info "Found $(echo "$services" | wc -l) services in stack"
    
    # Health check each service
    local failed_services=0
    local total_services=0
    
    echo "$services" | while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            total_services=$((total_services + 1))
            if ! check_service_health "$service" "$MAX_RETRIES"; then
                failed_services=$((failed_services + 1))
            fi
        fi
    done
    
    # Wait for read from subshell to complete
    wait
    
    # Re-check failed services count (since we can't get it from subshell)
    failed_services=0
    echo "$services" | while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            local replicas_info=$(docker service ls --filter name="$service" --format "{{.Replicas}}" 2>/dev/null)
            if [[ "$replicas_info" =~ ^([0-9]+)/([0-9]+)$ ]]; then
                local running="${BASH_REMATCH[1]}"
                local desired="${BASH_REMATCH[2]}"
                if [[ "$running" != "$desired" ]] || [[ "$running" -eq 0 ]]; then
                    failed_services=$((failed_services + 1))
                fi
            fi
        fi
    done
    
    # Service connectivity tests
    log_info "Testing service connectivity..."
    
    # Database connectivity test
    check_database_connectivity "$STACK_NAME" || log_warning "Database connectivity test failed"
    
    # Redis connectivity test  
    check_redis_connectivity "$STACK_NAME" || log_warning "Redis connectivity test failed"
    
    # HTTP endpoint tests
    local environment
    if [[ "$STACK_NAME" =~ powernode-(.+)$ ]]; then
        environment="${BASH_REMATCH[1]}"
    else
        environment="production"
    fi
    
    # Load environment variables if available
    if [[ -f ".env.${environment}" ]]; then
        set -a
        source ".env.${environment}"
        set +a
    fi
    
    # Test API endpoints
    local api_url="${BACKEND_URL:-https://${DOMAIN:-powernode.local}/api}"
    local frontend_url="${FRONTEND_URL:-https://${DOMAIN:-powernode.local}}"
    
    test_http_endpoint "${api_url}/v1/health" "API health endpoint" 5 30 || log_warning "API health test failed"
    test_http_endpoint "$frontend_url" "Frontend" 3 30 || log_warning "Frontend test failed"
    
    # Show resource usage
    echo
    show_resource_usage "$STACK_NAME"
    
    # Final summary
    echo
    log_info "=== Health Check Summary ==="
    
    # Count healthy services
    local healthy_services=0
    local total_services=0
    
    echo "$services" | while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            total_services=$((total_services + 1))
            local replicas_info=$(docker service ls --filter name="$service" --format "{{.Replicas}}" 2>/dev/null)
            if [[ "$replicas_info" =~ ^([0-9]+)/([0-9]+)$ ]]; then
                local running="${BASH_REMATCH[1]}"
                local desired="${BASH_REMATCH[2]}"
                if [[ "$running" == "$desired" ]] && [[ "$running" -gt 0 ]]; then
                    healthy_services=$((healthy_services + 1))
                fi
            fi
        fi
    done
    
    # Final service status
    docker service ls --filter name="$STACK_NAME" --format "table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Image}}"
    
    # Overall health determination
    local all_healthy=true
    echo "$services" | while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            local replicas_info=$(docker service ls --filter name="$service" --format "{{.Replicas}}" 2>/dev/null)
            if [[ "$replicas_info" =~ ^([0-9]+)/([0-9]+)$ ]]; then
                local running="${BASH_REMATCH[1]}"
                local desired="${BASH_REMATCH[2]}"
                if [[ "$running" != "$desired" ]] || [[ "$running" -eq 0 ]]; then
                    all_healthy=false
                    break
                fi
            fi
        fi
    done
    
    # Check the result outside the subshell
    local final_check_failed=false
    echo "$services" | while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            local replicas_info=$(docker service ls --filter name="$service" --format "{{.Replicas}}" 2>/dev/null)
            if [[ "$replicas_info" =~ ^([0-9]+)/([0-9]+)$ ]]; then
                local running="${BASH_REMATCH[1]}"
                local desired="${BASH_REMATCH[2]}"
                if [[ "$running" != "$desired" ]] || [[ "$running" -eq 0 ]]; then
                    final_check_failed=true
                    break
                fi
            fi
        fi
    done
    
    if [[ "$final_check_failed" == "true" ]]; then
        log_error "Health check failed: Some services are not healthy"
        log_info "Use 'docker service ps $STACK_NAME' to investigate failed services"
        exit 1
    else
        log_success "All services are healthy! ✓"
        log_success "Health check completed successfully for: $STACK_NAME"
        exit 0
    fi
}

# Execute main function
main "$@"