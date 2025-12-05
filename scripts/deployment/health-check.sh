#!/bin/bash
# Health check script for Docker Swarm deployment
# Usage: ./health-check.sh [stack-name]

set -euo pipefail

STACK_NAME=${1:-powernode-staging}
MAX_RETRIES=30
RETRY_INTERVAL=10

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

# Check service health
check_service_health() {
    local service_name=$1
    local health_endpoint=$2
    local expected_status=${3:-200}
    local retry_count=0
    
    log_info "Checking health of service: $service_name"
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        # Get service container IP
        local container_id=$(docker service ps "$service_name" --filter "desired-state=running" --format "{{.ID}}" | head -1)
        
        if [[ -z "$container_id" ]]; then
            log_warning "No running containers found for $service_name (attempt $((retry_count + 1))/$MAX_RETRIES)"
            sleep $RETRY_INTERVAL
            retry_count=$((retry_count + 1))
            continue
        fi
        
        # Try to get health status from container
        local health_status=$(docker service ps "$service_name" --filter "desired-state=running" --format "{{.CurrentState}}" | head -1)
        
        if echo "$health_status" | grep -q "Running"; then
            log_success "✓ Service $service_name is running"
            
            # If health endpoint provided, test it
            if [[ -n "$health_endpoint" ]]; then
                if curl -f -s --max-time 10 "$health_endpoint" >/dev/null 2>&1; then
                    log_success "✓ Health endpoint $health_endpoint is responding"
                    return 0
                else
                    log_warning "Health endpoint $health_endpoint not responding (attempt $((retry_count + 1))/$MAX_RETRIES)"
                fi
            else
                return 0
            fi
        else
            log_warning "Service $service_name not ready: $health_status (attempt $((retry_count + 1))/$MAX_RETRIES)"
        fi
        
        sleep $RETRY_INTERVAL
        retry_count=$((retry_count + 1))
    done
    
    log_error "Health check failed for $service_name after $MAX_RETRIES attempts"
    return 1
}

# Check database connectivity
check_database() {
    local service_name="${STACK_NAME}_postgres"
    
    log_info "Checking database connectivity..."
    
    # Check if PostgreSQL service is running
    if docker service ps "$service_name" --filter "desired-state=running" --quiet | head -1 >/dev/null; then
        log_success "✓ Database service is running"
        
        # Try to connect to database through backend service
        local backend_service="${STACK_NAME}_backend"
        local container_id=$(docker service ps "$backend_service" --filter "desired-state=running" --format "{{.Name}}.{{.ID}}" | head -1)
        
        if [[ -n "$container_id" ]]; then
            if docker exec "$container_id" rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" >/dev/null 2>&1; then
                log_success "✓ Database connection test passed"
                return 0
            else
                log_warning "Database connection test failed"
            fi
        fi
    else
        log_error "Database service is not running"
        return 1
    fi
}

# Check Redis connectivity
check_redis() {
    local service_name="${STACK_NAME}_redis"
    
    log_info "Checking Redis connectivity..."
    
    if docker service ps "$service_name" --filter "desired-state=running" --quiet | head -1 >/dev/null; then
        log_success "✓ Redis service is running"
        
        # Try to ping Redis through backend service
        local backend_service="${STACK_NAME}_backend"
        local container_id=$(docker service ps "$backend_service" --filter "desired-state=running" --format "{{.Name}}.{{.ID}}" | head -1)
        
        if [[ -n "$container_id" ]]; then
            if docker exec "$container_id" rails runner "Rails.cache.write('health_check', 'ok'); puts Rails.cache.read('health_check')" 2>/dev/null | grep -q "ok"; then
                log_success "✓ Redis connection test passed"
                return 0
            else
                log_warning "Redis connection test failed"
            fi
        fi
    else
        log_error "Redis service is not running"
        return 1
    fi
}

# Main health check function
main() {
    log_info "Starting health checks for stack: $STACK_NAME"
    
    local failed_checks=0
    
    # Check individual services
    local services=(
        "${STACK_NAME}_backend"
        "${STACK_NAME}_frontend" 
        "${STACK_NAME}_worker"
    )
    
    for service in "${services[@]}"; do
        if ! check_service_health "$service" ""; then
            failed_checks=$((failed_checks + 1))
        fi
    done
    
    # Check database
    if ! check_database; then
        failed_checks=$((failed_checks + 1))
    fi
    
    # Check Redis
    if ! check_redis; then
        failed_checks=$((failed_checks + 1))
    fi
    
    # Summary
    if [[ $failed_checks -eq 0 ]]; then
        log_success "All health checks passed!"
        
        # Display service status
        log_info "Service status:"
        docker service ls --filter name="$STACK_NAME"
        
        return 0
    else
        log_error "$failed_checks health check(s) failed"
        
        # Display failed services
        log_info "Service status:"
        docker service ls --filter name="$STACK_NAME"
        
        return 1
    fi
}

main "$@"