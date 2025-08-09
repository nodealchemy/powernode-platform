#!/bin/bash

# Automatic Development Environment Manager
# Helper script for Claude to automatically start/manage development servers

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_MANAGER="$PROJECT_ROOT/scripts/backend-manager.sh"
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

# Function to check if both servers are running and healthy
check_dev_environment() {
    local backend_running=false
    local frontend_running=false
    
    # Check backend
    if "$BACKEND_MANAGER" status > /dev/null 2>&1; then
        if curl -s -f --max-time 3 "http://localhost:3000/api/v1/health" > /dev/null 2>&1; then
            backend_running=true
        fi
    fi
    
    # Check frontend
    if "$FRONTEND_MANAGER" status > /dev/null 2>&1; then
        if curl -s -f --max-time 3 "http://localhost:3001" > /dev/null 2>&1; then
            frontend_running=true
        fi
    fi
    
    if $backend_running && $frontend_running; then
        return 0
    else
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
    
    # Start frontend second
    log "Ensuring frontend is running..."
    if ! "$FRONTEND_MANAGER" start; then
        error "Failed to start frontend server"
        return 1
    fi
    
    # Final verification
    if check_dev_environment; then
        success "Development environment is now fully operational!"
        log "Available at:"
        log "  • Backend API: http://localhost:3000"
        log "  • Frontend App: http://localhost:3001"
        return 0
    else
        error "Development environment failed to start properly"
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
    local frontend_status="❌ Not Running"
    
    if curl -s -f --max-time 3 "http://localhost:3000/api/v1/health" > /dev/null 2>&1; then
        backend_status="✅ Running & Healthy"
    fi
    
    if curl -s -f --max-time 3 "http://localhost:3001" > /dev/null 2>&1; then
        frontend_status="✅ Running & Healthy"
    fi
    
    echo "Development Environment Status:"
    echo "  Backend:  $backend_status"
    echo "  Frontend: $frontend_status"
    
    if [[ "$backend_status" == *"✅"* && "$frontend_status" == *"✅"* ]]; then
        echo ""
        echo "🚀 Ready for development!"
        echo "  • API: http://localhost:3000"
        echo "  • App: http://localhost:3001"
        return 0
    else
        return 1
    fi
}

# Function to restart both servers
restart_all() {
    log "Restarting development environment..."
    
    "$BACKEND_MANAGER" restart
    "$FRONTEND_MANAGER" restart
    
    if check_dev_environment; then
        success "Development environment restarted successfully!"
        return 0
    else
        error "Development environment failed to restart properly"
        return 1
    fi
}

# Main command handling
case "${1:-ensure}" in
    ensure|start)
        ensure_dev_environment
        ;;
    backend)
        ensure_backend
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
        echo "Usage: $0 {ensure|backend|frontend|status|restart|check}"
        echo ""
        echo "Commands:"
        echo "  ensure    - Automatically start both servers if needed (default)"
        echo "  backend   - Ensure only backend is running"
        echo "  frontend  - Ensure only frontend is running"
        echo "  status    - Show quick status of both servers"
        echo "  restart   - Restart both servers"
        echo "  check     - Check if environment is healthy (exit code based)"
        echo ""
        echo "This script is designed for Claude to automatically manage"
        echo "the development environment without manual intervention."
        exit 1
        ;;
esac