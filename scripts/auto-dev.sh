#!/bin/bash

# Automatic Development Environment Manager
# Helper script for Claude to automatically start/manage development servers including worker service

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_MANAGER="$PROJECT_ROOT/scripts/backend-manager.sh"
WORKER_MANAGER="$PROJECT_ROOT/scripts/worker-manager.sh"
FRONTEND_MANAGER="$PROJECT_ROOT/scripts/frontend-manager.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

# Function to wait for a service to become healthy with progress indicator
wait_for_service_health() {
    local service_name="$1"
    local health_url="$2"
    local max_wait="${3:-30}"
    local check_interval="${4:-2}"
    
    log "Waiting for $service_name to become healthy..."
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -s -f --max-time 3 "$health_url" > /dev/null 2>&1; then
            success "$service_name is now healthy (took ${elapsed}s)"
            return 0
        fi
        
        printf "\r${BLUE}[$(date +'%H:%M:%S')]${NC} Waiting for $service_name... ${elapsed}s/${max_wait}s"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    printf "\n"
    error "$service_name failed to become healthy within ${max_wait}s"
    return 1
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

# Comprehensive health check function with detailed reporting
detailed_health_check() {
    local verbose="${1:-false}"
    local backend_healthy=false
    local worker_healthy=false
    local worker_web_healthy=false
    local frontend_healthy=false
    
    if [ "$verbose" = "true" ]; then
        log "Running comprehensive health check..."
    fi
    
    # Check backend health endpoint
    if curl -s -f --max-time 5 "http://localhost:3000/api/v1/health" > /dev/null 2>&1; then
        backend_healthy=true
        if [ "$verbose" = "true" ]; then
            success "Backend API health endpoint responsive"
        fi
    else
        if [ "$verbose" = "true" ]; then
            error "Backend API health endpoint not responsive"
        fi
    fi
    
    # Check worker process status
    if "$WORKER_MANAGER" status 2>&1 | grep -q "Worker: RUNNING"; then
        worker_healthy=true
        if [ "$verbose" = "true" ]; then
            success "Worker process is running"
        fi
    else
        if [ "$verbose" = "true" ]; then
            error "Worker process is not running"
        fi
    fi
    
    # Check worker web interface
    if "$WORKER_MANAGER" status 2>&1 | grep -q "Web Interface: RUNNING" && curl -s -f --max-time 3 "http://localhost:4567" > /dev/null 2>&1; then
        worker_web_healthy=true
        if [ "$verbose" = "true" ]; then
            success "Worker web interface is accessible"
        fi
    else
        if [ "$verbose" = "true" ]; then
            error "Worker web interface is not accessible"
        fi
    fi
    
    # Check frontend
    if curl -s -f --max-time 5 "http://localhost:3001" > /dev/null 2>&1; then
        frontend_healthy=true
        if [ "$verbose" = "true" ]; then
            success "Frontend application is accessible"
        fi
    else
        if [ "$verbose" = "true" ]; then
            error "Frontend application is not accessible"
        fi
    fi
    
    # Return overall health status
    if $backend_healthy && $worker_healthy && $worker_web_healthy && $frontend_healthy; then
        if [ "$verbose" = "true" ]; then
            success "All services are healthy"
        fi
        return 0
    else
        if [ "$verbose" = "true" ]; then
            warn "Some services are not healthy"
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
    if ! wait_for_service_health "Backend" "http://localhost:3000/api/v1/health" 45 3; then
        error "Backend failed to start within timeout"
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
    if ! wait_for_service_health "Worker Web Interface" "http://localhost:4567" 30 2; then
        warn "Worker web interface may not be fully ready, but continuing..."
    fi
    
    # Start frontend third
    log "Ensuring frontend is running..."
    if ! "$FRONTEND_MANAGER" start; then
        error "Failed to start frontend server"
        return 1
    fi
    
    # Wait for frontend to be ready with proper health checking
    if ! wait_for_service_health "Frontend" "http://localhost:3001" 60 3; then
        error "Frontend failed to start within timeout"
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

# Function to restart all servers
restart_all() {
    log "Restarting development environment..."
    
    "$BACKEND_MANAGER" restart
    sleep 2
    "$WORKER_MANAGER" restart
    "$WORKER_MANAGER" start-web
    "$FRONTEND_MANAGER" restart
    
    if check_dev_environment; then
        success "Development environment restarted successfully!"
        return 0
    else
        error "Development environment failed to restart properly"
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
    echo "COMMANDS:"
    echo "  ensure     Start all services if needed (default command)"
    echo "  start      Alias for 'ensure'"
    echo "  backend    Ensure only backend service is running"
    echo "  worker     Ensure only worker service is running"
    echo "  frontend   Ensure only frontend service is running"
    echo "  status     Show quick status overview of all services"
    echo "  health     Run comprehensive health check with detailed diagnostics"
    echo "  check      Silent health check (exit code based, for scripts)"
    echo "  restart    Restart all services"
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
    echo "  $0 restart            # Restart all services"
    echo "  $0 backend            # Start only backend service"
    echo ""
    echo "TROUBLESHOOTING:"
    echo "  • If services fail to start, try: $0 stop && $0 ensure"
    echo "  • For detailed diagnostics, use: $0 health"
    echo "  • View individual service logs with screen commands:"
    echo "    - Backend:  screen -r powernode-backend"
    echo "    - Worker:   screen -r powernode-worker"
    echo "    - Frontend: screen -r powernode-frontend"
    echo ""
    echo "This script manages the complete Powernode development environment"
    echo "including Rails API backend, Sidekiq worker service, and React frontend."
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
        restart_all
        ;;
    health)
        if detailed_health_check true; then
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
            exit 1
        fi
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
        echo "Usage: $0 {ensure|backend|worker|frontend|status|restart|stop|check|health|help}"
        echo ""
        echo "❌ Unknown command: '$1'"
        echo ""
        echo "Available commands:"
        echo "  ensure, backend, worker, frontend, status, restart, stop, check, health, help"
        echo ""
        echo "💡 For detailed help and examples, run: $0 help"
        exit 1
        ;;
esac