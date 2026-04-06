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

check_service() {
  local name="$1"
  local unit="$2"
  local status
  status=$(systemctl is-active "$unit" 2>/dev/null || true)
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
check_service "PostgreSQL"         "postgresql"
check_service "Redis"              "redis-server"
echo ""

# Endpoints
echo "Endpoints:"
check_endpoint "API Health"        "http://localhost:3000/api/v1/health"
check_endpoint "Worker API"        "http://localhost:4567/health"
check_endpoint "Frontend"          "http://localhost:5173"
echo ""

# Recent errors (last 5 min)
echo "Recent Errors (5 min):"
BACKEND_ERRORS=$(journalctl -u powernode-backend@default --since "5 min ago" --no-pager -p err 2>/dev/null | grep -c "" || true)
WORKER_ERRORS=$(journalctl -u powernode-worker@default --since "5 min ago" --no-pager -p err 2>/dev/null | grep -c "" || true)
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
