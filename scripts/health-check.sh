#!/bin/bash
# Health check script for Powernode platform services
# Usage: bash scripts/health-check.sh
# Headless: claude -p "Run scripts/health-check.sh and report any issues" --allowedTools "Bash,Read"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# powernode-* units may live in the user scope (dev-cell: installer --user)
# instead of the system scope (dev box). Detect per unit; non-powernode units
# (postgresql, redis) are always system scope.
unit_scope() {
  if [[ "$1" == powernode-* ]] && systemctl --user cat "$1" &>/dev/null; then
    echo "user"
  else
    echo "system"
  fi
}

check_service() {
  local name="$1"
  local unit="$2"
  local status scope
  scope=$(unit_scope "$unit")
  if [[ "$scope" == "user" ]]; then
    status=$(systemctl --user is-active "$unit" 2>/dev/null || true)
  else
    status=$(systemctl is-active "$unit" 2>/dev/null || true)
  fi
  if [[ "$status" == "active" ]]; then
    printf "  ${GREEN}✓${NC} %-35s %s\n" "$name" "$unit"
  else
    printf "  ${RED}✗${NC} %-35s %s (%s)\n" "$name" "$unit" "$status"
    ERRORS=$((ERRORS + 1))
  fi
}

check_endpoint() {
  local name="$1"
  local url="$2"
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "$url" 2>/dev/null || echo "000")
  if [[ "$http_code" =~ ^2 ]]; then
    printf "  ${GREEN}✓${NC} %-35s %s (%s)\n" "$name" "$url" "$http_code"
  else
    printf "  ${RED}✗${NC} %-35s %s (%s)\n" "$name" "$url" "$http_code"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "═══════════════════════════════════════════"
echo " Powernode Health Check"
echo "═══════════════════════════════════════════"
echo ""

# Services
echo "Services:"
check_service "Rails API"          "powernode-backend@default"
check_service "Sidekiq Worker"     "powernode-worker@default"
check_service "Worker HTTP API"    "powernode-worker-web@default"
check_service "Frontend"           "powernode-frontend@default"
# Postgres/Redis unit names vary by host (system packages vs fleet modules) —
# probe connectivity instead of a unit name.
if pg_isready -q 2>/dev/null; then
  printf "  ${GREEN}✓${NC} %-35s %s\n" "PostgreSQL" "pg_isready"
else
  printf "  ${RED}✗${NC} %-35s %s\n" "PostgreSQL" "pg_isready failed"
  ERRORS=$((ERRORS + 1))
fi
if [[ "$(redis-cli ping 2>/dev/null)" == "PONG" ]]; then
  printf "  ${GREEN}✓${NC} %-35s %s\n" "Redis" "redis-cli ping"
else
  printf "  ${RED}✗${NC} %-35s %s\n" "Redis" "redis-cli ping failed"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Endpoints (frontend Vite port per configs/frontend-default.conf convention)
echo "Endpoints:"
check_endpoint "API Health"        "http://localhost:3000/api/v1/health"
check_endpoint "Worker API"        "http://localhost:4567/health"
check_endpoint "Frontend"          "http://localhost:3001"
echo ""

# Recent errors (last 5 min)
echo "Recent Errors (5 min):"
journal_errors() {
  local unit="$1"
  if [[ "$(unit_scope "$unit")" == "user" ]]; then
    journalctl --user -u "$unit" --since "5 min ago" --no-pager -p err 2>/dev/null | grep -c "" || true
  else
    journalctl -u "$unit" --since "5 min ago" --no-pager -p err 2>/dev/null | grep -c "" || true
  fi
}
BACKEND_ERRORS=$(journal_errors powernode-backend@default)
WORKER_ERRORS=$(journal_errors powernode-worker@default)
if [[ "$BACKEND_ERRORS" -gt 0 ]]; then
  printf "  ${YELLOW}!${NC} Backend: %d error lines\n" "$BACKEND_ERRORS"
else
  printf "  ${GREEN}✓${NC} Backend: clean\n"
fi
if [[ "$WORKER_ERRORS" -gt 0 ]]; then
  printf "  ${YELLOW}!${NC} Worker: %d error lines\n" "$WORKER_ERRORS"
else
  printf "  ${GREEN}✓${NC} Worker: clean\n"
fi
echo ""

# Summary
echo "═══════════════════════════════════════════"
if [[ "$ERRORS" -eq 0 ]]; then
  printf " ${GREEN}All checks passed${NC}\n"
else
  printf " ${RED}%d check(s) failed${NC}\n" "$ERRORS"
fi
echo "═══════════════════════════════════════════"

exit "$ERRORS"
