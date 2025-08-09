#!/bin/bash

# Backend Process Manager for Powernode Platform
# Manages Rails API server with comprehensive process control

set -e

# Configuration
RAILS_PORT=3000
RAILS_HOST="0.0.0.0"
PROJECT_ROOT="/home/rett/Projects/powernode-platform"
BACKEND_DIR="$PROJECT_ROOT/server"
PID_FILE="$PROJECT_ROOT/.pids/backend.pid"
LOG_FILE="$PROJECT_ROOT/logs/backend.log"
ERROR_LOG="$PROJECT_ROOT/logs/backend.error.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/.pids"
mkdir -p "$PROJECT_ROOT/logs"

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

# Function to find all Rails processes
find_rails_processes() {
    # Find processes by multiple criteria to catch all Rails instances
    local pids=""
    
    # Method 1: Find by port binding (most reliable)
    local port_pids=$(lsof -ti :$RAILS_PORT 2>/dev/null || true)
    
    # Method 2: Find by process name patterns
    local name_pids=$(pgrep -f "rails server\|puma.*$RAILS_PORT\|bundle.*rails" 2>/dev/null || true)
    
    # Method 3: Find by screen session processes
    local screen_pids=""
    if screen -list | grep -q "powernode-backend" 2>/dev/null; then
        # Find processes associated with screen session
        screen_pids=$(pgrep -f "SCREEN.*powernode-backend" 2>/dev/null || true)
        # Also find Rails processes that might be children of screen
        local screen_children=""
        for spid in $screen_pids; do
            screen_children="$screen_children $(pgrep -P "$spid" 2>/dev/null || true)"
        done
        screen_pids="$screen_pids $screen_children"
    fi
    
    # Method 4: Find by Rails temporary PID files
    local temp_pids=""
    if [[ -f "$BACKEND_DIR/tmp/pids/server.pid" ]]; then
        temp_pids=$(cat "$BACKEND_DIR/tmp/pids/server.pid" 2>/dev/null || true)
    fi
    
    # Combine all PIDs and remove duplicates
    pids=$(echo "$port_pids $name_pids $screen_pids $temp_pids" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
    echo "$pids"
}

# Function to kill Rails processes
kill_rails_processes() {
    local pids=$(find_rails_processes)
    
    if [[ -z "$pids" ]]; then
        return 0
    fi
    
    log "Found Rails processes: $pids"
    
    # First try graceful shutdown
    for pid in $pids; do
        if ps -p "$pid" > /dev/null 2>&1; then
            log "Gracefully stopping process $pid..."
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait up to 10 seconds for graceful shutdown
    local count=0
    while [[ $count -lt 10 ]]; do
        local remaining_pids=""
        for pid in $pids; do
            if ps -p "$pid" > /dev/null 2>&1; then
                remaining_pids="$remaining_pids $pid"
            fi
        done
        
        if [[ -z "$remaining_pids" ]]; then
            break
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    # Force kill remaining processes
    local remaining_pids=""
    for pid in $pids; do
        if ps -p "$pid" > /dev/null 2>&1; then
            remaining_pids="$remaining_pids $pid"
        fi
    done
    
    if [[ -n "$remaining_pids" ]]; then
        warn "Force killing remaining processes: $remaining_pids"
        for pid in $remaining_pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    
    # Clean up PID files
    rm -f "$PID_FILE"
    rm -f "$BACKEND_DIR/tmp/pids/server.pid"
}

# Function to check if backend is running
is_running() {
    local pids=$(find_rails_processes)
    [[ -n "$pids" ]]
}


# Function to start the backend
start() {
    log "Starting Rails backend server in screen session..."
    
    # Fast check if Rails is already running and healthy
    if is_running; then
        success "Rails server is already running at http://localhost:$RAILS_PORT"
        return 0
    fi
    
    # Check if screen is available
    if ! command -v screen >/dev/null 2>&1; then
        error "screen is not installed. Please install screen: sudo apt install screen"
        exit 1
    fi
    
    # Verify backend directory exists
    if [[ ! -d "$BACKEND_DIR" ]]; then
        error "Backend directory not found: $BACKEND_DIR"
        exit 1
    fi
    
    # Kill any existing screen session with the same name
    screen -S powernode-backend -X quit 2>/dev/null || true
    
    # Clear logs
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    # Start Rails server in detached screen session
    log "Starting Rails server in screen session 'powernode-backend'..."
    
    # Use screen with immediate detachment
    cd "$BACKEND_DIR"
    screen -dmS powernode-backend bash -c "exec bundle exec rails server -p $RAILS_PORT -b $RAILS_HOST > '$LOG_FILE' 2>&1"
    
    success "Rails server started in screen session 'powernode-backend'"
    log "View logs: screen -r powernode-backend"
    log "Or use: ./scripts/backend-manager.sh logs"
    return 0
}

# Function to stop the backend
stop() {
    log "Stopping Rails backend server..."
    
    # First try to kill the screen session
    if screen -list | grep -q "powernode-backend" 2>/dev/null; then
        log "Stopping screen session 'powernode-backend'..."
        screen -S powernode-backend -X quit 2>/dev/null || true
    fi
    
    # Also kill any remaining Rails processes
    if is_running; then
        kill_rails_processes
    else
        log "No Rails processes found running"
    fi
    
    # Clean up PID file
    rm -f "$PID_FILE"
    
    success "Rails backend stopped"
}

# Function to restart the backend
restart() {
    log "Restarting Rails backend server..."
    stop
    sleep 2
    start
}

# Function to show status
status() {
    log "Checking Rails backend status..."
    
    if is_running; then
        local pids=$(find_rails_processes)
        success "Rails server: Running (PID: $pids) - http://localhost:$RAILS_PORT"
        
        # Test health endpoint
        if curl -s "http://localhost:$RAILS_PORT/api/v1/health" > /dev/null 2>&1; then
            success "Health check: PASS"
        else
            warn "Health check: FAIL"
        fi
    else
        warn "Rails server: Not running"
    fi
}

# Function to show logs
logs() {
    local lines=${1:-50}
    
    if [[ -f "$LOG_FILE" ]]; then
        log "Showing last $lines lines of backend logs:"
        echo "--- STDOUT ---"
        tail -n "$lines" "$LOG_FILE"
        
        if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
            echo "--- STDERR ---"
            tail -n "$lines" "$ERROR_LOG"
        fi
    else
        warn "No log file found at $LOG_FILE"
    fi
}

# Function to follow logs
follow() {
    if [[ -f "$LOG_FILE" ]]; then
        log "Following backend logs (Ctrl+C to stop):"
        tail -f "$LOG_FILE"
    else
        warn "No log file found at $LOG_FILE"
    fi
}

# Main command handling
case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs "${2:-50}"
        ;;
    follow)
        follow
        ;;
    screen|attach)
        if screen -list | grep -q "powernode-backend" 2>/dev/null; then
            log "Attaching to screen session 'powernode-backend'..."
            screen -r powernode-backend
        else
            error "No screen session 'powernode-backend' found"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs [lines]|follow|screen}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the Rails backend server in screen session"
        echo "  stop    - Stop the Rails backend server"
        echo "  restart - Restart the Rails backend server"
        echo "  status  - Show server status and health"
        echo "  logs    - Show recent log entries (default: 50 lines)"
        echo "  follow  - Follow log output in real-time"
        echo "  screen  - Attach to screen session (interactive mode)"
        exit 1
        ;;
esac