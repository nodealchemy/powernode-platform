#!/bin/bash

# Development Manager for Powernode Platform
# Orchestrates individual process managers for Rails API and React frontend

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Verify individual managers exist
check_managers() {
    if [[ ! -x "$BACKEND_MANAGER" ]]; then
        error "Backend manager not found or not executable: $BACKEND_MANAGER"
        exit 1
    fi
    
    if [[ ! -x "$FRONTEND_MANAGER" ]]; then
        error "Frontend manager not found or not executable: $FRONTEND_MANAGER"
        exit 1
    fi
}

start_services() {
    log "Starting Powernode development environment..."
    
    check_managers
    
    # Stop any existing services first
    stop_services
    
    # Start backend in background
    log "Starting Rails backend..."
    "$BACKEND_MANAGER" start
    
    # Start frontend in background
    log "Starting React frontend..."
    "$FRONTEND_MANAGER" start
    
    success "Development environment started successfully!"
    echo
    log "Services available at:"
    echo "  • Rails API: http://localhost:3000"
    echo "  • React App: http://localhost:3001"
    echo
    log "Management commands:"
    log "  • Status: ./dev-manager.sh status"
    log "  • Logs:   ./dev-manager.sh logs [rails|frontend]"
    log "  • Stop:   ./dev-manager.sh stop"
    log "  • Individual control: ./scripts/backend-manager.sh [command]"
    log "  • Individual control: ./scripts/frontend-manager.sh [command]"
}

stop_services() {
    log "Stopping development services..."
    
    check_managers
    
    # Stop both services
    "$BACKEND_MANAGER" stop
    "$FRONTEND_MANAGER" stop
    
    success "All services stopped"
}

restart_services() {
    log "Restarting development services..."
    
    check_managers
    
    # Restart both services
    "$BACKEND_MANAGER" restart
    "$FRONTEND_MANAGER" restart
    
    success "All services restarted"
}

check_status() {
    log "Checking service status..."
    echo
    
    check_managers
    
    # Check status of both services
    "$BACKEND_MANAGER" status
    "$FRONTEND_MANAGER" status
}

show_logs() {
    local service=${1:-all}
    local lines=${2:-50}
    
    check_managers
    
    case $service in
        rails|backend)
            "$BACKEND_MANAGER" logs "$lines"
            ;;
        frontend|react)
            "$FRONTEND_MANAGER" logs "$lines"
            ;;
        all|*)
            log "Showing logs for all services:"
            echo "=== Rails Backend ==="
            "$BACKEND_MANAGER" logs "$((lines/2))"
            echo
            echo "=== React Frontend ==="
            "$FRONTEND_MANAGER" logs "$((lines/2))"
            ;;
    esac
}

follow_logs() {
    local service=${1:-backend}
    
    check_managers
    
    case $service in
        rails|backend)
            "$BACKEND_MANAGER" follow
            ;;
        frontend|react)
            "$FRONTEND_MANAGER" follow
            ;;
        *)
            error "Please specify 'rails' or 'frontend' for follow logs"
            exit 1
            ;;
    esac
}

# Individual service control
control_backend() {
    check_managers
    "$BACKEND_MANAGER" "$@"
}

control_frontend() {
    check_managers
    "$FRONTEND_MANAGER" "$@"
}

# Main command handling
case "${1:-start}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        check_status
        ;;
    logs)
        show_logs "$2" "$3"
        ;;
    follow)
        follow_logs "$2"
        ;;
    backend)
        shift
        control_backend "$@"
        ;;
    frontend)
        shift
        control_frontend "$@"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs [service] [lines]|follow [service]|backend [cmd]|frontend [cmd]}"
        echo ""
        echo "Main commands:"
        echo "  start   - Start both Rails and React servers"
        echo "  stop    - Stop both servers"
        echo "  restart - Restart both servers"
        echo "  status  - Show status of both servers"
        echo "  logs    - Show logs (options: rails, frontend, all)"
        echo "  follow  - Follow logs in real-time (specify: rails or frontend)"
        echo ""
        echo "Individual service control:"
        echo "  backend [cmd]  - Control backend directly (start|stop|restart|status|logs|follow)"
        echo "  frontend [cmd] - Control frontend directly (start|stop|restart|status|logs|follow|clear-cache)"
        echo ""
        echo "Examples:"
        echo "  $0 start"
        echo "  $0 logs rails 100"
        echo "  $0 follow frontend"
        echo "  $0 backend restart"
        echo "  $0 frontend clear-cache"
        echo ""
        echo "Direct script usage:"
        echo "  ./scripts/backend-manager.sh [command]"
        echo "  ./scripts/frontend-manager.sh [command]"
        exit 1
        ;;
esac