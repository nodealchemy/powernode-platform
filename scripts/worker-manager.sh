#!/bin/bash

# Powernode Worker Service Management Script
# Manages the standalone Sidekiq worker service with screen-based process management

set -euo pipefail

WORKER_DIR="/home/rett/Projects/powernode-platform/worker"
SCREEN_SESSION="powernode-worker"
WEB_SCREEN_SESSION="powernode-worker-web"
PID_FILE="/var/tmp/powernode-worker.pid"
LOG_FILE="/home/rett/Projects/powernode-platform/logs/worker.log"
WEB_PID_FILE="/var/tmp/powernode-worker-web.pid"
WEB_LOG_FILE="/home/rett/Projects/powernode-platform/logs/worker-web.log"

# Load environment variables from .env file
load_environment() {
    if [[ -f "$WORKER_DIR/.env" ]]; then
        export $(grep -v '^#' "$WORKER_DIR/.env" | xargs)
    fi
}

# Load environment variables
load_environment

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[WORKER-MANAGER]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if worker is running
is_worker_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            # Clean up stale PID file
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Check if web interface is running
is_web_running() {
    if [[ -f "$WEB_PID_FILE" ]]; then
        local pid=$(cat "$WEB_PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            # Clean up stale PID file
            rm -f "$WEB_PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Check if screen session exists
screen_session_exists() {
    screen -list | grep -q "$SCREEN_SESSION"
}

# Check if web screen session exists
web_screen_session_exists() {
    screen -list | grep -q "$WEB_SCREEN_SESSION"
}

# Get worker health status
get_worker_health() {
    if ! is_worker_running; then
        echo "stopped"
        return
    fi
    
    # Check if Redis is accessible
    if ! redis-cli -u "${REDIS_URL:-redis://localhost:6379/1}" ping > /dev/null 2>&1; then
        echo "unhealthy-redis"
        return
    fi
    
    echo "healthy"
}

# Start worker service
start_worker() {
    if is_worker_running; then
        warn "Worker service is already running"
        return 0
    fi
    
    log "Starting Powernode worker service..."
    
    # Check dependencies
    if ! command -v screen > /dev/null; then
        error "GNU screen is not installed. Please install it first."
        return 1
    fi
    
    if ! command -v redis-cli > /dev/null; then
        error "Redis CLI is not available. Please ensure Redis is installed."
        return 1
    fi
    
    # Check if Redis is running
    if ! redis-cli -u "${REDIS_URL:-redis://localhost:6379/1}" ping > /dev/null 2>&1; then
        error "Redis server is not accessible at ${REDIS_URL:-redis://localhost:6379/1}"
        return 1
    fi
    
    # Change to worker directory
    cd "$WORKER_DIR"
    
    # Install dependencies if Gemfile.lock doesn't exist
    if [[ ! -f "Gemfile.lock" ]]; then
        log "Installing worker dependencies..."
        bundle install
    fi
    
    # Check for required environment variables
    if [[ -z "${SERVICE_TOKEN:-}" ]]; then
        error "SERVICE_TOKEN environment variable is not set"
        error "Please set SERVICE_TOKEN in your environment or .env file"
        return 1
    fi
    
    # Kill any existing screen session
    if screen_session_exists; then
        log "Terminating existing screen session..."
        screen -S "$SCREEN_SESSION" -X quit 2>/dev/null || true
        sleep 2
    fi
    
    # Create new screen session and start worker
    log "Creating screen session: $SCREEN_SESSION"
    screen -dmS "$SCREEN_SESSION" bash -c "
        cd '$WORKER_DIR'
        export WORKER_ENV=\${WORKER_ENV:-development}
        export REDIS_URL=\${REDIS_URL:-redis://localhost:6379/1}
        export BACKEND_API_URL=\${BACKEND_API_URL:-http://localhost:3000}
        export SERVICE_TOKEN='$SERVICE_TOKEN'
        
        echo 'Starting Sidekiq worker...' | tee -a '$LOG_FILE'
        exec bundle exec sidekiq -r ./config/application.rb -C ./config/sidekiq.yml 2>&1 | tee -a '$LOG_FILE'
    " 2>/dev/null
    
    # Wait briefly for the process to start with timeout
    local timeout=5
    local count=0
    while [[ $count -lt $timeout ]]; do
        local screen_pid=$(screen -list 2>/dev/null | grep "$SCREEN_SESSION" | awk '{print $1}' | cut -d. -f1)
        if [[ -n "$screen_pid" ]]; then
            echo "$screen_pid" > "$PID_FILE"
            success "Worker service started successfully (PID: $screen_pid)"
            
            # Note: Web interface can be started separately with: $0 start-web
            log "Worker started. Use '$0 start-web' to start the web interface separately"
            
            return 0
        fi
        sleep 0.5
        ((count++))
    done
    
    error "Failed to start worker service (timeout after ${timeout}s)"
    return 1
}

# Start Sidekiq web interface
start_web_interface() {
    if is_web_running; then
        log "Sidekiq web interface is already running"
        return 0
    fi
    
    log "Starting Sidekiq web interface..."
    
    # Check dependencies
    if ! command -v screen > /dev/null; then
        error "GNU screen is not installed. Please install it first."
        return 1
    fi
    
    # Change to worker directory
    cd "$WORKER_DIR"
    
    # Check for required environment variables
    if [[ -z "${SERVICE_TOKEN:-}" ]]; then
        error "SERVICE_TOKEN environment variable is not set"
        error "Please set SERVICE_TOKEN in your environment or .env file"
        return 1
    fi
    
    # Kill any existing web screen session
    if web_screen_session_exists; then
        log "Terminating existing web screen session..."
        screen -S "$WEB_SCREEN_SESSION" -X quit 2>/dev/null || true
        sleep 2
    fi
    
    # Create new screen session and start web interface
    log "Creating web screen session: $WEB_SCREEN_SESSION"
    screen -dmS "$WEB_SCREEN_SESSION" bash -c "
        cd '$WORKER_DIR'
        export WORKER_ENV=\${WORKER_ENV:-development}
        export REDIS_URL=\${REDIS_URL:-redis://localhost:6379/1}
        export BACKEND_API_URL=\${BACKEND_API_URL:-http://localhost:3001}
        export SERVICE_TOKEN='$SERVICE_TOKEN'
        export SIDEKIQ_WEB_HOST=\${SIDEKIQ_WEB_HOST:-0.0.0.0}
        export SIDEKIQ_WEB_PORT=\${SIDEKIQ_WEB_PORT:-4567}
        
        echo '[$(date)] INFO [WORKER] [] Worker service authentication configured' | tee -a '$WEB_LOG_FILE'
        exec bundle exec rackup -s puma -o \"\$SIDEKIQ_WEB_HOST\" -p \"\$SIDEKIQ_WEB_PORT\" config.ru 2>&1 | tee -a '$WEB_LOG_FILE'
    " 2>/dev/null
    
    # Wait briefly for the process to start with timeout
    local timeout=5
    local count=0
    while [[ $count -lt $timeout ]]; do
        local screen_pid=$(screen -list 2>/dev/null | grep "$WEB_SCREEN_SESSION" | awk '{print $1}' | cut -d. -f1)
        if [[ -n "$screen_pid" ]]; then
            echo "$screen_pid" > "$WEB_PID_FILE"
            local web_host="${SIDEKIQ_WEB_HOST:-0.0.0.0}"
            local web_port="${SIDEKIQ_WEB_PORT:-4567}"
            success "Sidekiq web interface started (PID: $screen_pid, Host: $web_host, Port: $web_port)"
            log "Web interface running in screen session '$WEB_SCREEN_SESSION'"
            log "To attach: screen -r $WEB_SCREEN_SESSION"
            return 0
        fi
        sleep 0.5
        ((count++))
    done
    
    error "Failed to start web interface (timeout after ${timeout}s)"
    return 1
}

# Stop web interface only
stop_web_interface() {
    local stopped=false
    
    if is_web_running; then
        local web_pid=$(cat "$WEB_PID_FILE")
        log "Stopping Sidekiq web interface (PID: $web_pid)..."
        
        # Send TERM signal for graceful shutdown
        if kill -TERM "$web_pid" 2>/dev/null; then
            # Wait for graceful shutdown
            for i in {1..10}; do
                if ! ps -p "$web_pid" > /dev/null 2>&1; then
                    break
                fi
                sleep 1
            done
            
            # Force kill if still running
            if ps -p "$web_pid" > /dev/null 2>&1; then
                kill -9 "$web_pid" 2>/dev/null || true
            fi
        fi
        
        rm -f "$WEB_PID_FILE"
        stopped=true
    fi
    
    # Kill web screen session
    if web_screen_session_exists; then
        log "Terminating web screen session '$WEB_SCREEN_SESSION'..."
        screen -S "$WEB_SCREEN_SESSION" -X quit 2>/dev/null || true
        stopped=true
    fi
    
    if $stopped; then
        success "Sidekiq web interface stopped"
    else
        log "Web interface is not running"
    fi
}

# Stop worker service
stop_worker() {
    local stopped=false
    
    # Stop web interface first
    stop_web_interface
    
    # Stop worker
    if is_worker_running; then
        local pid=$(cat "$PID_FILE")
        log "Stopping worker service (PID: $pid)..."
        
        # Send TERM signal to Sidekiq for graceful shutdown
        if kill -TERM "$pid" 2>/dev/null; then
            log "Waiting for graceful shutdown..."
            
            # Wait up to 30 seconds for graceful shutdown
            for i in {1..30}; do
                if ! ps -p "$pid" > /dev/null 2>&1; then
                    break
                fi
                sleep 1
            done
            
            # Force kill if still running
            if ps -p "$pid" > /dev/null 2>&1; then
                warn "Graceful shutdown timed out, forcing termination"
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        
        # Kill screen session
        if screen_session_exists; then
            screen -S "$SCREEN_SESSION" -X quit 2>/dev/null || true
        fi
        
        rm -f "$PID_FILE"
        success "Worker service stopped"
        stopped=true
    fi
    
    if ! $stopped; then
        log "Worker service is not running"
    fi
}

# Restart worker service
restart_worker() {
    log "Restarting worker service..."
    stop_worker
    # Reduced sleep for faster restart
    sleep 1
    start_worker
}

# Show worker status
status_worker() {
    local health=$(get_worker_health)
    
    echo "=== Powernode Worker Service Status ==="
    echo
    
    # Worker process status
    if is_worker_running; then
        local pid=$(cat "$PID_FILE")
        case $health in
            "healthy")
                success "Worker: RUNNING (PID: $pid) ✓"
                ;;
            "unhealthy-redis")
                warn "Worker: RUNNING (PID: $pid) - Redis connection failed ⚠️"
                ;;
            *)
                warn "Worker: RUNNING (PID: $pid) - Status unknown"
                ;;
        esac
    else
        error "Worker: STOPPED ✗"
    fi
    
    # Web interface status
    if is_web_running; then
        local web_pid=$(cat "$WEB_PID_FILE")
        local web_host="${SIDEKIQ_WEB_HOST:-0.0.0.0}"
        local web_port="${SIDEKIQ_WEB_PORT:-4567}"
        success "Web Interface: RUNNING (PID: $web_pid, Host: $web_host, Port: $web_port) ✓"
        echo "  Local URL:    http://localhost:$web_port"
        echo "  External URL: http://[HOST_IP]:$web_port"
        echo "  Sidekiq UI:   http://localhost:$web_port/sidekiq"
    else
        error "Web Interface: STOPPED ✗"
    fi
    
    # Screen session status
    if screen_session_exists; then
        success "Worker Screen Session: ACTIVE ($SCREEN_SESSION) ✓"
    else
        error "Worker Screen Session: INACTIVE ✗"
    fi
    
    if web_screen_session_exists; then
        success "Web Screen Session: ACTIVE ($WEB_SCREEN_SESSION) ✓"
    else
        error "Web Screen Session: INACTIVE ✗"
    fi
    
    # Configuration
    echo
    echo "=== Configuration ==="
    echo "Worker Directory: $WORKER_DIR"
    echo "Redis URL: ${REDIS_URL:-redis://localhost:6379/1}"
    echo "Backend API: ${BACKEND_API_URL:-http://localhost:3000}"
    echo "Log File: $LOG_FILE"
    echo "Environment: ${WORKER_ENV:-development}"
    
    # Queue stats (if worker is running)
    if [[ "$health" == "healthy" ]]; then
        echo
        echo "=== Queue Statistics ==="
        redis-cli -u "${REDIS_URL:-redis://localhost:6379/1}" eval "
            local queues = redis.call('SMEMBERS', 'queues')
            for i=1,#queues do
                local queue = queues[i]
                local size = redis.call('LLEN', 'queue:' .. queue)
                print(queue .. ': ' .. size)
            end
        " 0 2>/dev/null || echo "Unable to fetch queue stats"
    fi
    
    echo
}

# Show worker logs
show_logs() {
    local lines="${2:-50}"
    
    if [[ ! -f "$LOG_FILE" ]]; then
        warn "Log file not found: $LOG_FILE"
        return 1
    fi
    
    echo "=== Worker Logs (last $lines lines) ==="
    tail -n "$lines" "$LOG_FILE"
}

# Follow worker logs
follow_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        warn "Log file not found: $LOG_FILE"
        return 1
    fi
    
    echo "=== Following Worker Logs (Ctrl+C to exit) ==="
    tail -f "$LOG_FILE"
}

# Attach to worker screen session
attach_screen() {
    if ! screen_session_exists; then
        error "Worker screen session '$SCREEN_SESSION' does not exist"
        return 1
    fi
    
    log "Attaching to worker screen session '$SCREEN_SESSION'"
    log "Press Ctrl+A, D to detach from session"
    screen -r "$SCREEN_SESSION"
}

# Attach to web screen session
attach_web_screen() {
    if ! web_screen_session_exists; then
        error "Web screen session '$WEB_SCREEN_SESSION' does not exist"
        return 1
    fi
    
    log "Attaching to web screen session '$WEB_SCREEN_SESSION'"
    log "Press Ctrl+A, D to detach from session"
    screen -r "$WEB_SCREEN_SESSION"
}

# Show usage
show_usage() {
    echo "Usage: $0 {start|stop|restart|status|logs|follow|screen|web-screen|start-web|stop-web}"
    echo
    echo "Commands:"
    echo "  start      - Start the worker service only"
    echo "  start-web  - Start the web interface only (in separate screen session)"
    echo "  stop       - Stop the worker service and web interface"
    echo "  stop-web   - Stop the web interface only"
    echo "  restart    - Restart the worker service"
    echo "  status     - Show worker service status and statistics"
    echo "  logs       - Show recent worker logs (default: 50 lines)"
    echo "  follow     - Follow worker logs in real-time"
    echo "  screen     - Attach to the worker screen session"
    echo "  web-screen - Attach to the web interface screen session"
    echo
    echo "Examples:"
    echo "  $0 start && $0 start-web"
    echo "  $0 logs 100"
    echo "  $0 status"
    echo "  $0 screen       # Attach to worker"
    echo "  $0 web-screen   # Attach to web interface"
}

# Main command handler
case "${1:-}" in
    start)
        start_worker
        ;;
    stop)
        stop_worker
        ;;
    restart)
        restart_worker
        ;;
    status)
        status_worker
        ;;
    logs)
        show_logs "$@"
        ;;
    follow)
        follow_logs
        ;;
    start-web)
        start_web_interface
        ;;
    stop-web)
        stop_web_interface
        ;;
    screen)
        attach_screen
        ;;
    web-screen)
        attach_web_screen
        ;;
    *)
        show_usage
        exit 1
        ;;
esac