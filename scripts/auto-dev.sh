#!/bin/bash

# Automatic Development Environment Manager
# Helper script for Claude to automatically start/manage development servers including worker service

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_MANAGER="$PROJECT_ROOT/scripts/backend-manager.sh"
WORKER_MANAGER="$PROJECT_ROOT/scripts/worker-manager.sh"
FRONTEND_MANAGER="$PROJECT_ROOT/scripts/frontend-manager.sh"

# Service timeout configurations (can be overridden via environment)
BACKEND_TIMEOUT=${POWERNODE_BACKEND_TIMEOUT:-90}
WORKER_TIMEOUT=${POWERNODE_WORKER_TIMEOUT:-60}
WORKER_WEB_TIMEOUT=${POWERNODE_WORKER_WEB_TIMEOUT:-45}
FRONTEND_TIMEOUT=${POWERNODE_FRONTEND_TIMEOUT:-180}  # Increased for webpack builds
FINAL_CHECK_TIMEOUT=${POWERNODE_FINAL_CHECK_TIMEOUT:-30}

# Adaptive timeout multipliers based on system load
TIMEOUT_MULTIPLIER=1.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $1"
}

info() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')] ℹ${NC} $1"
}

debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${MAGENTA}[$(date +'%H:%M:%S')] 🔍${NC} $1"
    fi
}

# Function to calculate adaptive timeout based on system load
calculate_adaptive_timeout() {
    local base_timeout="$1"
    local service_name="$2"
    
    # Check system load average
    local load_avg=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    local cpu_count=$(nproc 2>/dev/null || echo 4)
    
    # Calculate load ratio (load per CPU)
    local load_ratio=$(echo "scale=2; $load_avg / $cpu_count" | bc 2>/dev/null || echo "0.5")
    
    # Adjust timeout based on load
    local multiplier=1.0
    if (( $(echo "$load_ratio > 2.0" | bc -l 2>/dev/null || echo 0) )); then
        multiplier=2.0
        warn "High system load detected (${load_avg}), doubling timeout for $service_name" >&2
    elif (( $(echo "$load_ratio > 1.0" | bc -l 2>/dev/null || echo 0) )); then
        multiplier=1.5
        info "Moderate system load (${load_avg}), increasing timeout by 50% for $service_name" >&2
    fi
    
    # Check if this is first startup (no cache/build artifacts)
    local first_startup_multiplier=1.0
    case "$service_name" in
        Frontend)
            # Check multiple indicators for first startup or rebuild scenarios
            if [ ! -d "$PROJECT_ROOT/frontend/node_modules/.cache" ]; then
                first_startup_multiplier=1.5
                info "First frontend startup detected, increasing timeout by 50%" >&2
            elif [ ! -d "$PROJECT_ROOT/frontend/build" ] && [ ! -d "$PROJECT_ROOT/frontend/.next" ]; then
                # No build artifacts present
                first_startup_multiplier=1.4
                info "No frontend build artifacts found, increasing timeout by 40%" >&2
            elif [ -f "$PROJECT_ROOT/frontend/package.json" ]; then
                # Check if package.json was recently modified (dependencies changed)
                local package_age=$(find "$PROJECT_ROOT/frontend/package.json" -mmin -60 2>/dev/null)
                if [ -n "$package_age" ]; then
                    first_startup_multiplier=1.3
                    info "Recent package.json changes detected, increasing timeout by 30%" >&2
                fi
            fi
            ;;
        Backend)
            if [ ! -f "$PROJECT_ROOT/server/tmp/pids/server.pid" ]; then
                first_startup_multiplier=1.3
                info "First backend startup detected, increasing timeout by 30%" >&2
            fi
            ;;
    esac
    
    # Calculate final timeout
    local final_timeout=$(echo "scale=0; $base_timeout * $multiplier * $first_startup_multiplier / 1" | bc 2>/dev/null || echo "$base_timeout")
    
    debug "Adaptive timeout for $service_name: ${final_timeout}s (base: ${base_timeout}s, load multiplier: ${multiplier}, first startup: ${first_startup_multiplier})" >&2
    
    # Only output the numeric value
    echo "$final_timeout"
}

# Function to detect service startup phase
detect_startup_phase() {
    local service_name="$1"
    local health_url="$2"
    local elapsed="$3"
    
    case "$service_name" in
        Backend)
            # Check for database migration indicators
            if pgrep -f "rails.*db:migrate" > /dev/null 2>&1; then
                printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Backend is running database migrations... ${elapsed}s"
                return 2  # Still initializing
            fi
            
            # Check for asset compilation
            if pgrep -f "rails.*assets:precompile" > /dev/null 2>&1; then
                printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Backend is compiling assets... ${elapsed}s"
                return 2
            fi
            ;;
            
        Frontend)
            # Check for webpack building
            if pgrep -f "webpack" > /dev/null 2>&1; then
                printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Frontend is building webpack bundle... ${elapsed}s"
                return 2
            fi
            
            # Check for TypeScript compilation
            if pgrep -f "tsc.*--watch" > /dev/null 2>&1; then
                printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Frontend is compiling TypeScript... ${elapsed}s"
                return 2
            fi
            
            # Check for initial npm install
            if pgrep -f "npm.*install" > /dev/null 2>&1; then
                printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Frontend is installing dependencies... ${elapsed}s"
                return 2
            fi
            
            # Check webpack-dev-server compilation status via network
            # webpack-dev-server returns specific headers during compilation
            local webpack_status=$(curl -s -I "http://localhost:3001" 2>/dev/null | grep -i "x-webpack-" | head -1)
            if [ -n "$webpack_status" ]; then
                debug "Webpack status detected: $webpack_status"
                
                # If webpack is still compiling, it may return partial responses
                if curl -s "http://localhost:3001/webpack-dev-server" 2>/dev/null | grep -q "progress"; then
                    printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Frontend webpack-dev-server is compiling... ${elapsed}s"
                    return 2
                fi
            fi
            
            # Check if the dev server is responding but still initializing
            local response_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3001" 2>/dev/null)
            if [ "$response_code" = "503" ] || [ "$response_code" = "504" ]; then
                printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Frontend dev server is initializing... ${elapsed}s"
                return 2
            fi
            ;;
            
        Worker*)
            # Check for Sidekiq booting
            if [ -f "$PROJECT_ROOT/worker/tmp/sidekiq.pid" ]; then
                local pid=$(cat "$PROJECT_ROOT/worker/tmp/sidekiq.pid" 2>/dev/null)
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    # Check if Sidekiq is still booting (checking memory growth)
                    local mem1=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1}')
                    sleep 1
                    local mem2=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print $1}')
                    
                    if [ -n "$mem1" ] && [ -n "$mem2" ] && [ "$mem2" -gt "$mem1" ]; then
                        printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} Worker is loading job classes... ${elapsed}s"
                        return 2
                    fi
                fi
            fi
            ;;
    esac
    
    return 0  # No special phase detected
}

# Function to parse JSON health response and extract status
parse_health_status() {
    local response="$1"
    local service_name="$2"
    
    # Try to extract status from JSON response
    local status=$(echo "$response" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
    
    if [ -n "$status" ]; then
        debug "$service_name health status: $status"
        case "$status" in
            healthy|ok|OK|running|operational)
                return 0
                ;;
            starting|initializing|booting)
                return 2  # Service is starting
                ;;
            *)
                return 1  # Service is unhealthy
                ;;
        esac
    fi
    
    # Special handling for Worker Web Interface (returns service info JSON)
    if echo "$response" | grep -q '"service":"Powernode Worker"'; then
        debug "$service_name detected as Powernode Worker service"
        return 0  # Worker web interface is healthy if it returns service info
    fi
    
    # Special handling for Frontend (webpack-dev-server returns HTML)
    if [ "$service_name" = "Frontend" ]; then
        # Check if response contains React app root element or webpack runtime
        if echo "$response" | grep -q -E '(id="root"|__webpack_require__|React|<!DOCTYPE html>)'; then
            debug "$service_name detected as React application"
            return 0  # Frontend is healthy if it returns HTML with React markers
        fi
    fi
    
    # Check for other success indicators
    if echo "$response" | grep -qi '\(success\|healthy\|ok\|version\|timestamp\)'; then
        return 0
    fi
    
    return 1
}

# Enhanced health check with exponential backoff and detailed diagnostics
wait_for_service_health_enhanced() {
    local service_name="$1"
    local health_url="$2"
    local base_timeout="${3:-60}"
    local initial_interval="${4:-1}"
    local max_interval="${5:-10}"
    
    # Calculate adaptive timeout
    local max_wait=$(calculate_adaptive_timeout "$base_timeout" "$service_name")
    
    log "Waiting for $service_name to become healthy (timeout: ${max_wait}s)..."
    
    # Show timeout configuration if custom
    if [ "$max_wait" != "$base_timeout" ]; then
        info "Timeout adjusted from ${base_timeout}s to ${max_wait}s based on system conditions"
    fi
    
    local elapsed=0
    local attempt=0
    local interval=$initial_interval
    local last_error=""
    local consecutive_failures=0
    local last_phase_check=0
    
    while [ $elapsed -lt $max_wait ]; do
        attempt=$((attempt + 1))
        
        # Check startup phase every 5 seconds
        if [ $((elapsed - last_phase_check)) -ge 5 ]; then
            detect_startup_phase "$service_name" "$health_url" "$elapsed"
            local phase_status=$?
            last_phase_check=$elapsed
            
            # If service is in a known initialization phase, be more patient
            if [ $phase_status -eq 2 ]; then
                consecutive_failures=0  # Reset failure count during initialization
            fi
        fi
        
        # Attempt health check with detailed error capture
        local response
        local http_code
        response=$(curl -s -w "\n%{http_code}" --max-time 5 "$health_url" 2>&1)
        http_code=$(echo "$response" | tail -n1)
        response=$(echo "$response" | head -n-1)
        
        debug "Attempt $attempt: HTTP $http_code for $service_name"
        
        # Check HTTP status code
        if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
            # Parse JSON response if available
            if [ -n "$response" ]; then
                if parse_health_status "$response" "$service_name"; then
                    success "$service_name is healthy (took ${elapsed}s, $attempt attempts)"
                    
                    # Show service details if available
                    local version=$(echo "$response" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
                    if [ -n "$version" ]; then
                        info "$service_name version: $version"
                    fi
                    
                    return 0
                elif [ $? -eq 2 ]; then
                    # Service is still starting
                    printf "\r${CYAN}[$(date +'%H:%M:%S')]${NC} $service_name is initializing... ${elapsed}s/${max_wait}s"
                else
                    last_error="Service reports unhealthy status"
                fi
            else
                # No response body but successful HTTP code
                success "$service_name responded successfully (took ${elapsed}s)"
                return 0
            fi
        elif [ "$http_code" = "000" ]; then
            last_error="Connection refused or timeout"
            consecutive_failures=$((consecutive_failures + 1))
        elif [ "$http_code" = "503" ]; then
            last_error="Service unavailable (still starting)"
            printf "\r${YELLOW}[$(date +'%H:%M:%S')]${NC} $service_name unavailable, retrying... ${elapsed}s/${max_wait}s"
        else
            last_error="HTTP $http_code"
            consecutive_failures=$((consecutive_failures + 1))
        fi
        
        # Check for consecutive failures (increase threshold during high load)
        local failure_threshold=5
        if [ "$(echo "$(uptime | awk '{print $(NF-2)}' | sed 's/,//') > 4.0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
            failure_threshold=8  # More tolerance during high load
        fi
        
        if [ $consecutive_failures -ge $failure_threshold ]; then
            warn "$service_name has failed $consecutive_failures consecutive health checks"
            
            # Try to get diagnostic information
            if command -v lsof >/dev/null 2>&1; then
                local port=$(echo "$health_url" | grep -o ':[0-9]*' | sed 's/://')
                if [ -n "$port" ]; then
                    local process=$(lsof -i :"$port" 2>/dev/null | grep LISTEN | head -1)
                    if [ -z "$process" ]; then
                        error "No process listening on port $port for $service_name"
                        
                        # Suggest restart
                        info "Try restarting $service_name with appropriate manager script"
                    fi
                fi
            fi
            consecutive_failures=0
        fi
        
        # Progress indicator
        printf "\r${BLUE}[$(date +'%H:%M:%S')]${NC} Waiting for $service_name... ${elapsed}s/${max_wait}s (attempt $attempt)"
        
        # Exponential backoff with jitter
        sleep $interval
        elapsed=$((elapsed + interval))
        
        # Increase interval with exponential backoff
        interval=$((interval * 2))
        if [ $interval -gt $max_interval ]; then
            interval=$max_interval
        fi
    done
    
    printf "\n"
    error "$service_name failed to become healthy within ${max_wait}s"
    if [ -n "$last_error" ]; then
        error "Last error: $last_error"
    fi
    
    # Provide troubleshooting suggestions
    info "Troubleshooting suggestions:"
    info "  1. Check service logs: screen -r powernode-${service_name,,}"
    info "  2. Verify port availability: lsof -i :$(echo "$health_url" | grep -o ':[0-9]*' | sed 's/://')"
    info "  3. Restart service: $0 restart"
    
    return 1
}

# Function to wait for a service to become healthy with progress indicator
wait_for_service_health() {
    # Delegate to enhanced version
    wait_for_service_health_enhanced "$@"
}

# Function to check if all servers are running and healthy
check_dev_environment() {
    local backend_running=false
    local worker_running=false
    local frontend_running=false
    
    # Check backend
    if "$BACKEND_MANAGER" status > /dev/null 2>&1; then
        if curl -s -f --max-time 3 "http://localhost:3000/api/v1/health" > /dev/null 2>&1; then
            backend_running=true
        fi
    fi
    
    # Check worker - use manager status for both worker and web interface
    if "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING" && "$WORKER_MANAGER" status 2>&1 | grep -q "Web Interface: RUNNING"; then
        worker_running=true
    fi
    
    # Check frontend
    if "$FRONTEND_MANAGER" status > /dev/null 2>&1; then
        if curl -s -f --max-time 3 "http://localhost:3001" > /dev/null 2>&1; then
            frontend_running=true
        fi
    fi
    
    if $backend_running && $worker_running && $frontend_running; then
        return 0
    else
        return 1
    fi
}

# Enhanced health check for individual services with JSON parsing
check_service_health_detailed() {
    local service_name="$1"
    local health_url="$2"
    local extra_checks="${3:-}"
    
    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" --max-time 5 "$health_url" 2>&1)
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
        # Extract detailed information from JSON response
        local status=$(echo "$response" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
        local version=$(echo "$response" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
        local uptime=$(echo "$response" | grep -o '"uptime"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"uptime"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/' 2>/dev/null)
        
        # Check for database connectivity (backend specific)
        local db_status="unknown"
        if echo "$response" | grep -q '"database"'; then
            db_status=$(echo "$response" | grep -o '"database"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"database"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
        fi
        
        # Check for Redis connectivity (if applicable)
        local redis_status="unknown"
        if echo "$response" | grep -q '"redis"'; then
            redis_status=$(echo "$response" | grep -o '"redis"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"redis"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)
        fi
        
        # Build health report
        echo "${service_name}:"
        echo "  Status: ${status:-healthy}"
        [ -n "$version" ] && echo "  Version: $version"
        [ -n "$uptime" ] && echo "  Uptime: $(($uptime / 60)) minutes"
        [ "$db_status" != "unknown" ] && echo "  Database: $db_status"
        [ "$redis_status" != "unknown" ] && echo "  Redis: $redis_status"
        
        # Run extra checks if provided
        if [ -n "$extra_checks" ]; then
            eval "$extra_checks"
        fi
        
        return 0
    else
        echo "${service_name}: ❌ Not responding (HTTP $http_code)"
        return 1
    fi
}

# Comprehensive health check function with detailed reporting
detailed_health_check() {
    local verbose="${1:-false}"
    local show_diagnostics="${2:-false}"
    local all_healthy=true
    
    if [ "$verbose" = "true" ]; then
        log "Running comprehensive health check with diagnostics..."
        echo ""
    fi
    
    # Backend API health check with details
    if [ "$verbose" = "true" ]; then
        log "Checking Backend API..."
    fi
    
    if check_service_health_detailed "Backend API" "http://localhost:3000/api/v1/health"; then
        if [ "$verbose" = "true" ]; then
            success "Backend API is healthy"
        fi
    else
        all_healthy=false
        if [ "$verbose" = "true" ]; then
            error "Backend API health check failed"
            
            # Additional diagnostics
            if [ "$show_diagnostics" = "true" ]; then
                info "Backend diagnostics:"
                # Check if Rails process is running
                if pgrep -f "puma.*3000" > /dev/null; then
                    info "  Rails server process is running"
                else
                    error "  Rails server process not found"
                fi
                
                # Check database connectivity directly
                if command -v psql >/dev/null 2>&1; then
                    if psql -U postgres -d powernode_development -c "SELECT 1" >/dev/null 2>&1; then
                        info "  PostgreSQL database is accessible"
                    else
                        error "  PostgreSQL database connection failed"
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
    
    # Worker service health check
    if [ "$verbose" = "true" ]; then
        log "Checking Worker Service..."
    fi
    
    local worker_status=$("$WORKER_MANAGER" status 2>&1)
    if echo "$worker_status" | grep -q "Worker: RUNNING"; then
        if [ "$verbose" = "true" ]; then
            success "Worker process is running"
            
            # Check Sidekiq process details
            if [ "$show_diagnostics" = "true" ]; then
                local sidekiq_pid=$(pgrep -f "sidekiq.*worker" | head -1)
                if [ -n "$sidekiq_pid" ]; then
                    info "  Sidekiq PID: $sidekiq_pid"
                    
                    # Check memory usage
                    if command -v ps >/dev/null 2>&1; then
                        local mem_usage=$(ps -o rss= -p "$sidekiq_pid" 2>/dev/null | awk '{printf "%.1f", $1/1024}')
                        [ -n "$mem_usage" ] && info "  Memory usage: ${mem_usage} MB"
                    fi
                fi
            fi
        fi
    else
        all_healthy=false
        if [ "$verbose" = "true" ]; then
            error "Worker process is not running"
        fi
    fi
    
    # Worker web interface check
    if echo "$worker_status" | grep -q "Web Interface: RUNNING"; then
        if curl -s -f --max-time 3 "http://localhost:4567" > /dev/null 2>&1; then
            if [ "$verbose" = "true" ]; then
                success "Worker web interface is accessible"
            fi
        else
            all_healthy=false
            if [ "$verbose" = "true" ]; then
                warn "Worker web interface process running but not responding"
            fi
        fi
    else
        all_healthy=false
        if [ "$verbose" = "true" ]; then
            error "Worker web interface is not running"
        fi
    fi
    
    echo ""
    
    # Frontend health check
    if [ "$verbose" = "true" ]; then
        log "Checking Frontend Application..."
    fi
    
    if check_service_health_detailed "Frontend" "http://localhost:3001" "echo '  Build status: Development mode'"; then
        if [ "$verbose" = "true" ]; then
            success "Frontend application is healthy"
        fi
    else
        all_healthy=false
        if [ "$verbose" = "true" ]; then
            error "Frontend health check failed"
            
            # Additional diagnostics
            if [ "$show_diagnostics" = "true" ]; then
                info "Frontend diagnostics:"
                # Check if Node process is running
                if pgrep -f "node.*3001" > /dev/null; then
                    info "  Node.js dev server is running"
                else
                    error "  Node.js dev server process not found"
                fi
                
                # Check for common frontend issues
                if [ -f "$PROJECT_ROOT/frontend/package.json" ]; then
                    info "  package.json exists"
                    
                    # Check if node_modules exists
                    if [ -d "$PROJECT_ROOT/frontend/node_modules" ]; then
                        info "  node_modules directory exists"
                    else
                        error "  node_modules missing - run 'npm install'"
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
    
    # System resource check
    if [ "$show_diagnostics" = "true" ] && [ "$verbose" = "true" ]; then
        log "System Resource Status:"
        
        # Memory usage
        if command -v free >/dev/null 2>&1; then
            local mem_info=$(free -h | grep "^Mem:" | awk '{print "Total: " $2 ", Used: " $3 ", Free: " $4}')
            info "  Memory: $mem_info"
        fi
        
        # Disk usage
        if command -v df >/dev/null 2>&1; then
            local disk_info=$(df -h "$PROJECT_ROOT" | tail -1 | awk '{print "Used: " $3 " / " $2 " (" $5 ")"}')
            info "  Disk: $disk_info"
        fi
        
        # Load average
        if command -v uptime >/dev/null 2>&1; then
            local load_avg=$(uptime | awk -F'load average:' '{print $2}')
            info "  Load average:$load_avg"
        fi
        
        echo ""
    fi
    
    # Overall status summary
    if $all_healthy; then
        if [ "$verbose" = "true" ]; then
            success "All services are healthy and operational"
        fi
        return 0
    else
        if [ "$verbose" = "true" ]; then
            error "Some services are not healthy"
            echo ""
            warn "Troubleshooting tips:"
            warn "  1. View individual service logs: $0 logs [backend|worker|frontend]"
            warn "  2. Restart all services: $0 restart"
            warn "  3. Check system resources: $0 health --diagnostics"
        fi
        return 1
    fi
}

# Function to automatically ensure development environment is running
ensure_dev_environment() {
    log "Checking development environment status..."
    
    if check_dev_environment; then
        success "Development environment is already running and healthy"
        return 0
    fi
    
    log "Starting development environment..."
    
    # Start backend first
    log "Ensuring backend is running..."
    if ! "$BACKEND_MANAGER" start; then
        error "Failed to start backend server"
        return 1
    fi
    
    # Wait for backend to be ready with proper health checking
    if ! wait_for_service_health "Backend" "http://localhost:3000/api/v1/health" "$BACKEND_TIMEOUT"; then
        error "Backend failed to start within timeout"
        
        # Offer to retry with extended timeout
        info "Tip: You can increase the timeout by setting POWERNODE_BACKEND_TIMEOUT environment variable"
        info "Example: POWERNODE_BACKEND_TIMEOUT=120 $0 ensure"
        return 1
    fi
    
    # Start worker second
    log "Ensuring worker is running..."
    if ! "$WORKER_MANAGER" start; then
        error "Failed to start worker service"
        return 1
    fi
    
    # Wait for worker to be ready
    log "Waiting for worker process to initialize..."
    sleep 5
    
    # Start worker web interface
    log "Ensuring worker web interface is running..."
    if ! "$WORKER_MANAGER" start-web; then
        error "Failed to start worker web interface"
        return 1
    fi
    
    # Wait for worker web interface to be ready
    if ! wait_for_service_health "Worker Web Interface" "http://localhost:4567" "$WORKER_WEB_TIMEOUT"; then
        warn "Worker web interface may not be fully ready, but continuing..."
        info "Tip: Increase timeout with POWERNODE_WORKER_WEB_TIMEOUT if needed"
    fi
    
    # Start frontend third
    log "Ensuring frontend is running..."
    if ! "$FRONTEND_MANAGER" start; then
        error "Failed to start frontend server"
        return 1
    fi
    
    # Wait for frontend to be ready with proper health checking
    if ! wait_for_service_health "Frontend" "http://localhost:3001" "$FRONTEND_TIMEOUT"; then
        error "Frontend failed to start within timeout"
        
        # Offer suggestions for slow frontend builds
        info "Frontend builds can be slow on first run or after dependency changes"
        info "Tip: Increase timeout with POWERNODE_FRONTEND_TIMEOUT=180 $0 ensure"
        
        # Check for common issues
        if [ ! -d "$PROJECT_ROOT/frontend/node_modules" ]; then
            error "node_modules not found! Run: cd frontend && npm install"
        fi
        
        return 1
    fi
    
    # Final comprehensive verification
    log "Running final health verification..."
    if detailed_health_check false; then
        success "Development environment is now fully operational!"
        echo ""
        log "🚀 All services are healthy and ready:"
        log "  • Backend API:  http://localhost:3000 (external: http://[HOST_IP]:3000)"
        log "  • Worker Web:   http://localhost:4567 (external: http://[HOST_IP]:4567)"
        log "  • Frontend App: http://localhost:3001 (external: http://[HOST_IP]:3001)"
        return 0
    else
        error "Development environment failed final health check"
        log "Run with 'health' command for detailed diagnostics"
        return 1
    fi
}

# Function to start only backend if needed
ensure_backend() {
    log "Ensuring backend server is running..."
    
    if curl -s --max-time 1 --connect-timeout 1 "http://localhost:3000" > /dev/null 2>&1; then
        success "Backend is already running and healthy"
        return 0
    fi
    
    "$BACKEND_MANAGER" start
}

# Function to start only worker if needed
ensure_worker() {
    log "Ensuring worker service is running..."
    
    if "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING" && "$WORKER_MANAGER" status 2>&1 | grep -q "Web Interface: RUNNING"; then
        success "Worker and web interface are already running and healthy"
        return 0
    fi
    
    # Start worker service if needed
    if ! "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING"; then
        "$WORKER_MANAGER" start
    fi
    
    # Start web interface if needed
    if ! "$WORKER_MANAGER" status 2>&1 | grep -q "Web Interface: RUNNING"; then
        "$WORKER_MANAGER" start-web
    fi
}

# Function to start only frontend if needed
ensure_frontend() {
    log "Ensuring frontend server is running..."
    
    if curl -s -f --max-time 3 "http://localhost:3001" > /dev/null 2>&1; then
        success "Frontend is already running and healthy"
        return 0
    fi
    
    "$FRONTEND_MANAGER" start
}

# Function to show quick status
quick_status() {
    local backend_status="❌ Not Running"
    local worker_status="❌ Not Running"
    local frontend_status="❌ Not Running"
    
    if curl -s -f --max-time 3 "http://localhost:3000/api/v1/health" > /dev/null 2>&1; then
        backend_status="✅ Running & Healthy"
    fi
    
    # Check worker using manager status for both worker and web interface
    if "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING" && "$WORKER_MANAGER" status 2>&1 | grep -q "Web Interface: RUNNING"; then
        worker_status="✅ Running & Healthy (with Web UI)"
    elif "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING"; then
        worker_status="⚠️ Running (Web UI Stopped)"
    fi
    
    if curl -s -f --max-time 3 "http://localhost:3001" > /dev/null 2>&1; then
        frontend_status="✅ Running & Healthy"
    fi
    
    echo "Development Environment Status:"
    echo "  Backend:  $backend_status"
    echo "  Worker:   $worker_status"
    echo "  Frontend: $frontend_status"
    
    if [[ "$backend_status" == *"✅"* && "$worker_status" == *"✅"* && "$frontend_status" == *"✅"* ]]; then
        echo ""
        echo "🚀 Ready for development!"
        echo "  • API:    http://localhost:3000 (external: http://[HOST_IP]:3000)"
        echo "  • Worker: http://localhost:4567 (external: http://[HOST_IP]:4567)"
        echo "  • App:    http://localhost:3001 (external: http://[HOST_IP]:3001)"
        return 0
    else
        return 1
    fi
}

# Function to stop all servers
stop_all() {
    log "Stopping all development servers..."
    
    # Stop backend
    if "$BACKEND_MANAGER" status > /dev/null 2>&1; then
        log "Stopping backend server..."
        "$BACKEND_MANAGER" stop
        success "Backend server stopped"
    else
        log "Backend server already stopped"
    fi
    
    # Stop worker and web interface
    if "$WORKER_MANAGER" status 2>&1 | grep -q "RUNNING"; then
        log "Stopping worker service and web interface..."
        "$WORKER_MANAGER" stop-web > /dev/null 2>&1
        "$WORKER_MANAGER" stop
        success "Worker service stopped"
    else
        log "Worker service already stopped"
    fi
    
    # Stop frontend
    if "$FRONTEND_MANAGER" status > /dev/null 2>&1; then
        log "Stopping frontend server..."
        "$FRONTEND_MANAGER" stop
        success "Frontend server stopped"
    else
        log "Frontend server already stopped"
    fi
    
    success "All development servers stopped"
}

# Function to verify service is fully stopped
verify_service_stopped() {
    local service_name="$1"
    local port="$2"
    local max_wait="${3:-10}"
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        # Check if port is still in use
        if ! lsof -i :"$port" >/dev/null 2>&1; then
            debug "$service_name port $port is free"
            return 0
        fi
        
        debug "$service_name port $port still in use, waiting..."
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    warn "$service_name port $port still in use after ${max_wait}s"
    return 1
}

# Function to restart all servers
restart_all() {
    log "Restarting development environment..."
    
    # Step 1: Stop all services cleanly
    log "Step 1/4: Stopping all services..."
    stop_all
    
    # Step 2: Verify services are stopped and ports are free
    log "Step 2/4: Verifying services are stopped..."
    local all_stopped=true
    
    if ! verify_service_stopped "Backend" 3000 10; then
        warn "Backend port 3000 still in use"
        all_stopped=false
    fi
    
    if ! verify_service_stopped "Worker Web" 4567 5; then
        warn "Worker Web port 4567 still in use"
        all_stopped=false
    fi
    
    if ! verify_service_stopped "Frontend" 3001 10; then
        warn "Frontend port 3001 still in use"
        all_stopped=false
    fi
    
    if [ "$all_stopped" = "false" ]; then
        error "Some services did not stop cleanly"
        info "Attempting force cleanup..."
        
        # Force kill any remaining processes
        pkill -f "puma.*3000" 2>/dev/null || true
        pkill -f "sidekiq" 2>/dev/null || true
        pkill -f "node.*3001" 2>/dev/null || true
        
        sleep 3
    else
        success "All services stopped cleanly"
    fi
    
    # Step 3: Wait a moment for system resources to settle
    log "Step 3/4: Waiting for system resources to settle..."
    sleep 2
    
    # Step 4: Start all services using ensure_dev_environment
    log "Step 4/4: Starting all services..."
    if ensure_dev_environment; then
        success "Development environment restarted successfully!"
        return 0
    else
        error "Development environment failed to restart properly"
        
        # Provide diagnostics
        log "Running diagnostics..."
        detailed_health_check true false
        
        return 1
    fi
}

# Enhanced help function with detailed documentation
show_help() {
    echo "Powernode Development Environment Manager"
    echo "========================================="
    echo ""
    echo "USAGE:"
    echo "  $0 [COMMAND]"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  POWERNODE_BACKEND_TIMEOUT    Backend startup timeout (default: 90s)"
    echo "  POWERNODE_WORKER_TIMEOUT     Worker startup timeout (default: 60s)"
    echo "  POWERNODE_WORKER_WEB_TIMEOUT Worker web UI timeout (default: 45s)"
    echo "  POWERNODE_FRONTEND_TIMEOUT   Frontend startup timeout (default: 180s)"
    echo "  DEBUG                        Enable debug output (true/false)"
    echo ""
    echo "COMMANDS:"
    echo "  ensure     Start all services if needed (default command)"
    echo "  start      Alias for 'ensure'"
    echo "  backend    Ensure only backend service is running"
    echo "  worker     Ensure only worker service is running"
    echo "  frontend   Ensure only frontend service is running"
    echo "  status     Show quick status overview of all services"
    echo "  health     Run comprehensive health check with detailed diagnostics"
    echo "  health -d  Include system diagnostics in health check"
    echo "  check      Silent health check (exit code based, for scripts)"
    echo "  logs       View service logs (logs [backend|worker|frontend])"
    echo "  monitor    Live monitoring dashboard (updates every 5s)"
    echo "  restart    Restart all services (with full health checks)"
    echo "  restart -q Quick restart (skip health checks)"
    echo "  stop       Stop all services"
    echo "  help       Show this help message"
    echo ""
    echo "SERVICE ENDPOINTS:"
    echo "  Backend API:  http://localhost:3000 (Rails API server)"
    echo "  Worker Web:   http://localhost:4567 (Sidekiq web interface)"
    echo "  Frontend App: http://localhost:3001 (React development server)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Start all services (default)"
    echo "  $0 ensure             # Start all services explicitly"
    echo "  $0 status             # Check service status"
    echo "  $0 health             # Detailed health diagnostics"
    echo "  $0 health -d          # Health check with system diagnostics"
    echo "  $0 monitor            # Live service monitoring"
    echo "  $0 restart            # Restart with health checks (slower)"
    echo "  $0 restart -q         # Quick restart without checks (faster)"
    echo "  $0 backend            # Start only backend service"
    echo ""
    echo "  # With custom timeouts for slow systems:"
    echo "  POWERNODE_FRONTEND_TIMEOUT=180 $0 ensure"
    echo ""
    echo "  # Debug mode for troubleshooting:"
    echo "  DEBUG=true $0 ensure"
    echo ""
    echo "TROUBLESHOOTING:"
    echo "  • If services fail to start, try: $0 stop && $0 ensure"
    echo "  • For slow systems, increase timeouts:"
    echo "    export POWERNODE_FRONTEND_TIMEOUT=180"
    echo "    export POWERNODE_BACKEND_TIMEOUT=120"
    echo "  • For detailed diagnostics, use: $0 health --diagnostics"
    echo "  • Enable debug mode: DEBUG=true $0 ensure"
    echo "  • View individual service logs:"
    echo "    - Backend:  $0 logs backend  (or screen -r powernode-backend)"
    echo "    - Worker:   $0 logs worker   (or screen -r powernode-worker)"
    echo "    - Frontend: $0 logs frontend (or screen -r powernode-frontend)"
    echo ""
    echo ""
    echo "ADAPTIVE TIMEOUT FEATURES:"
    echo "  • Automatically adjusts timeouts based on system load"
    echo "  • Detects first startup and increases timeout accordingly"
    echo "  • Monitors service initialization phases (migrations, builds)"
    echo "  • Provides intelligent retry with exponential backoff"
    echo ""
    echo "This script manages the complete Powernode development environment"
    echo "including Rails API backend, Sidekiq worker service, and React frontend."
    echo "Timeouts adapt to system conditions for reliable service startup."
}

# Main command handling
case "${1:-ensure}" in
    ensure|start)
        ensure_dev_environment
        ;;
    backend)
        ensure_backend
        ;;
    worker)
        ensure_worker
        ;;
    frontend)
        ensure_frontend
        ;;
    status)
        quick_status
        ;;
    restart)
        # Check for quick restart flag
        if [ "${2:-}" = "--quick" ] || [ "${2:-}" = "-q" ]; then
            log "Quick restart (skipping health checks)..."
            stop_all
            sleep 2
            "$BACKEND_MANAGER" start
            "$WORKER_MANAGER" start
            "$WORKER_MANAGER" start-web
            "$FRONTEND_MANAGER" start
            success "Services restarted (use 'status' to verify)"
        else
            restart_all
        fi
        ;;
    health)
        # Check for additional flags
        show_diagnostics=false
        if [ "${2:-}" = "--diagnostics" ] || [ "${2:-}" = "-d" ]; then
            show_diagnostics=true
        fi
        
        if detailed_health_check true "$show_diagnostics"; then
            success "All services are healthy"
            echo ""
            echo "🚀 Development environment is fully operational!"
            echo "  • Backend API:  http://localhost:3000"
            echo "  • Worker Web:   http://localhost:4567"
            echo "  • Frontend App: http://localhost:3001"
            exit 0
        else
            error "Some services are not healthy"
            echo ""
            echo "💡 Try running: $0 ensure"
            echo "📊 For detailed diagnostics: $0 health --diagnostics"
            exit 1
        fi
        ;;
    logs)
        # View service logs
        service="${2:-all}"
        case "$service" in
            backend)
                log "Attaching to backend logs..."
                screen -r powernode-backend || error "Backend screen session not found"
                ;;
            worker)
                log "Attaching to worker logs..."
                screen -r powernode-worker || error "Worker screen session not found"
                ;;
            frontend)
                log "Attaching to frontend logs..."
                screen -r powernode-frontend || error "Frontend screen session not found"
                ;;
            all|*)
                log "Available log sessions:"
                screen -ls | grep powernode || warn "No active screen sessions found"
                echo ""
                echo "Usage: $0 logs [backend|worker|frontend]"
                ;;
        esac
        ;;
    monitor)
        # Live monitoring mode
        log "Starting live service monitor (press Ctrl+C to exit)..."
        while true; do
            clear
            echo "═══════════════════════════════════════════════════════════════"
            echo " POWERNODE SERVICE MONITOR - $(date +'%Y-%m-%d %H:%M:%S')"
            echo "═══════════════════════════════════════════════════════════════"
            echo ""
            
            # Quick status for each service
            printf "%-20s" "Backend API:"
            if curl -s -f --max-time 1 "http://localhost:3000/api/v1/health" > /dev/null 2>&1; then
                echo -e "${GREEN}● HEALTHY${NC}"
            else
                echo -e "${RED}● DOWN${NC}"
            fi
            
            printf "%-20s" "Worker Service:"
            if "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING"; then
                echo -e "${GREEN}● RUNNING${NC}"
            else
                echo -e "${RED}● STOPPED${NC}"
            fi
            
            printf "%-20s" "Worker Web UI:"
            if curl -s -f --max-time 1 "http://localhost:4567" > /dev/null 2>&1; then
                echo -e "${GREEN}● ACCESSIBLE${NC}"
            else
                echo -e "${RED}● UNREACHABLE${NC}"
            fi
            
            printf "%-20s" "Frontend App:"
            if curl -s -f --max-time 1 "http://localhost:3001" > /dev/null 2>&1; then
                echo -e "${GREEN}● SERVING${NC}"
            else
                echo -e "${RED}● OFFLINE${NC}"
            fi
            
            echo ""
            echo "───────────────────────────────────────────────────────────────"
            
            # System resources
            if command -v free >/dev/null 2>&1; then
                echo "Memory: $(free -h | grep '^Mem:' | awk '{print $3 " / " $2 " used"}')"
            fi
            
            if command -v uptime >/dev/null 2>&1; then
                echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
            fi
            
            echo "───────────────────────────────────────────────────────────────"
            echo "Press Ctrl+C to exit | Refreshing every 5 seconds..."
            
            sleep 5
        done
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    stop)
        stop_all
        ;;
    check)
        if check_dev_environment; then
            success "Development environment is healthy"
            exit 0
        else
            error "Development environment has issues"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {ensure|backend|worker|frontend|status|restart|stop|check|health|logs|monitor|help}"
        echo ""
        echo "❌ Unknown command: '$1'"
        echo ""
        echo "Available commands:"
        echo "  ensure    - Start all services if not running"
        echo "  status    - Quick status check"
        echo "  health    - Detailed health diagnostics"
        echo "  monitor   - Live service monitoring"
        echo "  logs      - View service logs"
        echo "  restart   - Restart all services"
        echo "  stop      - Stop all services"
        echo "  help      - Show detailed help"
        echo ""
        echo "💡 For detailed help and examples, run: $0 help"
        exit 1
        ;;
esac