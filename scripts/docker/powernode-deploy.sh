#!/usr/bin/env bash
# Powernode Docker Deployment Manager
# Handles deploying powernode services via Docker Compose or Swarm.
#
# Usage:
#   powernode-deploy.sh up [--env <file>]           # Start all services
#   powernode-deploy.sh down                        # Stop all services
#   powernode-deploy.sh status                      # Show service status
#   powernode-deploy.sh logs [service]              # View service logs
#   powernode-deploy.sh health                      # Health check all services
#   powernode-deploy.sh migrate                     # Run database migrations
#   powernode-deploy.sh rollback                    # Rollback to previous images
#   powernode-deploy.sh exec <service> <command>    # Execute command in service
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[DEPLOY]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}     $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Detect compose file
detect_compose_file() {
    if [[ -n "${COMPOSE_FILE:-}" ]]; then
        echo "${COMPOSE_FILE}"
    elif [[ -f "${PROJECT_ROOT}/docker/docker-compose.prod.yml" ]] && [[ "${POWERNODE_ENV:-}" == "production" ]]; then
        echo "${PROJECT_ROOT}/docker/docker-compose.prod.yml"
    else
        echo "${PROJECT_ROOT}/docker/docker-compose.yml"
    fi
}

COMPOSE_FILE="$(detect_compose_file)"

dc() {
    docker compose -f "${COMPOSE_FILE}" "$@"
}

# ──────────────────────────────────────────────────────────────────
cmd_up() {
    local env_file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env) env_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    log_info "Starting services..."
    log_info "Compose file: ${COMPOSE_FILE}"

    local args=(up -d)

    if [[ -n "${env_file}" ]]; then
        args=(--env-file "${env_file}" up -d)
    fi

    dc "${args[@]}"

    log_ok "Services started"
    echo ""
    cmd_status
}

cmd_down() {
    log_info "Stopping services..."
    dc down
    log_ok "Services stopped"
}

cmd_status() {
    echo ""
    echo "Powernode Docker Service Status"
    echo "==============================="
    echo ""
    dc ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

cmd_logs() {
    local service="${1:-}"
    if [[ -n "${service}" ]]; then
        dc logs -f "${service}"
    else
        dc logs -f
    fi
}

cmd_health() {
    log_info "Running health checks..."
    echo ""

    local all_healthy=true

    # Check each service
    for service in backend worker frontend; do
        local status
        status="$(dc ps --format '{{.Status}}' "${service}" 2>/dev/null || echo "not running")"

        if echo "${status}" | grep -qi "healthy\|up"; then
            echo -e "  ${GREEN}OK${NC}    ${service}: ${status}"
        else
            echo -e "  ${RED}FAIL${NC}  ${service}: ${status}"
            all_healthy=false
        fi
    done

    echo ""

    # API health endpoint
    local api_port
    api_port="$(dc port backend 3000 2>/dev/null | cut -d: -f2 || echo "")"
    if [[ -n "${api_port}" ]]; then
        local response
        response="$(curl -sf "http://localhost:${api_port}/api/v1/health" 2>/dev/null || echo "")"
        if [[ -n "${response}" ]]; then
            echo -e "  ${GREEN}OK${NC}    API health: ${response}"
        else
            echo -e "  ${RED}FAIL${NC}  API health: no response"
            all_healthy=false
        fi
    fi

    echo ""
    if [[ "${all_healthy}" == true ]]; then
        log_ok "All services healthy"
    else
        log_error "Some services are unhealthy"
        return 1
    fi
}

cmd_migrate() {
    log_info "Running database migrations..."
    dc exec backend bundle exec rails db:migrate
    log_ok "Migrations complete"
}

cmd_rollback() {
    log_info "Rolling back to previous images..."

    # Check for previous image tags
    local registry="${POWERNODE_REGISTRY:-docker.io/powernode}"
    for service in backend worker frontend; do
        local current_tag
        current_tag="$(dc images "${service}" --format '{{.Tag}}' 2>/dev/null | head -1)"
        log_info "${service}: current tag = ${current_tag}"
    done

    log_warn "To rollback, re-deploy with the previous version tag:"
    echo "  scripts/docker/powernode-build.sh --tag <previous-version>"
    echo "  docker compose -f docker/docker-compose.prod.yml up -d"
}

cmd_exec() {
    local service="${1:-}"
    shift || true
    if [[ -z "${service}" ]]; then
        log_error "Usage: powernode-deploy.sh exec <service> <command>"
        exit 1
    fi
    dc exec "${service}" "$@"
}

# ──────────────────────────────────────────────────────────────────
usage() {
    echo "Powernode Docker Deployment Manager"
    echo ""
    echo "Usage: $(basename "$0") <command> [options]"
    echo ""
    echo "Commands:"
    echo "  up [--env <file>]          Start all services"
    echo "  down                       Stop all services"
    echo "  status                     Show service status"
    echo "  logs [service]             View service logs"
    echo "  health                     Health check all services"
    echo "  migrate                    Run database migrations"
    echo "  rollback                   Show rollback instructions"
    echo "  exec <service> <command>   Execute command in service container"
    echo ""
    echo "Environment:"
    echo "  COMPOSE_FILE               Override compose file path"
    echo "  POWERNODE_ENV              Set to 'production' for prod compose file"
    echo "  POWERNODE_REGISTRY         Container registry (default: docker.io/powernode)"
}

command="${1:-}"
shift || true

case "${command}" in
    up)       cmd_up "$@" ;;
    down)     cmd_down ;;
    status)   cmd_status ;;
    logs)     cmd_logs "$@" ;;
    health)   cmd_health ;;
    migrate)  cmd_migrate ;;
    rollback) cmd_rollback ;;
    exec)     cmd_exec "$@" ;;
    help|--help|-h) usage ;;
    *)
        if [[ -n "${command}" ]]; then
            log_error "Unknown command: ${command}"
        fi
        usage
        exit 1
        ;;
esac
