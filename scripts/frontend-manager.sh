#!/bin/bash

# Frontend Process Manager for Powernode Platform
# Manages React development server with comprehensive process control

set -e

# Configuration
REACT_PORT=3001
REACT_HOST="0.0.0.0"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
PID_FILE="$PROJECT_ROOT/.pids/frontend.pid"
LOG_FILE="$PROJECT_ROOT/logs/frontend.log"
ERROR_LOG="$PROJECT_ROOT/logs/frontend.error.log"

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

# Function to find all React processes
find_react_processes() {
    local pids=""
    
    # Method 1: Find by port binding (most reliable)
    local port_pids=$(lsof -ti :$REACT_PORT 2>/dev/null || true)
    
    # Method 2: Find by process name patterns
    local name_pids=$(pgrep -f "react-scripts.*start\|node.*react-scripts\|webpack.*serve\|npm.*start" 2>/dev/null || true)
    
    # Method 3: Find by screen session processes
    local screen_pids=""
    if screen -list | grep -q "powernode-frontend" 2>/dev/null; then
        # Find processes associated with screen session
        screen_pids=$(pgrep -f "SCREEN.*powernode-frontend" 2>/dev/null || true)
        # Also find React processes that might be children of screen
        local screen_children=""
        for spid in $screen_pids; do
            local children=$(pgrep -P "$spid" 2>/dev/null || true)
            screen_children="$screen_children $children"
            # Also get grandchildren (npm -> node -> react-scripts)
            for child_pid in $children; do
                local grandchildren=$(pgrep -P "$child_pid" 2>/dev/null || true)
                screen_children="$screen_children $grandchildren"
            done
        done
        screen_pids="$screen_pids $screen_children"
    fi
    
    # Method 4: Find React processes by their parent-child relationship
    local parent_pids=$(pgrep -f "npm.*start" 2>/dev/null || true)
    local child_pids=""
    for parent_pid in $parent_pids; do
        local children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
        child_pids="$child_pids $children"
    done
    
    # Combine all PIDs and remove duplicates
    pids=$(echo "$port_pids $name_pids $screen_pids $child_pids" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
    echo "$pids"
}

# Function to kill React processes
kill_react_processes() {
    local pids=$(find_react_processes)
    
    if [[ -z "$pids" ]]; then
        return 0
    fi
    
    log "Found React processes: $pids"
    
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
}

# Function to check if frontend is running
is_running() {
    local pids=$(find_react_processes)
    [[ -n "$pids" ]]
}

# Function to wait for frontend to be ready
wait_for_frontend() {
    local max_attempts=60  # React can take longer to compile
    local attempt=1
    
    log "Waiting for React development server to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -I "http://localhost:$REACT_PORT" | head -1 | grep -q "200"; then
            success "React development server is ready at http://localhost:$REACT_PORT"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    error "React development server failed to start within $((max_attempts * 2)) seconds"
    return 1
}

# Function to start the frontend
start() {
    log "Starting React frontend development server in screen session..."
    
    # Fast check if React is already running and healthy
    if is_running; then
        success "React server is already running at http://localhost:$REACT_PORT"
        return 0
    fi
    
    # Check if screen is available
    if ! command -v screen >/dev/null 2>&1; then
        error "screen is not installed. Please install screen: sudo apt install screen"
        exit 1
    fi
    
    # Verify frontend directory exists
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        error "Frontend directory not found: $FRONTEND_DIR"
        exit 1
    fi
    
    # Kill any existing screen session with the same name
    screen -S powernode-frontend -X quit 2>/dev/null || true
    
    # Clear logs
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    # Start React development server in detached screen session
    log "Starting React development server in screen session 'powernode-frontend'..."
    
    # Use screen with immediate detachment
    cd "$FRONTEND_DIR"
    screen -dmS powernode-frontend bash -c "PORT=$REACT_PORT HOST=$REACT_HOST NODE_OPTIONS='--no-deprecation' GENERATE_SOURCEMAP=true FAST_REFRESH=true exec npm start > '$LOG_FILE' 2>&1"
    
    success "React development server started in screen session 'powernode-frontend'"
    log "View logs: screen -r powernode-frontend"
    log "Or use: ./scripts/frontend-manager.sh logs"
    log "Frontend available at: http://localhost:$REACT_PORT"
    return 0
}

# Function to stop the frontend
stop() {
    log "Stopping React frontend development server..."
    
    # First try to kill the screen session
    if screen -list | grep -q "powernode-frontend" 2>/dev/null; then
        log "Stopping screen session 'powernode-frontend'..."
        screen -S powernode-frontend -X quit 2>/dev/null || true
    fi
    
    # Also kill any remaining React processes
    if is_running; then
        kill_react_processes
    else
        log "No React processes found running"
    fi
    
    # Clean up PID file
    rm -f "$PID_FILE"
    
    success "React frontend stopped"
}

# Function to restart the frontend
restart() {
    log "Restarting React frontend development server..."
    stop
    sleep 2
    start
}

# Function to show status
status() {
    log "Checking React frontend status..."
    
    if is_running; then
        local pids=$(find_react_processes)
        success "React server: Running (PID: $pids) - http://localhost:$REACT_PORT"
        
        # Test server response
        if curl -s -I "http://localhost:$REACT_PORT" | head -1 | grep -q "200"; then
            success "Server check: PASS"
        else
            warn "Server check: FAIL"
        fi
    else
        warn "React server: Not running"
    fi
}

# Function to show logs
logs() {
    local lines=${1:-50}
    
    if [[ -f "$LOG_FILE" ]]; then
        log "Showing last $lines lines of frontend logs:"
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
        log "Following frontend logs (Ctrl+C to stop):"
        tail -f "$LOG_FILE"
    else
        warn "No log file found at $LOG_FILE"
    fi
}

# Function to clear cache and restart
clear_cache() {
    log "Clearing React cache and restarting..."
    
    # Stop the server
    stop
    
    # Clear various caches
    cd "$FRONTEND_DIR"
    
    if [[ -d "node_modules/.cache" ]]; then
        log "Clearing webpack cache..."
        rm -rf node_modules/.cache
    fi
    
    if [[ -d ".eslintcache" ]]; then
        log "Clearing ESLint cache..."
        rm -f .eslintcache
    fi
    
    if [[ -d "build" ]]; then
        log "Clearing build directory..."
        rm -rf build
    fi
    
    # Restart with fresh cache
    start
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
    clear-cache)
        clear_cache
        ;;
    screen|attach)
        if screen -list | grep -q "powernode-frontend" 2>/dev/null; then
            log "Attaching to screen session 'powernode-frontend'..."
            screen -r powernode-frontend
        else
            error "No screen session 'powernode-frontend' found"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs [lines]|follow|clear-cache|screen}"
        echo ""
        echo "Commands:"
        echo "  start       - Start the React development server in screen session"
        echo "  stop        - Stop the React development server"
        echo "  restart     - Restart the React development server"
        echo "  status      - Show server status and health"
        echo "  logs        - Show recent log entries (default: 50 lines)"
        echo "  follow      - Follow log output in real-time"
        echo "  clear-cache - Clear React cache and restart"
        echo "  screen      - Attach to screen session (interactive mode)"
        exit 1
        ;;
esac